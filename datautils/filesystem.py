import ctypes
import os
from collections.abc import Iterator
from ctypes import wintypes
from pathlib import Path

_GENERIC_READ = 0x80000000
_FILE_SHARE_ALL = 0x00000007
_OPEN_EXISTING = 3
_FILE_FLAG_SEQUENTIAL_SCAN = 0x08000000
_INVALID_HANDLE_VALUE = wintypes.HANDLE(-1).value


def _open_windows_file(path: Path | str) -> tuple[object, int]:
    if os.name != "nt":
        raise OSError("the Windows file API fallback is only available on Windows")

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.CreateFileW.argtypes = [
        wintypes.LPCWSTR,
        wintypes.DWORD,
        wintypes.DWORD,
        wintypes.LPVOID,
        wintypes.DWORD,
        wintypes.DWORD,
        wintypes.HANDLE,
    ]
    kernel32.CreateFileW.restype = wintypes.HANDLE
    kernel32.GetFileSizeEx.argtypes = [
        wintypes.HANDLE,
        ctypes.POINTER(ctypes.c_longlong),
    ]
    kernel32.GetFileSizeEx.restype = wintypes.BOOL
    kernel32.ReadFile.argtypes = [
        wintypes.HANDLE,
        wintypes.LPVOID,
        wintypes.DWORD,
        ctypes.POINTER(wintypes.DWORD),
        wintypes.LPVOID,
    ]
    kernel32.ReadFile.restype = wintypes.BOOL
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel32.CloseHandle.restype = wintypes.BOOL
    handle = kernel32.CreateFileW(
        str(path),
        _GENERIC_READ,
        _FILE_SHARE_ALL,
        None,
        _OPEN_EXISTING,
        _FILE_FLAG_SEQUENTIAL_SCAN,
        None,
    )
    if handle == _INVALID_HANDLE_VALUE:
        raise ctypes.WinError(ctypes.get_last_error())
    return kernel32, handle


def get_windows_file_size(path: Path | str) -> int:
    """Read file size using CreateFileW, including legacy SMB paths."""

    kernel32, handle = _open_windows_file(path)
    try:
        size = ctypes.c_longlong()
        if not kernel32.GetFileSizeEx(handle, ctypes.byref(size)):
            raise ctypes.WinError(ctypes.get_last_error())
        return size.value
    finally:
        kernel32.CloseHandle(handle)


def read_windows_file_bytes(path: Path | str) -> bytes:
    """Read a file through Win32 when Python stat/open fails on legacy SMB."""

    kernel32, handle = _open_windows_file(path)
    try:
        chunks: list[bytes] = []
        chunk_size = 8 * 1024 * 1024
        while True:
            buffer = ctypes.create_string_buffer(chunk_size)
            bytes_read = wintypes.DWORD()
            if not kernel32.ReadFile(
                handle,
                buffer,
                chunk_size,
                ctypes.byref(bytes_read),
                None,
            ):
                raise ctypes.WinError(ctypes.get_last_error())
            if bytes_read.value == 0:
                break
            chunks.append(buffer.raw[: bytes_read.value])
        return b"".join(chunks)
    finally:
        kernel32.CloseHandle(handle)


def is_ignored_system_file(path_or_name: Path | str) -> bool:
    """Return true for common filesystem metadata files, not business files."""

    name = Path(path_or_name).name
    return name.startswith("._") or name.casefold() in {
        ".ds_store",
        "desktop.ini",
        "thumbs.db",
    }


def iter_files_by_extension(
    root: Path | str,
    extensions: set[str] | frozenset[str],
) -> Iterator[Path]:
    """Yield files recursively whose suffix is in a case-insensitive allow-list."""

    root_path = Path(root)
    if not root_path.exists() or not root_path.is_dir():
        raise FileNotFoundError(f"source directory is unavailable: {root_path}")

    normalized_extensions = {extension.casefold() for extension in extensions}
    for directory, _, file_names in os.walk(root_path):
        directory_path = Path(directory)
        for file_name in file_names:
            if is_ignored_system_file(file_name):
                continue
            path = directory_path / file_name
            if path.suffix.casefold() in normalized_extensions:
                yield path
