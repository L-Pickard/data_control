"""Read-only source verification. No writes, jobs, stored procedures or SQL settings."""
import sys
from datetime import date
from pathlib import Path
from unittest.mock import Mock
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from shinerutils.sql import get_sqlalchemy_engine
from shinerutils.updates.inventory_cost import _load, validate_dataset, DATASET_COLUMNS, RECEIPT_COLUMNS, UNADJUSTED_COLUMNS, COUNT_COLUMNS, LEGACY_SCOPE

engines = [get_sqlalchemy_engine('shinersql02', 'NAV_LIVE'), get_sqlalchemy_engine('shinersql04', 'BC_LIVE_USA')]
scope = LEGACY_SCOPE if '--all' not in sys.argv else [{'entity': 'Shiner Ltd', 'locations': None}]
for query, columns in [('dataset', DATASET_COLUMNS), ('receipts', RECEIPT_COLUMNS), ('unadjusted', UNADJUSTED_COLUMNS), ('checks', COUNT_COLUMNS)]:
    frame = _load(*engines, 'inventory_cost_' + query, date(2026,10,19), columns, Mock(), scope)
    if query == 'dataset':
        validate_dataset(frame)
        print(query, len(frame), frame.groupby(['entity','location_code']).size().to_dict(), flush=True)
    else:
        print(query, len(frame), flush=True)
for engine in engines:
    engine.dispose()
