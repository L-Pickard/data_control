USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [finance].[build_inventory_cost]
	 @dataset_id INT
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     15/10/2026
=================================================================================================================================================
Builds an inventory cost dataset from finance.inventory_cost_staging, which the inventory cost job has just filled from
NAV for the dataset's as-of date (cost = actual + expected cost, in each company's own currency). In one transaction:

  1. checks the staging rows: all for this dataset, at least one, no blank keys or missing quantity or cost, positive
     quantities, only the three companies, no repeated company and item, every item in dbo.items;
  2. inserts them into finance.inventory_cost_lines with the location, the company's currency and the cost converted at
     the rates stored on the dataset header into GBP, EUR and USD;
  3. completes the header (status, completed_at, line_count, total_gbp/eur/usd);
  4. drops finance.inventory_cost_staging (like dbo.sales_staging after update_sales_table).

The dataset must be 'loading' (claimed by claim_inventory_cost_request). On any error nothing is written and the
staging table is kept for diagnosis; the job then marks the dataset failed (fail_inventory_cost_request).
Conversion: DECIMAL(38, 20) x DECIMAL(38, 20) keeps 6 decimal places, more than enough for an amount of money.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	DECLARE @transaction_started BIT = 0;
	DECLARE @error NVARCHAR(2048);
	DECLARE @rows INT;
	DECLARE @other_datasets INT;
	DECLARE @missing_values INT;
	DECLARE @non_positive INT;
	DECLARE @unknown_companies INT;
	DECLARE @repeated INT;
	DECLARE @missing_items INT;

	IF NOT EXISTS (
			SELECT 1

			FROM [finance].[inventory_cost]

			WHERE [dataset_id] = @dataset_id
				AND [status] = N'loading'
			)
		THROW 50161, 'The inventory cost dataset is not loading, so it cannot be built.', 1;

	IF OBJECT_ID(N'[finance].[inventory_cost_staging]', N'U') IS NULL
		THROW 50162, 'finance.inventory_cost_staging does not exist: the job has not loaded the dataset.', 1;

	SELECT @rows = COUNT(*)
		,@other_datasets = SUM(CASE
				WHEN st.[dataset_id] IS NULL
					OR st.[dataset_id] <> @dataset_id
					THEN 1
				ELSE 0
				END)
		,@missing_values = SUM(CASE
				WHEN NULLIF(LTRIM(RTRIM(st.[entity])), N'') IS NULL
					OR NULLIF(LTRIM(RTRIM(st.[item_id])), N'') IS NULL
					OR st.[quantity] IS NULL
					OR st.[cost] IS NULL
					THEN 1
				ELSE 0
				END)
		,@non_positive = SUM(CASE
				WHEN st.[quantity] <= 0
					THEN 1
				ELSE 0
				END)
		,@unknown_companies = SUM(CASE
				WHEN st.[entity] IN (N'Shiner Ltd', N'Shiner B.V', N'Shiner LLC')
					THEN 0
				ELSE 1
				END)
		,@missing_items = SUM(CASE
				WHEN it.[item_id] IS NULL
					THEN 1
				ELSE 0
				END)

	FROM [finance].[inventory_cost_staging] AS st

	LEFT JOIN [dbo].[items] AS it
		ON it.[item_id] = st.[item_id];

	SELECT @repeated = COUNT(*)

	FROM (
		SELECT st.[entity]
			,st.[item_id]

		FROM [finance].[inventory_cost_staging] AS st

		GROUP BY st.[entity]
			,st.[item_id]

		HAVING COUNT(*) > 1
		) AS duplicates;

	SET @error = CASE
			WHEN @rows = 0
				THEN N'The staging table is empty: NAV returned no stock.'
			WHEN @other_datasets > 0
				THEN CONCAT(@other_datasets, N' staging rows belong to another dataset.')
			WHEN @missing_values > 0
				THEN CONCAT(@missing_values, N' staging rows have no company, item, quantity or cost.')
			WHEN @non_positive > 0
				THEN CONCAT(@non_positive, N' staging rows have a quantity of 0 or less.')
			WHEN @unknown_companies > 0
				THEN CONCAT(@unknown_companies, N' staging rows are for a company other than Shiner Ltd, Shiner B.V or Shiner LLC.')
			WHEN @repeated > 0
				THEN CONCAT(@repeated, N' company and item pairs appear more than once.')
			WHEN @missing_items > 0
				THEN CONCAT(@missing_items, N' staging rows are for items not yet in dbo.items. Run the items update, then create the dataset again.')
			END;

	IF @error IS NOT NULL
		THROW 50163, @error, 1;

	BEGIN TRY
		IF @@TRANCOUNT = 0
		BEGIN
			BEGIN TRANSACTION;

			SET @transaction_started = 1;

		END;

		INSERT INTO [finance].[inventory_cost_lines] (
			 [dataset_id]
			,[entity]
			,[item_id]
			,[location_code]
			,[currency_code]
			,[quantity]
			,[cost]
			,[expected_cost]
			,[cost_gbp]
			,[cost_eur]
			,[cost_usd]
			,[first_receipt]
			,[last_receipt]
			)
		SELECT @dataset_id
			,st.[entity]
			,st.[item_id]
			,CASE st.[entity]
				WHEN N'Shiner Ltd'
					THEN N'BRISTOL'
				WHEN N'Shiner B.V'
					THEN N'3PL'
				WHEN N'Shiner LLC'
					THEN N'POMONA'
				END
			,en.[currency_code]
			,st.[quantity]
			,st.[cost]
			,ISNULL(st.[expected_cost], 0)
			,CAST(st.[cost] * CASE en.[currency_code]
					WHEN 'GBP'
						THEN 1
					WHEN 'EUR'
						THEN hd.[eur_gbp]
					WHEN 'USD'
						THEN hd.[usd_gbp]
					END AS DECIMAL(38, 20))
			,CAST(st.[cost] * CASE en.[currency_code]
					WHEN 'GBP'
						THEN hd.[gbp_eur]
					WHEN 'EUR'
						THEN 1
					WHEN 'USD'
						THEN hd.[usd_eur]
					END AS DECIMAL(38, 20))
			,CAST(st.[cost] * CASE en.[currency_code]
					WHEN 'GBP'
						THEN hd.[gbp_usd]
					WHEN 'EUR'
						THEN hd.[eur_usd]
					WHEN 'USD'
						THEN 1
					END AS DECIMAL(38, 20))
			,st.[first_receipt]
			,st.[last_receipt]

		FROM [finance].[inventory_cost_staging] AS st

		INNER JOIN [dbo].[entities] AS en
			ON en.[entity] = st.[entity]

		CROSS JOIN [finance].[inventory_cost] AS hd

		WHERE hd.[dataset_id] = @dataset_id;

		SET @rows = @@ROWCOUNT;

		UPDATE hd

		SET [status] = N'complete'
			,[completed_at] = SYSDATETIME()
			,[line_count] = @rows
			,[total_gbp] = totals.[total_gbp]
			,[total_eur] = totals.[total_eur]
			,[total_usd] = totals.[total_usd]
			,[message] = NULL

		FROM [finance].[inventory_cost] AS hd

		CROSS APPLY (
			SELECT ISNULL(SUM(ln.[cost_gbp]), 0) AS [total_gbp]
				,ISNULL(SUM(ln.[cost_eur]), 0) AS [total_eur]
				,ISNULL(SUM(ln.[cost_usd]), 0) AS [total_usd]

			FROM [finance].[inventory_cost_lines] AS ln

			WHERE ln.[dataset_id] = hd.[dataset_id]
			) AS totals

		WHERE hd.[dataset_id] = @dataset_id;

		-- Below we drop the inventory cost staging table after all operations are complete

		DROP TABLE

		IF EXISTS [finance].[inventory_cost_staging];
			IF @transaction_started = 1
				COMMIT TRANSACTION;

	END TRY

	BEGIN CATCH
		IF @transaction_started = 1
			AND XACT_STATE() <> 0
			ROLLBACK TRANSACTION;

		THROW;

	END CATCH;
END;

GO
