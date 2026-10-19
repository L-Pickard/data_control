"""Inventory cost check and dataset job: validation, transactions and single-operation locking; no database access."""

import sys
import unittest
from contextlib import contextmanager
from datetime import date
from decimal import Decimal
from pathlib import Path
import json
from types import SimpleNamespace
from unittest.mock import MagicMock, Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from pandas import DataFrame
from shinerutils.updates import inventory_cost
from shinerutils.updates.inventory_cost import (
    RECEIPT_COLUMNS,
    UNADJUSTED_COLUMNS,
    process_inventory_cost_operation,
    run_inventory_cost_check,
    run_inventory_cost_dataset,
    validate_dataset,
)

MODULE = "shinerutils.updates.inventory_cost"
AS_OF = date(2026, 9, 30)


def stock(entity="Shiner Ltd", item="ABC001", **changes):
    row = {
        "entity": entity, "location_code": "BRISTOL", "item_id": item, "quantity": Decimal("2"), "cost": Decimal("10.12345678901234567890"),
        "expected_cost": Decimal("1.5"), "first_receipt": "2024-01-01", "last_receipt": "2026-09-01",
    }
    row.update(changes)
    return row


def receipt(entity="Shiner Ltd"):
    return dict.fromkeys(RECEIPT_COLUMNS, None) | {"entity": entity, "location_code": "BRISTOL", "document_no": "PRC-1", "document_line_no": 10000,
                                                   "item_id": "ABC001", "quantity": Decimal("5"), "quantity_invoiced": Decimal("0"),
                                                   "quantity_not_invoiced": Decimal("5")}


def unadjusted(entity="Shiner Ltd", entry=1):
    return dict.fromkeys(UNADJUSTED_COLUMNS, None) | {"entity": entity, "location_code": "BRISTOL", "entry_no": entry, "item_id": "ABC001",
                                                      "entry_type": "Purchase", "quantity": Decimal("3"), "remaining_quantity": Decimal("3")}


class ValidateDatasetTests(unittest.TestCase):
    def test_same_item_at_two_locations_is_kept_but_same_location_duplicate_is_refused(self):
        self.assertEqual(len(validate_dataset(DataFrame([stock(), stock(location_code="AMAZON")]))), 2)
        with self.assertRaises(ValueError):
            validate_dataset(DataFrame([stock(), stock()]))

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
            "empty": DataFrame(columns=inventory_cost.DATASET_COLUMNS),
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
        connection = MagicMock()
        connection.exec_driver_sql.side_effect = build_error
        @contextmanager
        def transaction(engine):
            yield connection
        with patch(f"{MODULE}.concurrent_df_load_params", loads), patch(f"{MODULE}.transactional_connection", transaction):
            summary = run_inventory_cost_dataset("nav", "llc", "warehouse", Mock(), 7, AS_OF)
        return summary, loads, connection

    def test_saves_parameterised_json_without_staging_and_preserves_decimals(self):
        summary, loads, connection = self.run_dataset(DataFrame([stock()]))
        self.assertIn("7", summary)
        self.assertEqual(loads.call_args.args[2][0], "2026-09-30")
        self.assertIn('name="Shiner Ltd"', loads.call_args.args[2][1])
        sql, params = connection.exec_driver_sql.call_args.args
        self.assertIn("@dataset_id = ?, @rows_json = ?", sql)
        self.assertNotIn("staging", sql)
        self.assertEqual(params[0], 7)
        payload = json.loads(params[1])
        self.assertEqual(payload[0]["cost"], "10.12345678901234567890")
        self.assertEqual(payload[0]["first_receipt"], "2024-01-01")

    def test_zero_and_small_decimals_use_fixed_not_exponent_notation(self):
        _, _, connection = self.run_dataset(DataFrame([stock(cost=Decimal("0E-20"), expected_cost=Decimal("1E-20"))]))
        payload = json.loads(connection.exec_driver_sql.call_args.args[1][1])
        self.assertEqual(payload[0]["cost"], "0.00000000000000000000")
        self.assertEqual(payload[0]["expected_cost"], "0.00000000000000000001")

    def test_build_failure_raises(self):
        with self.assertRaisesRegex(RuntimeError, "items missing"):
            self.run_dataset(DataFrame([stock()]), RuntimeError("items missing"))

    def test_invalid_source_is_not_saved(self):
        with patch(f"{MODULE}.concurrent_df_load_params", return_value=(None, "NAV unavailable")), patch(f"{MODULE}.transactional_connection") as transaction:
            with self.assertRaises(RuntimeError):
                run_inventory_cost_dataset("nav", "llc", "warehouse", Mock(), 7, AS_OF)
            transaction.assert_not_called()


class CheckTests(unittest.TestCase):
    def setUp(self):
        self.connection = MagicMock()
        @contextmanager
        def transaction(engine):
            yield self.connection
        self.transaction = transaction

    def run_check(self, counts=None, listed=2, receipt_count=1):
        if counts is None:
            counts = [{"entity": entity, "unposted_entries": 4 if entity == "Shiner Ltd" else 0} for entity in inventory_cost.ENTITIES]
        frames = {
            "inventory_cost_receipts": DataFrame([receipt() for _ in range(receipt_count)], columns=RECEIPT_COLUMNS),
            "inventory_cost_unadjusted": DataFrame([unadjusted(entry=entry) for entry in range(listed)], columns=UNADJUSTED_COLUMNS),
            "inventory_cost_checks": DataFrame(counts, columns=inventory_cost.COUNT_COLUMNS),
        }
        def load(engine, path, *args):
            frame = frames[Path(path).stem]
            return (frame if engine == "nav" else frame.iloc[0:0]), None
        writer = Mock()
        with patch(f"{MODULE}.concurrent_df_load_params", side_effect=load) as loads, patch(f"{MODULE}.write_df_to_sql_db", writer), patch(
            f"{MODULE}.transactional_connection", self.transaction
        ):
            summary = run_inventory_cost_check("nav", "llc", "warehouse", Mock(), 3, AS_OF)
        self.assertEqual(loads.call_count, 6)  # Three different reads on each server; no additional warning count read.
        return summary, writer

    def test_writes_lists_and_their_lengths_in_one_transaction(self):
        summary, writer = self.run_check()
        self.assertEqual([call.args[1] for call in writer.call_args_list], ["inventory_cost_receipts", "inventory_cost_unadjusted"])
        self.assertTrue(all(call.args[0] is self.connection for call in writer.call_args_list))
        self.assertEqual(writer.call_args_list[0].args[2].check_id.tolist(), [3])
        self.assertTrue(all(call.kwargs["schema"] == "finance" for call in writer.call_args_list))
        sql, params = self.connection.exec_driver_sql.call_args.args
        self.assertIn("@uninvoiced_lines = ?, @unadjusted_entries = ?", sql)
        self.assertEqual(params, (3, 4, 1, 2))
        self.assertIn("1 receipt lines not invoiced, 2 entries", summary)

    def test_empty_warning_lists_pass_zero_counts_without_inserting(self):
        summary, writer = self.run_check(listed=0, receipt_count=0)
        writer.assert_not_called()
        self.assertEqual(self.connection.exec_driver_sql.call_args.args[1], (3, 4, 0, 0))

    def test_missing_duplicate_or_unknown_company_count_writes_nothing(self):
        valid = [{"entity": entity, "unposted_entries": 0} for entity in inventory_cost.ENTITIES]
        for counts in [[], valid[:2], [valid[0], valid[0], valid[2]], valid[:2]+[{"entity": "Unknown", "unposted_entries": 0}]]:
            with self.subTest(counts=counts), self.assertRaises(ValueError):
                self.run_check(counts=counts)
        self.connection.exec_driver_sql.assert_not_called()

    def test_null_or_negative_blocking_count_writes_nothing(self):
        for count in [None, -1]:
            counts = [{"entity": entity, "unposted_entries": count if entity == "Shiner Ltd" else 0} for entity in inventory_cost.ENTITIES]
            with self.subTest(count=count), self.assertRaises(ValueError):
                self.run_check(counts=counts)
        self.connection.exec_driver_sql.assert_not_called()

    def test_nav_count_queries_only_read_value_entries(self):
        root = Path(__file__).resolve().parents[1]
        for server, companies in [("shinersql02", 2), ("shinersql04", 1)]:
            sql = (root / "sql" / "select" / server / "inventory_cost_checks.sql").read_text(encoding="utf-8")
            self.assertNotIn("Item Ledger Entry", sql)
            self.assertNotIn("[unadjusted_entries]", sql)
            self.assertEqual(sql.count("AS [unposted_entries]"), companies)
            self.assertEqual(sql.count("ve.[Cost Amount (Actual)] <> ve.[Cost Posted to G_L]"), companies)
            self.assertEqual(sql.count("ve.[Posting Date] < @day_after"), companies)


class ScopeTests(unittest.TestCase):
    def test_xml_preserves_blank_all_and_escapes_location_text(self):
        from xml.etree.ElementTree import fromstring
        xml = fromstring(inventory_cost.scope_xml([{"entity": "Shiner Ltd", "locations": ["", "A&B\""]}, {"entity": "Shiner LLC", "locations": None}]))
        self.assertEqual(xml[0][0].attrib["code"], "")
        self.assertEqual(xml[0][1].attrib["code"], 'A&B"')
        self.assertEqual(xml[1].attrib["all"], "1")

    def test_invalid_or_empty_scopes_are_refused(self):
        for scope in [[], [{"entity": "Unknown", "locations": None}], [{"entity": "Shiner Ltd", "locations": []}],
                      [{"entity": "Shiner Ltd", "locations": ["TOO-LONG-CODE"]}]]:
            with self.subTest(scope=scope), self.assertRaises(ValueError):
                inventory_cost.scope_xml(scope)

    def test_unselected_server_is_not_contacted_and_blank_is_distinct_from_all(self):
        scope = [{"entity": "Shiner Ltd", "locations": [""]}]
        with patch(f"{MODULE}.concurrent_df_load_params", return_value=(DataFrame([stock(location_code="")]), None)) as load:
            frame = inventory_cost._load("nav", "llc", "inventory_cost_dataset", AS_OF, inventory_cost.DATASET_COLUMNS, Mock(), scope)
        self.assertEqual(len(frame), 1)
        load.assert_called_once()
        self.assertEqual(load.call_args.args[0], "nav")
        self.assertIn('all="0"', load.call_args.args[2][1])

    def test_rows_outside_scope_are_refused_before_saving(self):
        with patch(f"{MODULE}.concurrent_df_load_params", return_value=(DataFrame([stock(location_code="AMAZON")]), None)):
            with self.assertRaisesRegex(ValueError, "selected locations"):
                inventory_cost._load("nav", "llc", "inventory_cost_dataset", AS_OF, inventory_cost.DATASET_COLUMNS, Mock(), [{"entity": "Shiner Ltd", "locations": ["BRISTOL"]}])


class SourceReadRetryTests(unittest.TestCase):
    def read(self, answers):
        logger = Mock()
        with patch(f"{MODULE}.concurrent_df_load_params", side_effect=answers) as load, patch(f"{MODULE}.sleep") as delay:
            result = inventory_cost._read_source("nav", Path("inventory_cost_unadjusted.sql"), ("2026-10-19",), logger, "sql02 inventory_cost_unadjusted")
        return result, load, delay, logger

    def test_success_needs_no_retry(self):
        frame = DataFrame([{"x": 1}])
        result, load, delay, logger = self.read([(frame, None)])
        self.assertIs(result[0], frame)
        self.assertEqual(load.call_count, 1)
        delay.assert_not_called()

    def test_deadlock_retries_then_returns_complete_result(self):
        frame = DataFrame([{"x": 1}])
        error = "pyodbc ('40001', 'deadlock victim (1205)') [SQL: SELECT private]"
        result, load, delay, logger = self.read([(None, error)] * 3 + [(frame, None)])
        self.assertIs(result[0], frame)
        self.assertEqual(load.call_count, 4)
        self.assertEqual(delay.call_count, 3)
        self.assertTrue(all(load.call_args_list[0].args == call.args for call in load.call_args_list))
        self.assertEqual(logger.warning.call_count, 3)
        logger.error.assert_not_called()

    def test_exhausted_deadlocks_are_bounded_and_public_message_has_no_sql(self):
        error = "pyodbc deadlock (1205) [SQL: SELECT private]"
        (frame, message), load, delay, logger = self.read([(None, error)] * 4)
        self.assertIsNone(frame)
        self.assertIn("SQL02 was busy", message)
        self.assertIn("4 attempts", message)
        self.assertNotIn("SELECT", message)
        self.assertNotIn("pyodbc", message)
        self.assertEqual(load.call_count, 4)
        self.assertEqual(logger.error.call_args.kwargs["message"], error)

    def test_other_errors_fail_once_without_retry_or_sql_in_public_message(self):
        error = "SQLSTATE 40001: invalid column (207) [SQL: SELECT private]"
        (_, message), load, delay, logger = self.read([(None, error)])
        self.assertIn("SQL02", message)
        self.assertNotIn("SELECT", message)
        self.assertEqual(load.call_count, 1)
        delay.assert_not_called()


class OperationTests(unittest.TestCase):
    def run_operation(self, row=None, lock=0, runner_error=None):
        engine, connection, logger = MagicMock(), MagicMock(), Mock()
        engine.connect.return_value.__enter__.return_value = connection
        connection.exec_driver_sql.return_value.scalar_one.return_value = lock
        connection.exec_driver_sql.return_value.fetchone.return_value = row
        runner = Mock(return_value="done", side_effect=runner_error)
        with patch(f"{MODULE}.run_inventory_cost_check", runner), patch(f"{MODULE}._fail", return_value=None) as fail:
            result = process_inventory_cost_operation("nav", "llc", engine, logger)
        return result, connection, logger, runner, fail

    def test_runs_exactly_one_operation_and_releases_lock(self):
        result, connection, logger, runner, fail = self.run_operation(SimpleNamespace(request_kind="check", request_id=4, as_of_date=AS_OF, scope_json=json.dumps(inventory_cost.LEGACY_SCOPE)))
        self.assertEqual(result, 1)
        runner.assert_called_once()
        self.assertEqual(runner.call_args.args[2], connection)
        calls = [call.args[0] for call in connection.exec_driver_sql.call_args_list]
        self.assertEqual(sum("begin_inventory_cost_operation" in sql for sql in calls), 1)
        self.assertIn("sp_releaseapplock", calls[-1])
        logger.success.assert_called_once()
        fail.assert_not_called()

    def test_idle_run_does_not_read_nav_or_log(self):
        result, connection, logger, runner, fail = self.run_operation()
        self.assertEqual(result, 0)
        runner.assert_not_called()
        self.assertEqual(logger.method_calls, [])
        self.assertIn("sp_releaseapplock", connection.exec_driver_sql.call_args.args[0])

    def test_concurrent_worker_is_refused(self):
        result, connection, logger, runner, fail = self.run_operation(lock=-1)
        self.assertIsNone(result)
        runner.assert_not_called()
        self.assertFalse(any("begin_inventory_cost_operation" in call.args[0] for call in connection.exec_driver_sql.call_args_list))

    def test_failure_rolls_back_marks_failed_and_releases_lock(self):
        result, connection, logger, runner, fail = self.run_operation(
            SimpleNamespace(request_kind="check", request_id=4, as_of_date=AS_OF, scope_json=json.dumps(inventory_cost.LEGACY_SCOPE)), runner_error=RuntimeError("NAV timed out"))
        self.assertEqual(result, 1)
        connection.rollback.assert_called()
        self.assertEqual(fail.call_args.args[1:], ("check", 4, "NAV timed out"))
        logger.error.assert_called_once()
        self.assertIn("sp_releaseapplock", connection.exec_driver_sql.call_args.args[0])


if __name__ == "__main__":
    unittest.main()
