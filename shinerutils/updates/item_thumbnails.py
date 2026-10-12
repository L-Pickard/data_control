"""Fill the SQL18 thumbnail folder: copy marketing's thumbnails and make the missing ones.

Each run does three things, in this order:

1. Copies thumbnails that are new or changed in marketing's NAS folder to the
   SQL18 folder. Nothing on the NAS is changed. A real thumbnail replaces a
   generated one of the same name.
2. Makes a 450 x 450 thumbnail from the product photo of every eligible item
   that still has no thumbnail in the SQL18 folder.
3. Adds the files it touched to the image catalogue (source SQL18_THUMBNAIL),
   so they show at once. The morning image refresh finds them again by itself.

Eligible items are not placeholders and are unblocked in Shiner Ltd or
Shiner B.V, or sold in the last month. Photos are read from the Item Docs
share only (the NAS_ITEM_DOCS rows of the catalogue); SharePoint is not used.
Nothing is ever deleted, and a file that is not a generated thumbnail is
never replaced by one.
"""

from __future__ import annotations

import os
import shutil
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import datetime, timezone
from hashlib import sha256
from io import BytesIO
from pathlib import Path
from time import perf_counter
from typing import Any

from pandas import DataFrame
from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy.dialects.mssql import BIGINT, BINARY, DATETIME2, INTEGER, NVARCHAR
from sqlalchemy.engine import Engine

from shinerutils.constants import PROJECT_ROOT
from shinerutils.filesystem import is_ignored_system_file, read_windows_file_bytes
from shinerutils.logging import DatabaseLogger
from shinerutils.sql import execute_sql_procedure, write_df_to_sql_db
from shinerutils.updates.item_images import IMAGE_EXTENSIONS, ItemMatcher
from shinerutils.utils import environment_value, load_environment_file

TABLE = "item_thumbnails"
SOURCE_CODE = "SQL18_THUMBNAIL"
STAGING_TABLE = "item_thumbnail_locations_staging"
DEFAULT_NAS_THUMBNAIL_PATH = r"\\Shinernas01\ShinerData\MARKETING\001 Master Thumbnail Images"
DEFAULT_SQL18_THUMBNAIL_PATH = r"\\SHINERSQL18\001 Master Thumbnail Images"
THUMBNAIL_SIDE = 450
JPEG_QUALITY = 85
# The largest product photo in the catalogue is about 21 MB.
MAX_PHOTO_BYTES = 25 * 1024 * 1024
THUMBNAIL_SUFFIX = "_THUMB.jpg"
# Characters Windows does not allow in a file name. An item whose number holds one is skipped.
_INVALID_NAME_CHARACTERS = frozenset('<>:"/\\|?*')
STAGING_DATATYPES = {
    "item_id": NVARCHAR(20),
    "image_key": NVARCHAR(255),
    "file_name": NVARCHAR(255),
    "location_uri": NVARCHAR(2048),
    "location_hash": BINARY(32),
    "file_size": BIGINT(),
    "width": INTEGER(),
    "height": INTEGER(),
    "last_modified": DATETIME2(precision=3),
}

# The product photo to shrink for each eligible item: its first photo on the Item Docs share that the catalogue
# could read. "Sold in the last month" is by posting date, on SQL Server's own clock.
CANDIDATE_SQL = """
WITH sold AS (
    SELECT DISTINCT s.[item_id]
    FROM [dbo].[sales] AS s
    WHERE s.[posting_date] >= DATEADD(MONTH, -1, CAST(SYSDATETIME() AS DATE))
)
SELECT i.[item_id], p.[location_uri], p.[last_modified]
FROM [dbo].[items] AS i
CROSS APPLY (
    SELECT TOP (1) il.[location_uri], il.[last_modified]
    FROM [dbo].[item_images] AS ii
    INNER JOIN [dbo].[item_image_locations] AS il
        ON il.[item_image_id] = ii.[item_image_id]
    WHERE ii.[item_id] = i.[item_id]
        AND ii.[image_type] = N'PRODUCT'
        AND il.[source_code] = N'NAS_ITEM_DOCS'
        AND il.[width] IS NOT NULL
        AND il.[file_size] <= ?
    ORDER BY ii.[display_order], il.[image_location_id]
) AS p
WHERE i.[item_id] <> N''
    AND i.[is_placeholder] = 0
    AND (
        i.[ltd_blocked] = 0
        OR i.[bv_blocked] = 0
        OR EXISTS (SELECT 1 FROM sold AS s WHERE s.[item_id] = i.[item_id])
    )
ORDER BY i.[item_id];
"""


def _progress(message: str) -> None:
    print(f"[item_thumbnails] {message}", flush=True)


@dataclass(frozen=True)
class ThumbnailSettings:
    nas_thumbnail_path: Path
    sql18_thumbnail_path: Path

    @classmethod
    def from_environment(cls) -> ThumbnailSettings:
        load_environment_file(PROJECT_ROOT / ".env")
        return cls(
            nas_thumbnail_path=Path(
                environment_value("IMAGE_NAS_THUMBNAIL_PATH", default=DEFAULT_NAS_THUMBNAIL_PATH)
                or DEFAULT_NAS_THUMBNAIL_PATH
            ),
            sql18_thumbnail_path=Path(
                environment_value("IMAGE_SQL18_THUMBNAIL_PATH", default=DEFAULT_SQL18_THUMBNAIL_PATH)
                or DEFAULT_SQL18_THUMBNAIL_PATH
            ),
        )


@dataclass(frozen=True)
class ThumbnailResult:
    copied: int
    generated: int
    regenerated: int
    unreadable: int
    catalogued: int
    candidates: int
    # Set when the files were written but their catalogue rows could not be added.
    catalogue_error: str | None = None

    @property
    def files_written(self) -> int:
        return self.copied + self.generated + self.regenerated


@dataclass(frozen=True)
class _Photo:
    item_id: str
    path: Path
    last_modified: datetime | None


def make_thumbnail(content: bytes, side: int = THUMBNAIL_SIDE) -> bytes | None:
    """Fit a picture inside a white square and return it as a JPEG, or None when it cannot be read.

    The picture is never enlarged. A photo stored on its side is turned upright, and transparent areas become
    white. This matches the thumbnails the portal makes in memory (PictureShrinker.cs).
    """

    try:
        with Image.open(BytesIO(content)) as source:
            # A large JPEG is decoded at a reduced size (still at least twice the thumbnail), which is what
            # makes this fast: a 20-megapixel photo is never held in full.
            source.draft("RGB", (side * 2, side * 2))
            image = ImageOps.exif_transpose(source)
            if image.mode in ("RGBA", "LA") or (image.mode == "P" and "transparency" in image.info):
                image = image.convert("RGBA")
                background = Image.new("RGBA", image.size, "white")
                image = Image.alpha_composite(background, image).convert("RGB")
            else:
                image = image.convert("RGB")
            image.thumbnail((side, side), Image.Resampling.LANCZOS)
            canvas = Image.new("RGB", (side, side), "white")
            canvas.paste(image, ((side - image.width) // 2, (side - image.height) // 2))
            output = BytesIO()
            canvas.save(output, "JPEG", quality=JPEG_QUALITY, optimize=True)
            return output.getvalue()
    except (OSError, ValueError, UnidentifiedImageError, Image.DecompressionBombError):
        return None


def thumbnail_file_name(item_id: str) -> str | None:
    """`<item>_THUMB.jpg`, the name marketing's thumbnails use; None when the item number cannot be a file name."""

    name = item_id.strip()
    if not name or name != item_id or name.endswith(".") or any(
        character in _INVALID_NAME_CHARACTERS or ord(character) < 32 for character in name
    ):
        return None
    return name + THUMBNAIL_SUFFIX


def _read_bytes(path: Path) -> bytes:
    try:
        return path.read_bytes()
    except OSError:
        # The Item Docs share sometimes refuses Python's ordinary open (Windows error 59).
        return read_windows_file_bytes(path)


def _write_atomically(target: Path, write: Any) -> None:
    """Write beside the target, then swap it in, so a reader never sees half a file."""

    temporary = target.with_name(f"{target.name}.{os.getpid()}.tmp")
    try:
        write(temporary)
        os.replace(temporary, target)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def _utc(timestamp: float) -> datetime:
    return datetime.fromtimestamp(timestamp, timezone.utc).replace(tzinfo=None)


@dataclass(frozen=True)
class _File:
    path: Path
    size: int
    modified: float


def scan_pictures(root: Path) -> dict[str, _File]:
    """Every picture under a folder, by its path below the folder in lower case.

    Sizes and times come from the folder listing itself (os.scandir), not from one request per file: over the
    network that is the difference between seconds and many minutes for 21,000 files.
    """

    if not root.is_dir():
        raise FileNotFoundError(f"source directory is unavailable: {root}")
    files: dict[str, _File] = {}
    folders = [root]
    while folders:
        folder = folders.pop()
        with os.scandir(folder) as entries:
            for entry in entries:
                if entry.is_dir(follow_symlinks=False):
                    folders.append(Path(entry.path))
                elif not is_ignored_system_file(entry.name) and Path(entry.name).suffix.casefold() in IMAGE_EXTENSIONS:
                    stat = entry.stat()
                    path = Path(entry.path)
                    files[str(path.relative_to(root)).casefold()] = _File(path, stat.st_size, stat.st_mtime)
    return files


def _same_file(source: _File, target: _File) -> bool:
    # Copies keep the source's modified time; two seconds allows for coarser file systems.
    return source.size == target.size and abs(source.modified - target.modified) <= 2


def copy_new_nas_thumbnails(
    settings: ThumbnailSettings,
    nas_files: dict[str, _File],
    sql18_files: dict[str, _File],
    *,
    dry_run: bool = False,
) -> list[Path]:
    """Copy thumbnails that are new or changed on the NAS; returns the SQL18 paths written (or that would be)."""

    targets: list[Path] = []
    for key, source in sorted(nas_files.items()):
        existing = sql18_files.get(key)
        if existing is not None and _same_file(source, existing):
            continue
        target = settings.sql18_thumbnail_path / source.path.relative_to(settings.nas_thumbnail_path)
        targets.append(target)
        if not dry_run:
            target.parent.mkdir(parents=True, exist_ok=True)
            _write_atomically(target, lambda temporary, source=source: shutil.copy2(source.path, temporary))
        sql18_files[key] = _File(target, source.size, source.modified)
    return targets


def _candidates(engine: Engine) -> list[_Photo]:
    with engine.connect() as connection:
        rows = connection.exec_driver_sql(CANDIDATE_SQL, (MAX_PHOTO_BYTES,)).fetchall()
    return [_Photo(item_id, Path(uri), modified) for item_id, uri, modified in rows]


def _item_ids(engine: Engine) -> set[str]:
    with engine.connect() as connection:
        return {
            row[0]
            for row in connection.exec_driver_sql(
                "SELECT [item_id] FROM [dbo].[items] WHERE [item_id] <> N'';"
            )
        }


def plan_thumbnails(
    photos: Iterable[_Photo],
    sql18_files: dict[str, _File],
    nas_names: set[str],
    matcher: ItemMatcher,
) -> tuple[list[tuple[_Photo, str]], list[tuple[_Photo, str]]]:
    """Which thumbnails to make, and which generated ones to make again because the photo is newer.

    sql18_files: file name (lower case) -> file, for every picture in the SQL18 folder.
    nas_names: file names (lower case) in marketing's folder; a file with one of these names is theirs.
    """

    items_with_thumbnail = {matcher.from_file_name(file.path.name) for file in sql18_files.values()}
    create: list[tuple[_Photo, str]] = []
    refresh: list[tuple[_Photo, str]] = []
    for photo in photos:
        name = thumbnail_file_name(photo.item_id)
        if name is None:
            continue
        existing = sql18_files.get(name.casefold())
        if existing is None:
            # Any thumbnail of the item counts, whatever marketing called it.
            if photo.item_id not in items_with_thumbnail:
                create.append((photo, name))
        elif name.casefold() not in nas_names and photo.last_modified is not None:
            if photo.last_modified > _utc(existing.modified):
                refresh.append((photo, name))
    return create, refresh


def _location_row(path: Path, item_id: str) -> dict[str, Any]:
    stat = path.stat()
    with Image.open(path) as image:
        width, height = image.size
    uri = str(path)
    return {
        "item_id": item_id,
        "image_key": path.name.strip().casefold(),
        "file_name": path.name,
        "location_uri": uri,
        "location_hash": sha256(uri.casefold().encode("utf-8")).digest(),
        "file_size": stat.st_size,
        "width": width,
        "height": height,
        "last_modified": _utc(stat.st_mtime),
    }


def _add_to_catalogue(engine: Engine, rows: list[dict[str, Any]]) -> None:
    write_df_to_sql_db(
        engine, STAGING_TABLE, DataFrame(rows), "replace", chunksize=min(len(rows), 20000), datatype=STAGING_DATATYPES
    )
    _, error = execute_sql_procedure(engine, "EXEC [dbo].[merge_item_thumbnail_locations];")
    if error is not None:
        raise RuntimeError(error)


def make_missing_item_thumbnails(
    engine_sql18: Engine,
    logger: DatabaseLogger,
    *,
    dry_run: bool = False,
    limit: int | None = None,
    output_dir: Path | None = None,
) -> ThumbnailResult | None:
    """Copy new NAS thumbnails, make the missing ones and add both to the catalogue.

    dry_run: count what would be copied and made; write nothing anywhere.
    limit: make at most this many thumbnails in this run.
    output_dir: a trial run. Thumbnails are written to this folder instead; nothing is copied from the NAS,
        the SQL18 folder is only read and the catalogue is not changed.
    """

    try:
        started = perf_counter()
        settings = ThumbnailSettings.from_environment()
        trial = output_dir is not None
        if not settings.sql18_thumbnail_path.is_dir():
            raise FileNotFoundError(f"the SQL18 thumbnail folder is unavailable: {settings.sql18_thumbnail_path}")

        nas_files = scan_pictures(settings.nas_thumbnail_path)
        sql18_files = scan_pictures(settings.sql18_thumbnail_path)
        _progress(f"{len(nas_files):,} thumbnails on the NAS, {len(sql18_files):,} in the SQL18 folder.")
        copied: list[Path] = []
        if not trial:
            # Also records each copy in sql18_files (in a dry run too), so a copied file is not counted as missing.
            copied = copy_new_nas_thumbnails(settings, nas_files, sql18_files, dry_run=dry_run)
            _progress(f"{len(copied):,} thumbnails {'would be' if dry_run else 'were'} copied from the NAS.")
        nas_names = {file.path.name.casefold() for file in nas_files.values()}
        sql18_by_name = {file.path.name.casefold(): file for file in sql18_files.values()}

        matcher = ItemMatcher(_item_ids(engine_sql18))
        photos = _candidates(engine_sql18)
        create, refresh = plan_thumbnails(photos, sql18_by_name, nas_names, matcher)
        _progress(
            f"{len(photos):,} eligible items have a product photo; {len(create):,} need a thumbnail and "
            f"{len(refresh):,} generated thumbnails are older than their photo."
        )
        work = [(photo, name, False) for photo, name in create] + [(photo, name, True) for photo, name in refresh]
        if limit is not None:
            work = work[:limit]

        generated = regenerated = unreadable = 0
        written: list[tuple[Path, str]] = []
        if not dry_run:
            folder = output_dir if trial else settings.sql18_thumbnail_path
            folder.mkdir(parents=True, exist_ok=True)
            for position, (photo, name, again) in enumerate(work, start=1):
                thumbnail: bytes | None = None
                try:
                    thumbnail = make_thumbnail(_read_bytes(photo.path))
                except OSError:
                    pass
                if thumbnail is None:
                    unreadable += 1
                else:
                    target = folder / name
                    _write_atomically(target, lambda temporary, data=thumbnail: temporary.write_bytes(data))
                    written.append((target, photo.item_id))
                    regenerated += again
                    generated += not again
                if position % 250 == 0 or position == len(work):
                    _progress(f"{position:,}/{len(work):,} photos read; {len(written):,} thumbnails written.")
        else:
            generated = sum(1 for _, _, again in work if not again)
            regenerated = len(work) - generated

        catalogued = 0
        catalogue_error: str | None = None
        if not dry_run and not trial:
            rows = [_location_row(path, item_id) for path, item_id in written]
            for path in copied:
                item_id = matcher.from_file_name(path.name)
                if item_id is not None:
                    rows.append(_location_row(path, item_id))
            if rows:
                try:
                    _add_to_catalogue(engine_sql18, rows)
                    catalogued = len(rows)
                except Exception as exc:  # noqa: BLE001
                    # The files are in place; only their catalogue rows are missing until the morning refresh.
                    catalogue_error = str(exc)
                    try:
                        with engine_sql18.begin() as connection:
                            connection.exec_driver_sql(f"DROP TABLE IF EXISTS [dbo].[{STAGING_TABLE}];")
                    except Exception:  # noqa: BLE001, S110
                        pass
                    logger.error(
                        table=TABLE,
                        action="add thumbnails to the image catalogue",
                        message=f"{len(rows)} thumbnail files were written but not added to the catalogue; "
                        f"the morning image refresh will add them. Error: {exc}",
                        rows=len(rows),
                    )

        if unreadable:
            logger.warning(
                table=TABLE,
                action="read product photos",
                message=f"{unreadable} product photos could not be read or are not pictures; "
                "their items still have no thumbnail",
                rows=unreadable,
            )
        result = ThumbnailResult(len(copied), generated, regenerated, unreadable, catalogued, len(photos), catalogue_error)
        _progress(
            f"{'Dry run: ' if dry_run else ''}{result.copied:,} copied, {result.generated:,} made, "
            f"{result.regenerated:,} made again, {result.unreadable:,} unreadable, "
            f"{result.catalogued:,} added to the catalogue, in {perf_counter() - started:.1f} seconds."
        )
        return result
    except Exception as exc:  # noqa: BLE001
        _progress(f"ERROR: {exc}")
        logger.error(table=TABLE, action="make missing item thumbnails", message=str(exc))
        return None
