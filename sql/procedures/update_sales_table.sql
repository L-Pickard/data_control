USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE
	OR

ALTER PROCEDURE [dbo].[update_sales_table]
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     15/07/2026
=================================================================================================================================================

================================================================================================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @transaction_started BIT = 0;

BEGIN TRY
	IF @@TRANCOUNT = 0
	BEGIN
		BEGIN TRANSACTION;

		SET @transaction_started = 1;
	
	END;

	-- The below update statement sets the base deductions and currency columns

	UPDATE sta
	
	SET  sta.[royalty_value] 		 	= [dbo].[fnc_calculate_item_royalty](sta.[item_id], sta.[customer_id], sta.[entity], sta.[sales])
		,sta.[customer_rebate_value] 	= [dbo].[fnc_calculate_customer_rebate](sta.[item_id], sta.[customer_id], sta.[entity], sta.[sales])
		,sta.[gbp_sales]			 	= [dbo].[fnc_convert_currency](sta.[currency_code], 'GBP', sta.[posting_date], sta.[sales])
		,sta.[gbp_cost]				 	= [dbo].[fnc_convert_currency](sta.[currency_code], 'GBP', sta.[posting_date], sta.[cost])
		,sta.[eur_sales]			 	= [dbo].[fnc_convert_currency](sta.[currency_code], 'EUR', sta.[posting_date], sta.[sales])
		,sta.[eur_cost]				 	= [dbo].[fnc_convert_currency](sta.[currency_code], 'EUR', sta.[posting_date], sta.[cost])
		,sta.[usd_sales]			 	= [dbo].[fnc_convert_currency](sta.[currency_code], 'USD', sta.[posting_date], sta.[sales])
		,sta.[usd_cost]				 	= [dbo].[fnc_convert_currency](sta.[currency_code], 'USD', sta.[posting_date], sta.[cost])
	
	FROM [dbo].[sales_staging] AS sta;

	-- The below update statement sets the values for the currency deduction columns.

	UPDATE sta
	
	SET  sta.[gbp_royalty]			 	= [dbo].[fnc_convert_currency](sta.[currency_code], 'GBP', sta.[posting_date], sta.[royalty_value])
		,sta.[gbp_rebate]			 	= [dbo].[fnc_convert_currency](sta.[currency_code], 'GBP', sta.[posting_date], sta.[customer_rebate_value])
		,sta.[eur_rebate]			 	= [dbo].[fnc_convert_currency](sta.[currency_code], 'EUR', sta.[posting_date], sta.[customer_rebate_value])
		,sta.[eur_royalty]			 	= [dbo].[fnc_convert_currency](sta.[currency_code], 'EUR', sta.[posting_date], sta.[royalty_value])
		,sta.[usd_royalty]			 	= [dbo].[fnc_convert_currency](sta.[currency_code], 'USD', sta.[posting_date], sta.[royalty_value])
		,sta.[usd_rebate]			 	= [dbo].[fnc_convert_currency](sta.[currency_code], 'USD', sta.[posting_date], sta.[customer_rebate_value])
	
	FROM [dbo].[sales_staging] AS sta;

	-- The below update statement sets the values for the currency margin columns.

	UPDATE sta
	
	SET  sta.[gbp_margin] 	= ISNULL(sta.[gbp_sales], 0) - (ISNULL(sta.[gbp_cost], 0) + ISNULL(sta.[gbp_royalty], 0) + ISNULL(sta.[gbp_rebate], 0))
		,sta.[eur_margin] 	= ISNULL(sta.[eur_sales], 0) - (ISNULL(sta.[eur_cost], 0) + ISNULL(sta.[eur_royalty], 0) + ISNULL(sta.[eur_rebate], 0))
		,sta.[usd_margin] 	= ISNULL(sta.[usd_sales], 0) - (ISNULL(sta.[usd_cost], 0) + ISNULL(sta.[usd_royalty], 0) + ISNULL(sta.[usd_rebate], 0))
	
	FROM [dbo].[sales_staging] AS sta;

	-- The below code checks whether there are records missing in the foriegn key tables and inserts them to keep referential integerity
	-- Insert any missing customers from staging table into customers table.

	INSERT INTO [dbo].[customers] (
		 [customer_id]
		,[currency_code]
		)
	
	SELECT DISTINCT st.[customer_id]
		,st.[currency_code]
	
	FROM [dbo].[sales_staging] AS st
	
	WHERE NOT EXISTS (
			SELECT 1
			
			FROM [customers]
			
			WHERE [customer_id] = st.[customer_id]
			);

	-- Insert any missing salespersons from staging table into sales_people table.

	INSERT INTO [dbo].[sales_people] ([salesperson_id])
	
	SELECT DISTINCT st.[salesperson_id]
	
	FROM [dbo].[sales_staging] AS st
	
	WHERE NOT EXISTS (
			SELECT 1
			
			FROM [sales_people]
			
			WHERE [salesperson_id] = st.[salesperson_id]
			);

	-- Insert any missing countries from staging table into countries table.

	INSERT INTO [dbo].[countries] (
		 [country_id]
		,[iso_code]
		)
	
	SELECT DISTINCT st.[country_id]
		,LEFT(st.[country_id], 2)
	
	FROM [dbo].[sales_staging] AS st
	
	WHERE NOT EXISTS (
			SELECT 1
			
			FROM [countries]
			
			WHERE [country_id] = st.[country_id]
			);

	-- Insert any missing brands from staging table into brands table.

	INSERT INTO [dbo].[brands] ([brand_id])
	
	SELECT DISTINCT CAST(LEFT(st.[item_id], 3) AS NVARCHAR(20))
	
	FROM [dbo].[sales_staging] AS st
	
	WHERE NULLIF(st.[item_id], '') IS NOT NULL
		AND NOT EXISTS (
			SELECT 1
			
			FROM [dbo].[brands] AS br
			
			WHERE br.[brand_id] = CAST(LEFT(st.[item_id], 3) AS NVARCHAR(20))
			);

	-- Below we insert the new sales records from the staging table into the sales table.

	INSERT INTO [dbo].[sales] (
		 [posting_date]
		,[document_date]
		,[location_code]
		,[customer_id]
		,[document_no]
		,[order_no]
		,[doc_type]
		,[salesperson_id]
		,[country_id]
		,[entity]
		,[is_adjusted]
		,[exclusion]
		,[intercompany]
		,[sales_type]
		,[item_id]
		,[quantity]
		,[gbp_sales]
		,[gbp_cost]
		,[gbp_royalty]
		,[gbp_rebate]
		,[gbp_margin]
		,[gbp_adjusted_margin]
		,[eur_sales]
		,[eur_cost]
		,[eur_royalty]
		,[eur_rebate]
		,[eur_margin]
		,[eur_adjusted_margin]
		,[usd_sales]
		,[usd_cost]
		,[usd_royalty]
		,[usd_rebate]
		,[usd_margin]
		,[usd_adjusted_margin]
		)
	
	SELECT st.[posting_date]
		,st.[document_date]
		,st.[location_code]
		,st.[customer_id]
		,st.[document_no]
		,st.[order_no]
		,st.[doc_type]
		,st.[salesperson_id]
		,st.[country_id]
		,st.[entity]
		,0 AS [is_adjusted]
		,[dbo].[fnc_is_customer_exclusion](st.[entity], st.[customer_id]) 			AS [exclusion]
		,[dbo].[fnc_is_customer_intercompany](st.[entity], st.[customer_id]) 		AS [intercompany]
		,CASE 
			WHEN cu.[customer_name] LIKE '%D2C%'
				THEN 'D2C'
			ELSE 'B2B'
			END 																	AS [sales_type]
		,st.[item_id]
		,st.[quantity]
		,st.[gbp_sales]
		,st.[gbp_cost]
		,st.[gbp_royalty]
		,st.[gbp_rebate]
		,st.[gbp_margin]
		,st.[gbp_margin] 															AS [gbp_adjusted_margin]
		,st.[eur_sales]
		,st.[eur_cost]
		,st.[eur_royalty]
		,st.[eur_rebate]
		,st.[eur_margin]
		,st.[eur_margin] 															AS [eur_adjusted_margin]
		,st.[usd_sales]
		,st.[usd_cost]
		,st.[usd_royalty]
		,st.[usd_rebate]
		,st.[usd_margin]
		,st.[usd_margin] 															AS [usd_adjusted_margin]
	
	FROM [data_control].[dbo].[sales_staging] AS st
	
	INNER JOIN [dbo].[customers] AS cu
		ON st.[customer_id] = cu.[customer_id];

	EXEC [dbo].[update_adjusted_margin];

	-- Advance each entity only when its staging rows contain a later posting date.

	UPDATE en
	SET [sales_increment] = staged.[max_posting_date]
	FROM [dbo].[entities] AS en
	INNER JOIN (
		SELECT
			 [entity]
			,MAX([posting_date]) AS [max_posting_date]
		FROM [dbo].[sales_staging]
		GROUP BY [entity]
	) AS staged
		ON staged.[entity] = en.[entity]
	WHERE staged.[max_posting_date] > en.[sales_increment];

	-- Below we execute the stored procedure to update adjusted margins

	EXECUTE [dbo].[update_adjusted_margin]
		 @start_date = '2025-05-01';

	-- Below we drop the sales staging table after all operations are complete

	DROP TABLE

	IF EXISTS [dbo].[sales_staging];
		IF @transaction_started = 1
			COMMIT TRANSACTION;

END TRY

BEGIN CATCH
	IF @transaction_started = 1
		AND XACT_STATE() <> 0
		ROLLBACK TRANSACTION;

	THROW;

END CATCH

GO
