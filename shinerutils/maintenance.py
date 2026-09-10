"""Post-load maintenance without a transaction spanning multiple SQL commands."""

import json

from sqlalchemy.engine import Engine

from shinerutils.logging import DatabaseLogger


def maintain_loaded_tables(
    engine: Engine, tables: list[str], logger: DatabaseLogger
) -> None:
    if not tables:
        logger.info(action="database maintenance", message="No successful loads to maintain.")
        return
    try:
        with engine.connect().execution_options(isolation_level="AUTOCOMMIT") as connection:
            result = connection.exec_driver_sql(
                "EXEC dbo.run_daily_maintenance @TablesJson=?;",
                (json.dumps(sorted(set(tables))),),
            )
            # SQL Server may deliver an error after a preceding result set.
            cursor = result.cursor
            if cursor is not None:
                while True:
                    if cursor.description is not None:
                        cursor.fetchall()
                    if not cursor.nextset():
                        break
            result.close()
        logger.success(
            action="database maintenance",
            message="Statistics maintenance and the scheduled index check completed. "
            "See dbo.database_maintenance_log for individual actions.",
        )
    except Exception as exc:
        logger.failure(action="database maintenance", message=str(exc))
        raise
