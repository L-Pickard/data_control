from concurrent.futures import ThreadPoolExecutor

from sqlalchemy.engine import Engine
from pandas import concat

from datautils.sql import execute_sql_procedure, write_df_to_sql_db
from datautils.utils import concurrent_df_load
from datautils.logging import DatabaseLogger
from datautils.constants import PROJECT_ROOT, SELECTS_SQL02, SELECTS_SQL04


def update_exchange_rates_table(
    engine_sql02: Engine, engine_sql04: Engine, engine_sql18: Engine, logger: DatabaseLogger
) -> int | None:

    with ThreadPoolExecutor(max_workers=2) as executor:
        future_sql02 = executor.submit(
            concurrent_df_load,
            engine_sql02,
            SELECTS_SQL02 / "exchange_rates.sql",
            logger,
            "sql02 exchange_rates",
        )

        future_sql04 = executor.submit(
            concurrent_df_load,
            engine_sql04,
            SELECTS_SQL04 / "exchange_rates.sql",
            logger,
            "sql04 exchange_rates",
        )

    try:
        action = "load sql02/sql04 exchange rates data concurrently"

        df_sql02, err_sql02 = future_sql02.result()
        df_sql04, err_sql04 = future_sql04.result()

    except Exception as e:
        logger.error(
            "exchange_rates",
            action,
            f"an error occurred. Error: {e}",
        )

        return None

    if err_sql02 is not None:
        action = "read in and execute sql02 exchange_rates query and return results as a dataframe."
        logger.error(
            "exchange_rates",
            action,
            err_sql02,
        )

    if err_sql04 is not None:
        action = "read in and execute sql04 exchange_rates query and return results as a dataframe."
        logger.error(
            "exchange_rates",
            action,
            err_sql04,
        )

    if err_sql02 is not None or err_sql04 is not None:
        return None

    # it's not actually possible for df_sql04 or df_sql05 to be returned as none without an error string being returned also.
    # I added the below to stop pylance moaning at me!

    assert df_sql02 is not None, "df_sql02 should not be None here"
    assert df_sql04 is not None, "df_sql04 should not be None here"

    action = "combine exchange_rates dataframes from sql02 and sql04"

    try:
        df = concat([df_sql02, df_sql04], ignore_index=True)

    except Exception as e:
        logger.error(
            "exchange_rates",
            action,
            f"an error occurred. Error: {e}",
        )

        return None

    rows = len(df)

    if rows == 0:
        action = "exchange_rates dataframe row length check"

        logger.error(
            "exchange_rates",
            action,
            "the dataframe has no rows of data",
            0,
        )

        return None

    action = "recreate sql18 exchange_rates table"

    table_definition_path = PROJECT_ROOT / "sql" / "tables" / "exchange_rates.sql"

    try:
        table_definition_sql = table_definition_path.read_text(encoding="utf-8")
        header_lines = {
            "USE [DATA_CONTROL]",
            "SET ANSI_NULLS ON",
            "SET QUOTED_IDENTIFIER ON",
            "GO",
        }
        table_definition_sql = "\n".join(
            line
            for line in table_definition_sql.splitlines()
            if line.strip().upper() not in header_lines
        )

        _, err = execute_sql_procedure(engine_sql18, table_definition_sql)
        if err is not None:
            raise RuntimeError(err)

    except Exception as e:
        logger.error(
            "exchange_rates",
            action,
            f"an error has occurred. Error {e}",
        )

        return None

    action = "write new exchange_rates data to sql18 exchange_rates table"

    try:
        write_df_to_sql_db(
            engine_sql18,
            "exchange_rates",
            df,
            "append",
            chunksize=rows,
        )
    except Exception as e:  # noqa: BLE001
        logger.error(
            "exchange_rates",
            action,
            f"an error has occurred: Error {e}",
        )

        return None

    return rows
