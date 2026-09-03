USE [data_control];

GO

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO

CREATE
	OR

ALTER PROCEDURE [dbo].[update_sales_orders_table]
AS
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	DECLARE @transaction_started BIT = 0;

	IF OBJECT_ID(N'dbo.sales_orders_staging', N'U') IS NULL THROW 50001
		,'dbo.sales_orders_staging does not exist.'
		,1;
		IF NOT EXISTS (
				SELECT 1
				
				FROM [dbo].[sales_orders_staging]
				) THROW 50002
			,'dbo.sales_orders_staging contains no rows.'
			,1;
			IF EXISTS (
					SELECT [entity]
						,[document_type]
						,[document_no]
						,[line_no]
					
					FROM [dbo].[sales_orders_staging]
					
					GROUP BY [entity]
						,[document_type]
						,[document_no]
						,[line_no]
					
					HAVING COUNT(*) > 1
					) THROW 50003
				,'dbo.sales_orders_staging contains duplicate business keys.'
				,1;
				IF EXISTS (
						SELECT 1
						
						FROM [dbo].[sales_orders_staging]
						
						WHERE [entity] IS NULL
							OR [document_type] IS NULL
							OR [document_no] IS NULL
							OR [line_no] IS NULL
							OR NULLIF([sell_to_customer_id], N'') IS NULL
							OR NULLIF([bill_to_customer_id], N'') IS NULL
						) THROW 50004
					,'dbo.sales_orders_staging contains a NULL or blank required key.'
					,1;
				BEGIN TRY
					IF @@TRANCOUNT = 0
					BEGIN
						BEGIN TRANSACTION;
						SET @transaction_started = 1;
					END;

					INSERT INTO [dbo].[customers] (
						[customer_id]
						,[currency_code]
						)
					
					SELECT refs.[customer_id]
						,MAX(refs.[currency_code])
					
					FROM (
						SELECT [sell_to_customer_id] AS [customer_id]
							,[currency_code]
						
						FROM [dbo].[sales_orders_staging]
						
						
						UNION ALL
						
						SELECT [bill_to_customer_id]
							,[currency_code]
						
						FROM [dbo].[sales_orders_staging]
						) AS refs
					
					WHERE NULLIF(refs.[customer_id], N'') IS NOT NULL
						AND NOT EXISTS (
							SELECT 1
							
							FROM [dbo].[customers] AS c
							
							WHERE c.[customer_id] = refs.[customer_id]
							)
					
					GROUP BY refs.[customer_id];

					INSERT INTO [dbo].[sales_people] ([salesperson_id])
					
					SELECT DISTINCT s.[salesperson_id]
					
					FROM [dbo].[sales_orders_staging] AS s
					
					WHERE NULLIF(s.[salesperson_id], N'') IS NOT NULL
						AND NOT EXISTS (
							SELECT 1
							
							FROM [dbo].[sales_people] AS sp
							
							WHERE sp.[salesperson_id] = s.[salesperson_id]
							);

					INSERT INTO [dbo].[countries] (
						[country_id]
						,[iso_code]
						)
					
					SELECT refs.[country_id]
						,LEFT(refs.[country_id], 2)
					
					FROM (
						SELECT [ship_to_country_id] AS [country_id]
						
						FROM [dbo].[sales_orders_staging]
						
						
						UNION
						
						SELECT [vat_country_id]
						
						FROM [dbo].[sales_orders_staging]
						) AS refs
					
					WHERE NULLIF(refs.[country_id], N'') IS NOT NULL
						AND NOT EXISTS (
							SELECT 1
							
							FROM [dbo].[countries] AS c
							
							WHERE c.[country_id] = refs.[country_id]
							);

					INSERT INTO [dbo].[brands] ([brand_id])
					
					SELECT refs.[brand_id]
					
					FROM (
						SELECT DISTINCT [brand_dimension_code] AS [brand_id]
						
						FROM [dbo].[sales_orders_staging]
						
						WHERE NULLIF([brand_dimension_code], N'') IS NOT NULL
						
						
						UNION
						
						SELECT DISTINCT CAST(LEFT([item_id], 3) AS NVARCHAR(20))
						
						FROM [dbo].[sales_orders_staging]
						
						WHERE NULLIF([item_id], N'') IS NOT NULL
						) AS refs
					
					WHERE NOT EXISTS (
							SELECT 1
							
							FROM [dbo].[brands] AS b
							
							WHERE b.[brand_id] = refs.[brand_id]
							);

					INSERT INTO [dbo].[items] ([item_id], [is_placeholder])
					SELECT DISTINCT s.[item_id], 1
					
					FROM [dbo].[sales_orders_staging] AS s
					
					WHERE NULLIF(s.[item_id], N'') IS NOT NULL
						AND NOT EXISTS (
							SELECT 1
							
							FROM [dbo].[items] AS i
							
							WHERE i.[item_id] = s.[item_id]
							);

					INSERT INTO [dbo].[dates] (
						[calendar_date]
						,[is_placeholder]
						)
					
					SELECT refs.[calendar_date]
						,1
					
					FROM (
						SELECT [order_date] AS [calendar_date]
						
						FROM [dbo].[sales_orders_staging]
						
						
						UNION
						
						SELECT [posting_date]
						
						FROM [dbo].[sales_orders_staging]
						
						
						UNION
						
						SELECT [shipment_date]
						
						FROM [dbo].[sales_orders_staging]
						) AS refs
					
					WHERE refs.[calendar_date] IS NOT NULL
						AND NOT EXISTS (
							SELECT 1
							
							FROM [dbo].[dates] AS d
							
							WHERE d.[date_key] = [dbo].[fnc_date_key](refs.[calendar_date])
							);

					DELETE
					
					FROM [dbo].[sales_orders];

					INSERT INTO [dbo].[sales_orders] (
						[entity]
						,[document_type]
						,[document_no]
						,[line_no]
						,[sell_to_customer_id]
						,[bill_to_customer_id]
						,[your_reference]
						,[ship_to_country_id]
						,[ship_to_code]
						,[document_date]
						,[order_date]
						,[posting_date]
						,[shipment_date]
						,[payment_terms_code]
						,[due_date]
						,[shipment_method_code]
						,[location_code]
						,[country_dimension_code]
						,[brand_dimension_code]
						,[customer_posting_group]
						,[currency_code]
						,[currency_factor]
						,[customer_price_group]
						,[prices_including_vat]
						,[salesperson_id]
						,[vat_country_id]
						,[intercompany_document_no]
						,[external_reference]
						,[last_modified]
						,[preorder]
						,[purchase_order_id]
						,[purchase_order_line_no]
						,[drop_shipment]
						,[document_status]
						,[line_type]
						,[gl_account_id]
						,[item_id]
						,[quantity]
						,[outstanding_quantity]
						,[unit_price]
						,[unit_cost]
						,[unit_cost_lcy]
						,[vat_percentage]
						,[line_discount_percentage]
						,[amount]
						,[amount_including_vat]
						,[outstanding_amount]
						,[quantity_shipped]
						,[quantity_invoiced]
						)
					
					SELECT [entity]
						,[document_type]
						,[document_no]
						,[line_no]
						,[sell_to_customer_id]
						,[bill_to_customer_id]
						,NULLIF([your_reference], N'')
						,NULLIF([ship_to_country_id], N'')
						,NULLIF([ship_to_code], N'')
						,[document_date]
						,[order_date]
						,[posting_date]
						,[shipment_date]
						,NULLIF([payment_terms_code], N'')
						,[due_date]
						,NULLIF([shipment_method_code], N'')
						,NULLIF([location_code], N'')
						,NULLIF([country_dimension_code], N'')
						,NULLIF([brand_dimension_code], N'')
						,NULLIF([customer_posting_group], N'')
						,[currency_code]
						,[currency_factor]
						,NULLIF([customer_price_group], N'')
						,[prices_including_vat]
						,NULLIF([salesperson_id], N'')
						,NULLIF([vat_country_id], N'')
						,NULLIF([intercompany_document_no], N'')
						,NULLIF([external_reference], N'')
						,[last_modified]
						,[preorder]
						,NULLIF([purchase_order_id], N'')
						,[purchase_order_line_no]
						,[drop_shipment]
						,[document_status]
						,[line_type]
						,NULLIF([gl_account_id], N'')
						,NULLIF([item_id], N'')
						,[quantity]
						,[outstanding_quantity]
						,[unit_price]
						,[unit_cost]
						,[unit_cost_lcy]
						,[vat_percentage]
						,[line_discount_percentage]
						,[amount]
						,[amount_including_vat]
						,[outstanding_amount]
						,[quantity_shipped]
						,[quantity_invoiced]
					
					FROM [dbo].[sales_orders_staging];

					DROP TABLE [dbo].[sales_orders_staging];

					IF @transaction_started = 1
						COMMIT TRANSACTION;
				
				END TRY

	BEGIN CATCH
		IF @transaction_started = 1 AND XACT_STATE() <> 0
			ROLLBACK TRANSACTION;

		THROW;
	
	END CATCH;

END;

GO

