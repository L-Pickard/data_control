"""Run the inventory cost checks and datasets queued in Shiner Reports.

Meant for a SQL Agent job that runs every minute (one job, so requests never run side by side):
    python scripts/run_inventory_cost.py

Each queued check or dataset is claimed, run against NAV (SQL02 and SQL04) and written to data_control; see
shinerutils/updates/inventory_cost.py. When nothing is queued the script exits without connecting to NAV or writing
to db_log, so a run every minute does not fill the log. Exit code 1 means a request failed or the queue could not
be read (the failure is in db_log and on the request itself).
"""

from __future__ import annotations

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))


def main() -> int:
    import shinerutils
    from shinerutils.logging import DatabaseLogger
    from shinerutils.updates.inventory_cost import TABLE

    logger = DatabaseLogger()
    engines = {
        "sql02": shinerutils.get_sqlalchemy_engine("shinersql02", "NAV_LIVE"),
        "sql04": shinerutils.get_sqlalchemy_engine("shinersql04", "BC_LIVE_USA"),
        "warehouse": shinerutils.get_sqlalchemy_engine("shinersql18", "data_control"),
    }
    exit_code = 0

    try:
        handled = shinerutils.process_inventory_cost_requests(engines["sql02"], engines["sql04"], engines["warehouse"], logger)
        if handled is None:
            print("The inventory cost queue could not be read")
            exit_code = 1
        elif handled:
            print(f"{handled} inventory cost request(s) handled")
        if any(record.level in ("ERROR", "CRITICAL", "FAILURE") for record in logger.records):
            exit_code = 1
    except Exception as exc:  # noqa: BLE001
        logger.critical(table=TABLE, action="run inventory cost requests", message=f"inventory cost job crashed: {exc}")
        print(f"inventory cost job crashed: {exc}")
        exit_code = 1
    finally:
        # Engines connect lazily: with nothing queued only the warehouse was opened, and nothing is logged.
        if logger.records:
            error = logger.flush_log_records(engines["warehouse"])
            if error is not None:
                print(error)
                exit_code = 1
        for engine in engines.values():
            engine.dispose()

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
