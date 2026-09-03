from concurrent.futures import ThreadPoolExecutor

from pandas import DataFrame, concat, to_datetime
from sqlalchemy.dialects.mssql import DATETIME2, INTEGER, NVARCHAR, VARBINARY
from sqlalchemy.engine import Engine

from datautils.constants import SELECTS_SQL02, SELECTS_SQL04
from datautils.logging import DatabaseLogger
from datautils.sql import write_df_to_sql_db
from datautils.utils import concurrent_df_load


TABLE = "record_link"
STAGING_TABLE = "record_link_staging"
KEY_COLUMNS = ["entity", "system", "link_id"]
REQUIRED_COLUMNS = [
    *KEY_COLUMNS,
    "record_id",
    "type",
    "created",
    "modified",
]
EXPECTED_COLUMNS = [
    "entity",
    "system",
    "link_id",
    "record_id",
    "url",
    "description",
    "type",
    "created",
    "modified",
]
DATATYPES = {
    "entity": NVARCHAR(20),
    "system": NVARCHAR(10),
    "link_id": INTEGER(),
    "record_id": VARBINARY(448),
    "url": NVARCHAR(2048),
    "description": NVARCHAR(250),
    "type": INTEGER(),
    "created": DATETIME2(precision=0),
    "modified": DATETIME2(precision=0),
}


def _validate_record_links(df: DataFrame, valid_entities: set[str]) -> DataFrame:
    missing_columns = set(EXPECTED_COLUMNS).difference(df.columns)
    unexpected_columns = set(df.columns).difference(EXPECTED_COLUMNS)
    if missing_columns or unexpected_columns:
        raise ValueError(
            "record-link columns do not match the target table; "
            f"missing={sorted(missing_columns)}, "
            f"unexpected={sorted(unexpected_columns)}"
        )
    if df.empty:
        raise ValueError("the combined record-link queries returned no rows")
    if df[REQUIRED_COLUMNS].isna().any().any():
        raise ValueError("a required record-link column contains NULL")

    df = df.copy()
    df["entity"] = df["entity"].astype("string").str.strip()
    df["system"] = df["system"].astype("string").str.strip()
    df["record_id"] = df["record_id"].apply(
        lambda value: bytes(value)
        if isinstance(value, (bytes, bytearray, memoryview))
        else value
    )
    df["created"] = to_datetime(df["created"], errors="raise")
    df["modified"] = to_datetime(df["modified"], errors="raise")

    if df.duplicated(subset=KEY_COLUMNS).any():
        raise ValueError("the combined record-link source contains duplicate keys")
    if not set(df["entity"]).issubset(valid_entities):
        invalid = sorted(set(df["entity"]).difference(valid_entities))
        raise ValueError(f"record links contain unknown entities: {invalid}")
    if df["system"].eq("").any() or df["system"].str.len().gt(10).any():
        raise ValueError("a record-link system is blank or longer than 10 characters")
    if df["link_id"].le(0).any():
        raise ValueError("a record-link link_id is not positive")
    if not df["record_id"].map(lambda value: isinstance(value, bytes)).all():
        raise ValueError("a record-link record_id is not binary data")
    if df["record_id"].map(len).gt(448).any():
        raise ValueError("a record-link record_id exceeds 448 bytes")
    if df["url"].dropna().astype("string").str.len().gt(2048).any():
        raise ValueError("a record-link URL exceeds 2048 characters")
    if df["description"].dropna().astype("string").str.len().gt(250).any():
        raise ValueError("a record-link description exceeds 250 characters")
    if df["modified"].lt(df["created"]).any():
        raise ValueError("a record-link modified timestamp precedes its created timestamp")

    return df[EXPECTED_COLUMNS]


def _valid_entities(engine: Engine) -> set[str]:
    with engine.connect() as connection:
        result = connection.exec_driver_sql(
            "SELECT [entity] FROM [dbo].[entities];"
        )
        return {row[0] for row in result}


def update_record_link_table(
    engine_sql02: Engine,
    engine_sql04: Engine,
    engine_sql18: Engine,
    logger: DatabaseLogger,
) -> int | None:
    """Atomically replace record links from NAV and Business Central."""

    with ThreadPoolExecutor(max_workers=2) as executor:
        future_sql02 = executor.submit(
            concurrent_df_load,
            engine_sql02,
            SELECTS_SQL02 / "record_link.sql",
            logger,
            "sql02 record links",
        )
        future_sql04 = executor.submit(
            concurrent_df_load,
            engine_sql04,
            SELECTS_SQL04 / "record_link.sql",
            logger,
            "sql04 record links",
        )

        try:
            df_sql02, error_sql02 = future_sql02.result()
            df_sql04, error_sql04 = future_sql04.result()
        except Exception as exc:  # noqa: BLE001
            logger.error(TABLE, "load record-link sources", str(exc))
            return None

    if error_sql02 is not None:
        logger.error(TABLE, "read sql02 record links", error_sql02)
    if error_sql04 is not None:
        logger.error(TABLE, "read sql04 record links", error_sql04)
    if error_sql02 is not None or error_sql04 is not None:
        return None

    assert df_sql02 is not None, "df_sql02 should not be None without an error"
    assert df_sql04 is not None, "df_sql04 should not be None without an error"

    try:
        df = concat([df_sql02, df_sql04], ignore_index=True)
        df = _validate_record_links(df, _valid_entities(engine_sql18))
    except Exception as exc:  # noqa: BLE001
        logger.error(TABLE, "validate record links", str(exc))
        return None

    rows = len(df)

    try:
        write_df_to_sql_db(
            engine_sql18,
            STAGING_TABLE,
            df,
            "replace",
            chunksize=min(rows, 20000),
            datatype=DATATYPES,
        )

        with engine_sql18.begin() as connection:
            connection.exec_driver_sql("DELETE FROM [dbo].[record_link];")
            connection.exec_driver_sql(
                "INSERT INTO [dbo].[record_link] ("
                "[entity], [system], [link_id], [record_id], [url], "
                "[description], [type], [created], [modified]) "
                "SELECT [entity], [system], [link_id], [record_id], [url], "
                "[description], [type], [created], [modified] "
                "FROM [dbo].[record_link_staging];"
            )
            connection.exec_driver_sql(
                "DROP TABLE [dbo].[record_link_staging];"
            )
    except Exception as exc:  # noqa: BLE001
        try:
            with engine_sql18.begin() as connection:
                connection.exec_driver_sql(
                    "DROP TABLE IF EXISTS [dbo].[record_link_staging];"
                )
        except Exception:  # noqa: BLE001
            pass
        logger.error(TABLE, "replace record links", str(exc))
        return None

    return rows
