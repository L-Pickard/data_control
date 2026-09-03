import os
from ftplib import FTP
from pathlib import Path


def get_ftp_connection(
    server_env: str = "FTP_SERVER",
    user_env: str = "FTP_USER",
    password_env: str = "FTP_PASS",
) -> tuple[FTP | None, str | None]:
    """Return an authenticated FTP connection or an error message."""

    try:
        server = os.environ.get(server_env)
        username = os.environ.get(user_env)
        password = os.environ.get(password_env)
        if not server or not username or not password:
            raise RuntimeError(
                f"FTP credentials require {server_env}, {user_env}, and {password_env}"
            )

        ftp = FTP(server)
        ftp.login(username, password)
        return ftp, None
    except Exception as e:  # noqa: BLE001
        return None, str(e)


def list_ftp_files(
    ftp: FTP, directory: str = "/"
) -> tuple[list[str] | None, str | None]:
    """Return the files in an FTP directory or an error message."""

    try:
        ftp.cwd(directory)
        return ftp.nlst(), None
    except Exception as e:  # noqa: BLE001
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
    except Exception as e:  # noqa: BLE001
        return str(e)


def delete_ftp_file(ftp: FTP, remote_name: str) -> str | None:
    """Delete a remote file and return an error message if deletion fails."""

    try:
        ftp.delete(remote_name)
        return None
    except Exception as e:  # noqa: BLE001
        return str(e)
