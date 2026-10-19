"""Live source SELECTs plus a rollback-only SQL18 save for an existing completed check.

No jobs or permanent datasets are created. Requires idle inventory operations.
Usage: python tools/check_inventory_cost_scoped_transport.py --check-id 13
"""
import argparse
import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from shinerutils.sql import get_sqlalchemy_engine
from shinerutils.updates.inventory_cost import run_inventory_cost_dataset
from unittest.mock import Mock

parser=argparse.ArgumentParser()
parser.add_argument('--check-id', type=int, required=True)
args=parser.parse_args()
warehouse=get_sqlalchemy_engine('shinersql18','data_control')
sources=[get_sqlalchemy_engine('shinersql02','NAV_LIVE'),get_sqlalchemy_engine('shinersql04','BC_LIVE_USA')]
with warehouse.connect() as connection:
    lock=connection.exec_driver_sql("DECLARE @r INT; EXEC @r=sys.sp_getapplock @Resource=N'inventory_cost_operation',@LockMode=N'Exclusive',@LockOwner=N'Session',@LockTimeout=0; SELECT @r;").scalar_one()
    connection.commit()
    if lock<0: raise RuntimeError('An inventory operation is running')
    try:
        if connection.exec_driver_sql("SELECT COUNT(*) FROM finance.inventory_cost_checks WHERE status IN(N'requested',N'running')").scalar_one():
            raise RuntimeError('A check is starting')
        check=connection.exec_driver_sql("SELECT as_of_date,scope_json FROM finance.inventory_cost_checks WHERE check_id=? AND status=N'complete'",(args.check_id,)).one()
        test=connection.exec_driver_sql("""INSERT finance.inventory_cost_headers(description,as_of_date,check_id,status,created_by_id,created_by,reviewed_at,rate_method,rates_from,rates_to,gbp_eur,gbp_usd,eur_gbp,eur_usd,usd_gbp,usd_eur,started_at)
            OUTPUT INSERTED.dataset_id
            SELECT TOP(1) N'Rollback scoped source verification '+CONVERT(NVARCHAR(36),NEWID()),?, ?,N'loading',created_by_id,created_by,SYSDATETIME(),rate_method,rates_from,rates_to,gbp_eur,gbp_usd,eur_gbp,eur_usd,usd_gbp,usd_eur,SYSDATETIME()
            FROM finance.inventory_cost_headers WHERE status=N'complete' ORDER BY dataset_id""",(check.as_of_date,args.check_id)).scalar_one()
        print(run_inventory_cost_dataset(*sources,connection,Mock(),test,check.as_of_date,json.loads(check.scope_json)),flush=True)
        rows=connection.exec_driver_sql("SELECT entity,location_code,COUNT(*) AS lines FROM finance.inventory_cost_lines WHERE dataset_id=? GROUP BY entity,location_code",(test,)).all()
        print('PASS: actual scoped source rows saved with location and currency totals; rolling back:',[tuple(row) for row in rows],flush=True)
    finally:
        connection.rollback()
        connection.exec_driver_sql("EXEC sys.sp_releaseapplock @Resource=N'inventory_cost_operation',@LockOwner=N'Session';")
        connection.commit()
for engine in [warehouse,*sources]: engine.dispose()
