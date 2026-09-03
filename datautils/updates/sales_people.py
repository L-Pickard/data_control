from concurrent.futures import ThreadPoolExecutor

from sqlalchemy.engine import Engine
from sqlalchemy.dialects.mssql import BIT, NVARCHAR
from pandas import concat

from datautils.sql import execute_sql_procedure, write_df_to_sql_db
from datautils.utils import concurrent_df_load
from datautils.logging import DatabaseLogger
from datautils.constants import SELECTS_SQL02, SELECTS_SQL04


SALES_PEOPLE_DATATYPES = {
    "salesperson_id": NVARCHAR(20),
    "name": NVARCHAR(100),
    "email": NVARCHAR(100),
    "active": BIT(),
}


def update_sales_people_table(
    engine_sql02: Engine, engine_sql04: Engine, engine_sql18: Engine, logger: DatabaseLogger
) -> int | None:

    with ThreadPoolExecutor(max_workers=2) as executor:
        future_sql02 = executor.submit(
            concurrent_df_load,
            engine_sql02,
            SELECTS_SQL02 / "sales_people.sql",
            logger,
            "sql02 sales_people",
        )

        future_sql04 = executor.submit(
            concurrent_df_load,
            engine_sql04,
            SELECTS_SQL04 / "sales_people.sql",
            logger,
            "sql04 sales_people",
        )

        try:
            action = "load sql02/sql04 sales_people data concurrently"

            df_sql02, err_sql02 = future_sql02.result()
            df_sql04, err_sql04 = future_sql04.result()

        except Exception as e:
            logger.error(
                "sales_people",
                action,
                f"an error occurred. Error: {e}",
            )

            return None

    if err_sql02 is not None:
        action = "Execute sql02 sales_people query and return results as a dataframe."
        logger.error(
            "sales_people",
            action,
            err_sql02,
        )

    if err_sql04 is not None:
        action = "Execute sql04 sales_people query and return results as a dataframe."
        logger.error(
            "sales_people",
            action,
            err_sql04,
        )

    if err_sql02 is not None or err_sql04 is not None:
        return None

    # it's not actually possible for df_sql02 or df_sql04 to be returned as none without an error string being returned also.
    # I added the below to stop pylance moaning at me!

    assert df_sql02 is not None, "df_sql02 should not be None here"
    assert df_sql04 is not None, "df_sql04 should not be None here"

    action = "remove sales_people codes from df_sql04 where they exists in df_sql02"

    try:
        sales_people_codes_df_sql02 = set(df_sql02["salesperson_id"])

        df_sql04 = df_sql04[
            ~df_sql04["salesperson_id"].isin(sales_people_codes_df_sql02)
        ]

        df = concat([df_sql02, df_sql04], ignore_index=True)

        missing_name = df["name"].isna() | df["name"].astype("string").str.strip().eq(
            ""
        )
        df.loc[missing_name, "name"] = (
            df.loc[missing_name, "salesperson_id"].astype("string").str.title()
        )
        df["email"] = df["email"].fillna("")
        df["active"] = False

    except Exception as e:
        logger.error(
            "sales_people",
            action,
            f"an error occurred. Error: {e}",
        )

        return None

    rows = len(df)

    if rows == 0:
        action = "sales_people dataframe row length check"

        logger.error(
            "sales_people",
            action,
            "the dataframe has no rows of data",
            0,
        )

        return None
    action = "remove purchaser foreign key constraints and delete old sales_people data."

    execute_sql = """
	ALTER TABLE [dbo].[customers] NOCHECK CONSTRAINT [fk_customers_sales_people];
	IF EXISTS (
		SELECT 1 FROM sys.foreign_keys
		WHERE [name] = N'FK_vendors_sales_people'
			AND [parent_object_id] = OBJECT_ID(N'dbo.vendors')
	)
		ALTER TABLE [dbo].[vendors] NOCHECK CONSTRAINT [FK_vendors_sales_people];
	IF OBJECT_ID(N'dbo.sales_orders', N'U') IS NOT NULL
		ALTER TABLE [dbo].[sales_orders]
			NOCHECK CONSTRAINT [FK_sales_orders_sales_people];

    DELETE FROM [dbo].[sales_people];
    """

    try:
        _, err = execute_sql_procedure(engine_sql18, execute_sql)
        if err is not None:
            raise RuntimeError(err)
    except Exception as e:  # noqa: BLE001
        logger.error(
            "sales_people",
            action,
            f"an error has occcurred. ERROR: {e}",
        )

        return None

    action = "write new sales_people data to sql18 sales_people table"

    try:
        write_df_to_sql_db(
            engine_sql18,
            "sales_people",
            df,
            "append",
            rows,
            SALES_PEOPLE_DATATYPES,
        )
    except Exception as e:  # noqa: BLE001
        logger.error(
            "sales_people",
            action,
            f"an error has occurred: Error {e}",
        )

        return None

    action = "apply purchaser foreign key constraints for sales_people table."

    execute_sql = """
	IF OBJECT_ID(N'dbo.sales_orders', N'U') IS NOT NULL
		UPDATE so SET [salesperson_id] = NULL
		FROM [dbo].[sales_orders] AS so
		WHERE so.[salesperson_id] IS NOT NULL AND NOT EXISTS (
			SELECT 1 FROM [dbo].[sales_people] AS sp
			WHERE sp.[salesperson_id] = so.[salesperson_id]);
    ALTER TABLE [dbo].[customers] WITH CHECK CHECK CONSTRAINT [fk_customers_sales_people];
	IF EXISTS (
		SELECT 1 FROM sys.foreign_keys
		WHERE [name] = N'FK_vendors_sales_people'
			AND [parent_object_id] = OBJECT_ID(N'dbo.vendors')
	)
		ALTER TABLE [dbo].[vendors] WITH CHECK CHECK CONSTRAINT [FK_vendors_sales_people];
	IF OBJECT_ID(N'dbo.sales_orders', N'U') IS NOT NULL
		ALTER TABLE [dbo].[sales_orders] WITH CHECK
			CHECK CONSTRAINT [FK_sales_orders_sales_people];
    """

    try:
        _, err = execute_sql_procedure(engine_sql18, execute_sql)
        if err is not None:
            raise RuntimeError(err)
    except Exception as e:  # noqa: BLE001
        logger.error(
            "sales_people",
            action,
            f"unable to apply constraints. ERROR: {e}",
        )

        return None

    return rows
