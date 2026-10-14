"""Refresh the inventory-cost snapshot on demand."""

from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal

from pandas import DataFrame, concat, to_datetime
from sqlalchemy.dialects.mssql import DATE, DECIMAL, NVARCHAR
from sqlalchemy.engine import Engine

from shinerutils.constants import SELECTS_SQL02, SELECTS_SQL04
from shinerutils.logging import DatabaseLogger
from shinerutils.sql import write_df_to_sql_db
from shinerutils.utils import concurrent_df_load

TABLE = "item_inventory_costs"
KEY_COLUMNS = ["entity", "item_id"]
RECEIPT_COLUMNS = ["first_receipt", "last_receipt"]
COLUMNS = [*KEY_COLUMNS, "quantity", "cost", *RECEIPT_COLUMNS]


def _validate_item_inventory_costs(frame: DataFrame) -> None:
    if frame.empty:
        raise ValueError("the combined inventory-cost source returned no rows")
    
    if frame[[*KEY_COLUMNS, "quantity", "cost"]].isna().any().any():
        raise ValueError("inventory costs contain a NULL key, quantity or cost")
    
    if frame.duplicated(subset=KEY_COLUMNS).any():
        raise ValueError("inventory costs contain duplicate entity/item keys")
    
    for column in KEY_COLUMNS:
        if (
            frame[column]
            .map(
                lambda value: (
                    not isinstance(value, str) or not value.strip() or len(value) > 20
                )
            )
            .any()
        ):
            raise ValueError(f"inventory costs contain an invalid {column}")
        
    if not frame["entity"].isin(["Shiner Ltd", "Shiner B.V", "Shiner LLC"]).all():
        raise ValueError("inventory costs contain an unknown entity")
    
    for column in ("quantity", "cost"):
        
        frame[column] = frame[column].map(lambda value: Decimal(str(value)))

        if not frame[column].map(
            lambda value: isinstance(value, Decimal) and value.is_finite()
        ).all():
            raise ValueError(f"inventory costs contain a non-finite {column}")
        
    if frame["quantity"].map(lambda value: value <= 0).any():
        raise ValueError("inventory costs contain a non-positive quantity")

    for column in RECEIPT_COLUMNS:
        frame[column] = to_datetime(frame[column], errors="raise").dt.date
    if (frame["first_receipt"].isna() != frame["last_receipt"].isna()).any():
        raise ValueError("inventory costs contain an incomplete receipt date range")
    dated = frame.loc[frame["first_receipt"].notna()]
    if (dated["first_receipt"] > dated["last_receipt"]).any():
        raise ValueError("inventory costs contain a reversed receipt date range")
    for column in RECEIPT_COLUMNS:
        frame[column] = frame[column].astype(object).where(frame[column].notna(), None)


def update_item_inventory_costs_table(engine_sql02: Engine, engine_sql04: Engine, engine_sql18: Engine, logger: DatabaseLogger,
) -> int | None:
    
    action = "load inventory-cost sources"

    try:

        with ThreadPoolExecutor(max_workers=2) as executor:
            futures = [
                executor.submit(
                    concurrent_df_load, engine, path / f"{TABLE}.sql", logger, label
                )
                for engine, path, label in (
                    (engine_sql02, SELECTS_SQL02, "sql02 inventory costs"),
                    (engine_sql04, SELECTS_SQL04, "sql04 inventory costs"),
                )
            ]

            results = [future.result() for future in futures]

        frames = []
        for frame, error in results:

            if error is not None:
                raise RuntimeError(error)
            
            if frame is None:
                raise ValueError("an inventory-cost source returned no dataframe")
            
            frames.append(frame.loc[:, COLUMNS])

        action = "validate inventory costs"

        frame = concat(frames, ignore_index=True)

        _validate_item_inventory_costs(frame)

        rows = len(frame)

        action = "replace sql18 item_inventory_costs data"

        with engine_sql18.begin() as connection:
            connection.exec_driver_sql("DELETE FROM [dbo].[item_inventory_costs];")
            write_df_to_sql_db(
                connection,
                TABLE,
                frame,
                "append",
                chunksize=min(rows, 20000),
                datatype={
                    "entity": NVARCHAR(20),
                    "item_id": NVARCHAR(20),
                    "quantity": DECIMAL(38, 20),
                    "cost": DECIMAL(38, 20),
                    "first_receipt": DATE(),
                    "last_receipt": DATE(),
                },
                schema="dbo",
            )
        return rows
    
    except Exception as exc:  # noqa: BLE001
        logger.error(table=TABLE, action=action, message=str(exc))
        return None
