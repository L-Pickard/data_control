from concurrent.futures import ThreadPoolExecutor

from pandas import concat, merge, read_csv
from sqlalchemy.engine import Engine

from shinerutils.constants import DOCUMENTS, SELECTS_SQL04, SELECTS_SQL05
from shinerutils.logging import DatabaseLogger
from shinerutils.updates.dimensions import upsert_dimension
from shinerutils.utils import concurrent_df_load


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
            table="countries",
            action=action,
            message=f"an error occurred. Error: {e}",
        )

        return None

    if err_sql04 is not None:
        action = "read in and execute sql04 countries query and return results as a dataframe."
        logger.error(
            table="countries",
            action=action,
            message=err_sql04,
        )

    if err_sql05 is not None:
        action = "read in and execute sql05 countries query and return results as a dataframe."
        logger.error(
            table="countries",
            action=action,
            message=err_sql05,
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
            table="countries",
            action=action,
            message=f"an error occurred. Error: {e}",
        )

        return None

    rows = len(df)

    if rows == 0:
        action = "countries dataframe row length check"

        logger.error(
            table="countries",
            action=action,
            message="the dataframe has no rows of data",
            rows=0,
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
            table="countries",
            action=action,
            message=f"an error occurred. Error: {e}",
        )

        return None

    action = "atomically update and insert countries while preserving referenced codes"
    try:
        upsert_dimension(engine_sql18, "countries", df)
    except Exception as e:  # noqa: BLE001
        logger.error(
            table="countries", action=action,
            message=f"dimension update failed: {e}",
        )
        return None

    return rows
