# Item image source configuration

The item-image refresh reads two SharePoint document libraries and two UNC
directories. Microsoft Graph requires an Entra application with permission to
write to the configured SharePoint site (for example, `Sites.Selected` with a
write grant, or `Sites.ReadWrite.All`).

The updater automatically loads `C:\Users\leo.pickard\src\data_control\.env`.
Copy `.env.example` to `.env`, then enter the three required values:

```text
MS_GRAPH_TENANT_ID=<tenant GUID>
MS_GRAPH_CLIENT_ID=<application/client GUID>
MS_GRAPH_CLIENT_SECRET=<client secret>
```

`.env` is excluded from Git. Values already set in the process environment take
precedence over values in the file, so the same code also works with server-level
environment variables or a deployment secret store.

You may supply direct SharePoint IDs:

```text
IMAGE_SHAREPOINT_SITE_ID=<optional site ID>
IMAGE_SHAREPOINT_PRODUCT_DRIVE_ID=<optional Product Images drive ID>
IMAGE_SHAREPOINT_THUMBNAIL_DRIVE_ID=<optional BC_Images drive ID>
```

The two drive IDs are optional. When either is blank, the updater resolves it
from the site and library names. A direct drive ID takes precedence over its
library name. The site ID is only used while resolving a missing drive ID; when
it is also blank, the updater resolves the site from its hostname and path.

The current source names and paths are built-in defaults. They can be changed
without editing code by setting any of the following variables:

```text
IMAGE_SHAREPOINT_HOSTNAME=shinerltd.sharepoint.com
IMAGE_SHAREPOINT_SITE_PATH=/sites/ShinerUKLtd
IMAGE_SHAREPOINT_PRODUCT_LIBRARY=Product Images
IMAGE_SHAREPOINT_THUMBNAIL_LIBRARY=BC_Images
IMAGE_SHAREPOINT_PRODUCT_UPLOAD_WORKERS=1
IMAGE_SHAREPOINT_THUMBNAIL_UPLOAD_WORKERS=4
IMAGE_NAS_ITEM_DOCS_PATH=\\shinersql02\item_docs
IMAGE_NAS_THUMBNAIL_PATH=\\Shinernas01\ShinerData\MARKETING\001 Master Thumbnail Images
```

The process identity must also have read access to both UNC directories.

Product-image candidates come from `dbo.record_link`, joined to Shiner Ltd
items where `ltd_blocked = 0`. The updater uses those exact record-link paths;
it does not recursively crawl all of `\\shinersql02\item_docs`. Thumbnail
candidates are the image files under the configured thumbnail directory.

Both SharePoint libraries are compared by case-insensitive filename. Only
missing filenames are uploaded to the library root. Existing SharePoint files
are never deliberately replaced, renamed or deleted. Duplicate missing source
filenames cause the update to stop rather than overwrite one with another.
macOS AppleDouble files (`._*`) and common operating-system metadata files are
ignored. Small images use the single-request Graph upload API; large files use
resumable upload sessions. Transient timeouts, throttling and server errors are
retried. Product Images use one worker by default because the Item Docs SMB
share is sensitive to concurrent reads; thumbnails use four workers. When
Python receives Windows error 59 from the legacy Item Docs SMB share, file size
and bytes are read directly through the Win32 file API without making a staging
copy.

## Update architecture

The Python update performs only source-facing work:

1. Resolve the SharePoint site and libraries through Microsoft Graph.
2. Read eligible Item Docs paths from `dbo.record_link` and scan thumbnails.
3. Upload files whose names are missing from their SharePoint library.
4. Read the resulting SharePoint root files and network sources.
5. Match files to current item IDs, combine mirrored locations and validate the
   result.
6. Write `dbo.item_image_locations_staging`.
7. Execute `dbo.update_item_images_table`.

The stored procedure validates staging again and replaces `item_images` and
`item_image_locations` in one SQL transaction. A failed scan, staging write or
stored-procedure execution leaves the existing production rows unchanged.

`dbo.item_image_catalogue` presents item IDs together with their logical images
and physical locations. File size, width and height describe each
physical location and are exposed together in this view. Only items with both
a logical image and a physical image location are included; items without
images do not produce empty rows.

The refresh reads file size and image-header dimensions for UNC files. If the
Graph listing omits any of those values for a SharePoint image, the refresh
downloads that file and reads the missing metadata locally. A file that is
temporarily inaccessible or is not a decodable image remains in the catalogue
with null metadata rather than causing the complete refresh to fail.

Reusable helpers are exported from `shinerutils`:

- `load_environment_file`
- `environment_value`
- `first_environment_value`
- `iter_files_by_extension`
- `create_graph_session`
- `graph_get_json`
- `graph_paged_values`
- `resolve_sharepoint_site_id`
- `resolve_sharepoint_drive_id`
- `list_sharepoint_drive_files`
- `upload_sharepoint_file`
- `parse_graph_datetime`

Check what is missing without uploading:

```powershell
& "C:\Users\leo.pickard\src\data_control\venv\Scripts\python.exe" "C:\Users\leo.pickard\src\data_control\scripts\sync_item_images.py" --dry-run
```

Upload missing files without rebuilding the SQL catalogue:

```powershell
& "C:\Users\leo.pickard\src\data_control\venv\Scripts\python.exe" "C:\Users\leo.pickard\src\data_control\scripts\sync_item_images.py"
```

Upload missing files and then rebuild the SQL image catalogue:

```powershell
& "C:\Users\leo.pickard\src\data_control\venv\Scripts\python.exe" "C:\Users\leo.pickard\src\data_control\scripts\run_update.py" item_images
```

## Thumbnails made from product photos (12 October 2026)

`scripts/make_item_thumbnails.py` keeps the thumbnail folder on SHINERSQL18
(`\\SHINERSQL18\001 Master Thumbnail Images`, setting
`IMAGE_SQL18_THUMBNAIL_PATH`) filled. Each run:

1. Copies thumbnails that are new or changed in marketing's NAS folder to the
   SQL18 folder (same name, modified time kept). Nothing on the NAS changes. A
   marketing thumbnail replaces a generated one of the same name.
2. Makes `<item>_THUMB.jpg` (450 x 450, white background, JPEG) from the first
   Item Docs photo of each eligible item that has no thumbnail in the SQL18
   folder. A generated thumbnail is made again when its photo is newer.
3. Adds the files it wrote to the catalogue through
   `dbo.merge_item_thumbnail_locations` (source `SQL18_THUMBNAIL`).

Eligible items: not placeholders, and unblocked in Shiner Ltd or Shiner B.V,
or sold in the last month (the LLC flag is not used: it is unblocked for
nearly every item). Photos come from the `NAS_ITEM_DOCS` rows of the
catalogue only; SharePoint is not read. Nothing is deleted, and generated
thumbnails are not uploaded to the SharePoint `BC_Images` library.

The morning refresh scans the SQL18 folder as a fifth source
(`SQL18_THUMBNAIL`), so the rows survive its daily rebuild. The NAS rows
(`NAS_THUMBNAIL`) are unchanged. `sql/migrations/20261012_add_sql18_thumbnail_source.sql`
must be run before the first refresh with this code, or the refresh fails.

```powershell
python scripts\make_item_thumbnails.py --dry-run                       # counts only, writes nothing
python scripts\make_item_thumbnails.py --limit 25 --output-dir C:\Temp\trial   # trial: files to another folder only
python scripts\make_item_thumbnails.py                                 # the real run
python -W ignore tools\test_item_thumbnails.py                         # offline checks
```

SQL Server Agent job: `sql/database/agent_job_item_thumbnails.sql` (created
disabled; set its two paths first). Measured from a desktop PC on 12 October
2026: a run with nothing to do takes about 10 seconds, and thumbnails are made
at about 25 a second (2,589 were missing).
