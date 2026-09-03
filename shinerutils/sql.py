from collections.abc import Iterator, Mapping, Sequence
from contextlib import contextmanager
from typing import Any, Literal, TypeAlias
from urllib.parse import quote_plus

from pandas import DataFrame
from sqlalchemy import Connection, Engine, create_engine, text


DatabaseBind: TypeAlias = Engine | Connection


@contextmanager
def transactional_connection(bind: DatabaseBind) -> Iterator[Connection]:
    """Use an existing transaction or create one when given an engine."""

    if isinstance(bind, Connection):
        yield bind
    else:
        with bind.begin() as connection:
            yield connection


def get_sales_increment(engine: Engine, entity: str) -> str:

    entity = entity.strip()

    if not entity:
        raise ValueError("entity must not be blank")

    query = text(
        "SELECT [sales_increment] "
        "FROM [dbo].[entities] "
        "WHERE [entity] = :entity"
    )

    with engine.connect() as conn:
        increment_date = conn.execute(query, {"entity": entity}).scalar_one_or_none()

    if increment_date is None:
        raise ValueError(
            f"No sales increment found for entity {entity!r}"
        )

    return increment_date.isoformat()


def get_sqlalchemy_engine(
    server: str,
    db: str,
    driver: str = "ODBC Driver 17 for SQL Server",
    user: str | None = None,
    password: str | None = None,
) -> Engine:
    """
    The below function creates an engine to connect to specified database.

    """

    if user is None or password is None:
        odbc = (
            f"DRIVER={{{driver}}};SERVER={server};DATABASE={db};Trusted_Connection=yes;"
        )
        return create_engine(f"mssql+pyodbc:///?odbc_connect={quote_plus(odbc)}")
    else:
        drv = quote_plus(driver)
        return create_engine(
            f"mssql+pyodbc://{user}:{password}@{server}/{db}?driver={drv}"
        )


def execute_sql_procedure(
    bind: DatabaseBind, sql: str
) -> tuple[int | None, str | None]:
    """Execute SQL and return its row count or an error message."""

    try:
        with transactional_connection(bind) as connection:
            result = connection.exec_driver_sql(sql)
            rowcount = result.rowcount
            cursor = result.cursor

            # pyodbc can defer errors from later statements in a stored
            # procedure until its remaining result sets are consumed.
            if cursor is not None:
                while True:
                    if cursor.description is not None:
                        cursor.fetchall()
                    if not cursor.nextset():
                        break

            return rowcount, None
    except Exception as e:  # noqa: BLE001
        return None, str(e)


def fetch_sql_dataframe(
    engine: Engine, sql: str, params: Sequence | Mapping[str, Any] | None = None
) -> tuple[DataFrame | None, str | None]:

    try:
        with engine.connect() as conn:
            if isinstance(params, Mapping):
                res = conn.execute(text("SET NOCOUNT ON;\n" + sql), params)
            else:
                res = conn.exec_driver_sql("SET NOCOUNT ON;\n" + sql, params or ())

            cur = res.cursor

            if cur is None:
                return None, "ERROR: res.Cursor is None."

            cols = None
            rows = None

            while True:
                if cur.description is not None:
                    cols = [d[0] for d in cur.description]
                    rows = [tuple(row) for row in cur.fetchall()]

                if not cur.nextset():
                    break

            if cols is None:
                return None, "Batch did not return a SELECT result set."

            return DataFrame(rows, columns=cols), None

    except Exception as e:  # noqa: BLE001
        return None, f"Error fetching SQL DataFrame: {e}"


def write_df_to_sql_db(
    bind: DatabaseBind,
    table: str,
    df: DataFrame,
    if_exists: Literal["fail", "replace", "append", "delete_rows"] = "append",
    chunksize: int | None = 20000,
    datatype: dict | None = None,
    schema: str = "dbo",
) -> None:
    """Write a dataframe in its own transaction or the caller's transaction."""

    with transactional_connection(bind) as connection:
        connection = connection.execution_options(fast_executemany=True)

        df.to_sql(
            name=table,
            con=connection,
            schema=schema,
            index=False,
            if_exists=if_exists,
            dtype=datatype,
            chunksize=chunksize,
        )

        result = connection.exec_driver_sql(
            f"SELECT COUNT(*) FROM [{schema}].[{table}]"
        )
        actual_rows = result.scalar()

        if actual_rows == 0 and len(df) > 0:
            raise RuntimeError(
                f"df.to_sql completed but [{schema}].[{table}] contains 0 rows."
            )
