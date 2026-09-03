from concurrent.futures import ThreadPoolExecutor

from pandas import DataFrame, concat, to_numeric
from sqlalchemy.dialects.mssql import DECIMAL, NVARCHAR
from sqlalchemy.engine import Engine

from datautils.constants import SELECTS_SQL02, SELECTS_SQL04
from datautils.logging import DatabaseLogger
from datautils.sql import execute_sql_procedure, write_df_to_sql_db
from datautils.utils import concurrent_df_load

TABLE = "inventory"
STAGING_TABLE = "inventory_staging"
KEY_COLUMNS = ["entity", "item_id"]
QUANTITY_COLUMNS = [
    "inventory",
    "buffer_stock",
    "reserved_quantity",
    "unavailable_quantity",
]


def _validate_inventory(df: DataFrame) -> None:
    if df.empty:
        raise ValueError("the combined inventory source returned no rows")
    if df[KEY_COLUMNS + QUANTITY_COLUMNS].isna().any().any():
        raise ValueError("inventory contains a NULL key or quantity")
    if df.duplicated(subset=KEY_COLUMNS).any():
        raise ValueError("inventory contains duplicate entity/item keys")
    if (df[KEY_COLUMNS].astype("string").apply(lambda c: c.str.strip()) == "").any().any():
        raise ValueError("inventory contains a blank key")
    for column in QUANTITY_COLUMNS:
        df[column] = to_numeric(df[column], errors="raise")
        if (df[column] < 0).any():
            raise ValueError(f"inventory contains a negative {column}")


def update_inventory_table(
    engine_sql02: Engine,
    engine_sql04: Engine,
    engine_sql18: Engine,
    logger: DatabaseLogger,
) -> int | None:
    """Stage and atomically replace the current inventory snapshot."""

    with ThreadPoolExecutor(max_workers=2) as executor:
        nav_future = executor.submit(
            concurrent_df_load, engine_sql02, SELECTS_SQL02 / "inventory.sql",
            logger, "sql02 inventory"
        )
        llc_future = executor.submit(
            concurrent_df_load, engine_sql04, SELECTS_SQL04 / "inventory.sql",
            logger, "sql04 inventory"
        )
        try:
            df_nav, nav_error = nav_future.result()
            df_llc, llc_error = llc_future.result()
        except Exception as exc:  # noqa: BLE001
            logger.error(TABLE, "load inventory sources", str(exc))
            return None

    if nav_error is not None:
        logger.error(TABLE, "execute NAV inventory query", nav_error)
    if llc_error is not None:
        logger.error(TABLE, "execute LLC inventory query", llc_error)
    if nav_error is not None or llc_error is not None:
        return None

    assert df_nav is not None and df_llc is not None
    try:
        df = concat([df_nav, df_llc], ignore_index=True)
        _validate_inventory(df)
        rows = len(df)
        write_df_to_sql_db(
            engine_sql18,
            STAGING_TABLE,
            df,
            "replace",
            chunksize=min(rows, 20000),
            datatype={
                "entity": NVARCHAR(20),
                "item_id": NVARCHAR(20),
                **{column: DECIMAL(38, 20) for column in QUANTITY_COLUMNS},
            },
            schema="dbo",
        )
        _, error = execute_sql_procedure(
            engine_sql18, "EXEC [dbo].[update_inventory_table];"
        )
        if error is not None:
            raise RuntimeError(error)
        return rows
    except Exception as exc:  # noqa: BLE001
        try:
            with engine_sql18.begin() as connection:
                connection.exec_driver_sql(
                    "DROP TABLE IF EXISTS [dbo].[inventory_staging];"
                )
        except Exception:  # noqa: BLE001
            pass
        logger.error(TABLE, "validate and replace inventory data", str(exc))
        return None
