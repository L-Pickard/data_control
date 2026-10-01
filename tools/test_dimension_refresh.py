"""Regression checks for the 1 October refresh failures."""
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from pandas import DataFrame
from shinerutils.updates.dimensions import upsert_dimension
from shinerutils.updates.item_images import _product_image_links, _record_link_path


class RefreshTests(unittest.TestCase):
    def test_bad_dimension_keys_do_not_open_transaction(self):
        for ids in [[], [None], ["GB", "GB"]]:
            engine = Mock()
            with self.assertRaises(ValueError):
                upsert_dimension(engine, "countries", DataFrame({"country_id": ids}))
            engine.begin.assert_not_called()

    def test_write_failure_exits_transaction_with_error(self):
        from unittest.mock import MagicMock
        engine = MagicMock()
        connection = engine.begin.return_value.__enter__.return_value
        connection.execute.side_effect = [None, RuntimeError("write failed")]
        frame = DataFrame([
            dict(country_id=code, iso_code=code, country_name=code, flag_image_url=None)
            for code in ["GB", "US"]
        ])
        with self.assertRaisesRegex(RuntimeError, "write failed"):
            upsert_dimension(engine, "countries", frame)
        self.assertIs(engine.begin.return_value.__exit__.call_args.args[0], RuntimeError)

    def test_file_urls_and_unc_paths(self):
        expected = Path(r"\\shinersql02\item_docs\ABC\image one.jpg")
        for value in [str(expected), "file://" + str(expected),
                      "file://shinersql02/item_docs/ABC/image%20one.jpg"]:
            self.assertEqual(_record_link_path(value), expected)

    def test_file_url_still_obeys_root_boundary(self):
        from unittest.mock import MagicMock
        engine = MagicMock()
        connection = engine.connect.return_value.__enter__.return_value
        connection.exec_driver_sql.return_value = [
            ("OK", r"file://\\shinersql02\item_docs\products\OK\image.jpg"),
            ("BAD", r"file://\\other\share\image.jpg"),
            ("BAD", r"file://\\shinersql02\item_docs\products\..\private\image.jpg"),
        ]
        logger = Mock()
        links = _product_image_links(engine, Path(r"\\shinersql02\item_docs\products"), logger)
        self.assertEqual([item for _, item in links], ["OK"])
        self.assertEqual(logger.warning.call_args.kwargs["rows"], 2)


if __name__ == "__main__":
    unittest.main()
