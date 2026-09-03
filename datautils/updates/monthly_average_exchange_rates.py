from pandas import DataFrame, offsets, to_datetime
from sqlalchemy.engine import Engine

from datautils.constants import SELECTS_SQL18
from datautils.logging import DatabaseLogger
from datautils.sql import write_df_to_sql_db
from datautils.utils import concurrent_df_load


TABLE = "monthly_avg_xr"
STAGING_TABLE = "monthly_avg_xr_staging"
KEY_COLUMNS = ["end_date", "currency_pair_code"]


def _validate_rates(df: DataFrame) -> DataFrame:
    if df.empty:
        raise ValueError("the Finance monthly average exchange-rate query returned no rows")
    if df.isna().any().any():
        raise ValueError("monthly average exchange rates contain NULL values")
    if df.duplicated(subset=KEY_COLUMNS).any():
        raise ValueError("monthly average exchange rates contain duplicate keys")

    df = df.copy()
    df["start_date"] = to_datetime(df["start_date"])
    df["end_date"] = to_datetime(df["end_date"])

    expected_start = df["start_date"].dt.to_period("M").dt.start_time
    expected_end = df["start_date"] + offsets.MonthEnd(0)
    if (df["start_date"] != expected_start).any():
        raise ValueError("a start_date is not the first day of its month")
    if (df["end_date"] != expected_end).any():
        raise ValueError("an end_date is not the month end for its start_date")

    expected_codes = df["from_currency_code"] + "/" + df["to_currency_code"]
    if not df["currency_pair_code"].equals(expected_codes):
        raise ValueError("a currency_pair_code does not match its currencies")
    if (df["from_currency_code"] == df["to_currency_code"]).any():
        raise ValueError("a monthly rate converts a currency to itself")
    if (df["exchange_rate_value"] <= 0).any():
        raise ValueError("monthly exchange-rate values must be positive")

    return df


def update_monthly_average_exchange_rates_table(
    engine_finance: Engine,
    engine_sql18: Engine,
    logger: DatabaseLogger,
) -> int | None:
    """Refresh the snapshot and flag forecasts only when Finance data changes."""

    query_path = SELECTS_SQL18 / "monthly_average_exchange_rates.sql"
    df, error = concurrent_df_load(
        engine_finance,
        query_path,
        logger,
        TABLE,
    )
    if error is not None:
        logger.error(TABLE, "read Finance monthly rates", error)
        return None

    assert df is not None, "df should not be None when no error was returned"
    try:
        df = _validate_rates(df)
    except Exception as exc:  # noqa: BLE001
        logger.error(TABLE, "validate Finance monthly rates", str(exc))
        return None

    try:
        write_df_to_sql_db(
            engine_sql18,
            STAGING_TABLE,
            df,
            "replace",
            chunksize=len(df),
        )

        with engine_sql18.begin() as connection:
            changed = connection.exec_driver_sql(
                "SELECT CASE WHEN EXISTS ("
                "SELECT [start_date], [end_date], [from_currency_code], "
                "[to_currency_code], [currency_pair_code], [exchange_rate_value] "
                "FROM [dbo].[monthly_avg_xr_staging] EXCEPT "
                "SELECT [start_date], [end_date], [from_currency_code], "
                "[to_currency_code], [currency_pair_code], [exchange_rate_value] "
                "FROM [dbo].[monthly_avg_xr]) OR EXISTS ("
                "SELECT [start_date], [end_date], [from_currency_code], "
                "[to_currency_code], [currency_pair_code], [exchange_rate_value] "
                "FROM [dbo].[monthly_avg_xr] EXCEPT "
                "SELECT [start_date], [end_date], [from_currency_code], "
                "[to_currency_code], [currency_pair_code], [exchange_rate_value] "
                "FROM [dbo].[monthly_avg_xr_staging]) "
                "THEN 1 ELSE 0 END;"
            ).scalar_one()

            if changed:
                connection.exec_driver_sql(
                    "DELETE FROM [dbo].[monthly_avg_xr];"
                )
                connection.exec_driver_sql(
                    "INSERT INTO [dbo].[monthly_avg_xr] ("
                    "[start_date], [end_date], [from_currency_code], "
                    "[to_currency_code], [currency_pair_code], "
                    "[exchange_rate_value]) SELECT [start_date], [end_date], "
                    "[from_currency_code], [to_currency_code], "
                    "[currency_pair_code], [exchange_rate_value] "
                    "FROM [dbo].[monthly_avg_xr_staging];"
                )
            connection.exec_driver_sql(
                "DROP TABLE [dbo].[monthly_avg_xr_staging];"
            )

        if not changed:
            logger.info(TABLE, "compare Finance monthly rates", "source is unchanged", 0)
            return 0

        return len(df)
    except Exception as exc:  # noqa: BLE001
        try:
            with engine_sql18.begin() as connection:
                connection.exec_driver_sql(
                    "DROP TABLE IF EXISTS "
                    "[dbo].[monthly_avg_xr_staging];"
                )
        except Exception:  # noqa: BLE001
            pass
        logger.error(TABLE, "refresh monthly average exchange rates", str(exc))
        return None
