from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from io import BytesIO
from typing import Any
from urllib.parse import quote

from pandas import DataFrame, concat, isna, read_excel
from sqlalchemy import Engine

from shinerutils.constants import PROJECT_ROOT
from shinerutils.logging import DatabaseLogger
from shinerutils.ms_graph import (
    GRAPH_ROOT,
    acquire_token,
    create_graph_session,
    download_sharepoint_file_bytes,
    graph_get_json,
    graph_paged_values,
)
from shinerutils.sql import execute_sql_procedure, write_df_to_sql_db
from shinerutils.utils import first_environment_value, load_environment_file


@dataclass(frozen=True)
class ItemPackagingSettings:
    graph_tenant_id: str
    graph_client_id: str
    graph_client_secret: str

    @classmethod
    def from_environment(cls) -> ItemPackagingSettings:
        load_environment_file(PROJECT_ROOT / ".env")

        return cls(
            graph_tenant_id=first_environment_value("MS_GRAPH_TENANT_ID"),
            graph_client_id=first_environment_value("MS_GRAPH_CLIENT_ID"),
            graph_client_secret=first_environment_value("MS_GRAPH_CLIENT_SECRET"),
        )


ITEM_PACKAGING_FILES = (
    "Distributed Goods EPR Standard Input Spreadsheet.xlsx",
    "NPD Hardgoods EPR Standard Input Spreadsheet.xlsx",
    "NPD Softgoods EPR Standard Input Spreadsheet.xlsx",
)

def read_item_packaging_dataframe(
    token: str,
    drive_id: str | None = None,
    *,
    sheet_name: str | int = 0,
) -> DataFrame:

    frames: list[DataFrame] = []

    with create_graph_session(token) as session:
        if drive_id is None:
            drive = graph_get_json(
                session,
                f"{GRAPH_ROOT}/sites/shinerltd.sharepoint.com/drive",
            )
            drive_id = str(drive["id"])

        folder_path = quote("Packaging/SKU Files", safe="/")

        files = graph_paged_values(
            session,
            f"{GRAPH_ROOT}/drives/{quote(drive_id, safe='')}/root:"
            f"/{folder_path}:/children",
        )

        files = [item for item in files if item.get("file") is not None]

        for filename in ITEM_PACKAGING_FILES:
            matches = [
                item
                for item in files
                if str(item.get("name", "")).casefold() == filename.casefold()
            ]

            if len(matches) != 1:
                raise ValueError(
                    f"Expected one SharePoint file named {filename!r}; "
                    f"found {len(matches)} in Packaging/SKU Files. "
                    f"Available files: {[item.get('name') for item in files]}"
                )

            content = download_sharepoint_file_bytes(
                session, drive_id, str(matches[0]["id"])
            )

            with BytesIO(content) as stream:
                frame = read_excel(
                    stream, sheet_name=sheet_name, header=2, engine="openpyxl"
                )

            if frame.columns[:2].tolist() != ["Complete", "SKU"]:
                raise ValueError(f"Unexpected header row in {filename!r}")

            if frames and not frame.columns.equals(frames[0].columns):
                raise ValueError(
                    f"Packaging columns in {filename!r} do not match "
                    f"{ITEM_PACKAGING_FILES[0]!r}"
                )

            frames.append(frame)

    return concat(frames, ignore_index=True, sort=False)


def _packaging_decimal(value: Any, *, coerce: bool = False) -> Decimal | None:

    if isna(value):
        return None
    try:
        number = Decimal(str(value).strip())
        if not number.is_finite():
            raise InvalidOperation
        return number
    except InvalidOperation as exc:
        if coerce:
            return None
        raise ValueError(f"Invalid packaging numeric value: {value!r}") from exc


def _packaging_recycled_flag(value: Any) -> bool:
    if isna(value) or value in ("No", "0", 0):
        return False
    if value in ("Yes", "1", 1):
        return True
    raise ValueError(f"Invalid recycled content flag: {value!r}")


def transform_item_packaging_dataframe(source: DataFrame) -> DataFrame:

    brand_type_column = "Own Brand, Licensee or Distributer"
    if brand_type_column not in source.columns:
        raise ValueError(f"Missing required packaging column: {brand_type_column!r}")

    definitions = (
        ("Primary Paper/Cardboard", 7, True, "Primary Packaging Per Item"),
        ("Plastic", 6, True, "Primary Packaging Per Item"),
        ("Steel", 2, True, "Primary Packaging Per Item"),
        ("Fabric / Fibres", 2, False, "Primary Packaging Per Item"),
        ("Cloth", 2, False, "Primary Packaging Per Item"),
        ("Other", 3, False, "Primary Packaging Per Item"),
        ("Secondary Paper/Cardboard", 5, False, "Secondary Packaging Per Carton"),
        ("Secondary Plastic", 5, False, "Secondary Packaging Per Carton"),
    )

    fields = [
        "Weight",
        "Component Type",
        "Material",
        "Grading",
        "Recycled Content?",
        "% of Recycled Content",
    ]

    result_columns = [
        "SKU",
        brand_type_column,
        "Category",
        "Article Type",
        "Instance",
        "Component Type",
        "Material",
        "Grading",
        "Recycled Content?",
        "% of Recycled Content",
        "Weight",
        "Average Carton Qty",
    ]

    tables = []

    occurrences: dict[str, int] = {}

    for article, count, recycled, category in definitions:
        for instance in range(1, count + 1):
            selected_fields = fields if recycled else fields[:4]
            source_columns = []

            for field in selected_fields:
                occurrence = occurrences.get(field, 0)
                source_columns.append(f"{field}.{occurrence}" if occurrence else field)
                occurrences[field] = occurrence + 1

            # reindex supplies nulls for absent fields, like MissingField.UseNull.

            component = source.reindex(
                columns=["SKU", "Average Carton Qty", brand_type_column, *source_columns]
            ).copy()
            component.columns = ["SKU", "Average Carton Qty", brand_type_column, *selected_fields]
            if not recycled:
                component["Recycled Content?"] = None
                component["% of Recycled Content"] = None
            component["Category"] = category
            component["Article Type"] = article
            component["Instance"] = instance
            tables.append(component)

    result = concat(tables, ignore_index=True)

    result = result.loc[result["SKU"].notna() & result["Weight"].notna()].copy()

    result["Average Carton Qty"] = (
        result["Average Carton Qty"].fillna(1).map(_packaging_decimal)
    )

    result["Recycled Content?"] = (
        result["Recycled Content?"].map(_packaging_recycled_flag).astype("bool")
    )

    result["% of Recycled Content"] = (
        result["% of Recycled Content"].fillna(0).map(_packaging_decimal)
    )
    result["Weight"] = result["Weight"].map(
        lambda value: _packaging_decimal(value, coerce=True)
    )
    result["Instance"] = result["Instance"].astype("int64")

    result = result.reindex(columns=result_columns).rename(
        columns={
            "SKU": "item_id",
            brand_type_column: "brand_type",
            "Category": "category",
            "Article Type": "article_type",
            "Instance": "instance",
            "Component Type": "component_type",
            "Material": "material",
            "Grading": "grading",
            "Recycled Content?": "recycled_content",
            "% of Recycled Content": "%_recycled_content",
            "Weight": "weight_kg",
            "Average Carton Qty": "avg_carton_qty",
        }
    )
    return result.reset_index(drop=True)


def update_item_packaging_table(engine_sql18: Engine, logger: DatabaseLogger) -> int | None:

    settings = ItemPackagingSettings.from_environment()

    token = acquire_token(
        settings.graph_tenant_id,
        settings.graph_client_id,
        settings.graph_client_secret,
    )

    if token is None:
        logger.error(
            table="item_packaging",
            action="authenticate with Microsoft Graph",
            message="Microsoft Graph did not return an access token",
        )

        return None

    try:
        df = read_item_packaging_dataframe(token)

        import_df = transform_item_packaging_dataframe(df)

    except Exception as exc:  # noqa: BLE001
        logger.error(
            table="item_packaging",
            action="read and transform SharePoint packaging workbooks",
            message=str(exc),
        )

        return None

    logger.info(
        table="item_packaging",
        action="combine SharePoint packaging workbooks",
        message=f"Combined {len(ITEM_PACKAGING_FILES)} workbooks into one DataFrame",
        rows=len(df),
    )

    action = "clear old data from item_packaging table"

    rows, err = execute_sql_procedure(
        engine_sql18, "DELETE FROM [dbo].[item_packaging];"
    )

    if err != None:
        logger.error(table="item_packaging", action=action, message=str(err))

        return None

    logger.info(
        table="item_packaging",
        action=action,
        message="procedure sucessfully executed",
        rows=rows,
    )

    action = "write transformed EPR data to item_packaging table"

    try:
        write_df_to_sql_db(engine_sql18, "item_packaging", import_df, "append")

    except Exception as err:  # noqa: BLE001
        logger.error(table="item_packaging", action=action, message=str(err))

        return None

    logger.info(
        table="item_packaging",
        action=action,
        message="data sucessfully written",
        rows=len(import_df),
    )

    return len(import_df)
