from dataclasses import asdict, dataclass, field
from datetime import datetime
from time import perf_counter
from typing import Literal, TypeAlias
from zoneinfo import ZoneInfo

from pandas import DataFrame, to_datetime
from sqlalchemy.engine import Engine

from datautils.constants import DB_LOG_TABLE, PROJECT_ROOT
from datautils.sql import write_df_to_sql_db

LogLevel: TypeAlias = Literal[
    "INFO", "DEBUG", "WARNING", "ERROR", "CRITICAL", "SUCCESS", "FAILURE"
]
UK_TIMEZONE = ZoneInfo("Europe/London")


def _now_uk() -> datetime:

    return datetime.now(tz=UK_TIMEZONE)


@dataclass
class LogRecord:
    timestamp: datetime = field(default_factory=_now_uk)
    duration_seconds: float = 0.0
    level: LogLevel = "INFO"
    table: str | None = None
    action: str | None = None
    message: str | None = None
    rows: int | None = None


class DatabaseLogger:
    def __init__(self):
        self.process_start = perf_counter()
        self.records: list[LogRecord] = []

    def log(
        self,
        level: LogLevel = "INFO",
        table: str | None = None,
        action: str | None = None,
        message: str = "",
        rows: int | None = None,
    ) -> LogRecord:

        record = LogRecord(
            level=level, table=table, action=action, message=message, rows=rows
        )

        record.duration_seconds = perf_counter() - self.process_start
        self.records.append(record)

        return record

    def info(
        self,
        table: str | None = None,
        action: str | None = None,
        message: str = "",
        rows: int | None = None,
    ) -> LogRecord:
        return self.log("INFO", table, action, message, rows)

    def debug(
        self,
        table: str | None = None,
        action: str | None = None,
        message: str = "",
        rows: int | None = None,
    ) -> LogRecord:
        return self.log("DEBUG", table, action, message, rows)

    def warning(
        self,
        table: str | None = None,
        action: str | None = None,
        message: str = "",
        rows: int | None = None,
    ) -> LogRecord:
        return self.log("WARNING", table, action, message, rows)

    def error(
        self,
        table: str | None = None,
        action: str | None = None,
        message: str = "",
        rows: int | None = None,
    ) -> LogRecord:
        return self.log("ERROR", table, action, message, rows)

    def critical(
        self,
        table: str | None = None,
        action: str | None = None,
        message: str = "",
        rows: int | None = None,
    ) -> LogRecord:
        return self.log("CRITICAL", table, action, message, rows)

    def success(
        self,
        table: str | None = None,
        action: str | None = None,
        message: str = "",
        rows: int | None = None,
    ) -> LogRecord:
        return self.log("SUCCESS", table, action, message, rows)

    def failure(
        self,
        table: str | None = None,
        action: str | None = None,
        message: str = "",
        rows: int | None = None,
    ) -> LogRecord:
        return self.log("FAILURE", table, action, message, rows)

    def to_dataframe(self) -> DataFrame:

        df = DataFrame([asdict(record) for record in self.records])

        if df.empty:
            return DataFrame(
                columns=[
                    "timestamp",
                    "duration_seconds",
                    "level",
                    "table",
                    "rows",
                    "action",
                    "message",
                ]
            )

        df = df.astype(
            {
                "level": "string",
                "table": "string",
                "action": "string",
                "message": "string",
            }
        )

        df["timestamp"] = to_datetime(df["timestamp"])
        df["duration_seconds"] = df["duration_seconds"].astype("float64")
        df["rows"] = df["rows"].astype("Int64")

        return df

    def output_logs_to_csv(self, df: DataFrame) -> None:

        timestamp = _now_uk().strftime("%Y%m%d_%H%M%S")

        df.to_csv(
            PROJECT_ROOT / f"backup_log_file_{timestamp}.csv", index=False, sep="~"
        )

    def flush_log_records(self, engine: Engine) -> None | str:

        try:
            df = self.to_dataframe()

        except Exception as e:
            return f"an error occurred writing log records to a pandas dataframe. Error: {e}"

        try:
            write_df_to_sql_db(engine, DB_LOG_TABLE, df, "append")
            return None
        except Exception as e:  # noqa: BLE001
            err = str(e)

        self.output_logs_to_csv(df)

        return err
