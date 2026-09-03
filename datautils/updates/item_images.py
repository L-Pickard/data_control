from __future__ import annotations

import os
from collections import defaultdict
from collections.abc import Callable, Iterable
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime, timezone
from hashlib import sha256
from io import BytesIO
from pathlib import Path
from threading import Event, Lock
from typing import Any

import requests
from pandas import DataFrame
from PIL import Image, UnidentifiedImageError
from sqlalchemy.dialects.mssql import (
    BIGINT,
    BINARY,
    BIT,
    DATETIME2,
    INTEGER,
    NVARCHAR,
)
from sqlalchemy.engine import Engine

from datautils.constants import PROJECT_ROOT
from datautils.filesystem import (
    get_windows_file_size,
    is_ignored_system_file,
    iter_files_by_extension,
    read_windows_file_bytes,
)
from datautils.logging import DatabaseLogger
from datautils.ms_graph import (
    acquire_token,
    create_graph_session,
    download_sharepoint_file_bytes,
    list_sharepoint_drive_files,
    parse_graph_datetime,
    resolve_sharepoint_drive_id,
    resolve_sharepoint_site_id,
    upload_sharepoint_file,
)
from datautils.sql import execute_sql_procedure, write_df_to_sql_db
from datautils.utils import (
    environment_value,
    first_environment_value,
    load_environment_file,
)

TABLE = "item_images"
STAGING_TABLE = "item_image_locations_staging"
IMAGE_EXTENSIONS = {
    ".avif",
    ".bmp",
    ".gif",
    ".jpeg",
    ".jpg",
    ".png",
    ".tif",
    ".tiff",
    ".webp",
}
STAGING_COLUMNS = [
    "item_id",
    "image_key",
    "image_type",
    "file_name",
    "display_order",
    "is_primary",
    "source_code",
    "source_file_id",
    "location_type",
    "location_uri",
    "location_hash",
    "file_size",
    "width",
    "height",
    "last_modified",
]
STAGING_DATATYPES = {
    "item_id": NVARCHAR(20),
    "image_key": NVARCHAR(255),
    "image_type": NVARCHAR(20),
    "file_name": NVARCHAR(255),
    "display_order": INTEGER(),
    "is_primary": BIT(),
    "source_code": NVARCHAR(30),
    "source_file_id": NVARCHAR(255),
    "location_type": NVARCHAR(10),
    "location_uri": NVARCHAR(2048),
    "location_hash": BINARY(32),
    "file_size": BIGINT(),
    "width": INTEGER(),
    "height": INTEGER(),
    "last_modified": DATETIME2(precision=3),
}


def _progress(message: str) -> None:
    print(f"[item_images] {message}", flush=True)


def _sharepoint_progress(source_name: str) -> Callable[[int], None]:
    last_reported = 0

    def report(items_read: int) -> None:
        nonlocal last_reported
        if items_read - last_reported >= 2_000:
            _progress(f"Reading {source_name}: {items_read:,} entries received...")
            last_reported = items_read

    return report


@dataclass(frozen=True)
class ImageSourceSettings:
    tenant_id: str
    client_id: str
    client_secret: str
    sharepoint_hostname: str
    sharepoint_site_path: str
    sharepoint_site_id: str | None
    product_library: str
    thumbnail_library: str
    product_drive_id: str | None
    thumbnail_drive_id: str | None
    item_docs_path: Path
    thumbnail_path: Path
    product_upload_workers: int
    thumbnail_upload_workers: int

    @classmethod
    def from_environment(cls) -> ImageSourceSettings:
        load_environment_file(PROJECT_ROOT / ".env")
        worker_settings = {
            "product_upload_workers": environment_value(
                "IMAGE_SHAREPOINT_PRODUCT_UPLOAD_WORKERS", default="1"
            )
            or "1",
            "thumbnail_upload_workers": environment_value(
                "IMAGE_SHAREPOINT_THUMBNAIL_UPLOAD_WORKERS",
                "IMAGE_SHAREPOINT_UPLOAD_WORKERS",
                default="4",
            )
            or "4",
        }
        parsed_workers: dict[str, int] = {}
        for setting, value in worker_settings.items():
            try:
                parsed_workers[setting] = int(value)
            except ValueError as exc:
                raise ValueError(f"{setting} must be an integer") from exc
            if not 1 <= parsed_workers[setting] <= 16:
                raise ValueError(f"{setting} must be between 1 and 16")

        return cls(
            tenant_id=first_environment_value(
                "MS_GRAPH_TENANT_ID", "AZURE_TENANT_ID", "GRAPH_TENANT_ID"
            ),
            client_id=first_environment_value(
                "MS_GRAPH_CLIENT_ID", "AZURE_CLIENT_ID", "GRAPH_CLIENT_ID"
            ),
            client_secret=first_environment_value(
                "MS_GRAPH_CLIENT_SECRET",
                "AZURE_CLIENT_SECRET",
                "GRAPH_CLIENT_SECRET",
            ),
            sharepoint_hostname=environment_value(
                "IMAGE_SHAREPOINT_HOSTNAME", default="example.invalid"
            )
            or "example.invalid",
            sharepoint_site_path=environment_value(
                "IMAGE_SHAREPOINT_SITE_PATH", default="/sites/ExampleUKLtd"
            )
            or "/sites/ExampleUKLtd",
            sharepoint_site_id=environment_value("IMAGE_SHAREPOINT_SITE_ID"),
            product_library=environment_value(
                "IMAGE_SHAREPOINT_PRODUCT_LIBRARY", default="Product Images"
            )
            or "Product Images",
            thumbnail_library=environment_value(
                "IMAGE_SHAREPOINT_THUMBNAIL_LIBRARY", default="BC_Images"
            )
            or "BC_Images",
            product_drive_id=environment_value("IMAGE_SHAREPOINT_PRODUCT_DRIVE_ID"),
            thumbnail_drive_id=environment_value("IMAGE_SHAREPOINT_THUMBNAIL_DRIVE_ID"),
            item_docs_path=Path(
                environment_value(
                    "IMAGE_NAS_ITEM_DOCS_PATH", default=r"\\source_a\item_docs"
                )
                or r"\\source_a\item_docs"
            ),
            thumbnail_path=Path(
                environment_value(
                    "IMAGE_NAS_THUMBNAIL_PATH",
                    default=r"\\Examplenas01\ExampleData\MARKETING\001 Master Thumbnail Images",
                )
                or r"\\Examplenas01\ExampleData\MARKETING\001 Master Thumbnail Images"
            ),
            product_upload_workers=parsed_workers["product_upload_workers"],
            thumbnail_upload_workers=parsed_workers["thumbnail_upload_workers"],
        )


@dataclass(frozen=True)
class ImageSyncResult:
    product_images: int
    thumbnail_images: int

    @property
    def total(self) -> int:
        return self.product_images + self.thumbnail_images


def _resolve_image_drive_ids(
    token: str, settings: ImageSourceSettings
) -> tuple[str, str]:
    session = create_graph_session(token)
    try:
        product_drive_id = settings.product_drive_id
        thumbnail_drive_id = settings.thumbnail_drive_id
        if product_drive_id is None or thumbnail_drive_id is None:
            site_id = settings.sharepoint_site_id
            if site_id is None:
                site_id = resolve_sharepoint_site_id(
                    session,
                    settings.sharepoint_hostname,
                    settings.sharepoint_site_path,
                )
            if product_drive_id is None:
                product_drive_id = resolve_sharepoint_drive_id(
                    session, site_id, settings.product_library
                )
            if thumbnail_drive_id is None:
                thumbnail_drive_id = resolve_sharepoint_drive_id(
                    session, site_id, settings.thumbnail_library
                )
        return product_drive_id, thumbnail_drive_id
    finally:
        session.close()


class ItemMatcher:
    def __init__(self, item_ids: set[str]) -> None:
        self._by_upper = {item_id.upper(): item_id for item_id in item_ids}
        self._lengths = sorted({len(item_id) for item_id in item_ids}, reverse=True)

    def exact(self, value: str) -> str | None:
        return self._by_upper.get(value.strip().upper())

    def from_file_name(self, file_name: str) -> str | None:
        stem = Path(file_name).stem.strip().upper()
        for suffix in ("_THUMBNAIL", "-THUMBNAIL", "_THUMB", "-THUMB"):
            if stem.endswith(suffix):
                stem = stem[: -len(suffix)]
                break

        exact = self._by_upper.get(stem)
        if exact is not None:
            return exact

        for length in self._lengths:
            if len(stem) <= length or stem[length] not in {"_", "-", " "}:
                continue
            candidate = self._by_upper.get(stem[:length])
            if candidate is not None:
                return candidate

        return None


def _image_key(file_name: str) -> str:
    return file_name.strip().casefold()


def _missing_uploads(
    source_files: Iterable[Path],
    sharepoint_items: list[dict[str, Any]],
    source_name: str,
) -> list[Path]:
    existing_names = {
        str(item.get("name", "")).strip().casefold()
        for item in sharepoint_items
        if str(item.get("name", "")).strip()
    }
    missing_by_name: dict[str, list[Path]] = defaultdict(list)
    for path in source_files:
        normalized_name = path.name.strip().casefold()
        if normalized_name and normalized_name not in existing_names:
            missing_by_name[normalized_name].append(path)

    collisions = {
        name: paths for name, paths in missing_by_name.items() if len(paths) > 1
    }
    if collisions:
        examples = ", ".join(
            f"{name} ({len(paths)} files)"
            for name, paths in sorted(collisions.items())[:10]
        )
        raise ValueError(
            f"{source_name} contains duplicate filenames that cannot be safely "
            f"uploaded to one SharePoint root: {examples}"
        )

    return sorted(
        (paths[0] for paths in missing_by_name.values()),
        key=lambda path: path.name.casefold(),
    )


def _upload_paths(
    token: str,
    drive_id: str,
    paths: list[Path],
    source_name: str,
    workers: int,
) -> int:
    """Upload one source list concurrently with per-worker HTTP sessions."""

    total = len(paths)
    if total == 0:
        return 0

    worker_count = min(workers, total)
    batches = [paths[index::worker_count] for index in range(worker_count)]
    state_lock = Lock()
    stop = Event()
    processed = 0
    uploaded = 0
    already_exists = 0

    def upload_batch(batch: list[Path]) -> None:
        nonlocal processed, uploaded, already_exists
        session = create_graph_session(token)
        try:
            for path in batch:
                if stop.is_set():
                    return
                existed = False
                try:
                    upload_sharepoint_file(session, drive_id, path)
                except FileExistsError:
                    existed = True
                except Exception:
                    stop.set()
                    raise

                with state_lock:
                    processed += 1
                    if existed:
                        already_exists += 1
                    else:
                        uploaded += 1
                    if processed == 1 or processed % 100 == 0 or processed == total:
                        _progress(
                            f"{source_name} upload progress: "
                            f"{processed:,}/{total:,} checked; "
                            f"{uploaded:,} uploaded."
                        )
        finally:
            session.close()

    if worker_count == 1:
        # Keep access to older authenticated SMB shares on the calling thread.
        # Some Windows environments do not reliably make that UNC context
        # available inside a ThreadPoolExecutor worker.
        upload_batch(batches[0])
    else:
        with ThreadPoolExecutor(max_workers=worker_count) as executor:
            futures = [executor.submit(upload_batch, batch) for batch in batches]
            for future in as_completed(futures):
                future.result()

    if already_exists:
        _progress(
            f"{source_name}: skipped {already_exists:,} files that appeared in "
            "SharePoint after the initial listing."
        )
    return uploaded


def _upload_missing_images(
    token: str,
    product_drive_id: str,
    thumbnail_drive_id: str,
    settings: ImageSourceSettings,
    product_files: list[tuple[Path, str]],
    logger: DatabaseLogger,
    *,
    dry_run: bool = False,
) -> ImageSyncResult:
    """Upload missing network images without changing existing SharePoint files."""

    product_session = create_graph_session(token)
    thumbnail_session = create_graph_session(token)
    try:
        _progress("Reading the Product Images and BC_Images SharePoint libraries...")
        with ThreadPoolExecutor(max_workers=2) as executor:
            product_future = executor.submit(
                list_sharepoint_drive_files,
                product_session,
                product_drive_id,
                recursive=False,
                progress=_sharepoint_progress("Product Images"),
            )
            thumbnail_future = executor.submit(
                list_sharepoint_drive_files,
                thumbnail_session,
                thumbnail_drive_id,
                recursive=False,
                progress=_sharepoint_progress("BC_Images"),
            )
            product_items = product_future.result()
            thumbnail_items = thumbnail_future.result()

        _progress(
            f"SharePoint listing complete: {len(product_items):,} Product Images "
            f"entries and {len(thumbnail_items):,} BC_Images entries."
        )
        _progress("Comparing SharePoint filenames with the network sources...")

        product_paths = _missing_uploads(
            (path for path, _ in product_files),
            product_items,
            "Item Docs",
        )
        thumbnail_paths = _missing_uploads(
            iter_files_by_extension(settings.thumbnail_path, IMAGE_EXTENSIONS),
            thumbnail_items,
            "thumbnail directory",
        )

        logger.info(
            TABLE,
            "check missing SharePoint images",
            f"found {len(product_paths)} product and {len(thumbnail_paths)} "
            "thumbnail images to upload",
            len(product_paths) + len(thumbnail_paths),
        )
        _progress(
            f"Comparison complete: {len(product_paths):,} Product Images and "
            f"{len(thumbnail_paths):,} BC thumbnails need uploading."
        )

        if dry_run:
            _progress("Dry run complete; no files were uploaded.")
            return ImageSyncResult(len(product_paths), len(thumbnail_paths))

        product_total = len(product_paths)
        if product_total:
            _progress(
                f"Uploading {product_total:,} missing Product Images using "
                f"{settings.product_upload_workers} worker..."
            )
        product_uploaded = _upload_paths(
            token,
            product_drive_id,
            product_paths,
            "Product Images",
            settings.product_upload_workers,
        )
        thumbnail_total = len(thumbnail_paths)
        if thumbnail_total:
            _progress(
                f"Uploading {thumbnail_total:,} missing BC thumbnails using "
                f"{settings.thumbnail_upload_workers} workers..."
            )
        thumbnail_uploaded = _upload_paths(
            token,
            thumbnail_drive_id,
            thumbnail_paths,
            "BC thumbnails",
            settings.thumbnail_upload_workers,
        )
        _progress("SharePoint uploads complete.")
        return ImageSyncResult(product_uploaded, thumbnail_uploaded)
    finally:
        product_session.close()
        thumbnail_session.close()


def _sharepoint_records(
    session: requests.Session,
    drive_id: str,
    source_code: str,
    image_type: str,
    matcher: ItemMatcher,
) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    metadata_downloads = 0
    for item in list_sharepoint_drive_files(
        session,
        drive_id,
        recursive=False,
        progress=_sharepoint_progress(source_code),
    ):
        item_id = item.get("id")
        file_name = str(item.get("name", "")).strip()
        if Path(file_name).suffix.casefold() not in IMAGE_EXTENSIONS:
            continue
        web_url = str(item.get("webUrl", "")).strip()
        if not web_url:
            raise ValueError(f"SharePoint image {file_name!r} has no webUrl")

        image = item.get("image") or {}
        file_size = item.get("size")
        width = image.get("width")
        height = image.get("height")
        if item_id and (file_size is None or width is None or height is None):
            try:
                content = download_sharepoint_file_bytes(session, drive_id, str(item_id))
                if file_size is None:
                    file_size = len(content)
                if width is None or height is None:
                    with Image.open(BytesIO(content)) as downloaded_image:
                        width, height = downloaded_image.size
                metadata_downloads += 1
                if metadata_downloads % 100 == 0:
                    _progress(
                        f"Reading {source_code}: downloaded {metadata_downloads:,} "
                        "files with missing metadata..."
                    )
            except Image.DecompressionBombError as exc:
                _progress(
                    f"Reading {source_code}: dimensions skipped for "
                    f"{file_name!r}: {exc}"
                )
            except (OSError, UnidentifiedImageError, requests.RequestException):
                pass
        records.append(
            {
                "item_id": matcher.from_file_name(file_name),
                "image_key": _image_key(file_name),
                "image_type": image_type,
                "file_name": file_name,
                "source_code": source_code,
                "source_file_id": str(item_id) if item_id else None,
                "location_type": "WEB",
                "location_uri": web_url,
                "file_size": file_size,
                "width": width,
                "height": height,
                "last_modified": parse_graph_datetime(item.get("lastModifiedDateTime")),
            }
        )

    return records


def _network_image_metadata(
    file_path: Path,
) -> tuple[int | None, int | None, int | None, datetime | None]:
    """Read location metadata, including legacy Windows SMB files where possible."""

    file_size: int | None = None
    last_modified: datetime | None = None
    try:
        stat = file_path.stat()
        file_size = stat.st_size
        last_modified = datetime.fromtimestamp(stat.st_mtime, timezone.utc).replace(
            tzinfo=None
        )
    except OSError:
        try:
            file_size = get_windows_file_size(file_path)
        except OSError:
            pass

    width: int | None = None
    height: int | None = None
    try:
        with Image.open(file_path) as image:
            width, height = image.size
    except Image.DecompressionBombError as exc:
        _progress(f"Dimensions skipped for {file_path}: {exc}")
    except UnidentifiedImageError:
        pass
    except OSError:
        try:
            content = read_windows_file_bytes(file_path)
            with Image.open(BytesIO(content)) as image:
                width, height = image.size
        except Image.DecompressionBombError as exc:
            _progress(f"Dimensions skipped for {file_path}: {exc}")
        except (OSError, UnidentifiedImageError):
            pass

    return file_size, width, height, last_modified


def _network_records(
    root: Path,
    source_code: str,
    image_type: str,
    matcher: ItemMatcher,
    *,
    item_from_top_folder: bool,
    product_files: list[tuple[Path, str]] | None = None,
) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    if item_from_top_folder:
        if product_files is None:
            raise ValueError("product_files is required for Item Docs")
        files = iter(product_files)
    else:
        files = (
            (file_path, None)
            for file_path in iter_files_by_extension(root, IMAGE_EXTENSIONS)
        )

    for file_path, folder_item_id in files:
        file_size, width, height, last_modified = _network_image_metadata(file_path)

        file_name = file_path.name
        matched_item = folder_item_id
        if matched_item is None:
            matched_item = matcher.from_file_name(file_name)

        records.append(
            {
                "item_id": matched_item,
                "image_key": _image_key(file_name),
                "image_type": image_type,
                "file_name": file_name,
                "source_code": source_code,
                "source_file_id": None,
                "location_type": "UNC",
                "location_uri": str(file_path),
                "file_size": file_size,
                "width": width,
                "height": height,
                "last_modified": last_modified,
            }
        )

    return records


def _combine_locations(
    source_records: list[list[dict[str, Any]]],
) -> tuple[DataFrame, int]:
    grouped: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for records in source_records:
        for record in records:
            grouped[(record["image_type"], record["image_key"])].append(record)

    expanded: list[dict[str, Any]] = []
    unmatched = 0
    for records in grouped.values():
        item_ids = sorted(
            {record["item_id"] for record in records if record["item_id"] is not None}
        )
        if not item_ids:
            unmatched += len(records)
            continue

        seen: set[tuple[str, str, bytes]] = set()
        for item_id in item_ids:
            for record in records:
                location_uri = record["location_uri"]
                location_hash = sha256(location_uri.casefold().encode("utf-8")).digest()
                key = (item_id, record["source_code"], location_hash)
                if key in seen:
                    continue
                seen.add(key)
                expanded.append(
                    {
                        **record,
                        "item_id": item_id,
                        "location_hash": location_hash,
                    }
                )

    if not expanded:
        raise ValueError("none of the discovered images matched an item")

    logical_keys = sorted(
        {(row["item_id"], row["image_type"], row["image_key"]) for row in expanded}
    )
    order_by_key: dict[tuple[str, str, str], int] = {}
    by_item_type: dict[tuple[str, str], list[str]] = defaultdict(list)
    for item_id, image_type, image_key in logical_keys:
        by_item_type[(item_id, image_type)].append(image_key)
    for (item_id, image_type), image_keys in by_item_type.items():
        for position, image_key in enumerate(sorted(image_keys), start=1):
            order_by_key[(item_id, image_type, image_key)] = position

    for row in expanded:
        position = order_by_key[(row["item_id"], row["image_type"], row["image_key"])]
        row["display_order"] = position
        row["is_primary"] = position == 1

    frame = DataFrame(expanded)
    return frame[STAGING_COLUMNS], unmatched


def _item_ids(engine: Engine) -> set[str]:
    with engine.connect() as connection:
        return {
            row[0]
            for row in connection.exec_driver_sql(
                "SELECT [item_id] FROM [dbo].[items] WHERE [item_id] <> N'';"
            )
        }


def _product_image_links(
    engine: Engine,
    root: Path,
    logger: DatabaseLogger,
) -> list[tuple[Path, str]]:
    """Read unblocked LTD image paths from record_link without crawling Item Docs."""

    root_path = os.path.normcase(os.path.abspath(root))
    files: dict[str, tuple[Path, str]] = {}
    ignored = 0
    with engine.connect() as connection:
        rows = connection.exec_driver_sql(
            "SELECT i.[item_id], rl.[url] "
            "FROM [dbo].[items] AS i "
            "INNER JOIN [dbo].[record_link] AS rl "
            "ON rl.[entity] = N'Example Ltd' "
            "AND rl.[system] = N'NAV' "
            "AND rl.[record_id] = i.[record_id] "
            "WHERE i.[item_id] <> N'' "
            "AND i.[ltd_blocked] = 0 "
            "AND rl.[url] IS NOT NULL;"
        )
        for item_id, raw_url in rows:
            path = Path(str(raw_url).strip())
            if (
                is_ignored_system_file(path)
                or path.suffix.casefold() not in IMAGE_EXTENSIONS
            ):
                continue
            normalized_path = os.path.normcase(os.path.abspath(path))
            try:
                if os.path.commonpath((root_path, normalized_path)) != root_path:
                    ignored += 1
                    continue
            except ValueError:
                ignored += 1
                continue
            files[normalized_path] = (path, item_id)

    if ignored:
        logger.warning(
            TABLE,
            "validate Item Docs record links",
            f"ignored {ignored} image links outside the configured Item Docs root",
            ignored,
        )
    return sorted(files.values(), key=lambda value: str(value[0]).casefold())


def _replace_images(engine: Engine, frame: DataFrame) -> None:
    rows = len(frame)
    write_df_to_sql_db(
        engine,
        STAGING_TABLE,
        frame,
        "replace",
        chunksize=min(rows, 20000),
        datatype=STAGING_DATATYPES,
    )

    _, error = execute_sql_procedure(
        engine,
        "EXEC [dbo].[update_item_images_table];",
    )
    if error is not None:
        raise RuntimeError(error)


def sync_item_images_to_sharepoint(
    engine_sql18: Engine,
    logger: DatabaseLogger,
    *,
    dry_run: bool = False,
) -> ImageSyncResult | None:
    """Upload network images missing from SharePoint, or only report a dry run."""

    try:
        _progress("Starting SharePoint image synchronization.")
        _progress("Loading current item IDs and unblocked LTD image record links...")
        item_ids = _item_ids(engine_sql18)
        if not item_ids:
            raise ValueError("items must be populated before images are synchronized")
        settings = ImageSourceSettings.from_environment()
        product_files = _product_image_links(
            engine_sql18, settings.item_docs_path, logger
        )
        _progress(f"Found {len(product_files):,} eligible Product Image links.")
        _progress("Authenticating with Microsoft Graph...")
        token = acquire_token(
            settings.tenant_id, settings.client_id, settings.client_secret
        )
        if not token:
            raise ValueError("Microsoft Graph did not return an access token")
        _progress("Authentication successful; resolving SharePoint libraries...")
        product_drive_id, thumbnail_drive_id = _resolve_image_drive_ids(token, settings)
        _progress("SharePoint libraries resolved.")
        result = _upload_missing_images(
            token,
            product_drive_id,
            thumbnail_drive_id,
            settings,
            product_files,
            logger,
            dry_run=dry_run,
        )
        action = "check missing SharePoint images" if dry_run else "upload images"
        message = (
            f"dry run found {result.total} missing images"
            if dry_run
            else f"uploaded {result.total} missing images without replacing existing files"
        )
        logger.info(TABLE, action, message, result.total)
        _progress(message.capitalize() + ".")
        return result
    except Exception as exc:  # noqa: BLE001
        _progress(f"ERROR: {exc}")
        logger.error(TABLE, "synchronize SharePoint images", str(exc))
        return None


def update_item_images_table(
    engine_sql18: Engine,
    logger: DatabaseLogger,
) -> int | None:
    """Refresh item images from two SharePoint libraries and two UNC roots."""

    try:
        _progress("Starting upload and SQL catalogue refresh.")
        _progress("Loading current item IDs and unblocked LTD image record links...")
        item_ids = _item_ids(engine_sql18)
        if not item_ids:
            raise ValueError("items must be populated before item images are updated")
        matcher = ItemMatcher(item_ids)
        settings = ImageSourceSettings.from_environment()
        product_files = _product_image_links(
            engine_sql18, settings.item_docs_path, logger
        )
        _progress(f"Found {len(product_files):,} eligible Product Image links.")

        _progress("Authenticating with Microsoft Graph...")
        token = acquire_token(
            settings.tenant_id, settings.client_id, settings.client_secret
        )
        if not token:
            raise ValueError("Microsoft Graph did not return an access token")

        _progress("Authentication successful; resolving SharePoint libraries...")
        product_drive_id, thumbnail_drive_id = _resolve_image_drive_ids(token, settings)
        _progress("SharePoint libraries resolved.")

        upload_result = _upload_missing_images(
            token,
            product_drive_id,
            thumbnail_drive_id,
            settings,
            product_files,
            logger,
        )
        logger.info(
            TABLE,
            "upload missing SharePoint images",
            f"uploaded {upload_result.total} missing images without replacing "
            "existing files",
            upload_result.total,
        )

        _progress("Reading final SharePoint and network image metadata...")
        product_session = create_graph_session(token)
        thumbnail_session = create_graph_session(token)

        try:
            with ThreadPoolExecutor(max_workers=4) as executor:
                futures = [
                    executor.submit(
                        _sharepoint_records,
                        product_session,
                        product_drive_id,
                        "SP_PRODUCT",
                        "PRODUCT",
                        matcher,
                    ),
                    executor.submit(
                        _sharepoint_records,
                        thumbnail_session,
                        thumbnail_drive_id,
                        "SP_THUMBNAIL",
                        "THUMBNAIL",
                        matcher,
                    ),
                    executor.submit(
                        _network_records,
                        settings.item_docs_path,
                        "NAS_ITEM_DOCS",
                        "PRODUCT",
                        matcher,
                        item_from_top_folder=True,
                        product_files=product_files,
                    ),
                    executor.submit(
                        _network_records,
                        settings.thumbnail_path,
                        "NAS_THUMBNAIL",
                        "THUMBNAIL",
                        matcher,
                        item_from_top_folder=False,
                    ),
                ]
                source_records = [future.result() for future in futures]
        finally:
            product_session.close()
            thumbnail_session.close()

        _progress(
            "Metadata read complete: "
            + ", ".join(
                f"{source}={len(records):,}"
                for source, records in zip(
                    ("SP_PRODUCT", "SP_THUMBNAIL", "NAS_ITEM_DOCS", "NAS_THUMBNAIL"),
                    source_records,
                    strict=True,
                )
            )
            + "."
        )

        for source, records in zip(
            ("SP_PRODUCT", "SP_THUMBNAIL", "NAS_ITEM_DOCS", "NAS_THUMBNAIL"),
            source_records,
            strict=True,
        ):
            logger.info(
                TABLE,
                f"scan {source}",
                f"discovered {len(records)} image files",
                len(records),
            )

        frame, unmatched = _combine_locations(source_records)
        if unmatched:
            logger.warning(
                TABLE,
                "match images to items",
                f"ignored {unmatched} source files that did not match an item",
                unmatched,
            )

        _progress("Writing staging data and executing update_item_images_table...")
        _replace_images(engine_sql18, frame)
        logical_images = frame[["item_id", "image_type", "image_key"]].drop_duplicates()
        logger.info(
            TABLE,
            "replace item images",
            f"loaded {len(logical_images)} logical images and {len(frame)} locations",
            len(logical_images),
        )
        _progress(
            f"SQL catalogue refresh complete: {len(logical_images):,} logical "
            f"images and {len(frame):,} locations."
        )
        return len(frame)
    except Exception as exc:  # noqa: BLE001
        try:
            with engine_sql18.begin() as connection:
                connection.exec_driver_sql(
                    "DROP TABLE IF EXISTS [dbo].[item_image_locations_staging];"
                )
        except Exception:  # noqa: BLE001, S110
            pass
        _progress(f"ERROR: {exc}")
        logger.error(TABLE, "update item images", str(exc))
        return None
