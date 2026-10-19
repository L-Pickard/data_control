"""Manual live transport check against data_control only; no NAV reads.

Uses an existing saved snapshot as input and rolls back every fixture change.
Run only when inventory operations are idle; this acquires the operation lock.
Not part of the offline unit-test suite.
"""
from unittest.mock import patch
import pandas as pd
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import shinerutils
from shinerutils.updates.inventory_cost import run_inventory_cost_dataset
from shinerutils.logging import DatabaseLogger
def main():
    engine=shinerutils.get_sqlalchemy_engine("shinersql18","data_control")
    with engine.connect() as connection:
        lock=connection.exec_driver_sql("DECLARE @r int; EXEC @r=sys.sp_getapplock @Resource=N'inventory_cost_operation',@LockMode=N'Exclusive',@LockOwner=N'Session',@LockTimeout=0; SELECT @r;").scalar_one()
        connection.commit()
        assert lock>=0
        try:
            source=connection.exec_driver_sql("SELECT TOP(1) dataset_id,as_of_date,line_count,total_gbp,total_eur,total_usd FROM finance.inventory_cost_headers WHERE status=N'complete' ORDER BY dataset_id").fetchone()
            frame=pd.read_sql_query("SELECT entity,location_code,item_id,quantity,cost,expected_cost,first_receipt,last_receipt FROM finance.inventory_cost_lines WHERE dataset_id=?",connection,params=(source.dataset_id,),coerce_float=False)
            result=connection.exec_driver_sql("""INSERT finance.inventory_cost_headers(description,as_of_date,check_id,status,created_by_id,created_by,cost_adjusted_confirmed_at,posted_to_gl_confirmed_at,reviewed_at,override_reason,override_at,rate_method,rates_from,rates_to,gbp_eur,gbp_usd,eur_gbp,eur_usd,usd_gbp,usd_eur,started_at)
    OUTPUT INSERTED.dataset_id
    SELECT N'Rollback-only Python transport verification '+CONVERT(nvarchar(36),NEWID()),as_of_date,check_id,N'loading',created_by_id,created_by,cost_adjusted_confirmed_at,posted_to_gl_confirmed_at,reviewed_at,override_reason,override_at,rate_method,rates_from,rates_to,gbp_eur,gbp_usd,eur_gbp,eur_usd,usd_gbp,usd_eur,SYSDATETIME() FROM finance.inventory_cost_headers WHERE dataset_id=?""",(source.dataset_id,))
            test_id=result.scalar_one()
            with patch("shinerutils.updates.inventory_cost._load",return_value=frame):
                run_inventory_cost_dataset(None,None,connection,DatabaseLogger(),test_id,source.as_of_date)
            actual=connection.exec_driver_sql("SELECT line_count,total_gbp,total_eur,total_usd FROM finance.inventory_cost_headers WHERE dataset_id=?",(test_id,)).fetchone()
            assert tuple(actual)==tuple(source)[2:], (actual,source)
            print(f"PASS: Python parameter transport and direct SQL save reconciled {actual.line_count} rows and all totals; rolling back")
        finally:
            connection.rollback()
            connection.exec_driver_sql("EXEC sys.sp_releaseapplock @Resource=N'inventory_cost_operation',@LockOwner=N'Session';")
            connection.commit()
    engine.dispose()


if __name__ == "__main__":
    main()
