import os
from contextlib import contextmanager
from ftplib import FTP, all_errors
from pathlib import Path

FTP_TIMEOUT_SECONDS = 120


@contextmanager
def polling_lock(lock_path: Path):
    """Hold a Windows byte-range lock for the entire polling run.

    The file remains on disk; Windows releases the lock even if Python is killed.
    All scheduled/manual runs must use the same path, including over SMB.
    """
    import msvcrt

    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a+b") as lock_file:
        lock_file.seek(0, os.SEEK_END)
        if lock_file.tell() == 0:
            lock_file.write(b"0")
            lock_file.flush()
        lock_file.seek(0)
        try:
            msvcrt.locking(lock_file.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError as exc:
            raise RuntimeError(
                "Cannot acquire FTP polling lock; another run may still be active."
            ) from exc
        try:
            yield
        finally:
            lock_file.seek(0)
            msvcrt.locking(lock_file.fileno(), msvcrt.LK_UNLCK, 1)


def get_ftp_connection(
    server_env: str = "FTP_SERVER",
    user_env: str = "FTP_USER",
    password_env: str = "FTP_PASS",
    timeout_seconds: float = FTP_TIMEOUT_SECONDS,
) -> tuple[FTP | None, str | None]:
    """Return an authenticated FTP connection or an error message."""

    server = os.environ.get(server_env)
    username = os.environ.get(user_env)
    password = os.environ.get(password_env)
    if not server or not username or not password:
        return None, f"FTP credentials require {server_env}, {user_env}, and {password_env}"

    ftp = None
    try:
        ftp = FTP(timeout=timeout_seconds)
        ftp.connect(server)
        ftp.login(username, password)
        return ftp, None
    except all_errors as e:
        if ftp is not None:
            ftp.close()
        return None, str(e)


def list_ftp_files(
    ftp: FTP, directory: str = "/"
) -> tuple[list[str] | None, str | None]:
    """Return the files in an FTP directory or an error message."""

    try:
        ftp.cwd(directory)
        return ftp.nlst(), None
    except all_errors as e:
        return None, str(e)


def download_ftp_file(
    ftp: FTP, remote_name: str, local_path: Path
) -> str | None:
    """Download a file and return an error message if the operation fails."""

    try:
        local_path.parent.mkdir(parents=True, exist_ok=True)
        with local_path.open("wb") as local_file:
            ftp.retrbinary(f"RETR {remote_name}", local_file.write)
        return None
    except all_errors as e:
        return str(e)


def delete_ftp_file(ftp: FTP, remote_name: str) -> str | None:
    """Delete a remote file and return an error message if deletion fails."""

    try:
        ftp.delete(remote_name)
        return None
    except all_errors as e:
        return str(e)
