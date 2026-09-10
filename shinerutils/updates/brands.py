"""
========================================================================================================================
Project:  Data Control Data Warehouse
Language: Python
Author:   Leo Pickard
Version:  1.0
Date:     28/05/2026
========================================================================================================================
This module updates the brands table by loading brand data from shinersql02, joining it to static brand group data,
writing the result to a staging table, and executing the update_brands_table stored procedure.
========================================================================================================================
"""

from pandas import merge, read_csv
from sqlalchemy.dialects.mssql import NVARCHAR
from sqlalchemy.engine import Engine

from shinerutils.constants import DOCUMENTS, SELECTS_SQL02
from shinerutils.logging import DatabaseLogger
from shinerutils.sql import (
    execute_sql_procedure,
    fetch_sql_dataframe,
    write_df_to_sql_db,
)

OPTIONAL_TEXT_COLUMNS = (
    "brand_name",
    "buying_category",
    "brand_group",
    "revenue_group",
)


def normalize_optional_brand_text(df):
    """Trim optional brand attributes and preserve missing values as NULL."""

    for column in OPTIONAL_TEXT_COLUMNS:
        values = df[column].astype("string").str.strip()
        df[column] = values.mask(values == "", None)
    return df


def update_brands_table(
    engine_sql02: Engine, engine_sql18: Engine, logger: DatabaseLogger
) -> int | None:

    query_path = SELECTS_SQL02 / "brands.sql"

    action = f"read in shinersql02 query file: {query_path.resolve()}"

    try:
        query = query_path.read_text(encoding="utf-8")

    except (OSError, UnicodeError) as e:
        logger.error(
            table="brands",
            action=action,
            message=f"error reading query file. ERROR: {str(e)}",
        )

        return None

    logger.info(
        table="brands",
        action=action,
        message="shinersql02 brands query file read successfully",
    )

    action = "execute shinersql02 brand table query against db"

    df, err = fetch_sql_dataframe(engine_sql02, query)

    if err is not None:
        logger.error(
            table="brands",
            action=action,
            message=f"error executing query. ERROR: {err}",
        )

        return None

    if df is None:
        logger.error(
            table="brands",
            action=action,
            message="ERROR: the dataframe returned is none.",
        )

        return None

    brand_groups_path = DOCUMENTS / "brand_groups.csv"

    try:
        action = (
            f"read csv file into pandas dataframe. File: {brand_groups_path.resolve()}"
        )

        df_brand_groups = read_csv(brand_groups_path)

        action = (
            "perform a left join to brand groups dataframe from main brands dataframe"
        )

        df = merge(
            df, df_brand_groups, on="brand_id", how="left", validate="one_to_one"
        )

        df = normalize_optional_brand_text(df)

    except Exception as e:  # noqa: BLE001
        logger.error(
            table="brands",
            action=action,
            message=f"error joining dataframes. ERROR: {str(e)}",
        )

        return None

    action = "write brand staging table to database"

    rows = len(df)

    if rows == 0:
        logger.error(
            table="brands",
            action=action,
            message="dataframe contains no rows of data",
        )

        return None

    brand_staging_datatypes = {
        "brand_id": NVARCHAR(20),
        "brand_name": NVARCHAR(100),
        "buying_category": NVARCHAR(100),
        "brand_group": NVARCHAR(100),
        "revenue_group": NVARCHAR(100),
    }

    try:
        write_df_to_sql_db(
            engine_sql18,
            "brands_staging",
            df,
            "replace",
            datatype=brand_staging_datatypes,
        )
    except Exception as e:  # noqa: BLE001
        logger.error(
            table="brands",
            action=action,
            message=f"error writing table. ERROR: {e}",
        )

        return None

    logger.info(
        table="brands",
        action=action,
        message="successfully written data to database brand staging table",
        rows=rows,
    )

    action = "execute update_brands_table stored procedure"

    try:
        _, err = execute_sql_procedure(
            engine_sql18, "EXEC [dbo].[update_brands_table];"
        )
        if err is not None:
            raise RuntimeError(err)
    except Exception as e:  # noqa: BLE001
        logger.error(
            table="brands",
            action=action,
            message=f"error executing query. ERROR: {e}",
        )

        return None

    logger.info(
        table="brands",
        action=action,
        message="successfully executed stored procedure",
        rows=rows,
    )

    return rows
