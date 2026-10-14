"""Inventory-cost refresh failure and transaction checks; no database writes."""

import sys
import unittest
from decimal import Decimal
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from pandas import DataFrame
from shinerutils.updates.item_inventory_costs import update_item_inventory_costs_table

MODULE = "shinerutils.updates.item_inventory_costs"


def source(entity):
    return DataFrame([{
        "entity": entity, "item_id": "ABC001", "quantity": Decimal("2"),
        "cost": Decimal("123.12345678901234567890"),
        "first_receipt": "2024-01-01", "last_receipt": "2026-10-14",
    }])


class InventoryCostTests(unittest.TestCase):
    def setUp(self):
        self.warehouse = MagicMock()
        self.logger = Mock()

    def run_update(self, loader, writer):
        with patch(f"{MODULE}.concurrent_df_load", side_effect=loader), patch(
            f"{MODULE}.write_df_to_sql_db", writer
        ):
            return update_item_inventory_costs_table(
                "nav", "llc", self.warehouse, self.logger
            )

    @staticmethod
    def load(engine, *args):
        return source("Shiner Ltd" if engine == "nav" else "Shiner LLC"), None

    def test_success_combines_sources_and_preserves_decimal_precision(self):
        writer = Mock()
        self.assertEqual(self.run_update(self.load, writer), 2)
        connection = self.warehouse.begin.return_value.__enter__.return_value
        self.assertIs(writer.call_args.args[0], connection)
        frame = writer.call_args.args[2]
        self.assertEqual(set(frame.entity), {"Shiner Ltd", "Shiner LLC"})
        self.assertEqual(frame.cost.tolist(), [Decimal("123.12345678901234567890")] * 2)
        self.assertEqual(frame.columns.tolist(), ["entity", "item_id", "quantity", "cost", "first_receipt", "last_receipt"])

    def test_missing_receipt_history_is_nullable(self):
        def load(engine, *args):
            frame, error = self.load(engine)
            frame["first_receipt"] = None
            frame["last_receipt"] = None
            return frame, error
        writer = Mock()
        self.assertEqual(self.run_update(load, writer), 2)
        self.assertEqual(writer.call_args.args[2]["first_receipt"].tolist(), [None, None])

    def test_invalid_receipt_range_does_not_open_transaction(self):
        for first in ("2027-01-01", "not a date", None):
            with self.subTest(first=first):
                def load(engine, *args):
                    frame, error = self.load(engine)
                    frame["first_receipt"] = first
                    return frame, error
                self.assertIsNone(self.run_update(load, Mock()))
                self.warehouse.begin.assert_not_called()

    def test_source_failure_does_not_open_write_transaction(self):
        def load(engine, *args):
            return (None, "source unavailable") if engine == "llc" else self.load(engine)
        self.assertIsNone(self.run_update(load, Mock()))
        self.warehouse.begin.assert_not_called()

    def test_invalid_data_does_not_open_write_transaction(self):
        for invalid in (None, Decimal("NaN"), Decimal("Infinity")):
            with self.subTest(cost=invalid):
                def load(engine, *args):
                    frame, error = self.load(engine)
                    frame.loc[0, "cost"] = invalid
                    return frame, error
                self.assertIsNone(self.run_update(load, Mock()))
                self.warehouse.begin.assert_not_called()

    def test_duplicate_keys_do_not_open_write_transaction(self):
        self.assertIsNone(self.run_update(lambda *args: (source("Shiner LLC"), None), Mock()))
        self.warehouse.begin.assert_not_called()

    def test_insert_failure_rolls_back_delete(self):
        self.assertIsNone(self.run_update(self.load, Mock(side_effect=RuntimeError("insert failed"))))
        transaction = self.warehouse.begin.return_value
        self.assertIs(transaction.__exit__.call_args.args[0], RuntimeError)
        self.logger.error.assert_called_once()


if __name__ == "__main__":
    unittest.main()
