from pathlib import Path

LOGGING_DB = "data_control"

DB_LOG_TABLE = "db_log"

PROJECT_ROOT = Path(__file__).resolve().parent.parent

SQL_SELECTS = PROJECT_ROOT / "sql" / "select"

SELECTS_SQL02 = SQL_SELECTS / "shinersql02"

SELECTS_SQL04 = SQL_SELECTS / "shinersql04"

SELECTS_SQL05 = SQL_SELECTS / "shinersql05"

SELECTS_SQL18 = SQL_SELECTS / "shinersql18"

DOCUMENTS =  PROJECT_ROOT / "documents"
