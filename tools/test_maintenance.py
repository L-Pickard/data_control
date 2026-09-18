"""Maintenance integration tests; no source databases or real loaders are used."""
import sys
import unittest
from contextlib import ExitStack
from pathlib import Path
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import shinerutils
from scripts import daily_updates
from shinerutils.maintenance import maintain_loaded_tables


class MaintenanceTests(unittest.TestCase):
    def test_empty_success_list_does_not_connect(self):
        engine, logger = Mock(), Mock()
        maintain_loaded_tables(engine, [], logger)
        engine.connect.assert_not_called()

    def test_autocommit_parameters_and_deferred_error(self):
        engine, logger, connection, cursor = Mock(), Mock(), Mock(), Mock()
        options = engine.connect.return_value.execution_options
        options.return_value.__enter__ = Mock(return_value=connection)
        options.return_value.__exit__ = Mock(return_value=False)
        connection.exec_driver_sql.return_value.cursor = cursor
        cursor.nextset.side_effect = [RuntimeError('late SQL failure')]
        with self.assertRaisesRegex(RuntimeError, 'late SQL failure'):
            maintain_loaded_tables(engine, ['sales_orders', 'items', 'items'], logger)
        options.assert_called_once_with(isolation_level='AUTOCOMMIT')
        self.assertEqual(connection.exec_driver_sql.call_args.args[0],
                         'EXEC dbo.run_daily_maintenance @TablesJson=?;')
        self.assertEqual(connection.exec_driver_sql.call_args.args[1], ('["items", "sales_orders"]',))
        logger.failure.assert_called_once()
        logger.success.assert_not_called()

    def test_success_consumes_results(self):
        engine, logger, connection, cursor = Mock(), Mock(), Mock(), Mock()
        options = engine.connect.return_value.execution_options.return_value
        options.__enter__ = Mock(return_value=connection)
        options.__exit__ = Mock(return_value=False)
        connection.exec_driver_sql.return_value.cursor = cursor
        cursor.nextset.side_effect = [True, False]
        maintain_loaded_tables(engine, ['items'], logger)
        self.assertEqual(cursor.fetchall.call_count, 2)
        logger.success.assert_called_once()

    def test_daily_script_excludes_failed_loads_and_includes_image_tables(self):
        with ExitStack() as stack:
            for name in daily_updates.main.__code__.co_names:
                if name.startswith('update_'):
                    stack.enter_context(patch.object(shinerutils, name, return_value=None if name=='update_sales_orders_table' else 10))
            stack.enter_context(patch.object(shinerutils, 'get_sqlalchemy_engine', return_value=Mock()))
            logger=Mock()
            logger.flush_log_records.return_value=None
            stack.enter_context(patch('shinerutils.logging.DatabaseLogger', return_value=logger))
            maintenance=stack.enter_context(patch('shinerutils.maintenance.maintain_loaded_tables'))
            stack.enter_context(patch('builtins.print'))
            daily_updates.main()
            tables=maintenance.call_args.args[1]
            self.assertNotIn('sales_orders', tables)
            self.assertIn('purchase_orders', tables)
            self.assertIn('item_images', tables)
            self.assertIn('item_image_locations', tables)
            logger.flush_log_records.assert_called_once()


if __name__ == '__main__':
    unittest.main()
