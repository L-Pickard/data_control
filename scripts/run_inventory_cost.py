"""SQL Agent entry point: run one on-demand inventory check or dataset, then exit."""

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
        handled = shinerutils.process_inventory_cost_operation(engines["sql02"], engines["sql04"], engines["warehouse"], logger)
        if handled is None:
            print("The inventory operation could not be started")
            exit_code = 1
        elif handled:
            print(f"{handled} inventory cost operation handled")
        if any(record.level in ("ERROR", "CRITICAL", "FAILURE") for record in logger.records):
            exit_code = 1
    except Exception as exc:  # noqa: BLE001
        logger.critical(table=TABLE, action="run inventory cost requests", message=f"inventory cost job crashed: {exc}")
        print(f"inventory cost job crashed: {exc}")
        exit_code = 1
    finally:
        # Engines connect lazily: with no pending operation only the warehouse was opened, and nothing is logged.
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
