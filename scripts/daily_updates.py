import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))


def main() -> None:
    from shinerutils import (
        get_sqlalchemy_engine,
        update_brands_table,
        update_countries_table,
        update_customers_table,
        update_exchange_rates_table,
        update_inventory_table,
        update_item_images_table,
        update_item_packaging_table,
        update_items_table,
        update_purchase_orders_table,
        update_record_link_table,
        update_sales_orders_table,
        update_sales_people_table,
        update_sales_table,
        update_vendors_table,
    )
    from shinerutils.logging import DatabaseLogger

    # initialize new instance of logger class

    logger = DatabaseLogger()

    # initialize new instances of sqlalchemy engine class to connect to different servers/databases

    engine_sql02 = get_sqlalchemy_engine("shinersql18", "NAV_LIVE")
    engine_sql04 = get_sqlalchemy_engine("shinersql04", "BC_LIVE_USA")
    engine_sql05 = get_sqlalchemy_engine("shinersql05", "BC_UAT_UK")
    engine_finance = get_sqlalchemy_engine("shinersql18", "Finance")
    engine_sql18 = get_sqlalchemy_engine("shinersql18", "data_control")

    try:
        # execute function to update salesperson table and log wether it resulted in success or failure

        rows_affected = update_sales_people_table(
            engine_sql02, engine_sql04, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[sales_people] table"

        if rows_affected is None:

            print("An error occurred updating sales_people table")

            logger.failure(
                table="sales_people",
                action=action,
                message="sales_people table update has failed",
            )

        else:
            print(
                "sales_people table has been successfully updated, rows affected: ",
                rows_affected,
            )

            logger.success(
                table="sales_people",
                action=action,
                message=f"sales_people table has sucessfully been updated. {rows_affected} were inserted. old data was replaced.",
                rows=rows_affected,
            )

        # execute function to update countries table and log wether it resulted in success or failure

        rows_affected = update_countries_table(
            engine_sql04, engine_sql05, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[countries] table"

        if rows_affected is None:

            print("An error occurred updating countries table")

            logger.failure(
                table="countries",
                action=action,
                message="countries table update has failed",
            )

        else:
            print(
                "countries table has been successfully updated, rows affected: ",
                rows_affected,
            )

            logger.success(
                table="countries",
                action=action,
                message=f"countries table has sucessfully been updated. {rows_affected} were inserted. old data was replaced.",
                rows=rows_affected,
            )

        # execute function to update customers table and log wether it resulted in success or failure

        rows_affected = update_customers_table(
            engine_sql02, engine_sql04, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[customers] table"

        if rows_affected is None:

            print("An error occurred updating customers table")

            logger.failure(
                table="customers",
                action=action,
                message="customers table update has failed",
            )

        else:
            print(
                "customers table has been successfully updated, rows affected: ",
                rows_affected,
            )

            logger.success(
                table="customers",
                action=action,
                message=f"customers table has sucessfully been updated. {rows_affected} were inserted. old data was replaced.",
                rows=rows_affected,
            )

        # Update the vendor dimension after its country and purchaser dimensions.

        rows_affected = update_vendors_table(
            engine_sql02, engine_sql04, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[vendors] table"

        if rows_affected is None:

            print("An error occurred updating vendors table")

            logger.failure(
                table="vendors",
                action=action,
                message="vendors table update has failed",
            )
        else:
            print(
                "vendors table has been successfully updated, rows affected: ",
                rows_affected,
            )
            logger.success(
                table="vendors",
                action=action,
                message=f"vendors table has successfully been updated. {rows_affected} "
                "were inserted. old data was replaced.",
                rows=rows_affected,
            )

        # execute function to update brands table and log whether it resulted in success or failure

        rows_affected = update_brands_table(engine_sql02, engine_sql18, logger)

        action = "update [data_control].[dbo].[brands] table"

        if rows_affected is None:

            print("An error occurred updating brands table")

            logger.failure(
                table="brands",
                action=action,
                message="brands table update has failed",
            )

        else:
            print(
                "brands table has been successfully updated, rows affected: ",
                rows_affected,
            )

            logger.success(
                table="brands",
                action=action,
                message=f"brands table has sucessfully been updated. {rows_affected} were inserted. old data was replaced.",
                rows=rows_affected,
            )

        # execute function to update items table and log whether it resulted in success or failure

        rows_affected = update_items_table(
            engine_sql02, engine_sql04, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[items] table"

        if rows_affected is None:

            print("An error occurred updating items table")

            logger.failure(
                table="items",
                action=action,
                message="items table update has failed",
            )

        else:
            print(
                "items table has been successfully updated, rows affected: ",
                rows_affected,
            )

            logger.success(
                table="items",
                action=action,
                message=f"items table has sucessfully been updated. {rows_affected} were inserted. old data was replaced.",
                rows=rows_affected,
            )

        # Inventory depends on the global item and brand dimensions.

        rows_affected = update_inventory_table(
            engine_sql02, engine_sql04, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[inventory] table"

        if rows_affected is None:

            print("An error occurred updating inventory table")

            logger.failure(
                table="inventory",
                action=action,
                message="inventory table update has failed",
            )
        else:
            print(
                "inventory table has been successfully updated, rows affected: ",
                rows_affected,
            )
            logger.success(
                table="inventory",
                action=action,
                message=f"inventory table has successfully been updated. "
                f"{rows_affected} rows were inserted; old data was replaced.",
                rows=rows_affected,
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
                table="record_link",
                action=action,
                message="record_link table update has failed",
            )
        else:
            print(
                "record_link table has been successfully updated, rows affected: ",
                rows_affected,
            )
            logger.success(
                table="record_link",
                action=action,
                message=f"record_link table has successfully been updated. "
                f"{rows_affected} rows were inserted. old data was replaced.",
                rows=rows_affected,
            )

        # Images depend on the refreshed item and record-link dimensions.

        rows_affected = update_item_images_table(engine_sql18, logger)

        action = "update [data_control].[dbo].[item_images] tables"

        if rows_affected is None:

            print("An error occurred updating item image tables")

            logger.failure(
                table="item_images",
                action=action,
                message="item image table update has failed",
            )
        else:
            print(
                "item image tables have been successfully updated, "
                "locations affected: ",
                rows_affected,
            )
            logger.success(
                table="item_images",
                action=action,
                message=f"item image tables have successfully been updated. "
                f"{rows_affected} locations were inserted.",
                rows=rows_affected,
            )

        rows_affected = update_item_packaging_table(engine_sql18, logger)

        action = "update [data_control].[dbo].[item_packaging] table"

        if rows_affected is None:

            print("An error occurred updating item_packaging table")

            logger.failure(
                table="item_packaging",
                action=action,
                message="item_packaging table update failed",
            )
        else:
            print(
                f"item_packaging table successfully updated, rows affected: {rows_affected}"
            )
            logger.success(
                table="item_packaging",
                action=action,
                message=f"item_packaging successfully updated; {rows_affected} rows inserted",
                rows=rows_affected,
            )

        # execute function to update exchange_rates table and log whether it resulted in success or failure

        rows_affected = update_exchange_rates_table(
            engine_sql02, engine_sql04, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[exchange_rates] table"

        if rows_affected is None:

            print("An error occurred updating exchange_rates table")

            logger.failure(
                table="exchange_rates",
                action=action,
                message="exchange_rates table update has failed",
            )

        else:
            print(
                "exchange_rates table has been successfully updated, rows affected: ",
                rows_affected,
            )

            logger.success(
                table="exchange_rates",
                action=action,
                message=f"exchange_rates table has sucessfully been updated. {rows_affected} were inserted. old data was replaced.",
                rows=rows_affected,
            )

        # Update purchase orders after the vendor and item dimensions.

        rows_affected = update_purchase_orders_table(
            engine_sql02, engine_sql04, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[purchase_orders] table"

        if rows_affected is None:

            print("An error occurred updating purchase_orders table")

            logger.failure(
                table="purchase_orders",
                action=action,
                message="purchase_orders table update has failed",
            )
        else:
            print(
                "purchase_orders table has been successfully updated, rows affected: ",
                rows_affected,
            )
            logger.success(
                table="purchase_orders",
                action=action,
                message=f"purchase_orders table has successfully been updated. "
                f"{rows_affected} rows were inserted. old data was replaced.",
                rows=rows_affected,
            )

        # Update current sales orders after their customer, item and date dimensions.

        rows_affected = update_sales_orders_table(
            engine_sql02, engine_sql04, engine_sql18, logger
        )

        action = "update [data_control].[dbo].[sales_orders] table"

        if rows_affected is None:

            print("An error occurred updating sales_orders table")

            logger.failure(
                table="sales_orders",
                action=action,
                message="sales_orders table update has failed",
            )
        else:
            print(
                "sales_orders table has been successfully updated, rows affected: ",
                rows_affected,
            )
            logger.success(
                table="sales_orders",
                action=action,
                message=f"sales_orders table has successfully been updated. "
                f"{rows_affected} rows were inserted. old data was replaced.",
                rows=rows_affected,
            )

        # Update sales after all dimensions and exchange rates are available.

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
                message=f"sales table has successfully been updated. "
                f"{rows_affected} rows were affected.",
                rows=rows_affected,
            )

    except Exception as e:

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

        engine_sql02.dispose()
        engine_sql04.dispose()
        engine_sql05.dispose()
        engine_finance.dispose()
        engine_sql18.dispose()


if __name__ == "__main__":
    main()
