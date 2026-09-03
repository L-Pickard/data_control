import sys
from datetime import datetime, timedelta
from ftplib import FTP
from pathlib import Path
from shutil import move
from typing import Literal

from pandas import DataFrame, read_csv, to_datetime, to_numeric
from pandas.errors import EmptyDataError, ParserError
from sqlalchemy.dialects.mssql import DATETIME2, DECIMAL, INTEGER, NVARCHAR
from sqlalchemy.engine import Engine
from sqlalchemy.exc import SQLAlchemyError

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from datautils import (
    delete_ftp_file,
    download_ftp_file,
    execute_sql_procedure,
    get_ftp_connection,
    get_sqlalchemy_engine,
    list_ftp_files,
    load_environment_file,
    write_df_to_sql_db,
)
from datautils.logging import UK_TIMEZONE, DatabaseLogger

PREORDER_COLUMNS = {
    "preorder_code": NVARCHAR(50),
    "season": NVARCHAR(20),
    "type": INTEGER,
    "brand_code": NVARCHAR(20),
    "category_code": NVARCHAR(20),
    "item_id": NVARCHAR(50),
    "description": NVARCHAR(300),
    "customer_id": NVARCHAR(20),
    "country_id": NVARCHAR(10),
    "quantity": DECIMAL(38, 20),
    "value": DECIMAL(38, 20),
    "currency_code": NVARCHAR(10),
    "order_timestamp": DATETIME2(3),
    "preorder_start": DATETIME2(3),
    "preorder_end": DATETIME2(3),
    "delivery_eta": DATETIME2(3),
}

PREORDER_DATETIME_COLUMNS = [
    "order_timestamp",
    "preorder_start",
    "preorder_end",
    "delivery_eta",
]

ACTIVE_COLUMNS = {
    "preorder_code": NVARCHAR(50),
    "region": NVARCHAR(10),
    "brand_code": NVARCHAR(20),
    "type": INTEGER,
    "season": NVARCHAR(20),
    "item_id": NVARCHAR(50),
    "description": NVARCHAR(300),
    "price_string": NVARCHAR(50),
}

EVENTS_COLUMNS = {
    "customer_id": NVARCHAR(20),
    "timestamp": DATETIME2(3),
    "event": NVARCHAR(30),
}

FILE_CONFIG = {
    "preorders.csv": (
        PREORDER_COLUMNS,
        PREORDER_DATETIME_COLUMNS,
        "preorders",
        "EXEC [dbo].[update_preorders_table] @source_type = N'current';",
    ),
    "preorders-history.csv": (
        PREORDER_COLUMNS,
        PREORDER_DATETIME_COLUMNS,
        "preorders_history",
        "EXEC [dbo].[update_preorders_table] @source_type = N'history';",
    ),
    "active.csv": (
        ACTIVE_COLUMNS,
        None,
        "preorder_lines",
        "EXEC [dbo].[update_preorder_lines_table];",
    ),
    "events.csv": (
        EVENTS_COLUMNS,
        ["timestamp"],
        "b2b_events",
        "EXEC [dbo].[insert_b2b_events];",
    ),
}

REFRESH_DIRECTORY = Path(
    r"\\EXAMPLESQL18\Users\developer\Desktop\Automated Projects\Refresh Files"
)
DOWNLOAD_DIRECTORY = Path(r"\\source_d\data_control\owtanet")
ARCHIVE_DIRECTORY = DOWNLOAD_DIRECTORY / "archive"
ERROR_DIRECTORY = DOWNLOAD_DIRECTORY / "error"
ARCHIVE_RETENTION_DAYS = 7


def create_pbi_refresh_file() -> str | None:

    try:
        data = [{"Command": "Refresh PB Dataset"}]

        df = DataFrame(data)

        df.to_csv(
            REFRESH_DIRECTORY
            / f"{datetime.now(tz=UK_TIMEZONE).strftime('%d.%m.%y %H.%M.%S')} Refresh Data.csv",
        )

        return None

    except Exception as e:  # noqa: BLE001
        return str(e)


def move_local_file(
    local_path: Path, destination: Literal["archive", "error"]
) -> str | None:

    destination_directory = (
        ARCHIVE_DIRECTORY if destination == "archive" else ERROR_DIRECTORY
    )
    try:
        destination_directory.mkdir(parents=True, exist_ok=True)
    except OSError as e:
        return f"prepare local FTP {destination} directory: {e}"

    if not local_path.is_file():
        return None

    timestamp = datetime.now(tz=UK_TIMEZONE).strftime("%Y%m%d%S")
    destination_name = f"{local_path.stem}_{timestamp}{local_path.suffix}"
    destination_path = destination_directory / destination_name

    try:
        move(local_path, destination_path)
    except OSError as e:
        return f"move {local_path.name} to {destination}: {e}"

    return None


def cleanup_archive_files() -> str | None:

    try:
        ARCHIVE_DIRECTORY.mkdir(parents=True, exist_ok=True)
        archived_files = [
            path for path in ARCHIVE_DIRECTORY.iterdir() if path.is_file()
        ]

    except OSError as e:
        return f"list archived FTP files: {e}"

    cutoff = datetime.now(tz=UK_TIMEZONE) - timedelta(days=ARCHIVE_RETENTION_DAYS)

    for archive_path in archived_files:
        try:
            modified = datetime.fromtimestamp(
                archive_path.stat().st_mtime,
                tz=UK_TIMEZONE,
            )

            if modified < cutoff:
                archive_path.unlink()

        except OSError as e:
            return f"remove expired archive {archive_path.name}: {e}"

    return None


def process_file(
    ftp: FTP, engine: Engine, file_name: str, logger: DatabaseLogger
) -> int | None:

    def finish(rows: int | None) -> int | None:
        
        destination: Literal["archive", "error"] = (
            "archive" if rows is not None else "error"
        )
        move_error = move_local_file(DOWNLOAD_DIRECTORY / file_name, destination)

        if move_error is not None:
            logger.error(
                table="ftp_polling",
                action=f"move local FTP file {file_name} to {destination}",
                message=f"Error: {move_error}",
            )
            print(f"Local FTP file move error: {move_error}")

        cleanup_error = cleanup_archive_files()

        if cleanup_error is not None:
            logger.error(
                table="ftp_polling",
                action="remove expired local FTP archive files",
                message=f"Error: {cleanup_error}",
            )
            print(f"Local FTP archive cleanup error: {cleanup_error}")

        return None if move_error is not None or cleanup_error is not None else rows

    column_datatypes, datetime_columns, table_name, procedure_sql = FILE_CONFIG[
        file_name
    ]

    local_path = DOWNLOAD_DIRECTORY / file_name

    error = download_ftp_file(ftp, file_name, local_path)

    if error is not None:
        logger.error(
            table_name,
            f"download {file_name} from owtanet reporting ftp.",
            f"Error: {error}",
        )

        return finish(None)

    error = delete_ftp_file(ftp, file_name)

    if error is not None:
        logger.error(
            table_name,
            f"delete {file_name} from owtanet reporting ftp.",
            f"Error: {error}",
        )

        return finish(None)

    action = f"read {file_name} into a pandas dataframe"

    try:
        df = read_csv(local_path, header=0)

    except (
        EmptyDataError,
        OSError,
        ParserError,
        UnicodeDecodeError,
        ValueError,
    ) as e:
        logger.error(table_name, action, f"Error: {e}")

        return finish(None)

    column_names = list(column_datatypes)

    if len(df.columns) != len(column_names):
        logger.error(
            file_name,
            f"read {file_name} into a dataframe",
            (f"expected {len(column_names)} csv columns, found {len(df.columns)}"),
        )

        return finish(None)

    action = f"rename {table_name} dataframe columns & convert datetime columns."

    try:
        df.columns = column_names

        if datetime_columns is not None:
            for column in datetime_columns:
                df[column] = to_datetime(
                    df[column],
                    format="%Y-%m-%d %H:%M:%S",
                    errors="coerce",
                )

        if file_name in {"preorders.csv", "preorders-history.csv"}:
            for column in ("quantity", "value"):
                df[column] = to_numeric(
                    df[column].astype("string").str.replace(",", "", regex=False),
                    errors="raise",
                )

    except (KeyError, OverflowError, TypeError, ValueError) as e:
        logger.error(table_name, action, f"Error: {e}")

        return finish(None)

    action = f"write {file_name} data to [dbo].[{table_name}_staging] table"

    try:
        write_df_to_sql_db(
            bind=engine,
            table=f"{table_name}_staging",
            df=df,
            if_exists="replace",
            datatype=column_datatypes,
        )

    except (SQLAlchemyError, OSError, TypeError, ValueError) as e:
        logger.error(table_name, action, f"Error: {e}")

        return finish(None)

    rows = len(df)

    logger.info(table_name, action, "staging data successfully written.", rows)

    action = f"execute procedure: {procedure_sql}"

    procedure_rows, err = execute_sql_procedure(engine, procedure_sql)

    if err is not None:
        logger.error(table_name, action, err)

        return finish(None)

    logger.info(table_name, action, "procedure executed successfully", procedure_rows)

    return finish(rows)


def main() -> int:

    exit_code = 0

    load_environment_file(PROJECT_ROOT / ".env")

    engine = get_sqlalchemy_engine("source_d", "data_control")

    logger = DatabaseLogger()

    action = "establish ftp client connection to owtanet reporting ftp"

    print("Connecting to the Owtanet reporting FTP...")

    try:
        ftp, error = get_ftp_connection()

        if error is not None:
            logger.error(table="ftp_polling", action=action, message=str(error))

            print(f"FTP connection failed: {error}")

            return 1

        assert ftp is not None, "FTP connection should not be None without an error"

        with ftp:
            action = "list files currently saved in the owtanet ftp"

            files, error = list_ftp_files(ftp)

            if error is not None:
                logger.error(table="ftp_polling", action=action, message=str(error))

                print(f"FTP file listing failed: {error}")

                return 1

            assert files is not None, "FTP files should not be None without an error"

            available_files = set(files)
            configured_files = set(FILE_CONFIG)
            files_to_process = configured_files & available_files

            print(f"FTP files found: {len(available_files)}")

            if not files_to_process:
                print("No configured files are currently available to process.")

            for file_name, (_, _, table_name, _) in FILE_CONFIG.items():
                if file_name not in available_files:
                    continue

                print(f"Processing {file_name}...")

                rows = process_file(ftp, engine, file_name, logger)

                action = f"update [dbo].[{table_name}]"

                if rows is not None:
                    logger.success(
                        table=table_name,
                        action=action,
                        message="table successfully updated.",
                        rows=rows,
                    )

                    print(f"{file_name} successfully processed; {rows} rows loaded.")

                    if file_name in {"preorders.csv", "preorders-history.csv"}:
                        action = (
                            "trigger a power bi dataset refresh for global preorders"
                        )

                        err = create_pbi_refresh_file()

                        if err is not None:
                            logger.error(
                                table="global_preorders", action=action, message=err
                            )

                            print(
                                "global_preorders power bi dataset has failed to refresh"
                            )

                        else:
                            logger.info(
                                table="global_preorders",
                                action=action,
                                message="pbi dataset has been refreshed",
                            )

                            print(
                                "global_preorders power bi dataset has successfully beeen refreshed."
                            )
                else:
                    logger.failure(
                        table=table_name,
                        action=action,
                        message="table update failed.",
                    )

                    print(f"{file_name} failed; see the database log for details.")

                    exit_code = 1

    finally:
        cleanup_error = cleanup_archive_files()

        if cleanup_error is not None:
            logger.error(
                table="ftp_polling",
                action="remove expired local FTP archive files",
                message=f"Error: {cleanup_error}",
            )

            print(f"Local FTP archive cleanup error: {cleanup_error}")

            exit_code = 1

        if logger.records:
            log_error = logger.flush_log_records(engine)

            if log_error is not None:
                print(f"Failed to write database logs: {log_error}")

                exit_code = 1

        engine.dispose()

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
