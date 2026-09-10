import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))


def main() -> None:
    from shinerutils.logging import DatabaseLogger
    from shinerutils import (
        get_sqlalchemy_engine,
        update_sales_table,
    )

    # initialize new instance of logger class

    logger = DatabaseLogger()

    # initialize new instances of sqlalchemy engine class to connect to different servers/databases

    engine_sql02 = get_sqlalchemy_engine("shinersql18", "NAV_LIVE")
    engine_sql04 = get_sqlalchemy_engine("shinersql04", "BC_LIVE_USA")
    engine_sql18 = get_sqlalchemy_engine("shinersql18", "data_control")

    try:
        # execute function to update salesperson table and log wether it resulted in success or failure

        rows_affected = update_sales_table(
            engine_sql02, engine_sql04, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[sales] table"

        if rows_affected is None:
            print("An error occurred updating sales table")

            logger.failure(
                table="sales",
                action=action,
                message="sales table update has failed",
            )

        else:
            print(
                "sales table has been successfully updated, rows affected: ",
                rows_affected,
            )

            logger.success(
                table="sales",
                action=action,
                message=f"sales table has sucessfully been updated. {rows_affected} were inserted. old data was replaced.",
                rows=rows_affected,
            )

 
    except Exception as e:  # noqa: BLE001
        logger.critical(
            table=None,
            action="run daily updates",
            message=f"daily update run crashed. Error: {e}",
        )
        raise

    finally:
        # write log records to db or file if not able to connect to db
        err = logger.flush_log_records(engine_sql18)
        if err is not None:
            print(err)


if __name__ == "__main__":
    main()
