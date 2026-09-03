import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))


def main() -> None:
    from datautils.logging import DatabaseLogger
    from datautils import (
        get_sqlalchemy_engine,
        update_brand_forecast_table,
        update_brands_table,
        update_countries_table,
        update_customers_table,
        update_exchange_rates_table,
        update_item_images_table,
        update_inventory_table,
        update_items_table,
        update_monthly_average_exchange_rates_table,
        update_preorders_table,
        update_purchase_orders_table,
        update_record_link_table,
        update_sales_people_table,
        update_sales_orders_table,
        update_sales_table,
        update_vendors_table,
    )

    # initialize new instance of logger class

    logger = DatabaseLogger()

    # initialize new instances of sqlalchemy engine class to connect to different servers/databases

    engine_sql02 = get_sqlalchemy_engine("source_d", "ERP_LIVE")
    engine_sql04 = get_sqlalchemy_engine("source_b", "ERP_LIVE_US")
    engine_sql05 = get_sqlalchemy_engine("source_c", "ERP_TEST_UK")
    engine_finance = get_sqlalchemy_engine("source_d", "Finance")
    engine_sql18 = get_sqlalchemy_engine("source_d", "data_control")

    try:
        # execute function to update salesperson table and log wether it resulted in success or failure

        rows_affected = update_sales_people_table(
            engine_sql02, engine_sql04, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[sales_people] table"

        if rows_affected is None:
            print("An error occurred updating sales_people table")

            logger.failure(
                "sales_people",
                action,
                "sales_people table update has failed",
            )

        else:
            print(
                "sales_people table has been successfully updated, rows affected: ",
                rows_affected,
            )

            logger.success(
                "sales_people",
                action,
                f"sales_people table has sucessfully been updated. {rows_affected} were inserted. old data was replaced.",
                rows_affected,
            )

        # execute function to update countries table and log wether it resulted in success or failure

        rows_affected = update_countries_table(
            engine_sql04, engine_sql05, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[countries] table"

        if rows_affected is None:
            print("An error occurred updating countries table")

            logger.failure(
                "countries",
                action,
                "countries table update has failed",
            )

        else:
            print(
                "countries table has been successfully updated, rows affected: ",
                rows_affected,
            )

            logger.success(
                "countries",
                action,
                f"countries table has sucessfully been updated. {rows_affected} were inserted. old data was replaced.",
                rows_affected,
            )

        # execute function to update customers table and log wether it resulted in success or failure

        rows_affected = update_customers_table(
            engine_sql02, engine_sql04, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[customers] table"

        if rows_affected is None:
            print("An error occurred updating customers table")

            logger.failure(
                "customers",
                action,
                "customers table update has failed",
            )

        else:
            print(
                "customers table has been successfully updated, rows affected: ",
                rows_affected,
            )

            logger.success(
                "customers",
                action,
                f"customers table has sucessfully been updated. {rows_affected} were inserted. old data was replaced.",
                rows_affected,
            )

        # Update the vendor dimension after its country and purchaser dimensions.

        rows_affected = update_vendors_table(
            engine_sql02, engine_sql04, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[vendors] table"

        if rows_affected is None:
            print("An error occurred updating vendors table")
            logger.failure(
                "vendors",
                action,
                "vendors table update has failed",
            )
        else:
            print(
                "vendors table has been successfully updated, rows affected: ",
                rows_affected,
            )
            logger.success(
                "vendors",
                action,
                f"vendors table has successfully been updated. {rows_affected} "
                "were inserted. old data was replaced.",
                rows_affected,
            )

        # execute function to update brands table and log whether it resulted in success or failure

        rows_affected = update_brands_table(engine_sql02, engine_sql18, logger)

        action = "update [data_control].[dbo].[brands] table"

        if rows_affected is None:
            print("An error occurred updating brands table")

            logger.failure(
                "brands",
                action,
                "brands table update has failed",
            )

        else:
            print(
                "brands table has been successfully updated, rows affected: ",
                rows_affected,
            )

            logger.success(
                "brands",
                action,
                f"brands table has sucessfully been updated. {rows_affected} were inserted. old data was replaced.",
                rows_affected,
            )

        # execute function to update items table and log whether it resulted in success or failure

        rows_affected = update_items_table(
            engine_sql02, engine_sql04, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[items] table"

        if rows_affected is None:
            print("An error occurred updating items table")

            logger.failure(
                "items",
                action,
                "items table update has failed",
            )

        else:
            print(
                "items table has been successfully updated, rows affected: ",
                rows_affected,
            )

            logger.success(
                "items",
                action,
                f"items table has sucessfully been updated. {rows_affected} were inserted. old data was replaced.",
                rows_affected,
            )

        # Inventory depends on the global item and brand dimensions.

        rows_affected = update_inventory_table(
            engine_sql02, engine_sql04, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[inventory] table"

        if rows_affected is None:
            print("An error occurred updating inventory table")
            logger.failure("inventory", action, "inventory table update has failed")
        else:
            print(
                "inventory table has been successfully updated, rows affected: ",
                rows_affected,
            )
            logger.success(
                "inventory",
                action,
                f"inventory table has successfully been updated. "
                f"{rows_affected} rows were inserted; old data was replaced.",
                rows_affected,
            )

        # Image selection uses record links, so refresh them after items and
        # before checking the image sources.

        rows_affected = update_record_link_table(
            engine_sql02, engine_sql04, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[record_link] table"

        if rows_affected is None:
            print("An error occurred updating record_link table")
            logger.failure(
                "record_link",
                action,
                "record_link table update has failed",
            )
        else:
            print(
                "record_link table has been successfully updated, rows affected: ",
                rows_affected,
            )
            logger.success(
                "record_link",
                action,
                f"record_link table has successfully been updated. "
                f"{rows_affected} rows were inserted. old data was replaced.",
                rows_affected,
            )

        # Images depend on the refreshed item and record-link dimensions.

        rows_affected = update_item_images_table(engine_sql18, logger)

        action = "update [data_control].[dbo].[item_images] tables"

        if rows_affected is None:
            print("An error occurred updating item image tables")
            logger.failure(
                "item_images",
                action,
                "item image table update has failed",
            )
        else:
            print(
                "item image tables have been successfully updated, "
                "locations affected: ",
                rows_affected,
            )
            logger.success(
                "item_images",
                action,
                f"item image tables have successfully been updated. "
                f"{rows_affected} locations were inserted.",
                rows_affected,
            )

        # execute function to update exchange_rates table and log whether it resulted in success or failure

        rows_affected = update_exchange_rates_table(
            engine_sql02, engine_sql04, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[exchange_rates] table"

        if rows_affected is None:
            print("An error occurred updating exchange_rates table")

            logger.failure(
                "exchange_rates",
                action,
                "exchange_rates table update has failed",
            )

        else:
            print(
                "exchange_rates table has been successfully updated, rows affected: ",
                rows_affected,
            )

            logger.success(
                "exchange_rates",
                action,
                f"exchange_rates table has sucessfully been updated. {rows_affected} were inserted. old data was replaced.",
                rows_affected,
            )

        # Refresh forecast exchange rates and flag forecasts when rates change.

        rows_affected = update_monthly_average_exchange_rates_table(
            engine_finance, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[monthly_avg_xr] table"

        if rows_affected is None:
            print("An error occurred updating monthly_avg_xr table")
            logger.failure(
                "monthly_avg_xr",
                action,
                "monthly_avg_xr table update has failed",
            )
        elif rows_affected == 0:
            print("monthly_avg_xr source is unchanged")
            logger.success(
                "monthly_avg_xr",
                action,
                "monthly_avg_xr source is unchanged; no rows were replaced",
                0,
            )
        else:
            print(
                "monthly_avg_xr table successfully updated, rows affected: ",
                rows_affected,
            )
            logger.success(
                "monthly_avg_xr",
                action,
                f"monthly_avg_xr successfully updated; {rows_affected} rows inserted",
                rows_affected,
            )

        # Refresh the forecast every day. It is a separate source snapshot and
        # must also populate a newly created or previously emptied table when
        # the monthly exchange-rate snapshot itself is unchanged.

        forecast_rows = update_brand_forecast_table(
            engine_finance, engine_sql18, logger
        )
        forecast_action = "update [data_control].[dbo].[brand_forecast] table"

        if forecast_rows is None:
            print("An error occurred updating brand_forecast table")
            logger.failure(
                "brand_forecast",
                forecast_action,
                "brand_forecast table update has failed",
            )
        else:
            print(
                "brand_forecast table successfully updated, rows affected: ",
                forecast_rows,
            )
            logger.success(
                "brand_forecast",
                forecast_action,
                f"brand_forecast successfully updated; {forecast_rows} rows inserted",
                forecast_rows,
            )

        # Update preorders after the brand and country dimensions.

        rows_affected = update_preorders_table(engine_finance, engine_sql18, logger)

        action = "update [data_control].[dbo].[preorders] table"

        if rows_affected is None:
            print("An error occurred updating preorders table")
            logger.failure(
                "preorders",
                action,
                "preorders table update has failed",
            )
        else:
            print(
                "preorders table successfully updated, source rows processed: ",
                rows_affected,
            )
            logger.success(
                "preorders",
                action,
                f"preorders successfully updated; "
                f"{rows_affected} source rows processed",
                rows_affected,
            )

        # Update purchase orders after the vendor and item dimensions.

        rows_affected = update_purchase_orders_table(
            engine_sql02, engine_sql04, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[purchase_orders] table"

        if rows_affected is None:
            print("An error occurred updating purchase_orders table")
            logger.failure(
                "purchase_orders",
                action,
                "purchase_orders table update has failed",
            )
        else:
            print(
                "purchase_orders table has been successfully updated, rows affected: ",
                rows_affected,
            )
            logger.success(
                "purchase_orders",
                action,
                f"purchase_orders table has successfully been updated. "
                f"{rows_affected} rows were inserted. old data was replaced.",
                rows_affected,
            )

        # Update current sales orders after their customer, item and date dimensions.

        rows_affected = update_sales_orders_table(
            engine_sql02, engine_sql04, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[sales_orders] table"

        if rows_affected is None:
            print("An error occurred updating sales_orders table")
            logger.failure(
                "sales_orders",
                action,
                "sales_orders table update has failed",
            )
        else:
            print(
                "sales_orders table has been successfully updated, rows affected: ",
                rows_affected,
            )
            logger.success(
                "sales_orders",
                action,
                f"sales_orders table has successfully been updated. "
                f"{rows_affected} rows were inserted. old data was replaced.",
                rows_affected,
            )

        # Update sales after all dimensions and exchange rates are available.

        rows_affected = update_sales_table(
            engine_sql02, engine_sql04, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[sales] table"

        if rows_affected is None:
            print("An error occurred updating sales table")
            logger.failure(
                "sales",
                action,
                "sales table update has failed",
            )
        else:
            print(
                "sales table has been successfully updated, rows affected: ",
                rows_affected,
            )
            logger.success(
                "sales",
                action,
                f"sales table has successfully been updated. "
                f"{rows_affected} rows were affected.",
                rows_affected,
            )

    except Exception as e:
        logger.critical(
            None,
            "run daily updates",
            f"daily update run crashed. Error: {e}",
        )
        raise

    finally:
        # write log records to db or file if not able to connect to db
        err = logger.flush_log_records(engine_sql18)
        if err is not None:
            print(err)

        engine_sql02.dispose()
        engine_sql04.dispose()
        engine_sql05.dispose()
        engine_finance.dispose()
        engine_sql18.dispose()


if __name__ == "__main__":
    main()
