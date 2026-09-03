from pathlib import Path

from pandas import DataFrame, read_csv, to_datetime
from sqlalchemy.dialects.mssql import DATE, INTEGER, NCHAR, NVARCHAR, SMALLINT, TINYINT
from sqlalchemy.engine import Engine

from datautils.constants import DOCUMENTS
from datautils.logging import DatabaseLogger
from datautils.sql import execute_sql_procedure, write_df_to_sql_db


TABLE = "dates"
CSV_PATH = DOCUMENTS / "dates_import.csv"
STAGING_TABLE = "dates_staging"

COLUMN_RENAMES = {
    "date": "calendar_date",
    "day": "day_of_month",
    "year": "calendar_year",
    "month_no": "calendar_month_no",
    "month_&_year": "calendar_month_year",
    "year_&_month_no": "calendar_year_month_no",
    "month_start": "calendar_month_start",
    "month_end": "calendar_month_end",
    "quarter": "calendar_quarter",
    "quarter_full": "calendar_quarter_name",
    "year_week": "iso_year_week",
    "financial_year_short": "financial_year_no",
    "financial_year_long": "financial_year_short",
    "financial_year_full": "financial_year_name",
    "day_of_financial Year": "day_of_financial_year",
    "days_remaining_in_financial_Year": "days_remaining_in_financial_year",
    "financial_quarter_full": "financial_quarter_name",
    "financial_quarter_&_year": "financial_quarter_year",
    "month_abbreviation_&_year": "month_abbreviation_year",
    "month_name_&_financial_year": "month_financial_year",
    "financial_month_&_year": "financial_month_year_no",
}

DATE_COLUMNS = (
    "calendar_date",
    "calendar_month_start",
    "calendar_month_end",
    "calendar_quarter_start",
    "calendar_quarter_end",
    "financial_year_start",
    "financial_year_end",
    "financial_quarter_start",
    "financial_quarter_end",
    "financial_month_start",
    "financial_month_end",
)

STAGING_DATATYPES = {
    "calendar_date": DATE(),
    "day_of_month": TINYINT(),
    "day_of_week": TINYINT(),
    "day_of_year": SMALLINT(),
    "day_name": NVARCHAR(9),
    "day_name_abbreviation": NCHAR(3),
    "week_of_year": TINYINT(),
    "week_of_month": TINYINT(),
    "calendar_year": SMALLINT(),
    "calendar_month_no": TINYINT(),
    "calendar_month_year": NVARCHAR(8),
    "calendar_year_month_no": INTEGER(),
    "calendar_month_start": DATE(),
    "calendar_month_end": DATE(),
    "calendar_quarter": TINYINT(),
    "calendar_quarter_name": NCHAR(2),
    "calendar_quarter_start": DATE(),
    "calendar_quarter_end": DATE(),
    "iso_year": SMALLINT(),
    "iso_week_no": TINYINT(),
    "iso_year_week": NCHAR(8),
    "financial_year_no": SMALLINT(),
    "financial_year_short": NCHAR(5),
    "financial_year_name": NVARCHAR(8),
    "financial_year_start": DATE(),
    "financial_year_end": DATE(),
    "financial_year_day_count": SMALLINT(),
    "day_of_financial_year": SMALLINT(),
    "days_remaining_in_financial_year": SMALLINT(),
    "financial_week_no": TINYINT(),
    "financial_quarter": TINYINT(),
    "financial_quarter_name": NCHAR(2),
    "financial_quarter_start": DATE(),
    "financial_quarter_end": DATE(),
    "day_of_financial_quarter": TINYINT(),
    "financial_quarter_year": NVARCHAR(8),
    "financial_month_no": TINYINT(),
    "financial_month_start": DATE(),
    "financial_month_end": DATE(),
    "day_of_financial_month": TINYINT(),
    "month_name": NVARCHAR(9),
    "month_name_abbreviation": NCHAR(3),
    "month_abbreviation_year": NCHAR(6),
    "month_financial_year": NVARCHAR(9),
    "financial_month_year_no": INTEGER(),
}


def prepare_dates_dataframe(path: Path = CSV_PATH) -> DataFrame:
    frame = read_csv(path).rename(columns=COLUMN_RENAMES)
    expected = set(STAGING_DATATYPES)
    missing = sorted(expected - set(frame.columns))
    unexpected = sorted(set(frame.columns) - expected)
    if missing or unexpected:
        raise ValueError(
            f"date CSV columns do not match staging; missing={missing}, "
            f"unexpected={unexpected}"
        )

    frame = frame[list(STAGING_DATATYPES)]
    for column in DATE_COLUMNS:
        frame[column] = to_datetime(frame[column], errors="raise").dt.date

    if frame.empty:
        raise ValueError("date CSV contains no rows")
    if frame.isna().any().any():
        raise ValueError("date CSV contains a missing value")
    if frame["calendar_date"].duplicated().any():
        raise ValueError("date CSV contains duplicate dates")

    ordered_dates = to_datetime(frame["calendar_date"]).sort_values()
    if not ordered_dates.diff().dropna().eq("1 day").all():
        raise ValueError("date CSV is not a continuous daily series")
    if not (
        (to_datetime(frame["calendar_date"]) >= to_datetime(frame["financial_year_start"]))
        & (to_datetime(frame["calendar_date"]) <= to_datetime(frame["financial_year_end"]))
    ).all():
        raise ValueError("a date falls outside its stated financial year")

    return frame


def update_dates_table(engine_sql18: Engine, logger: DatabaseLogger) -> int | None:
    """Validate and upsert the maintained date CSV into dbo.dates."""

    try:
        frame = prepare_dates_dataframe()
        write_df_to_sql_db(
            engine_sql18,
            STAGING_TABLE,
            frame,
            "replace",
            chunksize=20000,
            datatype=STAGING_DATATYPES,
        )
        _, error = execute_sql_procedure(
            engine_sql18,
            "EXEC [dbo].[update_dates_table];",
        )
        if error is not None:
            raise RuntimeError(error)
        logger.info(TABLE, "update dates", f"loaded {len(frame)} dates", len(frame))
        return len(frame)
    except Exception as exc:  # noqa: BLE001
        try:
            with engine_sql18.begin() as connection:
                connection.exec_driver_sql("DROP TABLE IF EXISTS [dbo].[dates_staging];")
        except Exception:  # noqa: BLE001, S110
            pass
        logger.error(TABLE, "update dates", str(exc))
        return None
