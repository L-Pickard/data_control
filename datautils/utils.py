import os
from pathlib import Path
from typing import Any, Mapping, Sequence

from sqlalchemy import Engine
from pandas import DataFrame
from datautils.sql import fetch_sql_dataframe
from datautils.logging import DatabaseLogger


def load_environment_file(
    path: str | Path,
    *,
    override: bool = False,
) -> bool:
    """Load simple KEY=VALUE settings from an environment file.

    Existing process environment variables win unless ``override`` is true.
    Blank lines and lines beginning with ``#`` are ignored. Values may be
    unquoted or enclosed in matching single or double quotes.
    """

    environment_path = Path(path)
    if not environment_path.is_file():
        return False

    for line_number, raw_line in enumerate(
        environment_path.read_text(encoding="utf-8-sig").splitlines(), start=1
    ):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()
        if "=" not in line:
            raise ValueError(
                f"invalid environment setting on line {line_number} of "
                f"{environment_path}: expected KEY=VALUE"
            )

        name, value = line.split("=", 1)
        name = name.strip()
        value = value.strip()
        if not name or not name.replace("_", "a").isalnum() or name[0].isdigit():
            raise ValueError(
                f"invalid environment variable name {name!r} on line "
                f"{line_number} of {environment_path}"
            )
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]

        if override or name not in os.environ:
            os.environ[name] = value

    return True


def environment_value(*names: str, default: str | None = None) -> str | None:
    """Return the first configured nonblank environment value, or a default."""

    for name in names:
        value = os.getenv(name)
        if value and value.strip():
            return value.strip()
    return default


def first_environment_value(*names: str) -> str:
    """Return the first configured nonblank environment variable."""

    value = environment_value(*names)
    if value is not None:
        return value
    raise ValueError(
        "one of these environment variables is required: " + ", ".join(names)
    )

def after_first_space(s: str) -> str:
    parts = s.split(" ", 1)
    return parts[1] if len(parts) > 1 else ""

def concurrent_df_load(engine: Engine, query_path: Path, logger: DatabaseLogger, source_name: str) -> tuple[DataFrame | None, str | None]:

    try:

        action = f"read in {source_name} query file: {query_path.resolve()}"

        query = query_path.read_text(encoding="utf-8")

        logger.info(
            after_first_space(source_name),
            "read file successfully",
            action,
        )

    except Exception as e:
        err = f"error reading query file for {source_name}. ERROR: {e}"
        return None, err

    action = f"execute {source_name} query against db"

    df, err = fetch_sql_dataframe(engine, query)

    if err is not None:
        err = f"an error occurred executing {source_name} query. ERROR: {err}"
        return None, err

    if df is None:
        err = f"{source_name} dataframe is none"
        return None, err
    
    logger.info(
        after_first_space(source_name),
        "query has sucessfully been executed and dataframe has been",
        action,
    )

    return df, None


def concurrent_df_load_params(
    engine: Engine,
    query_path: Path,
    params: Sequence | Mapping[str, Any],
    logger: DatabaseLogger,
    source_name: str,
) -> tuple[DataFrame | None, str | None]:

    try:
        action = f"read in {source_name} query file: {query_path.resolve()}"

        query = query_path.read_text(encoding="utf-8")

        logger.info(
            after_first_space(source_name),
            "read file successfully",
            action,
        )

    except Exception as e:
        err = f"error reading query file for {source_name}. ERROR: {e}"
        return None, err

    action = f"execute {source_name} query against db with params"

    df, err = fetch_sql_dataframe(engine, query, params)

    if err is not None:
        err = f"an error occurred executing {source_name} query. ERROR: {err}"
        return None, err

    if df is None:
        err = f"{source_name} dataframe is none"
        return None, err

    logger.info(
        after_first_space(source_name),
        "query has sucessfully been executed and dataframe has been",
        action,
    )

    return df, None
