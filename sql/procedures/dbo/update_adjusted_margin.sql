USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE
	OR

ALTER PROCEDURE [dbo].[update_adjusted_margin] @start_date DATE = NULL
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.2
Date:     08/10/2026
=================================================================================================================================================
Resets and recalculates adjusted margins for matching Shiner B.V and Shiner Ltd sales invoice rows.

A Shiner B.V invoice row is adjusted when Shiner Ltd invoiced the same order, item and quantity to Shiner B.V
(customer CU109441). Its adjusted margin is its own margin plus the Ltd leg's sales less cost. Royalty and
rebate are not taken off the Ltd leg: royalty is paid once, on the B.V sale to the customer. This is the rule
the Finance database uses.

@start_date: only B.V rows posted on or after this date are reset and recalculated. NULL recalculates the whole
sales table. update_sales_table passes the start of the rows it has just reloaded, so the lookback follows the
reload window and older rows are left as they are.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	DECLARE @transaction_started BIT = 0;

	BEGIN TRY
		IF @@TRANCOUNT = 0
		BEGIN
			BEGIN TRANSACTION;

			SET @transaction_started = 1;
		
		END;

		-- Both statements below use OPTION (RECOMPILE) so each run is planned for its own start date: a plan made
		-- for a week of rows must not be reused for the whole table, or the other way round.

		IF @start_date IS NULL
			SET @start_date = ISNULL((
						SELECT MIN([posting_date])
						
						FROM [dbo].[sales]
						), CAST(SYSDATETIME() AS DATE));

		-- Reset only the rows controlled by this calculation. This makes reruns
		-- deterministic and clears adjustments for rows that no longer qualify.

		UPDATE sl
		
		SET sl.[gbp_adjusted_margin]  = sl.[gbp_margin]
			,sl.[eur_adjusted_margin] = sl.[eur_margin]
			,sl.[usd_adjusted_margin] = sl.[usd_margin]
			,sl.[is_adjusted] = 0
		
		FROM [dbo].[sales] AS sl
		
		WHERE sl.[entity] = 'Shiner B.V'
			AND sl.[doc_type] = 'SI'
			AND sl.[posting_date] >= @start_date
		
		OPTION (RECOMPILE);

		WITH [bv_to_adjust]
		AS (
			SELECT bsl.[document_no]
				,bsl.[order_no]
				,bsl.[item_id]
				,COUNT_BIG(*) 		 	AS [row_count]
				,SUM(bsl.[quantity]) 	AS [total_bv_quantity]
			
			FROM [dbo].[sales] AS bsl
			
			WHERE bsl.[entity] = 'Shiner B.V'
				AND bsl.[doc_type] = 'SI'
				AND bsl.[posting_date] >= @start_date
				AND bsl.[order_no] <> ''
			
			GROUP BY bsl.[document_no]
				,bsl.[order_no]
				,bsl.[item_id]
			)
			,[ltd_margin]
		AS (
			SELECT lsl.[order_no]
				,lsl.[item_id]
				,SUM(lsl.[quantity]) AS [total_ltd_quantity]
				-- Sales less cost only: no royalty or rebate is taken off the intercompany leg.
				,SUM(ISNULL(lsl.[gbp_sales], 0) - ISNULL(lsl.[gbp_cost], 0)) AS [ltd_gbp_margin]
				,SUM(ISNULL(lsl.[eur_sales], 0) - ISNULL(lsl.[eur_cost], 0)) AS [ltd_eur_margin]
				,SUM(ISNULL(lsl.[usd_sales], 0) - ISNULL(lsl.[usd_cost], 0)) AS [ltd_usd_margin]
			
			FROM [dbo].[sales] AS lsl
			
			WHERE lsl.[customer_id] = 'CU109441'
				AND lsl.[entity] = 'Shiner Ltd'
				AND lsl.[doc_type] = 'SI'
				AND lsl.[order_no] <> ''
			
			GROUP BY lsl.[order_no]
				,lsl.[item_id]
			)
			,[update_data]
		AS (
			SELECT bv.[document_no]
				,bv.[order_no]
				,bv.[item_id]
				,bv.[row_count]
				,bv.[total_bv_quantity]
				,ltd.[ltd_gbp_margin]
				,ltd.[ltd_eur_margin]
				,ltd.[ltd_usd_margin]
			
			FROM [bv_to_adjust] AS bv
			
			INNER JOIN [ltd_margin] AS ltd
				ON bv.[order_no] = ltd.[order_no]
					AND bv.[item_id] = ltd.[item_id]
					AND bv.[total_bv_quantity] = ltd.[total_ltd_quantity]
			)
		
		UPDATE sl
		
		SET sl.[gbp_adjusted_margin] = sl.[gbp_margin] + CASE 
				WHEN ud.[total_bv_quantity] = 0
					THEN ud.[ltd_gbp_margin] / ud.[row_count]
				ELSE ud.[ltd_gbp_margin] * sl.[quantity] / ud.[total_bv_quantity]
				END
			,sl.[eur_adjusted_margin] = sl.[eur_margin] + CASE 
				WHEN ud.[total_bv_quantity] = 0
					THEN ud.[ltd_eur_margin] / ud.[row_count]
				ELSE ud.[ltd_eur_margin] * sl.[quantity] / ud.[total_bv_quantity]
				END
			,sl.[usd_adjusted_margin] = sl.[usd_margin] + CASE 
				WHEN ud.[total_bv_quantity] = 0
					THEN ud.[ltd_usd_margin] / ud.[row_count]
				ELSE ud.[ltd_usd_margin] * sl.[quantity] / ud.[total_bv_quantity]
				END
			,sl.[is_adjusted] = CASE 
				WHEN ud.[ltd_gbp_margin] <> 0
					OR ud.[ltd_eur_margin] <> 0
					OR ud.[ltd_usd_margin] <> 0
					THEN 1
				ELSE 0
				END
		
		FROM [dbo].[sales] AS sl
		
		INNER JOIN [update_data] AS ud
			ON sl.[document_no] = ud.[document_no]
				AND sl.[order_no] = ud.[order_no]
				AND sl.[item_id] = ud.[item_id]
		
		WHERE sl.[entity] = 'Shiner B.V'
			AND sl.[doc_type] = 'SI'
			AND sl.[posting_date] >= @start_date
		
		OPTION (RECOMPILE);

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