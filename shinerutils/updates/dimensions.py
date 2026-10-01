"""Refresh small dimensions without deleting keys used by historical facts."""

from pandas import DataFrame
from sqlalchemy import text
from sqlalchemy.engine import Engine


DIMENSIONS = {
    "countries": ("country_id", "iso_code", "country_name", "flag_image_url"),
    "sales_people": ("salesperson_id", "name", "email", "active"),
}


def upsert_dimension(engine: Engine, table: str, frame: DataFrame) -> None:
    columns = DIMENSIONS[table]
    key = columns[0]
    if frame.empty or frame[key].isna().any() or frame[key].duplicated().any():
        raise ValueError(f"{table} requires nonempty data with unique, non-NULL {key}")
    records = frame.loc[:, list(columns)].astype(object)
    records = records.where(records.notna(), None).to_dict("records")
    assignments = ", ".join(f"[{column}] = :{column}" for column in columns[1:])
    names = ", ".join(f"[{column}]" for column in columns)
    values = ", ".join(f":{column}" for column in columns)
    # The serializable key-range lock prevents simultaneous inserts of a new code.
    statement = text(f"""
        UPDATE [dbo].[{table}] WITH (UPDLOCK, HOLDLOCK)
        SET {assignments} WHERE [{key}] = :{key};
        IF @@ROWCOUNT = 0
            INSERT INTO [dbo].[{table}] ({names}) VALUES ({values});
    """)
    with engine.begin() as connection:
        for record in records:
            connection.execute(statement, record)
