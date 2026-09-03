from concurrent.futures import ThreadPoolExecutor

from pandas import concat
from sqlalchemy.dialects.mssql import DATE, DECIMAL, NVARCHAR
from sqlalchemy.engine import Engine

from datautils.constants import SELECTS_SQL02, SELECTS_SQL04
from datautils.logging import DatabaseLogger
from datautils.sql import (
    execute_sql_procedure,
    get_sales_increment,
    write_df_to_sql_db,
)
from datautils.utils import concurrent_df_load_params

SALES_STAGING_CALCULATED_COLUMNS = (
    "royalty_value",
    "customer_rebate_value",
    "gbp_sales",
    "gbp_cost",
    "gbp_royalty",
    "gbp_rebate",
    "gbp_margin",
    "eur_sales",
    "eur_cost",
    "eur_royalty",
    "eur_rebate",
    "eur_margin",
    "usd_sales",
    "usd_cost",
    "usd_royalty",
    "usd_rebate",
    "usd_margin",
)


SALES_STAGING_DATATYPES = {
    "posting_date": DATE(),
    "document_date": DATE(),
    "location_code": NVARCHAR(10),
    "customer_id": NVARCHAR(20),
    "document_no": NVARCHAR(20),
    "order_no": NVARCHAR(20),
    "doc_type": NVARCHAR(5),
    "salesperson_id": NVARCHAR(20),
    "country_id": NVARCHAR(10),
    "entity": NVARCHAR(20),
    "item_id": NVARCHAR(20),
    "currency_code": NVARCHAR(10),
    "quantity": DECIMAL(38, 20),
    "sales": DECIMAL(38, 20),
    "cost": DECIMAL(38, 20),
    **{column: DECIMAL(38, 20) for column in SALES_STAGING_CALCULATED_COLUMNS},
}


def update_sales_table(
    engine_sql02: Engine, engine_sql04: Engine, engine_sql18: Engine, logger: DatabaseLogger
) -> int | None:

    try:
        action = "retrieve sales increment dates from entities table"

        start_date_ltd = get_sales_increment(engine_sql18, "Example Ltd")

        start_date_bv = get_sales_increment(engine_sql18, "Example BV")

        start_date_llc = get_sales_increment(engine_sql18, "Example LLC")

    except Exception as e:  # noqa: BLE001
        logger.error(  # noqa: PLE1205
            "sales",
            action,
            f"an error occurred. Error: {e}",
        )

        return None

    with ThreadPoolExecutor(max_workers=2) as executor:
        future_sql02 = executor.submit(
            concurrent_df_load_params,
            engine_sql02,
            SELECTS_SQL02 / "sales.sql",
            (start_date_ltd, start_date_bv),
            logger,
            "sql02 sales",
        )

        future_sql04 = executor.submit(
            concurrent_df_load_params,
            engine_sql04,
            SELECTS_SQL04 / "sales.sql",
            (start_date_llc,),
            logger,
            "sql04 sales",
        )

        try:
            action = "load sql02/sql04 sales data concurrently"

            df_sql02, err_sql02 = future_sql02.result()
            df_sql04, err_sql04 = future_sql04.result()

        except Exception as e:  # noqa: BLE001
            logger.error(  # noqa: PLE1205
                "sales",
                action,
                f"an error occurred. Error: {e}",
            )

            return None

    if err_sql02 is not None:
        action = "Execute sql02 sales query and return results as a dataframe."
        logger.error(  # noqa: PLE1205
            "sales",
            action,
            err_sql02,
        )

    if err_sql04 is not None:
        action = "Execute sql04 sales query and return results as a dataframe."
        logger.error(  # noqa: PLE1205
            "sales",
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
        action = "append sql02 sales data to sql04 sales data and return as new df"

        df = concat(
            [df_sql02, df_sql04],
            ignore_index=True,
        )

    except Exception as e:  # noqa: BLE001
        logger.error(  # noqa: PLE1205
            "sales",
            action,
            f"an error occurred. Error: {e}",
        )

        return None

    for column in SALES_STAGING_CALCULATED_COLUMNS:
        df[column] = None

    rows = len(df)

    if rows == 0:
        action = "sales dataframe row length check"

        logger.error(  # noqa: PLE1205
            "sales",
            action,
            "the dataframe has no rows of data",
            0,
        )

        return None

    action = "write new sales data to sql18 sales_staging table"

    try:
        write_df_to_sql_db(
            engine_sql18,
            "sales_staging",
            df,
            "replace",
            chunksize=rows,
            datatype=SALES_STAGING_DATATYPES,
        )
    except Exception as e:  # noqa: BLE001
        logger.error(  # noqa: PLE1205
            "sales",
            action,
            f"an error has occurred: Error {e}",
        )

        return None

    action = "execute update_sales_table stored procedure"

    _, err = execute_sql_procedure(
        engine_sql18,
        "EXEC [dbo].[update_sales_table];",
    )

    if err is not None:
        logger.error(  # noqa: PLE1205
            "sales",
            action,
            f"an error has occurred: Error {err}",
        )

        return None

    return rows
