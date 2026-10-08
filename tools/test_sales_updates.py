"""Check incremental sales outcomes without touching databases."""

import sys
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from pandas import DataFrame
from shinerutils.updates.sales import update_sales_table


class SalesUpdateTests(unittest.TestCase):
    def run_update(self, sources):
        logger = Mock()
        def load(engine, *args):
            return sources[engine]
        with patch("shinerutils.updates.sales.get_sales_increment", return_value="2026-10-05"), \
             patch("shinerutils.updates.sales.concurrent_df_load_params", side_effect=load), \
             patch("shinerutils.updates.sales.write_df_to_sql_db") as write, \
             patch("shinerutils.updates.sales.execute_sql_procedure", return_value=(0, None)) as execute:
            result = update_sales_table("nav", "usa", "warehouse", logger)
        return result, logger, write, execute

    def test_empty_success_does_not_write_or_execute(self):
        result, logger, write, execute = self.run_update({
            "nav": (DataFrame(), None), "usa": (DataFrame(), None),
        })
        self.assertEqual(result, 0)
        logger.error.assert_not_called()
        self.assertIn("no new sales", logger.info.call_args.kwargs["message"])
        write.assert_not_called()
        execute.assert_not_called()

    def test_source_failure_is_not_an_empty_success(self):
        for source in ("nav", "usa"):
            with self.subTest(source=source):
                sources = {"nav": (DataFrame(), None), "usa": (DataFrame(), None)}
                sources[source] = (None, "query failed")
                result, logger, write, execute = self.run_update(sources)
                self.assertIsNone(result)
                logger.error.assert_called_once()
                write.assert_not_called()
                execute.assert_not_called()

    def test_one_empty_source_still_loads_other_source(self):
        for source in ("nav", "usa"):
            with self.subTest(source=source):
                sources = {"nav": (DataFrame(), None), "usa": (DataFrame(), None)}
                sources[source] = (DataFrame([{"entity": "Shiner Ltd"}]), None)
                result, logger, write, execute = self.run_update(sources)
                self.assertEqual(result, 1)
                write.assert_called_once()
                execute.assert_called_once()


if __name__ == "__main__":
    unittest.main()
