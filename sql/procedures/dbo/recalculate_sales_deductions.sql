USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [dbo].[recalculate_sales_deductions]
	 @start_date DATE = NULL
	,@apply BIT = 1
	,@return_row BIT = 1
	,@rows_changed INT = NULL OUTPUT
	,@gbp_margin_change DECIMAL(38, 6) = NULL OUTPUT
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     12/10/2026
=================================================================================================================================================
Recalculates the royalty, customer rebate and margin stored on dbo.sales from the rules as they are now, using the same
functions as update_sales_table (fnc_calculate_item_royalty, fnc_calculate_customer_rebate).

update_sales_table works the royalty and rebate out in the sale's own currency and then converts them. Both are a rate
times the sales value, so here the functions are given the GBP, EUR and USD sales values directly: the result is the
same, and the exchange rate of the day is not looked up again. Checked against every row on 12 October 2026: nothing
differed.

Like the load, the royalty also follows dbo.items.royalty, the intercompany customers in dbo.exclusions and the
customer list inside fnc_calculate_item_royalty as they are NOW, so a change to any of those reaches older rows too.

margin = sales - (cost + royalty + rebate). The adjusted margin moves by the same amount as the margin, so a row
adjusted by update_adjusted_margin keeps its Shiner Ltd part; run update_adjusted_margin afterwards if that part
should be worked out again as well.

@start_date: only sales posted on or after this date; NULL is the whole table.
@apply = 0 only counts. Only rows where a royalty or rebate differs by more than 0.00001 are written
(rounding in the two ways of converting stays far below that; a real change of rate is far above it).
Returns one row (rows_changed, gbp_margin_change) unless @return_row = 0. Normally called by run_margin_rule_recalculation.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	DECLARE @transaction_started BIT = 0;
	DECLARE @tolerance DECIMAL(38, 20) = 0.00001;

	-- The rows that differ are found first, without holding write locks, and then updated by their key.

	SELECT sl.[posting_date]
		,sl.[location_code]
		,sl.[customer_id]
		,sl.[document_no]
		,sl.[doc_type]
		,sl.[entity]
		,sl.[item_id]
		,sl.[salesperson_id]
		,nw.[gbp_royalty]
		,nw.[gbp_rebate]
		,nw.[eur_royalty]
		,nw.[eur_rebate]
		,nw.[usd_royalty]
		,nw.[usd_rebate]
		,(sl.[gbp_sales] - (sl.[gbp_cost] + nw.[gbp_royalty] + nw.[gbp_rebate])) - sl.[gbp_margin] AS [gbp_margin_change]

	INTO #deduction_changes

	FROM [dbo].[sales] AS sl

	CROSS APPLY (
		SELECT [dbo].[fnc_calculate_item_royalty](sl.[item_id], sl.[customer_id], sl.[entity], sl.[gbp_sales]) AS [gbp_royalty]
			,[dbo].[fnc_calculate_customer_rebate](sl.[item_id], sl.[customer_id], sl.[entity], sl.[gbp_sales]) AS [gbp_rebate]
			,[dbo].[fnc_calculate_item_royalty](sl.[item_id], sl.[customer_id], sl.[entity], sl.[eur_sales]) AS [eur_royalty]
			,[dbo].[fnc_calculate_customer_rebate](sl.[item_id], sl.[customer_id], sl.[entity], sl.[eur_sales]) AS [eur_rebate]
			,[dbo].[fnc_calculate_item_royalty](sl.[item_id], sl.[customer_id], sl.[entity], sl.[usd_sales]) AS [usd_royalty]
			,[dbo].[fnc_calculate_customer_rebate](sl.[item_id], sl.[customer_id], sl.[entity], sl.[usd_sales]) AS [usd_rebate]
		) AS nw

	WHERE (
			@start_date IS NULL
			OR sl.[posting_date] >= @start_date
			)
		AND (
			ABS(sl.[gbp_royalty] - nw.[gbp_royalty]) > @tolerance
			OR ABS(sl.[gbp_rebate] - nw.[gbp_rebate]) > @tolerance
			OR ABS(sl.[eur_royalty] - nw.[eur_royalty]) > @tolerance
			OR ABS(sl.[eur_rebate] - nw.[eur_rebate]) > @tolerance
			OR ABS(sl.[usd_royalty] - nw.[usd_royalty]) > @tolerance
			OR ABS(sl.[usd_rebate] - nw.[usd_rebate]) > @tolerance
			)

	OPTION (RECOMPILE);

	SET @rows_changed = @@ROWCOUNT;

	SELECT @gbp_margin_change = CAST(ISNULL(SUM(dc.[gbp_margin_change]), 0) AS DECIMAL(38, 6))

	FROM #deduction_changes AS dc;

	IF @apply = 1
		AND @rows_changed > 0
	BEGIN
		BEGIN TRY
			IF @@TRANCOUNT = 0
			BEGIN
				BEGIN TRANSACTION;

				SET @transaction_started = 1;

			END;

			-- Every column on the right is the value before this statement, so the adjusted margin moves by exactly
			-- the change in margin. margin_bin is a persisted computed column and follows by itself.

			UPDATE sl

			SET sl.[gbp_royalty] = dc.[gbp_royalty]
				,sl.[gbp_rebate] = dc.[gbp_rebate]
				,sl.[gbp_margin] = sl.[gbp_sales] - (sl.[gbp_cost] + dc.[gbp_royalty] + dc.[gbp_rebate])
				,sl.[gbp_adjusted_margin] = sl.[gbp_adjusted_margin] + (sl.[gbp_sales] - (sl.[gbp_cost] + dc.[gbp_royalty] + dc.[gbp_rebate])) - sl.[gbp_margin]
				,sl.[eur_royalty] = dc.[eur_royalty]
				,sl.[eur_rebate] = dc.[eur_rebate]
				,sl.[eur_margin] = sl.[eur_sales] - (sl.[eur_cost] + dc.[eur_royalty] + dc.[eur_rebate])
				,sl.[eur_adjusted_margin] = sl.[eur_adjusted_margin] + (sl.[eur_sales] - (sl.[eur_cost] + dc.[eur_royalty] + dc.[eur_rebate])) - sl.[eur_margin]
				,sl.[usd_royalty] = dc.[usd_royalty]
				,sl.[usd_rebate] = dc.[usd_rebate]
				,sl.[usd_margin] = sl.[usd_sales] - (sl.[usd_cost] + dc.[usd_royalty] + dc.[usd_rebate])
				,sl.[usd_adjusted_margin] = sl.[usd_adjusted_margin] + (sl.[usd_sales] - (sl.[usd_cost] + dc.[usd_royalty] + dc.[usd_rebate])) - sl.[usd_margin]

			FROM [dbo].[sales] AS sl

			INNER JOIN #deduction_changes AS dc
				ON sl.[posting_date] = dc.[posting_date]
					AND sl.[location_code] = dc.[location_code]
					AND sl.[customer_id] = dc.[customer_id]
					AND sl.[document_no] = dc.[document_no]
					AND sl.[doc_type] = dc.[doc_type]
					AND sl.[entity] = dc.[entity]
					AND sl.[item_id] = dc.[item_id]
					AND sl.[salesperson_id] = dc.[salesperson_id];

			SET @rows_changed = @@ROWCOUNT;

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

	DROP TABLE #deduction_changes;

	IF @return_row = 1
		SELECT @rows_changed AS [rows_changed]
			,@gbp_margin_change AS [gbp_margin_change];

END;

GO
