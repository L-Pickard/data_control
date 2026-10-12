"""Copy new marketing thumbnails to the SQL18 folder and make the missing ones from product photos.

Examples:
    python scripts/make_item_thumbnails.py --dry-run
    python scripts/make_item_thumbnails.py --limit 25 --output-dir C:\\Temp\\thumbnail-trial
    python scripts/make_item_thumbnails.py

Exit code 0 when the run succeeded (including "nothing to do"), 1 otherwise, so a SQL Server Agent step fails visibly.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

ACTION = "make missing item thumbnails"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="count what would be copied and made; write nothing")
    parser.add_argument("--limit", type=int, help="make at most this many thumbnails in this run")
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="trial run: write the thumbnails to this folder instead; the NAS copy and the catalogue are skipped",
    )
    args = parser.parse_args()
    if args.limit is not None and args.limit < 1:
        parser.error("--limit must be 1 or more")
    return args


def main() -> int:
    args = parse_args()

    from shinerutils import get_sqlalchemy_engine
    from shinerutils.logging import DatabaseLogger
    from shinerutils.updates.item_thumbnails import TABLE, make_missing_item_thumbnails

    logger = DatabaseLogger()
    engine = get_sqlalchemy_engine("shinersql18", "data_control")
    exit_code = 0
    # A dry run or a trial changes nothing, so it leaves no record in the load log either.
    record = not args.dry_run and args.output_dir is None
    try:
        result = make_missing_item_thumbnails(
            engine, logger, dry_run=args.dry_run, limit=args.limit, output_dir=args.output_dir
        )
        if result is None:
            print("Making item thumbnails failed; see the data-control log.")
            logger.failure(table=TABLE, action=ACTION, message="item thumbnails were not made")
            exit_code = 1
        elif result.catalogue_error is not None:
            logger.failure(
                table=TABLE,
                action=ACTION,
                message=f"{result.files_written} thumbnail files written but not added to the image catalogue",
                rows=result.files_written,
            )
            exit_code = 1
        else:
            logger.success(
                table=TABLE,
                action=ACTION,
                message=f"{result.copied} copied from the NAS, {result.generated} made, "
                f"{result.regenerated} made again, {result.unreadable} photos unreadable; "
                f"{result.catalogued} added to the image catalogue",
                rows=result.files_written,
            )
    except Exception as exc:  # noqa: BLE001
        logger.critical(table=TABLE, action=ACTION, message=f"item thumbnails crashed: {exc}")
        print(f"item thumbnails crashed: {exc}")
        exit_code = 1
    finally:
        if record or exit_code:
            error = logger.flush_log_records(engine)
            if error is not None:
                print(error)
                exit_code = 1
        engine.dispose()
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
