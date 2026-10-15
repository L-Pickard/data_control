"""Inventory cost check and dataset job: validation, transactions and queue handling; no database access."""

import sys
import unittest
from contextlib import contextmanager
from datetime import date
from decimal import Decimal
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from pandas import DataFrame
from shinerutils.updates import inventory_cost
from shinerutils.updates.inventory_cost import (
    RECEIPT_COLUMNS,
    UNADJUSTED_COLUMNS,
    process_inventory_cost_requests,
    run_inventory_cost_check,
    run_inventory_cost_dataset,
    validate_dataset,
)

MODULE = "shinerutils.updates.inventory_cost"
AS_OF = date(2026, 9, 30)


def stock(entity="Shiner Ltd", item="ABC001", **changes):
    row = {
        "entity": entity, "item_id": item, "quantity": Decimal("2"), "cost": Decimal("10.12345678901234567890"),
        "expected_cost": Decimal("1.5"), "first_receipt": "2024-01-01", "last_receipt": "2026-09-01",
    }
    row.update(changes)
    return row


def receipt(entity="Shiner Ltd"):
    return dict.fromkeys(RECEIPT_COLUMNS, None) | {"entity": entity, "document_no": "PRC-1", "document_line_no": 10000,
                                                   "item_id": "ABC001", "quantity": Decimal("5"), "quantity_invoiced": Decimal("0"),
                                                   "quantity_not_invoiced": Decimal("5")}


def unadjusted(entity="Shiner Ltd", entry=1):
    return dict.fromkeys(UNADJUSTED_COLUMNS, None) | {"entity": entity, "entry_no": entry, "item_id": "ABC001",
                                                      "entry_type": "Purchase", "quantity": Decimal("3"), "remaining_quantity": Decimal("3")}


class ValidateDatasetTests(unittest.TestCase):
    def test_valid_rows_keep_decimal_precision_and_missing_expected_cost_is_zero(self):
        frame = validate_dataset(DataFrame([stock(), stock("Shiner LLC", expected_cost=None), stock("Shiner B.V", expected_cost=float("nan"))]))
        self.assertEqual(frame.cost.tolist()[0], Decimal("10.12345678901234567890"))
        self.assertEqual(frame.expected_cost.tolist(), [Decimal("1.5"), Decimal(0), Decimal(0)])
        self.assertEqual(frame.first_receipt.tolist()[0], date(2024, 1, 1))

    def test_rows_without_receipts_are_kept_with_no_dates(self):
        frame = validate_dataset(DataFrame([stock(first_receipt=None, last_receipt=None)]))
        self.assertEqual(frame.first_receipt.tolist(), [None])

    def test_invalid_rows_are_refused(self):
        cases = {
            "empty": DataFrame(columns=inventory_cost.STAGING_COLUMNS),
            "unknown company": DataFrame([stock("Shiner Inc")]),
            "repeated item": DataFrame([stock(), stock()]),
            "zero quantity": DataFrame([stock(quantity=Decimal(0))]),
            "missing cost": DataFrame([stock(cost=None)]),
            "infinite cost": DataFrame([stock(cost=Decimal("Infinity"))]),
            "blank item": DataFrame([stock(item=" ")]),
            "reversed receipts": DataFrame([stock(first_receipt="2026-09-02")]),
            "half a receipt range": DataFrame([stock(last_receipt=None)]),
        }
        for name, frame in cases.items():
            with self.subTest(name):
                self.assertRaises(ValueError, validate_dataset, frame)


class DatasetTests(unittest.TestCase):
    def run_dataset(self, frame, build_error=None):
        loads = Mock(side_effect=lambda engine, *args: (frame if engine == "nav" else DataFrame(columns=frame.columns), None))
        writer, build = Mock(), Mock(return_value=(1, build_error))
        with patch(f"{MODULE}.concurrent_df_load_params", loads), patch(f"{MODULE}.write_df_to_sql_db", writer), patch(
            f"{MODULE}.execute_sql_procedure", build
        ):
            summary = run_inventory_cost_dataset("nav", "llc", "warehouse", Mock(), 7, AS_OF)
        return summary, loads, writer, build

    def test_stages_with_dataset_id_then_builds(self):
        summary, loads, writer, build = self.run_dataset(DataFrame([stock()]))
        self.assertIn("7", summary)
        self.assertEqual(loads.call_args.args[2], ("2026-09-30",))         # the as-of date is the query's ? parameter
        staged = writer.call_args.args[2]
        self.assertEqual(writer.call_args.args[1:4:2], ("inventory_cost_staging", "replace"))
        self.assertEqual(staged.dataset_id.tolist(), [7])
        self.assertEqual(writer.call_args.kwargs["schema"], "finance")
        self.assertEqual(build.call_args.args[1], "EXEC [finance].[build_inventory_cost] @dataset_id = 7;")

    def test_build_failure_raises(self):
        with self.assertRaises(RuntimeError):
            self.run_dataset(DataFrame([stock()]), build_error="items missing")

    def test_invalid_source_is_not_staged(self):
        with patch(f"{MODULE}.concurrent_df_load_params", return_value=(None, "NAV unavailable")), patch(
            f"{MODULE}.write_df_to_sql_db"
        ) as writer:
            with self.assertRaises(RuntimeError):
                run_inventory_cost_dataset("nav", "llc", "warehouse", Mock(), 7, AS_OF)
            writer.assert_not_called()


class CheckTests(unittest.TestCase):
    def setUp(self):
        self.connection = MagicMock()

        @contextmanager
        def transaction(engine):
            yield self.connection

        self.transaction = transaction

    def run_check(self, counts, listed):
        frames = {
            "inventory_cost_receipts": DataFrame([receipt()]),
            "inventory_cost_unadjusted": DataFrame([unadjusted(entry=entry) for entry in range(listed)], columns=UNADJUSTED_COLUMNS),
            "inventory_cost_checks": DataFrame(counts),
        }

        def load(engine, path, *args):
            frame = frames[Path(path).stem]
            return (frame if engine == "nav" else frame.iloc[0:0]), None

        writer = Mock()
        with patch(f"{MODULE}.concurrent_df_load_params", side_effect=load), patch(f"{MODULE}.write_df_to_sql_db", writer), patch(
            f"{MODULE}.transactional_connection", self.transaction
        ):
            summary = run_inventory_cost_check("nav", "llc", "warehouse", Mock(), 3, AS_OF)
        return summary, writer

    def test_writes_both_lists_and_completes_in_one_transaction(self):
        summary, writer = self.run_check([{"entity": "Shiner Ltd", "unadjusted_entries": 2, "unposted_entries": 4}], listed=2)
        self.assertEqual([call.args[1] for call in writer.call_args_list], ["inventory_cost_receipts", "inventory_cost_unadjusted"])
        self.assertTrue(all(call.args[0] is self.connection for call in writer.call_args_list))
        self.assertEqual(writer.call_args_list[0].args[2].check_id.tolist(), [3])
        self.assertTrue(all(call.kwargs["schema"] == "finance" for call in writer.call_args_list))
        sql, params = self.connection.exec_driver_sql.call_args.args
        self.assertIn("complete_inventory_cost_check", sql)
        self.assertEqual(params, (3, 4))
        self.assertIn("4 value entries not posted", summary)

    def test_count_and_list_that_differ_write_nothing(self):
        with self.assertRaises(ValueError):
            self.run_check([{"entity": "Shiner Ltd", "unadjusted_entries": 5, "unposted_entries": 0}], listed=2)
        self.connection.exec_driver_sql.assert_not_called()


class QueueTests(unittest.TestCase):
    def test_handles_each_request_and_marks_failures(self):
        claims = iter([("check", 1, AS_OF), ("dataset", 2, AS_OF), None])
        logger = Mock()
        check = Mock(return_value="check done")
        dataset = Mock(side_effect=RuntimeError("NAV timed out"))
        with patch(f"{MODULE}._claim", side_effect=lambda engine: next(claims)), patch(f"{MODULE}._fail", return_value=None) as fail, patch(
            f"{MODULE}.run_inventory_cost_check", check
        ), patch(f"{MODULE}.run_inventory_cost_dataset", dataset):
            handled = process_inventory_cost_requests("nav", "llc", "warehouse", logger)
        self.assertEqual(handled, 2)
        check.assert_called_once_with("nav", "llc", "warehouse", logger, 1, AS_OF)
        logger.success.assert_called_once()
        fail.assert_called_once_with("warehouse", "dataset", 2, "NAV timed out")

    def test_nothing_queued_logs_nothing(self):
        logger = Mock()
        with patch(f"{MODULE}._claim", return_value=None):
            self.assertEqual(process_inventory_cost_requests("nav", "llc", "warehouse", logger), 0)
        self.assertEqual(logger.method_calls, [])

    def test_unreadable_queue_returns_none(self):
        logger = Mock()
        with patch(f"{MODULE}._claim", side_effect=RuntimeError("login failed")):
            self.assertIsNone(process_inventory_cost_requests("nav", "llc", "warehouse", logger))
        logger.error.assert_called_once()

    def test_a_run_stops_after_the_limit(self):
        with patch(f"{MODULE}._claim", return_value=("check", 1, AS_OF)), patch(f"{MODULE}.run_inventory_cost_check", return_value="ok"):
            self.assertEqual(process_inventory_cost_requests("nav", "llc", "warehouse", Mock()), inventory_cost.MAX_REQUESTS_PER_RUN)


if __name__ == "__main__":
    unittest.main()
