from concurrent.futures import ThreadPoolExecutor

from pandas import concat
from sqlalchemy.engine import Engine

from datautils.constants import SELECTS_SQL02, SELECTS_SQL04
from datautils.logging import DatabaseLogger
from datautils.sql import write_df_to_sql_db
from datautils.utils import concurrent_df_load


PURCHASE_ORDER_KEY = [
    "entity",
    "document_type",
    "document_no",
    "line_no",
]


def _valid_dimension_ids(engine: Engine, table: str, column: str) -> set[str]:
    with engine.connect() as connection:
        result = connection.exec_driver_sql(f"SELECT [{column}] FROM [dbo].[{table}];")
        return {row[0] for row in result if row[0] is not None}


def update_purchase_orders_table(
    engine_sql02: Engine,
    engine_sql04: Engine,
    engine_sql18: Engine,
    logger: DatabaseLogger,
) -> int | None:

    with ThreadPoolExecutor(max_workers=2) as executor:
        future_nav = executor.submit(
            concurrent_df_load,
            engine_sql02,
            SELECTS_SQL02 / "purchase_orders.sql",
            logger,
            "sql02 purchase orders",
        )
        future_sql04 = executor.submit(
            concurrent_df_load,
            engine_sql04,
            SELECTS_SQL04 / "purchase_orders.sql",
            logger,
            "sql04 purchase orders",
        )

        try:
            action = "load sql02 and SQL04 purchase orders concurrently"
            df_nav, err_sql02 = future_nav.result()
            df_sql04, err_sql04 = future_sql04.result()
        except Exception as exc:  # noqa: BLE001
            logger.error("purchase_orders", action, f"Error: {exc}")
            return None

    if err_sql02 is not None:
        logger.error("purchase_orders", "execute NAV purchase-order query", err_sql02)
    if err_sql04 is not None:
        logger.error("purchase_orders", "execute SQL04 purchase-order query", err_sql04)
    if err_sql02 is not None or err_sql04 is not None:
        return None

    assert df_nav is not None, "df_nav should not be None here"
    assert df_sql04 is not None, "df_sql04 should not be None here"

    try:
        action = "combine and validate purchase-order data"

        df = concat([df_nav, df_sql04], ignore_index=True)
        df = df.drop_duplicates(subset=PURCHASE_ORDER_KEY, keep="first")

        vendor_ids = _valid_dimension_ids(engine_sql18, "vendors", "vendor_id")
        item_ids = _valid_dimension_ids(engine_sql18, "items", "item_id")

        df.loc[~df["vendor_id"].isin(vendor_ids), "vendor_id"] = None
        df.loc[~df["item_id"].isin(item_ids), "item_id"] = None
    except Exception as exc:  # noqa: BLE001
        logger.error("purchase_orders", action, f"Error: {exc}")
        return None

    rows = len(df)
    if rows == 0:
        logger.error(
            "purchase_orders",
            "purchase-orders dataframe row length check",
            "the dataframe has no rows of data",
            0,
        )
        return None

    try:
        action = "replace sql18 purchase_orders data"

        with engine_sql18.begin() as connection:
            connection.exec_driver_sql("DELETE FROM [dbo].[purchase_orders];")
            write_df_to_sql_db(
                connection,
                "purchase_orders",
                df,
                "append",
                chunksize=min(rows, 20000),
            )
    except Exception as exc:  # noqa: BLE001
        logger.error("purchase_orders", action, f"Error: {exc}")
        return None

    return rows
