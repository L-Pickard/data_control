"""Check or upload network images missing from the SharePoint image libraries."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="report missing images without uploading them",
    )
    return parser.parse_args()


def main() -> int:
    from datautils.logging import DatabaseLogger
    from datautils import (
        get_sqlalchemy_engine,
        sync_item_images_to_sharepoint,
    )

    args = parse_args()
    logger = DatabaseLogger()
    engine = get_sqlalchemy_engine("source_d", "data_control")
    exit_code = 0
    try:
        result = sync_item_images_to_sharepoint(
            engine,
            logger,
            dry_run=args.dry_run,
        )
        if result is None:
            print("Image synchronization failed; see the data-control log.")
            exit_code = 1
        elif args.dry_run:
            print(
                "Dry run: "
                f"{result.product_images} Product Images and "
                f"{result.thumbnail_images} BC thumbnails are missing "
                f"({result.total} total)."
            )
        else:
            print(
                f"Uploaded {result.product_images} Product Images and "
                f"{result.thumbnail_images} BC thumbnails "
                f"({result.total} total)."
            )
    finally:
        error = logger.flush_log_records(engine)
        if error is not None:
            print(error)
            exit_code = 1
        engine.dispose()
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
