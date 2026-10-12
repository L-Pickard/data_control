USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [dbo].[reset_sales_exclusion_flags]
	 @start_date DATE = NULL
	,@apply BIT = 1
	,@return_row BIT = 1
	,@rows_changed INT = NULL OUTPUT
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     12/10/2026
=================================================================================================================================================
Resets the stored exclusion and intercompany flags of dbo.sales to what dbo.exclusions says now, using the same
functions as update_sales_table (fnc_is_customer_exclusion, fnc_is_customer_intercompany).

@start_date: only sales posted on or after this date; NULL is the whole table.
@apply = 0 only counts the rows whose flags would change. Only rows that differ are written.
Returns one row (rows_changed) unless @return_row = 0. Normally called by run_margin_rule_recalculation.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	DECLARE @transaction_started BIT = 0;

	-- The rows that differ are found first, without holding write locks, and then updated by their key.

	SELECT sl.[posting_date]
		,sl.[location_code]
		,sl.[customer_id]
		,sl.[document_no]
		,sl.[doc_type]
		,sl.[entity]
		,sl.[item_id]
		,sl.[salesperson_id]
		,rl.[exclusion]
		,rl.[intercompany]

	INTO #flag_changes

	FROM [dbo].[sales] AS sl

	CROSS APPLY (
		SELECT [dbo].[fnc_is_customer_exclusion](sl.[entity], sl.[customer_id], CAST(LEFT(sl.[item_id], 3) AS NVARCHAR(20))) AS [exclusion]
			,[dbo].[fnc_is_customer_intercompany](sl.[entity], sl.[customer_id]) AS [intercompany]
		) AS rl

	WHERE (
			@start_date IS NULL
			OR sl.[posting_date] >= @start_date
			)
		AND (
			sl.[exclusion] <> rl.[exclusion]
			OR sl.[intercompany] <> rl.[intercompany]
			)

	OPTION (RECOMPILE);

	SET @rows_changed = @@ROWCOUNT;

	IF @apply = 1
		AND @rows_changed > 0
	BEGIN
		BEGIN TRY
			IF @@TRANCOUNT = 0
			BEGIN
				BEGIN TRANSACTION;

				SET @transaction_started = 1;

			END;

			UPDATE sl

			SET sl.[exclusion] = fc.[exclusion]
				,sl.[intercompany] = fc.[intercompany]

			FROM [dbo].[sales] AS sl

			INNER JOIN #flag_changes AS fc
				ON sl.[posting_date] = fc.[posting_date]
					AND sl.[location_code] = fc.[location_code]
					AND sl.[customer_id] = fc.[customer_id]
					AND sl.[document_no] = fc.[document_no]
					AND sl.[doc_type] = fc.[doc_type]
					AND sl.[entity] = fc.[entity]
					AND sl.[item_id] = fc.[item_id]
					AND sl.[salesperson_id] = fc.[salesperson_id];

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

	DROP TABLE #flag_changes;

	IF @return_row = 1
		SELECT @rows_changed AS [rows_changed];

END;

GO
