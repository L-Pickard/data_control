"""Run one of the registered data-control table updates.

Examples:
    python scripts/run_update.py vendors
    python scripts/run_update.py purchase_orders
    python scripts/run_update.py --list
"""

from __future__ import annotations

import argparse
import sys
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from sqlalchemy.engine import Engine

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))


@dataclass(frozen=True)
class UpdateDefinition:
    function_name: str
    engine_names: tuple[str, ...]


# This allow-list makes the command generic without accepting arbitrary Python
# modules, functions, SQL files, or table names from the command line.
UPDATES: dict[str, UpdateDefinition] = {
    "brand_forecast": UpdateDefinition(
        "update_brand_forecast_table", ("finance", "warehouse")
    ),
    "brands": UpdateDefinition("update_brands_table", ("sql02", "warehouse")),
    "countries": UpdateDefinition(
        "update_countries_table", ("sql04", "sql05", "warehouse")
    ),
    "customers": UpdateDefinition(
        "update_customers_table", ("sql02", "sql04", "warehouse")
    ),
    "dates": UpdateDefinition("update_dates_table", ("warehouse",)),
    "exchange_rates": UpdateDefinition(
        "update_exchange_rates_table", ("sql02", "sql04", "warehouse")
    ),
    "items": UpdateDefinition("update_items_table", ("sql02", "sql04", "warehouse")),
    "inventory": UpdateDefinition(
        "update_inventory_table", ("sql02", "sql04", "warehouse")
    ),
    "item_images": UpdateDefinition("update_item_images_table", ("warehouse",)),
    "monthly_avg_xr": UpdateDefinition(
        "update_monthly_average_exchange_rates_table", ("finance", "warehouse")
    ),
    "purchase_orders": UpdateDefinition(
        "update_purchase_orders_table", ("sql02", "sql04", "warehouse")
    ),
    "preorders": UpdateDefinition("update_preorders_table", ("finance", "warehouse")),
    "record_link": UpdateDefinition(
        "update_record_link_table", ("sql02", "sql04", "warehouse")
    ),
    "sales": UpdateDefinition("update_sales_table", ("sql02", "sql04", "warehouse")),
    "sales_orders": UpdateDefinition(
        "update_sales_orders_table", ("sql02", "sql04", "warehouse")
    ),
    "sales_people": UpdateDefinition(
        "update_sales_people_table", ("sql02", "sql04", "warehouse")
    ),
    "vendors": UpdateDefinition(
        "update_vendors_table", ("sql02", "sql04", "warehouse")
    ),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run a registered data-control table update."
    )
    parser.add_argument("table", nargs="?", choices=sorted(UPDATES))
    parser.add_argument(
        "--list", action="store_true", help="list the available table updates and exit"
    )
    args = parser.parse_args()
    if args.table is None and not args.list:
        parser.error("provide a table name or use --list")
    return args


def create_engines(get_engine: Callable[[str, str], Engine]) -> dict[str, Engine]:
    return {
        "sql02": get_engine("source_d", "ERP_LIVE"),
        "sql04": get_engine("source_b", "ERP_LIVE_US"),
        "sql05": get_engine("source_c", "ERP_TEST_UK"),
        "finance": get_engine("source_d", "Finance"),
        "warehouse": get_engine("source_d", "data_control"),
    }


def main() -> int:
    args = parse_args()
    if args.list:
        print("\n".join(sorted(UPDATES)))
        return 0

    # Delay project imports and database-engine creation until after argument
    # validation, so --help and --list do not require a database connection.
    import datautils
    from datautils.logging import DatabaseLogger

    definition = UPDATES[args.table]
    logger = DatabaseLogger()
    engines = create_engines(datautils.get_sqlalchemy_engine)
    warehouse = engines["warehouse"]
    action = f"update [data_control].[dbo].[{args.table}] table"
    exit_code = 0

    try:
        update_function = getattr(datautils, definition.function_name)
        function_engines = [engines[name] for name in definition.engine_names]
        rows_affected = update_function(*function_engines, logger)

        if rows_affected is None:
            print(f"An error occurred updating the {args.table} table")
            logger.failure(args.table, action, f"{args.table} table update failed")
            exit_code = 1
        elif rows_affected == 0:
            print(f"{args.table} source is unchanged")
            logger.success(
                args.table,
                action,
                f"{args.table} source is unchanged; no rows replaced",
                0,
            )
        else:
            print(
                f"{args.table} table successfully updated. "
                f"Rows affected: {rows_affected}"
            )
            logger.success(
                args.table,
                action,
                f"{args.table} table successfully updated; "
                f"{rows_affected} rows affected",
                rows_affected,
            )
    except Exception as exc:  # noqa: BLE001
        logger.critical(args.table, action, f"{args.table} update crashed: {exc}")
        print(f"{args.table} update crashed: {exc}")
        exit_code = 1
    finally:
        error = logger.flush_log_records(warehouse)
        if error is not None:
            print(error)
            exit_code = 1
        for engine in engines.values():
            engine.dispose()

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
