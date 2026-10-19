"""Manual SQL18-only check replay. Uses saved warning lists and rolls back all fixtures.

Does not connect to SQL02/SQL04 or run NAV queries. Run with inventory operations idle.
"""
import sys
from pathlib import Path
from unittest.mock import patch
import pandas as pd
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import shinerutils
from shinerutils.logging import DatabaseLogger
from shinerutils.updates.inventory_cost import ENTITIES, RECEIPT_COLUMNS, UNADJUSTED_COLUMNS, run_inventory_cost_check


def main():
    engine = shinerutils.get_sqlalchemy_engine("shinersql18", "data_control")
    with engine.connect() as connection:
        lock = connection.exec_driver_sql("DECLARE @r int; EXEC @r=sys.sp_getapplock @Resource=N'inventory_cost_operation',@LockMode=N'Exclusive',@LockOwner=N'Session',@LockTimeout=0; SELECT @r;").scalar_one()
        connection.commit()
        if lock < 0:
            raise RuntimeError("An inventory operation is running; try again when it finishes")
        try:
            source = connection.exec_driver_sql("SELECT TOP(1) check_id,as_of_date,uninvoiced_lines,unadjusted_entries,unposted_entries,is_passed FROM finance.inventory_cost_checks WHERE status=N'complete' ORDER BY uninvoiced_lines+unadjusted_entries DESC,check_id DESC").fetchone()
            if source is None:
                raise RuntimeError("No completed check exists to replay")
            frames = {}
            for query, table, columns in [
                ("inventory_cost_receipts", "inventory_cost_receipts", RECEIPT_COLUMNS),
                ("inventory_cost_unadjusted", "inventory_cost_unadjusted", UNADJUSTED_COLUMNS),
            ]:
                sql = "SELECT " + ",".join("[" + column + "]" for column in columns) + " FROM finance.[" + table + "] WHERE check_id=?"
                frames[query] = pd.read_sql_query(sql, connection, params=(source.check_id,), coerce_float=False)
            frames["inventory_cost_checks"] = pd.DataFrame([
                {"entity": entity, "unposted_entries": source.unposted_entries if entity == ENTITIES[0] else 0} for entity in ENTITIES
            ])
            assert len(frames["inventory_cost_receipts"]) == source.uninvoiced_lines
            assert len(frames["inventory_cost_unadjusted"]) == source.unadjusted_entries
            test_id = connection.exec_driver_sql("INSERT finance.inventory_cost_checks(as_of_date,status,requested_by_id,requested_by,started_at) OUTPUT INSERTED.check_id VALUES(?,N'running',N'rollback-only-verification',N'Rollback-only count verification',SYSDATETIME())", (source.as_of_date,)).scalar_one()
            with patch("shinerutils.updates.inventory_cost._load", side_effect=lambda sql02, sql04, query, *args: frames[query].copy()):
                run_inventory_cost_check(None, None, connection, DatabaseLogger(), test_id, source.as_of_date)
            actual = connection.exec_driver_sql("SELECT status,uninvoiced_lines,unadjusted_entries,unposted_entries,is_passed FROM finance.inventory_cost_checks WHERE check_id=?", (test_id,)).fetchone()
            assert tuple(actual) == ("complete", source.uninvoiced_lines, source.unadjusted_entries, source.unposted_entries, source.is_passed), actual
            print(f"PASS: check replay matches {actual.uninvoiced_lines} receipts, {actual.unadjusted_entries} unadjusted entries and the original pass/fail result; rolling back")
        finally:
            connection.rollback()
            connection.exec_driver_sql("EXEC sys.sp_releaseapplock @Resource=N'inventory_cost_operation',@LockOwner=N'Session';")
            connection.commit()
    engine.dispose()


if __name__ == "__main__":
    main()
