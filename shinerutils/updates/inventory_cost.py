"""Run one explicitly started inventory operation. No queue, staging table or scheduled polling."""

from concurrent.futures import ThreadPoolExecutor
from datetime import date
from decimal import Decimal
from pathlib import Path
import json
import re
from xml.etree.ElementTree import Element, SubElement, tostring
from random import uniform
from time import sleep

from pandas import DataFrame, concat, isna, to_datetime
from sqlalchemy.engine import Engine

from shinerutils.constants import SELECTS_SQL02, SELECTS_SQL04
from shinerutils.logging import DatabaseLogger
from shinerutils.sql import (
    transactional_connection,
    write_df_to_sql_db,
)
from shinerutils.utils import concurrent_df_load_params

TABLE = "inventory_cost"
# The tables and procedures are in data_control's [finance] schema (sql/database/schema_finance.sql).
SCHEMA = "finance"
ENTITIES = ("Shiner Ltd", "Shiner B.V", "Shiner LLC")
LEGACY_SCOPE = [{"entity": entity, "locations": [location]} for entity, location in zip(ENTITIES, ("BRISTOL", "3PL", "POMONA"))]


def scope_xml(scope):
    scope = LEGACY_SCOPE if scope is None else scope
    if not isinstance(scope, list) or not 1 <= len(scope) <= 3:
        raise ValueError("Invalid inventory scope")
    seen, root = set(), Element("scope")
    for entry in scope:
        entity, locations = entry.get("entity"), entry.get("locations")
        if entity not in ENTITIES or entity in seen:
            raise ValueError("Invalid inventory scope entity")
        seen.add(entity)
        node = SubElement(root, "entity", name=entity, all="1" if locations is None else "0")
        if locations is not None:
            if not isinstance(locations, list) or not 1 <= len(locations) <= 100:
                raise ValueError("Invalid inventory scope locations")
            for code in locations:
                if not isinstance(code, str) or len(code) > 10 or any(ord(c) < 32 for c in code):
                    raise ValueError("Invalid inventory location code")
                SubElement(node, "location", code=code)
    return tostring(root, encoding="unicode")

RECEIPT_COLUMNS = [
    "entity",
    "location_code",
    "document_no",
    "document_line_no",
    "order_no",
    "posting_date",
    "vendor_id",
    "vendor_name",
    "item_id",
    "description",
    "description_2",
    "colours",
    "size_1",
    "size_1_unit",
    "currency_code",
    "direct_unit_cost",
    "quantity",
    "quantity_invoiced",
    "quantity_not_invoiced",
]
UNADJUSTED_COLUMNS = [
    "entity",
    "location_code",
    "entry_no",
    "posting_date",
    "entry_type",
    "document_no",
    "item_id",
    "quantity",
    "remaining_quantity",
]
COUNT_COLUMNS = ["entity", "unposted_entries"]
DATASET_COLUMNS = [
    "entity",
    "location_code",
    "item_id",
    "quantity",
    "cost",
    "expected_cost",
    "first_receipt",
    "last_receipt",
]



# Retry only source SELECTs killed by SQL Server as a deadlock victim. Writes are never retried.
READ_RETRY_DELAYS = (1, 2, 4)


def _is_deadlock(error: str) -> bool:
    return re.search(r"\(1205\)", error) is not None


def _read_source(engine, path, params, logger, source_name):
    for attempt in range(len(READ_RETRY_DELAYS) + 1):
        frame, error = concurrent_df_load_params(engine, path, params, logger, source_name)
        if error is None:
            return frame, None
        deadlock = _is_deadlock(error)
        if deadlock and attempt < len(READ_RETRY_DELAYS):
            logger.warning(table=TABLE, action="retry inventory source read",
                           message=f"{source_name}: SQL deadlock 1205; retry {attempt + 1} of {len(READ_RETRY_DELAYS)}")
            # The helper has closed/rolled back the failed read connection before this retry.
            sleep(READ_RETRY_DELAYS[attempt] + uniform(0, 0.25))
            continue
        logger.error(table=TABLE, action=f"read {source_name} failed", message=error)
        source = source_name.split(" ", 1)[0].upper()
        if deadlock:
            return None, f"{source} was busy. The inventory read could not complete after {attempt + 1} attempts. Please try again."
        return None, f"The inventory data could not be read from {source}. Ask an administrator to check the database log."
    raise AssertionError("Unreachable source read retry state")


def _load(
    engine_sql02: Engine,
    engine_sql04: Engine,
    query: str,
    as_of: date,
    columns: list[str],
    logger: DatabaseLogger,
    scope=None,
) -> DataFrame:
    """Run sql/select/shinersql02 and shinersql04/<query>.sql for the as-of date and combine the results."""

    scope = LEGACY_SCOPE if scope is None else scope
    xml = scope_xml(scope)
    selected = {entry["entity"] for entry in scope}
    sources = [source for source in (
        (engine_sql02, SELECTS_SQL02, "sql02"),
        (engine_sql04, SELECTS_SQL04, "sql04"),
    ) if selected.intersection(ENTITIES[:2] if source[2] == "sql02" else ENTITIES[2:])]

    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [
            executor.submit(
                _read_source,
                engine,
                Path(path) / f"{query}.sql",
                (as_of.isoformat(), xml),
                logger,
                f"{label} {query}",
            )
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
            raise ValueError(
                f"the {query} query is missing columns: {', '.join(missing)}"
            )
        allowed = {entry["entity"]: entry.get("locations") for entry in scope}
        for entity, rows in frame.groupby("entity", dropna=False):
            if entity not in allowed:
                raise ValueError("source rows are outside the selected entities")
            if "location_code" in rows and allowed[entity] is not None and not rows["location_code"].isin(allowed[entity]).all():
                raise ValueError("source rows are outside the selected locations")
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
    """Check the NAV rows for a dataset before they are saved; build_inventory_cost checks them again."""

    if frame.empty:
        raise ValueError("NAV returned no stock for the as-of date")

    frame = frame.copy()

    for column in ("entity", "item_id"):
        if (
            frame[column]
            .map(
                lambda value: (
                    not isinstance(value, str) or not value.strip() or len(value) > 20
                )
            )
            .any()
        ):
            raise ValueError(f"the dataset contains an invalid {column}")

    if not frame["entity"].isin(ENTITIES).all():
        raise ValueError("the dataset contains an unknown company")

    if "location_code" not in frame or frame["location_code"].map(lambda code: not isinstance(code, str) or len(code) > 10).any():
        raise ValueError("the dataset contains an invalid location code")
    if frame.duplicated(subset=["entity", "location_code", "item_id"]).any():
        raise ValueError("the dataset contains a company, location and item more than once")

    # No expected cost (NULL from SQL, so None or NaN here) is 0.
    frame["expected_cost"] = frame["expected_cost"].map(
        lambda value: Decimal(0) if isna(value) else value
    )

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


def run_inventory_cost_check(
    engine_sql02: Engine,
    engine_sql04: Engine,
    engine_sql18: Engine,
    logger: DatabaseLogger,
    check_id: int,
    as_of: date,
    scope=None,
) -> str:
    """Run one claimed check and complete it; returns a summary for the log. Raises on any failure."""

    receipts = _load(
        engine_sql02,
        engine_sql04,
        "inventory_cost_receipts",
        as_of,
        RECEIPT_COLUMNS,
        logger,
        scope,
    )
    unadjusted = _load(
        engine_sql02,
        engine_sql04,
        "inventory_cost_unadjusted",
        as_of,
        UNADJUSTED_COLUMNS,
        logger,
        scope,
    )
    counts = _load(
        engine_sql02,
        engine_sql04,
        "inventory_cost_checks",
        as_of,
        COUNT_COLUMNS,
        logger,
        scope,
    )

    # One blocking count per company is required: missing source results must not pass a check.
    entities = {entry["entity"] for entry in (LEGACY_SCOPE if scope is None else scope)}
    if len(counts) != len(entities) or set(counts["entity"]) != entities:
        raise ValueError("the inventory_cost_checks query must return one count for each company")
    if counts["unposted_entries"].isna().any():
        raise ValueError("the inventory_cost_checks query returned a missing count")
    unposted = int(counts["unposted_entries"].sum())
    if (counts["unposted_entries"] < 0).any():
        raise ValueError("the inventory_cost_checks query returned a negative count")
    # The warning counts describe exactly the lists saved in this transaction, without rereading NAV.
    uninvoiced_lines, unadjusted_entries = len(receipts), len(unadjusted)

    receipts.insert(0, "check_id", check_id)
    unadjusted.insert(0, "check_id", check_id)

    with transactional_connection(engine_sql18) as connection:
        if not receipts.empty:
            write_df_to_sql_db(
                connection,
                "inventory_cost_receipts",
                receipts,
                "append",
                chunksize=min(len(receipts), 20000),
                schema=SCHEMA,
            )
        if not unadjusted.empty:
            write_df_to_sql_db(
                connection,
                "inventory_cost_unadjusted",
                unadjusted,
                "append",
                chunksize=min(len(unadjusted), 20000),
                schema=SCHEMA,
            )
        connection.exec_driver_sql(
            "EXEC [finance].[complete_inventory_cost_check] @check_id = ?, @unposted_entries = ?, "
            "@uninvoiced_lines = ?, @unadjusted_entries = ?;",
            (int(check_id), unposted, uninvoiced_lines, unadjusted_entries),
        )

    return (
        f"inventory cost check {check_id} as of {as_of.isoformat()} complete: {unposted} value entries not posted to "
        f"the G/L, {len(receipts)} receipt lines not invoiced, {len(unadjusted)} entries still to be cost-adjusted"
    )


def _json_value(value):
    if isinstance(value, Decimal):
        # SQL DECIMAL cannot parse exponent strings such as 0E-20 or 1E-20.
        return format(value, "f")
    if isinstance(value, date):
        return value.isoformat()
    raise TypeError(f"Unsupported inventory value: {type(value).__name__}")


def run_inventory_cost_dataset(
    engine_sql02: Engine,
    engine_sql04: Engine,
    engine_sql18: Engine,
    logger: DatabaseLogger,
    dataset_id: int,
    as_of: date,
    scope=None,
) -> str:
    """Read and validate NAV rows, then save lines and totals in one SQL transaction."""
    frame = validate_dataset(_load(engine_sql02, engine_sql04, "inventory_cost_dataset", as_of, DATASET_COLUMNS, logger, scope))
    # Decimal strings avoid binary-float loss; SQL parses them as DECIMAL(38,20).
    payload = json.dumps(frame.to_dict(orient="records"), default=_json_value, allow_nan=False)
    with transactional_connection(engine_sql18) as connection:
        connection.exec_driver_sql(
            "EXEC [finance].[build_inventory_cost] @dataset_id = ?, @rows_json = ?;",
            (int(dataset_id), payload),
        )
    return f"inventory cost dataset {dataset_id} as of {as_of.isoformat()} built: {len(frame)} lines"



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


def process_inventory_cost_operation(
    engine_sql02: Engine,
    engine_sql04: Engine,
    engine_sql18: Engine,
    logger: DatabaseLogger,
) -> int | None:
    """Run the single pending operation, holding a session lock until it finishes.

    The lock also prevents submissions while a worker is still exiting. A lost
    connection releases it; the next submission can identify interrupted work.
    """
    try:
        with engine_sql18.connect() as connection:
            lock = connection.exec_driver_sql(
                "DECLARE @result int; EXEC @result = sys.sp_getapplock "
                "@Resource=N'inventory_cost_operation', @LockMode=N'Exclusive', "
                "@LockOwner=N'Session', @LockTimeout=0; SELECT @result;"
            ).scalar_one()
            connection.commit()
            if lock < 0:
                raise RuntimeError("Another inventory operation is already running")
            try:
                row = connection.exec_driver_sql("EXEC [finance].[begin_inventory_cost_operation];").fetchone()
                connection.commit()
                if row is None:
                    return 0
                kind, operation_id, as_of = str(row.request_kind), int(row.request_id), row.as_of_date
                action = f"inventory cost {kind} {operation_id}"
                try:
                    runner = {"check": run_inventory_cost_check, "dataset": run_inventory_cost_dataset}[kind]
                    scope = json.loads(row.scope_json)
                    scope_xml(scope)  # Refuse malformed stored scope before reading either source.
                    summary = runner(engine_sql02, engine_sql04, connection, logger, operation_id, as_of, scope)
                    connection.commit()
                    logger.success(table=TABLE, action=action, message=summary)
                except Exception as exc:
                    connection.rollback()
                    logger.error(table=TABLE, action=action, message=str(exc))
                    error = _fail(engine_sql18, kind, operation_id, str(exc))
                    if error is not None:
                        logger.error(table=TABLE, action=f"mark {action} failed", message=error)
                return 1
            finally:
                connection.rollback()
                connection.exec_driver_sql(
                    "EXEC sys.sp_releaseapplock @Resource=N'inventory_cost_operation', @LockOwner=N'Session';"
                )
                connection.commit()
    except Exception as exc:
        logger.error(table=TABLE, action="start inventory cost operation", message=str(exc))
        return None
