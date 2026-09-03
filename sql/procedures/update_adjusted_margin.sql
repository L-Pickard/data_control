USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE
	OR

ALTER PROCEDURE [dbo].[update_adjusted_margin] @start_date DATE = '2025-05-01'
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.1
Date:     06/08/2026
=================================================================================================================================================
Resets and recalculates adjusted margins for matching Example BV and Example Ltd sales invoice rows.
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

		-- Reset only the rows controlled by this calculation. This makes reruns
		-- deterministic and clears adjustments for rows that no longer qualify.

		UPDATE sl
		
		SET sl.[gbp_adjusted_margin]  = sl.[gbp_margin]
			,sl.[eur_adjusted_margin] = sl.[eur_margin]
			,sl.[usd_adjusted_margin] = sl.[usd_margin]
			,sl.[is_adjusted] = 0
		
		FROM [dbo].[sales] AS sl
		
		WHERE sl.[entity] = 'Example BV'
			AND sl.[doc_type] = 'SI'
			AND sl.[posting_date] >= @start_date;;

		WITH [bv_to_adjust]
		AS (
			SELECT bsl.[document_no]
				,bsl.[order_no]
				,bsl.[item_id]
				,COUNT_BIG(*) 		 	AS [row_count]
				,SUM(bsl.[quantity]) 	AS [total_bv_quantity]
			
			FROM [dbo].[sales] AS bsl
			
			WHERE bsl.[entity] = 'Example BV'
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
				,SUM(lsl.[gbp_margin]) AS [ltd_gbp_margin]
				,SUM(lsl.[eur_margin]) AS [ltd_eur_margin]
				,SUM(lsl.[usd_margin]) AS [ltd_usd_margin]
			
			FROM [dbo].[sales] AS lsl
			
			WHERE lsl.[customer_id] = 'CUSTOMER_001'
				AND lsl.[entity] = 'Example Ltd'
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
		
		WHERE sl.[entity] = 'Example BV'
			AND sl.[doc_type] = 'SI'
			AND sl.[posting_date] >= @start_date;

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