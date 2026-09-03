USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [dbo].[delete_sales_from_date]
	@from_date DATE
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     12/08/2026
=================================================================================================================================================
Deletes sales rows whose posting date is greater than or equal to the caller-supplied date, then resets the sales increment date for every entity
to the preceding day. The sales extracts use a strict greater-than comparison, so this ensures the cutoff date is reloaded. Returns affected-row
counts for job logging.
================================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF @from_date IS NULL
		THROW 50001, 'The @from_date parameter cannot be NULL.', 1;
	IF @from_date = DATEFROMPARTS(1, 1, 1)
		THROW 50002, 'The @from_date parameter must be later than 0001-01-01.', 1;

	DECLARE @transaction_started BIT = 0;
	DECLARE @sales_rows_deleted INT;
	DECLARE @entities_updated INT;
	DECLARE @started_at DATETIME2(7) = SYSDATETIME();
	DECLARE @duration_seconds DECIMAL(38, 20);
	DECLARE @log_message NVARCHAR(MAX);

	BEGIN TRY
		IF @@TRANCOUNT = 0
		BEGIN
			BEGIN TRANSACTION;
			SET @transaction_started = 1;
		END;

		DELETE FROM [dbo].[sales]
		WHERE [posting_date] >= @from_date;

		SET @sales_rows_deleted = @@ROWCOUNT;

		UPDATE [dbo].[entities]
		SET [sales_increment] = DATEADD(DAY, -1, @from_date);

		SET @entities_updated = @@ROWCOUNT;
		SET @duration_seconds = CAST(DATEDIFF_BIG(MICROSECOND, @started_at, SYSDATETIME()) / 1000000.0 AS DECIMAL(38, 20));
		SET @log_message = CONCAT(
			 N'Successfully deleted ', @sales_rows_deleted, N' sales rows from ', CONVERT(NVARCHAR(10), @from_date, 23),
			 N' and reset ', @entities_updated, N' entity sales increment dates to ',
			 CONVERT(NVARCHAR(10), DATEADD(DAY, -1, @from_date), 23), N'.'
			);

		EXEC [dbo].[write_db_log]
			 @level = N'SUCCESS'
			,@table = N'sales'
			,@rows = @sales_rows_deleted
			,@action = N'delete sales data and reset sales increment dates'
			,@message = @log_message
			,@duration_seconds = @duration_seconds;

		IF @transaction_started = 1
			COMMIT TRANSACTION;

		SELECT
			 @sales_rows_deleted AS [sales_rows_deleted]
			,@entities_updated AS [entities_updated];
	END TRY

	BEGIN CATCH
		DECLARE @error_message NVARCHAR(4000) = ERROR_MESSAGE();

		IF @transaction_started = 1 AND XACT_STATE() <> 0
			ROLLBACK TRANSACTION;

		BEGIN TRY
			SET @duration_seconds = CAST(DATEDIFF_BIG(MICROSECOND, @started_at, SYSDATETIME()) / 1000000.0 AS DECIMAL(38, 20));
			SET @log_message = CONCAT(N'Failed to delete sales data and reset sales increment dates. Error: ', @error_message);

			EXEC [dbo].[write_db_log]
				 @level = N'FAILURE'
				,@table = N'sales'
				,@rows = NULL
				,@action = N'delete sales data and reset sales increment dates'
				,@message = @log_message
				,@duration_seconds = @duration_seconds;
		END TRY
		BEGIN CATCH
			-- Preserve and rethrow the original procedure error if logging also fails.
		END CATCH;

		THROW;
	END CATCH;
END;

GO
