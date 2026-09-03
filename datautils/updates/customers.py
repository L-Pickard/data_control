from concurrent.futures import ThreadPoolExecutor

from sqlalchemy.engine import Engine
from pandas import concat

from datautils.sql import write_df_to_sql_db
from datautils.utils import concurrent_df_load
from datautils.logging import DatabaseLogger
from datautils.constants import SELECTS_SQL02, SELECTS_SQL04


def update_customers_table(
    engine_sql02: Engine, engine_sql04: Engine, engine_sql18: Engine, logger: DatabaseLogger
) -> int | None:

    with ThreadPoolExecutor(max_workers=2) as executor:
        future_sql02 = executor.submit(
            concurrent_df_load,
            engine_sql02,
            SELECTS_SQL02 / "customers.sql",
            logger,
            "sql02 customers",
        )

        future_sql04 = executor.submit(
            concurrent_df_load,
            engine_sql04,
            SELECTS_SQL04 / "customers.sql",
            logger,
            "sql04 customers",
        )

        try:

            action = "load sql02/sql04 customers data concurrently"

            df_sql02, err_sql02 = future_sql02.result()
            df_sql04, err_sql04 = future_sql04.result()

        except Exception as e:

            logger.error(
                "customers",
                action,
                f"an error occurred. Error: {e}",
            )

            return None

    if err_sql02 is not None:
        action = "Execute sql02 customers query and return results as a dataframe."
        logger.error(
            "customers",
            action,
            err_sql02,
        )

    if err_sql04 is not None:
        action = "Execute sql04 customers query and return results as a dataframe."
        logger.error(
            "customers",
            action,
            err_sql04,
        )

    if err_sql02 is not None or err_sql04 is not None:
        return None

    # it's not actually possible for df_sql02 or df_sql04 to be returned as none without an error string being returned also.
    # I added the below to stop pylance moaning at me!

    assert df_sql02 is not None, "df_sql02 should not be None here"
    assert df_sql04 is not None, "df_sql04 should not be None here"

    try:

        action = "append sql04 customer data to sql02 customer data and return as new df"

        df = concat([df_sql02, df_sql04], ignore_index=True)
        df = df.drop_duplicates(subset=["customer_id"], keep="first")

        customer_ids = set(df["customer_id"].dropna())
        df.loc[
            ~df["bill_to_customer_id"].isin(customer_ids), "bill_to_customer_id"
        ] = None

    except Exception as e:

        logger.error(
            "customers",
            action,
            f"an error occurred. Error: {e}",
        )

        return None

    rows = len(df)

    if rows == 0:

        action = "customers dataframe row length check"

        logger.error(
            "customers",
            action,
            "the dataframe has no rows of data",
            0,
        )

        return None
    
    action = "atomically replace sql18 customers data"

    try:
        with engine_sql18.begin() as connection:
            connection.exec_driver_sql(
                "ALTER TABLE [dbo].[sales] "
                "NOCHECK CONSTRAINT [FK_sales_customers];"
            )
            connection.exec_driver_sql(
                "ALTER TABLE [dbo].[customers] "
                "NOCHECK CONSTRAINT [FK_customers_bill_to_customer];"
            )
            connection.exec_driver_sql(
                "IF OBJECT_ID(N'dbo.sales_orders', N'U') IS NOT NULL "
                "ALTER TABLE [dbo].[sales_orders] NOCHECK CONSTRAINT "
                "[FK_sales_orders_sell_to_customers], "
                "[FK_sales_orders_bill_to_customers];"
            )
            connection.exec_driver_sql("DELETE FROM [dbo].[customers];")
            write_df_to_sql_db(connection, "customers", df, "append", rows)
            connection.exec_driver_sql(
                "INSERT INTO [dbo].[customers] ([customer_id]) "
                "SELECT DISTINCT s.[customer_id] FROM [dbo].[sales] AS s "
                "WHERE NOT EXISTS ("
                "SELECT 1 FROM [dbo].[customers] AS c "
                "WHERE c.[customer_id] = s.[customer_id]);"
            )
            connection.exec_driver_sql(
                "IF OBJECT_ID(N'dbo.sales_orders', N'U') IS NOT NULL "
                "INSERT INTO [dbo].[customers] ([customer_id]) "
                "SELECT refs.[customer_id] FROM ("
                "SELECT so.[sell_to_customer_id] AS [customer_id] "
                "FROM [dbo].[sales_orders] AS so UNION "
                "SELECT so.[bill_to_customer_id] FROM [dbo].[sales_orders] AS so"
                ") AS refs WHERE NOT EXISTS ("
                "SELECT 1 FROM [dbo].[customers] AS c "
                "WHERE c.[customer_id] = refs.[customer_id]);"
            )
            connection.exec_driver_sql(
                "ALTER TABLE [dbo].[customers] WITH CHECK "
                "CHECK CONSTRAINT [FK_customers_bill_to_customer];"
            )
            connection.exec_driver_sql(
                "ALTER TABLE [dbo].[sales] WITH CHECK "
                "CHECK CONSTRAINT [FK_sales_customers];"
            )
            connection.exec_driver_sql(
                "IF OBJECT_ID(N'dbo.sales_orders', N'U') IS NOT NULL "
                "ALTER TABLE [dbo].[sales_orders] WITH CHECK CHECK CONSTRAINT "
                "[FK_sales_orders_sell_to_customers], "
                "[FK_sales_orders_bill_to_customers];"
            )
    except Exception as e:  # noqa: BLE001
        logger.error(
            "customers",
            action,
            f"an error has occurred: Error {e}",
        )

        return None

    return rows
