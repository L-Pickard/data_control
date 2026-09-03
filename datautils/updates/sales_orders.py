from concurrent.futures import ThreadPoolExecutor

from pandas import DataFrame, concat
from sqlalchemy.engine import Engine

from datautils.constants import SELECTS_SQL02, SELECTS_SQL04
from datautils.logging import DatabaseLogger
from datautils.sql import execute_sql_procedure, write_df_to_sql_db
from datautils.utils import concurrent_df_load

TABLE = "sales_orders"
STAGING_TABLE = "sales_orders_staging"
KEY_COLUMNS = ["entity", "document_type", "document_no", "line_no"]
REQUIRED_COLUMNS = KEY_COLUMNS + ["sell_to_customer_id", "bill_to_customer_id"]


def _validate_sales_orders(df: DataFrame) -> None:
    """Reject unsafe source snapshots before the warehouse transaction starts."""

    if df.empty:
        raise ValueError("the combined sales-order source returned no rows")
    if df[REQUIRED_COLUMNS].isna().any().any():
        raise ValueError("a required sales-order source column contains NULL")
    if df.duplicated(subset=KEY_COLUMNS).any():
        raise ValueError("the combined sales-order source contains duplicate keys")


def update_sales_orders_table(
    engine_sql02: Engine,
    engine_sql04: Engine,
    engine_sql18: Engine,
    logger: DatabaseLogger,
) -> int | None:
    """Stage and atomically replace the current sales-order line snapshot."""

    with ThreadPoolExecutor(max_workers=2) as executor:
        future_nav = executor.submit(
            concurrent_df_load,
            engine_sql02,
            SELECTS_SQL02 / "sales_orders.sql",
            logger,
            "sql02 sales orders",
        )
        future_llc = executor.submit(
            concurrent_df_load,
            engine_sql04,
            SELECTS_SQL04 / "sales_orders.sql",
            logger,
            "sql04 sales orders",
        )
        try:
            df_nav, nav_error = future_nav.result()
            df_llc, llc_error = future_llc.result()
        except Exception as exc:  # noqa: BLE001
            logger.error(TABLE, "load sales-order sources", str(exc))
            return None

    if nav_error is not None:
        logger.error(TABLE, "execute NAV sales-order query", nav_error)
    if llc_error is not None:
        logger.error(TABLE, "execute LLC sales-order query", llc_error)
    if nav_error is not None or llc_error is not None:
        return None

    assert df_nav is not None
    assert df_llc is not None

    try:
        df = concat([df_nav, df_llc], ignore_index=True)
        _validate_sales_orders(df)
        rows = len(df)
        write_df_to_sql_db(
            engine_sql18,
            STAGING_TABLE,
            df,
            "replace",
            chunksize=min(rows, 20000),
        )
        _, error = execute_sql_procedure(
            engine_sql18,
            "EXEC [dbo].[update_sales_orders_table];",
        )
        if error is not None:
            raise RuntimeError(error)
        return rows
    except Exception as exc:  # noqa: BLE001
        try:
            with engine_sql18.begin() as connection:
                connection.exec_driver_sql(
                    "DROP TABLE IF EXISTS [dbo].[sales_orders_staging];"
                )
        except Exception:  # noqa: BLE001
            pass
        logger.error(TABLE, "validate and replace sales-order data", str(exc))
        return None
