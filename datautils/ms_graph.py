
from collections import deque
from datetime import datetime, timezone
import os
from io import BytesIO
from pathlib import Path
from stat import S_ISREG
from time import sleep
from typing import Any, Callable
from urllib.parse import quote

import requests

from datautils.filesystem import get_windows_file_size, read_windows_file_bytes


GRAPH_ROOT = "https://graph.microsoft.com/v1.0"
RETRYABLE_GRAPH_STATUS_CODES = {429, 500, 502, 503, 504}
SIMPLE_UPLOAD_LIMIT = 10 * 1024 * 1024


def _retry_delay(response: requests.Response | None, attempt: int) -> float:
    if response is not None:
        retry_after = response.headers.get("Retry-After")
        if retry_after:
            try:
                return min(max(float(retry_after), 0.0), 60.0)
            except ValueError:
                pass
    return min(float(2**attempt), 30.0)


def _request_with_retry(
    request: Callable[[], requests.Response],
    *,
    attempts: int = 5,
) -> requests.Response:
    """Retry transient Graph timeouts, connection errors and throttling."""

    if attempts < 1:
        raise ValueError("attempts must be at least 1")
    for attempt in range(1, attempts + 1):
        response: requests.Response | None = None
        try:
            response = request()
            if response.status_code not in RETRYABLE_GRAPH_STATUS_CODES:
                return response
            if attempt == attempts:
                return response
        except (requests.Timeout, requests.ConnectionError):
            if attempt == attempts:
                raise

        delay = _retry_delay(response, attempt)
        if response is not None:
            response.close()
        sleep(delay)

    raise RuntimeError("request retry loop ended unexpectedly")


def _source_file_size(path: Path, *, attempts: int = 8) -> int:
    """Read file size with retries for transient UNC/network-share failures."""

    last_error: OSError | None = None
    for attempt in range(1, attempts + 1):
        try:
            file_stat = path.stat()
            if not S_ISREG(file_stat.st_mode):
                raise FileNotFoundError(f"upload source is not a file: {path}")
            return file_stat.st_size
        except OSError as exc:
            if getattr(exc, "winerror", None) == 59:
                return get_windows_file_size(path)
            last_error = exc
            if attempt < attempts:
                sleep(min(float(2**attempt), 15.0))

    raise FileNotFoundError(
        f"upload source file remained unavailable after {attempts} attempts: "
        f"{path}. Last error: {last_error}"
    ) from last_error


def _read_source_bytes(path: Path, *, attempts: int = 8) -> bytes:
    """Read a small source file with retries for transient UNC failures."""

    last_error: OSError | None = None
    for attempt in range(1, attempts + 1):
        try:
            return path.read_bytes()
        except OSError as exc:
            if getattr(exc, "winerror", None) == 59:
                return read_windows_file_bytes(path)
            last_error = exc
            if attempt < attempts:
                sleep(min(float(2**attempt), 15.0))

    raise OSError(
        f"could not read upload source after {attempts} attempts: {path}. "
        f"Last error: {last_error}"
    ) from last_error


def parse_graph_datetime(value: Any) -> datetime | None:
    """Convert a Microsoft Graph ISO timestamp to naive UTC for SQL DATETIME2."""

    if not value:
        return None
    parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    return parsed.astimezone(timezone.utc).replace(tzinfo=None)


def create_graph_session(token: str) -> requests.Session:
    """Return a reusable authenticated Microsoft Graph HTTP session."""

    if not token:
        raise ValueError("a Microsoft Graph access token is required")
    session = requests.Session()
    session.headers.update({"Authorization": f"Bearer {token}"})
    return session


def download_sharepoint_file_bytes(
    session: requests.Session,
    drive_id: str,
    item_id: str,
) -> bytes:
    """Download a SharePoint drive item, retrying transient Graph failures."""

    encoded_drive_id = quote(drive_id, safe="")
    encoded_item_id = quote(item_id, safe="")
    url = f"{GRAPH_ROOT}/drives/{encoded_drive_id}/items/{encoded_item_id}/content"
    response = _request_with_retry(
        lambda: session.get(url, timeout=(15, 120)),
    )
    try:
        response.raise_for_status()
        return response.content
    finally:
        response.close()


def graph_get_json(
    session: requests.Session,
    url: str,
    *,
    params: dict[str, str] | None = None,
    timeout: int = 60,
) -> dict[str, Any]:
    """GET a Microsoft Graph JSON object with consistent error handling."""

    response = session.get(url, params=params, timeout=timeout)
    response.raise_for_status()
    result = response.json()
    if not isinstance(result, dict):
        raise ValueError(f"Microsoft Graph returned a non-object response for {url}")
    return result


def graph_paged_values(
    session: requests.Session,
    url: str,
    *,
    params: dict[str, str] | None = None,
    progress: Callable[[int], None] | None = None,
) -> list[dict[str, Any]]:
    """Read all values from a paginated Microsoft Graph collection."""

    values: list[dict[str, Any]] = []
    next_url: str | None = url
    next_params = params
    while next_url is not None:
        payload = graph_get_json(session, next_url, params=next_params)
        page = payload.get("value", [])
        if not isinstance(page, list):
            raise ValueError(f"Microsoft Graph returned an invalid page for {next_url}")
        values.extend(item for item in page if isinstance(item, dict))
        if progress is not None:
            progress(len(values))
        next_url = payload.get("@odata.nextLink")
        next_params = None
    return values


def resolve_sharepoint_site_id(
    session: requests.Session, hostname: str, site_path: str
) -> str:
    """Resolve a SharePoint hostname and server-relative path to a site ID."""

    url = f"{GRAPH_ROOT}/sites/{hostname}:{site_path}"
    site_id = graph_get_json(session, url, params={"$select": "id"}).get("id")
    if not site_id:
        raise ValueError(f"could not resolve SharePoint site {hostname}:{site_path}")
    return str(site_id)


def resolve_sharepoint_drive_id(
    session: requests.Session, site_id: str, library_name: str
) -> str:
    """Resolve one document library by its display name."""

    drives = graph_paged_values(
        session,
        f"{GRAPH_ROOT}/sites/{site_id}/drives",
        params={"$select": "id,name,webUrl"},
    )
    matches = [
        drive
        for drive in drives
        if str(drive.get("name", "")).casefold() == library_name.casefold()
    ]
    if len(matches) != 1:
        available = sorted(str(drive.get("name", "")) for drive in drives)
        raise ValueError(
            f"expected one SharePoint library named {library_name!r}; "
            f"found {len(matches)}. Available libraries: {available}"
        )
    return str(matches[0]["id"])


def list_sharepoint_drive_files(
    session: requests.Session,
    drive_id: str,
    *,
    select: str = "id,name,size,webUrl,lastModifiedDateTime,file,image,folder",
    recursive: bool = True,
    progress: Callable[[int], None] | None = None,
) -> list[dict[str, Any]]:
    """List files in a SharePoint library, optionally traversing subfolders."""

    pending = deque([f"{GRAPH_ROOT}/drives/{drive_id}/root/children"])
    files: list[dict[str, Any]] = []
    while pending:
        children = graph_paged_values(
            session,
            pending.popleft(),
            params={"$select": select, "$top": "200"},
            progress=progress,
        )
        for item in children:
            item_id = item.get("id")
            if recursive and item.get("folder") is not None and item_id:
                pending.append(
                    f"{GRAPH_ROOT}/drives/{drive_id}/items/{item_id}/children"
                )
            elif item.get("file") is not None:
                files.append(item)
    return files


def upload_sharepoint_file(
    session: requests.Session,
    drive_id: str,
    source_path: Path | str,
    *,
    destination_name: str | None = None,
    chunk_size: int = 10 * 1024 * 1024,
) -> dict[str, Any]:
    """Upload one new file to a drive root without replacing name conflicts."""

    path = Path(source_path)
    file_size = _source_file_size(path)
    if file_size <= 0:
        raise ValueError(f"refusing to upload an empty file: {path}")
    if chunk_size <= 0 or chunk_size % 327_680 != 0:
        raise ValueError("chunk_size must be a positive multiple of 320 KiB")

    file_name = (destination_name or path.name).strip()
    if not file_name or file_name in {".", ".."} or "/" in file_name or "\\" in file_name:
        raise ValueError(f"invalid SharePoint destination filename: {file_name!r}")

    encoded_name = quote(file_name, safe="")

    if file_size <= SIMPLE_UPLOAD_LIMIT:
        upload_url = f"{GRAPH_ROOT}/drives/{drive_id}/root:/{encoded_name}:/content"
        content = _read_source_bytes(path)
        response = _request_with_retry(
            lambda: session.put(
                upload_url,
                headers={
                    "Content-Type": "application/octet-stream",
                    "If-None-Match": "*",
                },
                data=content,
                timeout=(10, 60),
            )
        )
        if response.status_code in {409, 412}:
            raise FileExistsError(f"SharePoint already contains {file_name!r}")
        response.raise_for_status()
        result = response.json()
        if not isinstance(result, dict):
            raise ValueError("Microsoft Graph returned an invalid upload result")
        return result

    create_url = (
        f"{GRAPH_ROOT}/drives/{drive_id}/root:/{encoded_name}:/createUploadSession"
    )
    response = _request_with_retry(
        lambda: session.post(
            create_url,
            json={
                "item": {
                    "@microsoft.graph.conflictBehavior": "fail",
                    "name": file_name,
                }
            },
            timeout=(10, 30),
        )
    )
    if response.status_code == 409:
        raise FileExistsError(f"SharePoint already contains {file_name!r}")
    response.raise_for_status()
    upload_url = response.json().get("uploadUrl")
    if not upload_url:
        raise ValueError("Microsoft Graph did not return an upload URL")

    try:
        source_stream = path.open("rb")
    except OSError as exc:
        if getattr(exc, "winerror", None) != 59:
            raise
        source_stream = BytesIO(read_windows_file_bytes(path))

    with source_stream as source:
        offset = 0
        while offset < file_size:
            content = source.read(min(chunk_size, file_size - offset))
            end = offset + len(content) - 1
            upload_response = _request_with_retry(
                lambda: requests.put(
                    upload_url,
                    headers={
                        "Content-Length": str(len(content)),
                        "Content-Range": f"bytes {offset}-{end}/{file_size}",
                    },
                    data=content,
                    timeout=(10, 120),
                )
            )
            if upload_response.status_code in {200, 201}:
                result = upload_response.json()
                if not isinstance(result, dict):
                    raise ValueError("Microsoft Graph returned an invalid upload result")
                return result
            if upload_response.status_code != 202:
                upload_response.raise_for_status()
            offset = end + 1

    raise RuntimeError(f"Microsoft Graph did not complete the upload for {file_name!r}")


def open_sharepoint_excel_desktop(web_url) -> str | None:

    try:

        os.startfile(f"ms-excel:ofe|u|{web_url}")

        return None
    
    except Exception as e:
        return str(e)


def get_sharepoint_file_info(token, site_id, sharepoint_path):

    url = f"https://graph.microsoft.com/v1.0/sites/{site_id}/drive/root:/{sharepoint_path}"
    headers = {"Authorization": f"Bearer {token}"}

    resp = requests.get(url, headers=headers)

    if resp.status_code == 404:

        return None

    resp.raise_for_status()
    return resp.json()


def acquire_token(tenant_id: str, client_id: str, client_secret: str) -> str | None:
    url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token"

    data = {
        "grant_type": "client_credentials",
        "client_id": client_id,
        "client_secret": client_secret,
        "scope": "https://graph.microsoft.com/.default",
    }

    resp = requests.post(url, data=data, timeout=60)
    resp.raise_for_status()

    result = resp.json()
    return result.get("access_token")


def download_sharepoint_file(token, site_id, sharepoint_path, local_path):
    url = f"https://graph.microsoft.com/v1.0/sites/{site_id}/drive/root:/{sharepoint_path}:/content"
    headers = {"Authorization": f"Bearer {token}"}

    resp = requests.get(url, headers=headers)

    if not resp.ok:
        print("URL:", url)
        print("Status:", resp.status_code)
        print("Body:", resp.text)
        resp.raise_for_status()

    with open(local_path, "wb") as f:
        f.write(resp.content)


def delete_sharepoint_file(token, site_id, remote_path):
    headers = {"Authorization": f"Bearer {token}"}

    url = f"https://graph.microsoft.com/v1.0/sites/{site_id}/drive/root:/{remote_path}"

    resp = requests.delete(url, headers=headers)

    if resp.status_code == 404:
        return

    resp.raise_for_status()


def file_is_from_today_utc(info) -> bool:

    last_modified_str = info.get("fileSystemInfo", {}).get("lastModifiedDateTime") or info.get(
        "lastModifiedDateTime"
    )

    if not last_modified_str:
        return False

    last_modified = datetime.fromisoformat(last_modified_str.replace("Z", "+00:00"))

    today_utc = datetime.now(timezone.utc).date()

    return last_modified.date() == today_utc
