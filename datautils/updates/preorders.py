from pandas import DataFrame
from sqlalchemy.dialects.mssql import DECIMAL
from sqlalchemy.engine import Engine

from datautils.constants import SELECTS_SQL18
from datautils.logging import DatabaseLogger
from datautils.sql import execute_sql_procedure, write_df_to_sql_db
from datautils.utils import concurrent_df_load


TABLE = "preorders"
KEY_COLUMNS = [
    "preorder_code",
    "item_no",
    "customer_no",
    "currency_code",
    "order_timestamp",
]


def _validate_preorders(df: DataFrame) -> None:
    if df.empty:
        raise ValueError("the combined Finance preorder query returned no rows")
    if df[KEY_COLUMNS].isna().any().any():
        raise ValueError("a preorder business-key column contains NULL")
    if df.duplicated(subset=KEY_COLUMNS).any():
        raise ValueError("the combined preorder source contains duplicate keys")


def update_preorders_table(
    engine_finance: Engine,
    engine_sql18: Engine,
    logger: DatabaseLogger,
) -> int | None:
    """Accumulate current and historical Finance preorders at business grain."""

    df, error = concurrent_df_load(
        engine_finance,
        SELECTS_SQL18 / "preorders.sql",
        logger,
        TABLE,
    )
    if error is not None:
        logger.error(TABLE, "read Finance preorders", error)
        return None

    assert df is not None, "df should not be None when no error was returned"
    try:
        _validate_preorders(df)
        write_df_to_sql_db(
            engine_sql18,
            "preorders_staging",
            df,
            "replace",
            chunksize=20000,
            datatype={
                "quantity": DECIMAL(38, 20),
                "value": DECIMAL(38, 20),
            },
        )

        _, error = execute_sql_procedure(
            engine_sql18,
            "EXEC [dbo].[update_preorders_table];",
        )
        if error is not None:
            raise RuntimeError(error)

        return len(df)
    except Exception as exc:  # noqa: BLE001
        try:
            with engine_sql18.begin() as connection:
                connection.exec_driver_sql(
                    "DROP TABLE IF EXISTS [dbo].[preorders_staging];"
                )
        except Exception:  # noqa: BLE001
            pass
        logger.error(TABLE, "update accumulated preorders", str(exc))
        return None
