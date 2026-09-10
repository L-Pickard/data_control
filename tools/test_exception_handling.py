"""Exception handling regression checks without external services."""

import sys
import unittest
from decimal import Decimal
from pathlib import Path
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from pandas import DataFrame

from shinerutils.ftp import get_ftp_connection, list_ftp_files
from shinerutils.ms_graph import open_sharepoint_excel_desktop
from shinerutils.updates.monthly_average_exchange_rates import _validate_rates
from shinerutils.utils import concurrent_df_load, concurrent_df_load_params


class ExceptionHandlingTests(unittest.TestCase):
    def test_query_read_errors_and_logger_errors(self):
        for load, extra in [(concurrent_df_load, []), (concurrent_df_load_params, [{}])]:
            path = Mock()
            for error in [OSError("missing"), UnicodeError("invalid encoding")]:
                path.read_text.side_effect = error
                frame, message = load(Mock(), path, *extra, Mock(), "sql02 brands")
                self.assertIsNone(frame)
                self.assertIn(str(error), message)
            path.read_text.side_effect = None
            path.read_text.return_value = "SELECT 1"
            logger = Mock()
            logger.info.side_effect = RuntimeError("logger bug")
            with self.assertRaisesRegex(RuntimeError, "logger bug"):
                load(Mock(), path, *extra, logger, "sql02 brands")

    def test_ftp_expected_errors_and_unexpected_errors(self):
        ftp = Mock()
        ftp.cwd.side_effect = TimeoutError("timeout")
        self.assertEqual(list_ftp_files(ftp), (None, "timeout"))
        ftp.cwd.side_effect = TypeError("bug")
        with self.assertRaises(TypeError):
            list_ftp_files(ftp)
        with patch.dict("os.environ", {}, clear=True), patch("shinerutils.ftp.FTP") as factory:
            connection, error = get_ftp_connection()
            self.assertIsNone(connection)
            self.assertIn("FTP credentials require", error)
            factory.assert_not_called()

    def test_excel_launch_errors(self):
        with patch("shinerutils.ms_graph.os.startfile", side_effect=OSError("no Excel")):
            self.assertEqual(open_sharepoint_excel_desktop("example"), "no Excel")
        with patch("shinerutils.ms_graph.os.startfile", side_effect=TypeError("bug")):
            with self.assertRaises(TypeError):
                open_sharepoint_excel_desktop("example")

    def test_validation(self):
        rates = dict(start_date="2026-01-01", end_date="2026-01-31", from_currency_code="GBP", to_currency_code="EUR", currency_pair_code="GBP/EUR", exchange_rate_value=Decimal("1.25"))
        for validate, row, text_column, number_column, date_column in [
            (_validate_rates, rates, "from_currency_code", "exchange_rate_value", "start_date"),
        ]:
            self.assertEqual(len(validate(DataFrame([row]))), 1)
            with self.assertRaisesRegex(ValueError, "missing columns"):
                validate(DataFrame([row]).drop(columns=[text_column]))
            for column, value in [(text_column, []), (number_column, "oops"), (date_column, {}), (date_column, "invalid"), (date_column, "NaT")]:
                with self.subTest(validate=validate.__name__, column=column, value=value):
                    with self.assertRaises(ValueError):
                        validate(DataFrame([{**row, column: value}]))


if __name__ == "__main__":
    unittest.main()
