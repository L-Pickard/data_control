from concurrent.futures import ThreadPoolExecutor

from pandas import DataFrame, isna, merge
from sqlalchemy.dialects.mssql import DECIMAL, VARBINARY
from sqlalchemy.engine import Engine

from datautils.constants import SELECTS_SQL02, SELECTS_SQL04
from datautils.logging import DatabaseLogger
from datautils.sql import execute_sql_procedure, write_df_to_sql_db
from datautils.utils import concurrent_df_load


def clean_varbinary(value):
    if isinstance(value, (bytes, bytearray)):
        return bytes(value)

    if isna(value) or value == "":
        return None

    return None


def clean_items_df(df) -> DataFrame:
    text_defaults = [
        "item_id",
        "vendor_reference",
        "brand_id",
        "description",
        "description_2",
        "colours",
        "size_1",
        "size_1_unit",
        "eu_size",
        "eu_size_unit",
        "us_size",
        "us_size_unit",
        "season",
        "item_info",
        "category_code",
        "group_code",
        "ean_barcode",
        "tariff_no",
        "hts_no",
        "uk_eu_vendor_no",
        "us_vendor_no",
        "coo",
        "unit_of_measure",
        "d2c_master_sku",
        "d2c_web_item",
    ]

    numeric_defaults = [
        "gbp_cost",
        "gbp_trade",
        "gbp_srp",
        "eur_cost",
        "eur_trade",
        "eur_srp",
        "usd_cost",
        "usd_trade",
        "usd_srp",
        "royalty",
        "ltd_buffer_stock",
        "bv_buffer_stock",
    ]

    bit_defaults = [
        "ltd_blocked",
        "bv_blocked",
        "llc_blocked",
        "pref_sale",
        "hot_product",
        "bread_butter",
        "owtanet_export",
        "web_item",
    ]

    integer_defaults = [
        "lead_time_days",
    ]

    for col in text_defaults:
        if col in df.columns:
            df[col] = df[col].fillna("")

    if "common_item_no" in df.columns:
        common_item_no = df["common_item_no"].astype("string").str.strip()
        df["common_item_no"] = common_item_no.mask(common_item_no == "", None)

    for col in numeric_defaults:
        if col in df.columns:
            df[col] = df[col].fillna(0)

    for col in bit_defaults:
        if col in df.columns:
            df[col] = df[col].fillna(0).astype(bool)

    for col in integer_defaults:
        if col in df.columns:
            df[col] = df[col].fillna(0).astype(int)

    if "record_id" in df.columns:
        df["record_id"] = df["record_id"].apply(
            lambda x: bytes(x) if isinstance(x, (bytes, bytearray)) else None
        )

    return df


def update_items_table(
    engine_sql02: Engine, engine_sql04: Engine, engine_sql18: Engine, logger: DatabaseLogger
) -> int | None:

    with ThreadPoolExecutor(max_workers=2) as executor:
        future_sql02 = executor.submit(
            concurrent_df_load,
            engine_sql02,
            SELECTS_SQL02 / "items.sql",
            logger,
            "sql02 items",
        )

        future_sql04 = executor.submit(
            concurrent_df_load,
            engine_sql04,
            SELECTS_SQL04 / "items.sql",
            logger,
            "sql04 items",
        )

    try:
        action = "load sql02/sql04 countries data concurrently"

        df_sql02, err_sql02 = future_sql02.result()
        df_sql04, err_sql04 = future_sql04.result()

    except Exception as e:  # noqa: BLE001
        logger.error(
            "items",
            action,
            f"an error occurred. Error: {e}",
        )

        return None

    if err_sql02 is not None:
        action = (
            "read in and execute sql02 items query and return results as a dataframe"
        )
        logger.error(
            "items",
            action,
            err_sql02,
        )

    if err_sql04 is not None:
        action = (
            "read in and execute sql04 items query and return results as a dataframe"
        )
        logger.error(
            "items",
            action,
            err_sql04,
        )

    if err_sql02 is not None or err_sql04 is not None:
        return None

    # it's not actually possible for df_sql04 or df_sql05 to be returned as none without an error string being returned also.
    # I added the below to stop pylance moaning at me!

    assert df_sql02 is not None, "df_sql02 should not be None here"
    assert df_sql04 is not None, "df_sql04 should not be None here"

    action = "combine item dataframes from sql02 and sql04"

    try:
        df = merge(
            df_sql02,
            df_sql04,
            on="item_id",
            how="outer",
            suffixes=("", "_sql04"),
        )

        for col in df_sql04.columns:
            if col == "item_id":
                continue

            sql04_col = f"{col}_sql04"

            if sql04_col in df.columns:
                df[col] = df[col].combine_first(df[sql04_col])
                df = df.drop(columns=[sql04_col])

    except Exception as e:
        logger.error(
            "items",
            action,
            f"an error occurred. Error: {e}",
        )
        return None

    rows = len(df)

    if rows == 0:
        action = "items dataframe row length check"

        logger.error(
            "items",
            action,
            "the dataframe has no rows of data",
            0,
        )

        return None

    df = clean_items_df(df)
    df_items = df.drop(columns=["brand_id"])
    df_items["is_placeholder"] = False

    action = "stage and atomically replace sql18 items data"

    try:
        write_df_to_sql_db(
            engine_sql18,
            "items_staging",
            df_items,
            "replace",
            chunksize=20000,
            datatype={"record_id": VARBINARY(60), "royalty": DECIMAL(38, 20)},
            schema="dbo",
        )
        _, error = execute_sql_procedure(
            engine_sql18,
            "EXEC [dbo].[update_items_table];",
        )
        if error is not None:
            raise RuntimeError(error)
    except Exception as e:  # noqa: BLE001
        try:
            with engine_sql18.begin() as connection:
                connection.exec_driver_sql(
                    "DROP TABLE IF EXISTS [dbo].[items_staging];"
                )
        except Exception:  # noqa: BLE001, S110
            pass
        logger.error(
            "items",
            action,
            f"an error has occurred: Error {e}",
        )

        return None

    return rows
