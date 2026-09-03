from concurrent.futures import ThreadPoolExecutor

from pandas import concat
from sqlalchemy.engine import Engine

from datautils.constants import SELECTS_SQL02, SELECTS_SQL04
from datautils.logging import DatabaseLogger
from datautils.sql import write_df_to_sql_db
from datautils.utils import concurrent_df_load


def update_vendors_table(
    engine_sql02: Engine, engine_sql04: Engine, engine_sql18: Engine, logger: DatabaseLogger
) -> int | None:
    """Replace the warehouse vendor dimension from the NAV and BC sources."""

    with ThreadPoolExecutor(max_workers=2) as executor:
        future_sql02 = executor.submit(
            concurrent_df_load,
            engine_sql02,
            SELECTS_SQL02 / "vendors.sql",
            logger,
            "sql02 vendors",
        )
        future_sql04 = executor.submit(
            concurrent_df_load,
            engine_sql04,
            SELECTS_SQL04 / "vendors.sql",
            logger,
            "sql04 vendors",
        )

        try:
            action = "load sql02/sql04 vendor data concurrently"
            df_sql02, err_sql02 = future_sql02.result()
            df_sql04, err_sql04 = future_sql04.result()
        except Exception as exc:  # noqa: BLE001
            logger.error("vendors", action, f"an error occurred. Error: {exc}")
            return None

    if err_sql02 is not None:
        logger.error("vendors", "execute sql02 vendors query", err_sql02)
    if err_sql04 is not None:
        logger.error("vendors", "execute sql04 vendors query", err_sql04)
    if err_sql02 is not None or err_sql04 is not None:
        return None

    assert df_sql02 is not None, "df_sql02 should not be None here"
    assert df_sql04 is not None, "df_sql04 should not be None here"

    try:
        action = "combine and clean vendor dataframes"
        df = concat([df_sql02, df_sql04], ignore_index=True)
        df = df.drop_duplicates(subset=["vendor_id"], keep="first")

        vendor_ids = set(df["vendor_id"].dropna())
        df.loc[~df["pay_to_vendor_id"].isin(vendor_ids), "pay_to_vendor_id"] = None
    except Exception as exc:  # noqa: BLE001
        logger.error("vendors", action, f"an error occurred. Error: {exc}")
        return None

    rows = len(df)
    if rows == 0:
        logger.error(
            "vendors",
            "vendors dataframe row length check",
            "the dataframe has no rows of data",
            0,
        )
        return None

    try:
        action = "replace sql18 vendors data"

        with engine_sql18.begin() as connection:
            connection.exec_driver_sql(
                "ALTER TABLE [dbo].[purchase_orders] "
                "NOCHECK CONSTRAINT [FK_purchase_orders_vendors];"
            )
            connection.exec_driver_sql(
                "ALTER TABLE [dbo].[vendors] "
                "NOCHECK CONSTRAINT [FK_vendors_pay_to_vendor];"
            )
            connection.exec_driver_sql("DELETE FROM [dbo].[vendors];")
            write_df_to_sql_db(
                connection,
                "vendors",
                df,
                "append",
                chunksize=rows,
            )
            connection.exec_driver_sql(
                "UPDATE po SET [vendor_id] = NULL "
                "FROM [dbo].[purchase_orders] AS po "
                "WHERE po.[vendor_id] IS NOT NULL AND NOT EXISTS ("
                "SELECT 1 FROM [dbo].[vendors] AS v "
                "WHERE v.[vendor_id] = po.[vendor_id]);"
            )
            connection.exec_driver_sql(
                "ALTER TABLE [dbo].[vendors] WITH CHECK "
                "CHECK CONSTRAINT [FK_vendors_pay_to_vendor];"
            )
            connection.exec_driver_sql(
                "ALTER TABLE [dbo].[purchase_orders] WITH CHECK "
                "CHECK CONSTRAINT [FK_purchase_orders_vendors];"
            )
    except Exception as exc:  # noqa: BLE001
        logger.error("vendors", action, f"an error has occurred: Error {exc}")
        return None

    return rows
