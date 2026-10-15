"""Run the inventory cost checks and build the inventory cost datasets that finance queues in Shiner Reports.

The portal only queues requests (finance.request_inventory_cost_check and finance.request_inventory_cost). This module,
run every minute by scripts/run_inventory_cost.py, claims them one at a time (finance.claim_inventory_cost_request),
reads NAV (SQL02: Ltd BRISTOL and B.V 3PL; SQL04: LLC POMONA) as at the request's date and writes the result:

* a check: the receipt lines not invoiced by the date and the entries still to be cost-adjusted (both warnings)
  into finance.inventory_cost_receipts / finance.inventory_cost_unadjusted, then finance.complete_inventory_cost_check with the
  number of value entries not posted to the G/L (the only blocker), all in one transaction;
* a dataset: the stock and its cost (actual + expected) into finance.inventory_cost_staging, then
  finance.build_inventory_cost, which moves it into finance.inventory_cost_lines and drops the staging table.

A request that fails is marked failed with the reason (finance.fail_inventory_cost_request) and logged.
"""

from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from decimal import Decimal
from pathlib import Path

from pandas import DataFrame, concat, isna, to_datetime
from sqlalchemy.dialects.mssql import DATE, DECIMAL, INTEGER, NVARCHAR
from sqlalchemy.engine import Engine

from shinerutils.constants import SELECTS_SQL02, SELECTS_SQL04
from shinerutils.logging import DatabaseLogger
from shinerutils.sql import execute_sql_procedure, transactional_connection, write_df_to_sql_db
from shinerutils.utils import concurrent_df_load_params

TABLE = "inventory_cost"
# The tables and procedures are in data_control's [finance] schema (sql/database/schema_finance.sql).
SCHEMA = "finance"
ENTITIES = ("Shiner Ltd", "Shiner B.V", "Shiner LLC")
# A run handles at most this many requests, so one minute's job cannot run on indefinitely.
MAX_REQUESTS_PER_RUN = 10

RECEIPT_COLUMNS = [
    "entity", "document_no", "document_line_no", "order_no", "posting_date", "vendor_id", "vendor_name", "item_id",
    "description", "description_2", "colours", "size_1", "size_1_unit", "currency_code", "direct_unit_cost",
    "quantity", "quantity_invoiced", "quantity_not_invoiced",
]
UNADJUSTED_COLUMNS = ["entity", "entry_no", "posting_date", "entry_type", "document_no", "item_id", "quantity", "remaining_quantity"]
COUNT_COLUMNS = ["entity", "unadjusted_entries", "unposted_entries"]
STAGING_COLUMNS = ["entity", "item_id", "quantity", "cost", "expected_cost", "first_receipt", "last_receipt"]
STAGING_DATATYPES = {
    "dataset_id": INTEGER(),
    "entity": NVARCHAR(20),
    "item_id": NVARCHAR(20),
    "quantity": DECIMAL(38, 20),
    "cost": DECIMAL(38, 20),
    "expected_cost": DECIMAL(38, 20),
    "first_receipt": DATE(),
    "last_receipt": DATE(),
}


def _load(engine_sql02: Engine, engine_sql04: Engine, query: str, as_of: date, columns: list[str], logger: DatabaseLogger) -> DataFrame:
    """Run sql/select/shinersql02 and shinersql04/<query>.sql for the as-of date and combine the results."""

    sources = ((engine_sql02, SELECTS_SQL02, "sql02"), (engine_sql04, SELECTS_SQL04, "sql04"))

    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [
            executor.submit(concurrent_df_load_params, engine, Path(path) / f"{query}.sql", (as_of.isoformat(),), logger, f"{label} {query}")
            for engine, path, label in sources
        ]
        results = [future.result() for future in futures]

    frames = []
    for frame, error in results:
        if error is not None:
            raise RuntimeError(error)
        if frame is None:
            raise ValueError(f"the {query} query returned no dataframe")
        missing = [column for column in columns if column not in frame.columns]
        if missing:
            raise ValueError(f"the {query} query is missing columns: {', '.join(missing)}")
        frames.append(frame.loc[:, columns])

    return concat(frames, ignore_index=True)


def _decimal(value) -> Decimal | None:
    if value is None:
        return None
    try:
        number = Decimal(str(value))
    except ArithmeticError:
        return None
    return number if number.is_finite() else None


def validate_dataset(frame: DataFrame) -> DataFrame:
    """Check the NAV rows for a dataset before they are staged; build_inventory_cost checks them again."""

    if frame.empty:
        raise ValueError("NAV returned no stock for the as-of date")

    frame = frame.copy()

    for column in ("entity", "item_id"):
        if frame[column].map(lambda value: not isinstance(value, str) or not value.strip() or len(value) > 20).any():
            raise ValueError(f"the dataset contains an invalid {column}")

    if not frame["entity"].isin(ENTITIES).all():
        raise ValueError("the dataset contains an unknown company")

    if frame.duplicated(subset=["entity", "item_id"]).any():
        raise ValueError("the dataset contains a company and item more than once")

    # No expected cost (NULL from SQL, so None or NaN here) is 0.
    frame["expected_cost"] = frame["expected_cost"].map(lambda value: Decimal(0) if isna(value) else value)

    for column in ("quantity", "cost", "expected_cost"):
        frame[column] = frame[column].map(_decimal)
        if frame[column].isna().any():
            raise ValueError(f"the dataset contains a missing or non-finite {column}")

    if frame["quantity"].map(lambda value: value <= 0).any():
        raise ValueError("the dataset contains a quantity of 0 or less")

    for column in ("first_receipt", "last_receipt"):
        frame[column] = to_datetime(frame[column], errors="raise").dt.date

    if (frame["first_receipt"].isna() != frame["last_receipt"].isna()).any():
        raise ValueError("the dataset contains an incomplete receipt date range")

    dated = frame.loc[frame["first_receipt"].notna()]
    if (dated["first_receipt"] > dated["last_receipt"]).any():
        raise ValueError("the dataset contains a reversed receipt date range")

    for column in ("first_receipt", "last_receipt"):
        frame[column] = frame[column].astype(object).where(frame[column].notna(), None)

    return frame


def run_inventory_cost_check(engine_sql02: Engine, engine_sql04: Engine, engine_sql18: Engine, logger: DatabaseLogger, check_id: int, as_of: date) -> str:
    """Run one claimed check and complete it; returns a summary for the log. Raises on any failure."""

    receipts = _load(engine_sql02, engine_sql04, "inventory_cost_receipts", as_of, RECEIPT_COLUMNS, logger)
    unadjusted = _load(engine_sql02, engine_sql04, "inventory_cost_unadjusted", as_of, UNADJUSTED_COLUMNS, logger)
    counts = _load(engine_sql02, engine_sql04, "inventory_cost_checks", as_of, COUNT_COLUMNS, logger)

    if counts[["unadjusted_entries", "unposted_entries"]].isna().any().any():
        raise ValueError("the inventory_cost_checks query returned a missing count")

    unposted = int(counts["unposted_entries"].sum())
    # The counted and listed flagged entries come from the same filters; a difference means the queries drifted.
    if int(counts["unadjusted_entries"].sum()) != len(unadjusted):
        raise ValueError("the counted and listed entries still to be cost-adjusted differ")

    receipts.insert(0, "check_id", check_id)
    unadjusted.insert(0, "check_id", check_id)

    with transactional_connection(engine_sql18) as connection:
        if not receipts.empty:
            write_df_to_sql_db(connection, "inventory_cost_receipts", receipts, "append", chunksize=min(len(receipts), 20000), schema=SCHEMA)
        if not unadjusted.empty:
            write_df_to_sql_db(connection, "inventory_cost_unadjusted", unadjusted, "append", chunksize=min(len(unadjusted), 20000), schema=SCHEMA)
        connection.exec_driver_sql(
            "EXEC [finance].[complete_inventory_cost_check] @check_id = ?, @unposted_entries = ?;", (int(check_id), unposted)
        )

    return (
        f"inventory cost check {check_id} as of {as_of.isoformat()} complete: {unposted} value entries not posted to "
        f"the G/L, {len(receipts)} receipt lines not invoiced, {len(unadjusted)} entries still to be cost-adjusted"
    )


def run_inventory_cost_dataset(engine_sql02: Engine, engine_sql04: Engine, engine_sql18: Engine, logger: DatabaseLogger, dataset_id: int, as_of: date) -> str:
    """Load one claimed dataset from NAV into staging and build it; returns a summary for the log. Raises on failure."""

    frame = validate_dataset(_load(engine_sql02, engine_sql04, "inventory_cost_staging", as_of, STAGING_COLUMNS, logger))
    frame.insert(0, "dataset_id", int(dataset_id))
    rows = len(frame)

    write_df_to_sql_db(
        engine_sql18, "inventory_cost_staging", frame, "replace", chunksize=min(rows, 20000), datatype=STAGING_DATATYPES, schema=SCHEMA
    )

    _, error = execute_sql_procedure(engine_sql18, f"EXEC [finance].[build_inventory_cost] @dataset_id = {int(dataset_id)};")
    if error is not None:
        raise RuntimeError(f"build_inventory_cost failed: {error}")

    return f"inventory cost dataset {dataset_id} as of {as_of.isoformat()} built: {rows} lines"


def _claim(engine_sql18: Engine) -> tuple[str, int, date] | None:
    with transactional_connection(engine_sql18) as connection:
        row = connection.exec_driver_sql("EXEC [finance].[claim_inventory_cost_request];").fetchone()
    if row is None:
        return None
    as_of = row.as_of_date
    return str(row.request_kind), int(row.request_id), as_of if isinstance(as_of, date) else date.fromisoformat(str(as_of)[:10])


def _fail(engine_sql18: Engine, kind: str, request_id: int, message: str) -> str | None:
    try:
        with transactional_connection(engine_sql18) as connection:
            connection.exec_driver_sql(
                "EXEC [finance].[fail_inventory_cost_request] @request_kind = ?, @request_id = ?, @message = ?;",
                (kind, int(request_id), message[:4000]),
            )
        return None
    except Exception as exc:  # noqa: BLE001
        return str(exc)


def process_inventory_cost_requests(engine_sql02: Engine, engine_sql04: Engine, engine_sql18: Engine, logger: DatabaseLogger) -> int | None:
    """Handle every queued check and dataset (up to MAX_REQUESTS_PER_RUN). Returns how many were handled, or None
    when the queue could not be read. Each request is logged as a success or an error."""

    runners: dict[str, Callable[..., str]] = {"check": run_inventory_cost_check, "dataset": run_inventory_cost_dataset}
    handled = 0

    while handled < MAX_REQUESTS_PER_RUN:
        try:
            request = _claim(engine_sql18)
        except Exception as exc:  # noqa: BLE001
            logger.error(table=TABLE, action="claim inventory cost request", message=str(exc))
            return None if handled == 0 else handled

        if request is None:
            break

        kind, request_id, as_of = request
        action = f"inventory cost {kind} {request_id}"
        handled += 1

        try:
            summary = runners[kind](engine_sql02, engine_sql04, engine_sql18, logger, request_id, as_of)
            logger.success(table=TABLE, action=action, message=summary)
        except Exception as exc:  # noqa: BLE001
            message = f"{exc}"
            logger.error(table=TABLE, action=action, message=message)
            error = _fail(engine_sql18, kind, request_id, message)
            if error is not None:
                logger.error(table=TABLE, action=f"mark {action} failed", message=error)

    return handled
