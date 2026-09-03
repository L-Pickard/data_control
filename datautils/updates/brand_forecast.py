from pandas import DataFrame, to_datetime
from sqlalchemy.dialects.mssql import DECIMAL
from sqlalchemy.engine import Engine

from datautils.constants import SELECTS_SQL18
from datautils.logging import DatabaseLogger
from datautils.sql import write_df_to_sql_db
from datautils.utils import concurrent_df_load


TABLE = "brand_forecast"
STAGING_TABLE = "brand_forecast_staging"
KEY_COLUMNS = ["entity", "brand_code", "sales_type", "date"]
REVENUE_COLUMNS = ["revenue", "gbp_revenue", "eur_revenue", "usd_revenue"]


def _validate_forecast(df: DataFrame) -> DataFrame:
    if df.empty:
        raise ValueError("the Finance brand forecast query returned no rows")
    if df.isna().any().any():
        raise ValueError("the Finance brand forecast contains NULL values")
    if df.duplicated(subset=KEY_COLUMNS).any():
        raise ValueError("the Finance brand forecast contains duplicate keys")

    df = df.copy()
    df["date"] = to_datetime(df["date"])

    if not df["sales_type"].isin(["B2B", "D2C"]).all():
        raise ValueError("the Finance brand forecast has an invalid sales_type")
    if not df["currency_code"].isin(["GBP", "EUR", "USD"]).all():
        raise ValueError("the Finance brand forecast has an invalid currency_code")

    return df


def update_brand_forecast_table(
    engine_finance: Engine,
    engine_sql18: Engine,
    logger: DatabaseLogger,
) -> int | None:
    """Atomically replace the warehouse brand forecast from Finance."""

    df, error = concurrent_df_load(
        engine_finance,
        SELECTS_SQL18 / "brand_forecast.sql",
        logger,
        TABLE,
    )
    if error is not None:
        logger.error(TABLE, "read Finance brand forecast", error)
        return None

    assert df is not None, "df should not be None when no error was returned"
    try:
        df = _validate_forecast(df)
    except Exception as exc:  # noqa: BLE001
        logger.error(TABLE, "validate Finance brand forecast", str(exc))
        return None

    try:
        write_df_to_sql_db(
            engine_sql18,
            STAGING_TABLE,
            df,
            "replace",
            chunksize=20000,
            datatype={column: DECIMAL(38, 20) for column in REVENUE_COLUMNS},
        )

        with engine_sql18.begin() as connection:
            connection.exec_driver_sql(
                "INSERT INTO [dbo].[brands] ([brand_id]) "
                "SELECT DISTINCT bf.[brand_code] "
                "FROM [dbo].[brand_forecast_staging] AS bf "
                "WHERE NOT EXISTS ("
                "SELECT 1 FROM [dbo].[brands] AS b "
                "WHERE b.[brand_id] = bf.[brand_code]);"
            )
            connection.exec_driver_sql("DELETE FROM [dbo].[brand_forecast];")
            connection.exec_driver_sql(
                "INSERT INTO [dbo].[brand_forecast] ("
                "[entity], [brand_code], [sales_type], [date], [currency_code], "
                "[revenue], [gbp_revenue], [eur_revenue], [usd_revenue]) "
                "SELECT [entity], [brand_code], [sales_type], [date], "
                "[currency_code], [revenue], [gbp_revenue], [eur_revenue], "
                "[usd_revenue] FROM [dbo].[brand_forecast_staging];"
            )
            connection.exec_driver_sql(
                "DROP TABLE [dbo].[brand_forecast_staging];"
            )

        return len(df)
    except Exception as exc:  # noqa: BLE001
        try:
            with engine_sql18.begin() as connection:
                connection.exec_driver_sql(
                    "DROP TABLE IF EXISTS [dbo].[brand_forecast_staging];"
                )
        except Exception:  # noqa: BLE001
            pass
        logger.error(TABLE, "replace brand forecast", str(exc))
        return None
