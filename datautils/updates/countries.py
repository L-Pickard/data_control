from concurrent.futures import ThreadPoolExecutor

from sqlalchemy.engine import Engine
from pandas import concat, read_csv, merge

from datautils.sql import execute_sql_procedure, write_df_to_sql_db
from datautils.utils import concurrent_df_load
from datautils.logging import DatabaseLogger
from datautils.constants import SELECTS_SQL04, SELECTS_SQL05, DOCUMENTS


def update_countries_table(
    engine_sql04: Engine, engine_sql05: Engine, engine_sql18: Engine, logger: DatabaseLogger
) -> int | None:

    with ThreadPoolExecutor(max_workers=2) as executor:
        future_sql04 = executor.submit(
            concurrent_df_load,
            engine_sql04,
            SELECTS_SQL04 / "countries.sql",
            logger,
            "sql04 countries",
        )

        future_sql05 = executor.submit(
            concurrent_df_load,
            engine_sql05,
            SELECTS_SQL05 / "countries.sql",
            logger,
            "sql05 countries",
        )

    try:

        action = "load sql04/sql05 countries data concurrently"

        df_sql04, err_sql04 = future_sql04.result()
        df_sql05, err_sql05 = future_sql05.result()

    except Exception as e:

        logger.error(
            "countries",
            action,
            f"an error occurred. Error: {e}",
        )

        return None

    if err_sql04 is not None:
        action = "read in and execute sql04 countries query and return results as a dataframe."
        logger.error(
            "countries",
            action,
            err_sql04,
        )

    if err_sql05 is not None:
        action = "read in and execute sql05 countries query and return results as a dataframe."
        logger.error(
            "countries",
            action,
            err_sql05,
        )

    if err_sql04 is not None or err_sql05 is not None:
        return None

    # it's not actually possible for df_sql04 or df_sql05 to be returned as none without an error string being returned also.
    # I added the below to stop pylance moaning at me!

    assert df_sql04 is not None, "df_sql04 should not be None here"
    assert df_sql05 is not None, "df_sql05 should not be None here"

    action = "remove country codes from df_sql04 where they exists in df_sql05"

    try:
        country_codes_df_sql05 = set(df_sql05["country_id"])

        df_sql04 = df_sql04[~df_sql04["country_id"].isin(country_codes_df_sql05)]

        df = concat([df_sql04, df_sql05], ignore_index=True)

    except Exception as e:
        logger.error(
            "countries",
            action,
            f"an error occurred. Error: {e}",
        )

        return None

    rows = len(df)

    if rows == 0:
        action = "countries dataframe row length check"

        logger.error(
            "countries",
            action,
            "the dataframe has no rows of data",
            0,
        )

        return None

    try:

        flag_csv_path = DOCUMENTS / "country_flags.csv"

        action = f"read in {flag_csv_path.resolve()} file to a pandas dataframe"

        df_flag_urls = read_csv(flag_csv_path)

        action = "perform a left join to flag url dataframe from main country dataframe"

        df = merge(df, df_flag_urls, on="country_id", how="left")

    except Exception as e:

        logger.error(
            "countries",
            action,
            f"an error occurred. Error: {e}",
        )

        return None

    action = "remove country foreign key constraints and delete old countries data."

    execute_sql = """
    ALTER TABLE [dbo].[customers] NOCHECK CONSTRAINT [fk_customers_countries];
	IF EXISTS (
		SELECT 1 FROM sys.foreign_keys
		WHERE [name] = N'FK_vendors_countries'
			AND [parent_object_id] = OBJECT_ID(N'dbo.vendors')
	)
		ALTER TABLE [dbo].[vendors] NOCHECK CONSTRAINT [FK_vendors_countries];
	IF OBJECT_ID(N'dbo.sales_orders', N'U') IS NOT NULL
		ALTER TABLE [dbo].[sales_orders] NOCHECK CONSTRAINT
			[FK_sales_orders_ship_to_countries], [FK_sales_orders_vat_countries];

    DELETE FROM [dbo].[countries];
    """

    try:
        _, err = execute_sql_procedure(engine_sql18, execute_sql)
        if err is not None:
            raise RuntimeError(err)
    except Exception as e:  # noqa: BLE001
        logger.error(
            "countries",
            action,
            f"an error has occurred. ERROR: {e}",
        )

        return None

    action = "write new countries data to sql18 countries table"

    try:
        write_df_to_sql_db(engine_sql18, "countries", df, "append", rows)
    except Exception as e:  # noqa: BLE001
        logger.error(
            "countries",
            action,
            f"an error has occurred: Error {e}",
        )

        return None

    action = "apply country foreign key constraints for countries table."

    execute_sql = """
	IF OBJECT_ID(N'dbo.sales_orders', N'U') IS NOT NULL
	BEGIN
		UPDATE so SET [ship_to_country_id] = NULL
		FROM [dbo].[sales_orders] AS so
		WHERE so.[ship_to_country_id] IS NOT NULL AND NOT EXISTS (
			SELECT 1 FROM [dbo].[countries] AS c
			WHERE c.[country_id] = so.[ship_to_country_id]);
		UPDATE so SET [vat_country_id] = NULL
		FROM [dbo].[sales_orders] AS so
		WHERE so.[vat_country_id] IS NOT NULL AND NOT EXISTS (
			SELECT 1 FROM [dbo].[countries] AS c
			WHERE c.[country_id] = so.[vat_country_id]);
	END;
    ALTER TABLE [dbo].[customers] WITH CHECK CHECK CONSTRAINT [fk_customers_countries];
	IF EXISTS (
		SELECT 1 FROM sys.foreign_keys
		WHERE [name] = N'FK_vendors_countries'
			AND [parent_object_id] = OBJECT_ID(N'dbo.vendors')
	)
		ALTER TABLE [dbo].[vendors] WITH CHECK CHECK CONSTRAINT [FK_vendors_countries];
	IF OBJECT_ID(N'dbo.sales_orders', N'U') IS NOT NULL
		ALTER TABLE [dbo].[sales_orders] WITH CHECK CHECK CONSTRAINT
			[FK_sales_orders_ship_to_countries], [FK_sales_orders_vat_countries];
    """

    try:
        _, err = execute_sql_procedure(engine_sql18, execute_sql)
        if err is not None:
            raise RuntimeError(err)
    except Exception as e:  # noqa: BLE001
        logger.error(
            "countries",
            action,
            f"unable to apply constraints. ERROR: {e}",
        )

        return None

    return rows
