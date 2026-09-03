"""
Shared utilities for data control scripts.
"""

from .constants import (
    DB_LOG_TABLE,
    DOCUMENTS,
    LOGGING_DB,
    PROJECT_ROOT,
    SELECTS_SQL02,
    SELECTS_SQL04,
    SELECTS_SQL05,
    SELECTS_SQL18,
    SQL_SELECTS,
)
from .logging import DatabaseLogger, LogRecord
from .filesystem import (
    get_windows_file_size,
    is_ignored_system_file,
    iter_files_by_extension,
    read_windows_file_bytes,
)
from .ftp import delete_ftp_file, download_ftp_file, get_ftp_connection, list_ftp_files
from .ms_graph import (
    acquire_token,
    create_graph_session,
    download_sharepoint_file_bytes,
    delete_sharepoint_file,
    download_sharepoint_file,
    file_is_from_today_utc,
    get_sharepoint_file_info,
    graph_get_json,
    graph_paged_values,
    list_sharepoint_drive_files,
    open_sharepoint_excel_desktop,
    parse_graph_datetime,
    resolve_sharepoint_drive_id,
    resolve_sharepoint_site_id,
    upload_sharepoint_file,
)
from .sql import (
    DatabaseBind,
    execute_sql_procedure,
    fetch_sql_dataframe,
    get_sales_increment,
    get_sqlalchemy_engine,
    transactional_connection,
    write_df_to_sql_db,
)
from .updates.brands import update_brands_table
from .updates.brand_forecast import update_brand_forecast_table
from .updates.countries import update_countries_table
from .updates.customers import update_customers_table
from .updates.dates import update_dates_table
from .updates.exchange_rates import update_exchange_rates_table
from .updates.items import update_items_table
from .updates.inventory import update_inventory_table
from .updates.item_images import (
    sync_item_images_to_sharepoint,
    update_item_images_table,
)
from .updates.monthly_average_exchange_rates import (
    update_monthly_average_exchange_rates_table,
)
from .updates.purchase_orders import update_purchase_orders_table
from .updates.preorders import update_preorders_table
from .updates.record_link import update_record_link_table
from .updates.sales import update_sales_table
from .updates.sales_orders import update_sales_orders_table
from .updates.sales_people import update_sales_people_table
from .updates.vendors import update_vendors_table
from .utils import (
    after_first_space,
    concurrent_df_load,
    concurrent_df_load_params,
    environment_value,
    first_environment_value,
    load_environment_file,
)

__all__ = [
    "DB_LOG_TABLE",
    "DatabaseBind",
    "DOCUMENTS",
    "LOGGING_DB",
    "PROJECT_ROOT",
    "SELECTS_SQL02",
    "SELECTS_SQL04",
    "SELECTS_SQL05",
    "SELECTS_SQL18",
    "SQL_SELECTS",
    "LogRecord",
    "DatabaseLogger",
    "acquire_token",
    "after_first_space",
    "concurrent_df_load",
    "concurrent_df_load_params",
    "create_graph_session",
    "download_sharepoint_file_bytes",
    "delete_sharepoint_file",
    "delete_ftp_file",
    "download_sharepoint_file",
    "download_ftp_file",
    "environment_value",
    "execute_sql_procedure",
    "fetch_sql_dataframe",
    "file_is_from_today_utc",
    "first_environment_value",
    "get_sales_increment",
    "get_ftp_connection",
    "get_sharepoint_file_info",
    "get_windows_file_size",
    "get_sqlalchemy_engine",
    "graph_get_json",
    "graph_paged_values",
    "iter_files_by_extension",
    "is_ignored_system_file",
    "list_sharepoint_drive_files",
    "load_environment_file",
    "open_sharepoint_excel_desktop",
    "parse_graph_datetime",
    "read_windows_file_bytes",
    "list_ftp_files",
    "resolve_sharepoint_drive_id",
    "resolve_sharepoint_site_id",
    "sync_item_images_to_sharepoint",
    "transactional_connection",
    "update_brands_table",
    "update_brand_forecast_table",
    "update_countries_table",
    "update_customers_table",
    "update_dates_table",
    "update_exchange_rates_table",
    "update_items_table",
    "update_inventory_table",
    "update_item_images_table",
    "update_monthly_average_exchange_rates_table",
    "update_purchase_orders_table",
    "update_preorders_table",
    "update_record_link_table",
    "update_sales_people_table",
    "update_sales_table",
    "update_sales_orders_table",
    "update_vendors_table",
    "upload_sharepoint_file",
    "write_df_to_sql_db",
]
