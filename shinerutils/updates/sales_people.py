from concurrent.futures import ThreadPoolExecutor

from sqlalchemy.engine import Engine
from pandas import concat

from shinerutils.updates.dimensions import upsert_dimension
from shinerutils.utils import concurrent_df_load
from shinerutils.logging import DatabaseLogger
from shinerutils.constants import SELECTS_SQL02, SELECTS_SQL04


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

        except Exception as e:  # noqa: BLE001
            logger.error(
                table="sales_people",
                action=action,
                message=f"an error occurred. Error: {e}",
            )

            return None

    if err_sql02 is not None:
        action = "Execute sql02 sales_people query and return results as a dataframe."
        logger.error(
            table="sales_people",
            action=action,
            message=err_sql02,
        )

    if err_sql04 is not None:
        action = "Execute sql04 sales_people query and return results as a dataframe."
        logger.error(
            table="sales_people",
            action=action,
            message=err_sql04,
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

    except Exception as e:  # noqa: BLE001
        logger.error(
            table="sales_people",
            action=action,
            message=f"an error occurred. Error: {e}",
        )

        return None

    rows = len(df)

    if rows == 0:
        action = "sales_people dataframe row length check"

        logger.error(
            table="sales_people",
            action=action,
            message="the dataframe has no rows of data",
            rows=0,
        )

        return None
    action = "atomically update and insert sales_people while preserving referenced codes"
    try:
        upsert_dimension(engine_sql18, "sales_people", df)
    except Exception as e:  # noqa: BLE001
        logger.error(
            table="sales_people", action=action,
            message=f"dimension update failed: {e}",
        )
        return None

    return rows
