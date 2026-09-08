"""Local regression checks; no FTP, SQL, or production-share access."""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts import ftp_polling
from shinerutils.ftp import download_ftp_file, get_ftp_connection, polling_lock


class FtpPollingTests(unittest.TestCase):
    def test_connection_timeout_and_failed_login_cleanup(self):
        with patch.dict("os.environ", FTP_SERVER="example", FTP_USER="user", FTP_PASS="test"):
            with patch("shinerutils.ftp.FTP") as factory:
                factory.return_value.login.side_effect = TimeoutError("timed out")
                connection, error = get_ftp_connection()
                self.assertIsNone(connection)
                self.assertEqual(error, "timed out")
                factory.assert_called_once_with(timeout=120)
                factory.return_value.close.assert_called_once()

    def test_transfer_timeout_releases_file(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "history.csv"
            ftp = Mock()

            def stalled_transfer(command, callback):
                callback(b"partial download")
                raise TimeoutError("transfer stalled")

            ftp.retrbinary.side_effect = stalled_transfer
            self.assertEqual(download_ftp_file(ftp, "history.csv", source), "transfer stalled")
            # Windows refuses this rename if the writer's handle is still open.
            source.rename(Path(folder) / "released.csv")

    def test_overlapping_process_is_rejected_and_lock_is_reusable(self):
        with tempfile.TemporaryDirectory() as folder:
            lock_path = Path(folder) / "polling.lock"
            code = (
                "from pathlib import Path; from shinerutils.ftp import polling_lock; "
                "import sys\nwith polling_lock(Path(sys.argv[1])): pass"
            )
            with polling_lock(lock_path):
                result = subprocess.run(
                    [sys.executable, "-c", code, str(lock_path)],
                    capture_output=True, text=True, timeout=30,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("another run may still be active", result.stderr)
            with polling_lock(lock_path):
                pass

    def test_locked_source_does_not_create_archive_copy(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "history.csv"
            source.write_bytes(b"loaded data")
            archive = Path(folder) / "archive"
            with patch.object(ftp_polling, "ARCHIVE_DIRECTORY", archive):
                with source.open("rb"):
                    error = ftp_polling.move_local_file(source, "archive")
                self.assertIsNotNone(error)
                self.assertTrue(source.exists())
                self.assertEqual(list(archive.iterdir()), [])
                self.assertIsNone(ftp_polling.move_local_file(source, "archive"))
                self.assertFalse(source.exists())
                self.assertEqual(next(archive.iterdir()).read_bytes(), b"loaded data")


if __name__ == "__main__":
    unittest.main()
