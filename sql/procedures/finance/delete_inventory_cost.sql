USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [finance].[delete_inventory_cost]
	 @dataset_id INT
	,@deleted_by NVARCHAR(256)
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     15/10/2026
=================================================================================================================================================
Permanently deletes an inventory cost dataset (user decision, 15 October 2026): the finance.inventory_cost_headers header and
its finance.inventory_cost_lines (ON DELETE CASCADE), in one transaction with a db_log record of what was deleted and by
whom. Called by the Shiner Reports portal (Inventory Datasets app, which has its own permission for deleting); the
portal passes the signed-in person's name.

A starting, complete or failed dataset can be deleted; one that is loading (being built by the job) is refused. Its
check stays (other datasets may use it). Returns one row: outcome (ok or refused) and message.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	SET @deleted_by = LTRIM(RTRIM(ISNULL(@deleted_by, N'')));

	IF @deleted_by = N''
		THROW 50171, 'The @deleted_by parameter cannot be blank.', 1;

	IF @@TRANCOUNT > 0
		THROW 50172, 'delete_inventory_cost cannot be called inside a transaction.', 1;

	DECLARE @description NVARCHAR(100);
	DECLARE @as_of_date DATE;
	DECLARE @status NVARCHAR(20);
	DECLARE @line_count INT;
	DECLARE @total_gbp DECIMAL(38, 20);
	DECLARE @log_message NVARCHAR(MAX);
	DECLARE @started_at DATETIME2(7) = SYSDATETIME();
	DECLARE @duration_seconds DECIMAL(38, 20);

	BEGIN TRANSACTION;

	SELECT @description = ic.[description]
		,@as_of_date = ic.[as_of_date]
		,@status = ic.[status]
		,@line_count = ic.[line_count]
		,@total_gbp = ic.[total_gbp]

	FROM [finance].[inventory_cost_headers] AS ic WITH (UPDLOCK, HOLDLOCK)

	WHERE ic.[dataset_id] = @dataset_id;

	IF @status IS NULL
		OR @status = N'loading'
	BEGIN
		ROLLBACK TRANSACTION;

		SELECT N'refused' AS [outcome]
			,CASE
				WHEN @status IS NULL
					THEN N'The dataset could not be found. It may already have been deleted.'
				ELSE N'The dataset is being built. Wait for it to finish, then delete it.'
				END AS [message];

		RETURN;

	END;

	DELETE

	FROM [finance].[inventory_cost_headers]

	WHERE [dataset_id] = @dataset_id;

	SET @duration_seconds = CAST(DATEDIFF_BIG(MICROSECOND, @started_at, SYSDATETIME()) / 1000000.0 AS DECIMAL(38, 20));

	SET @log_message = CONCAT(N'Inventory cost dataset ', @dataset_id, N' "', @description, N'" (as of ', CONVERT(NVARCHAR(10), @as_of_date, 23), N', ', @status
			, CASE
				WHEN @line_count IS NOT NULL
					THEN CONCAT(N', ', @line_count, N' lines, GBP ', CAST(@total_gbp AS DECIMAL(38, 2)))
				ELSE N''
				END, N') permanently deleted by ', @deleted_by, N' in Shiner Reports.');

	EXEC [dbo].[write_db_log]
		 @level = N'INFO'
		,@table = N'inventory_cost'
		,@rows = @line_count
		,@action = N'delete inventory cost dataset'
		,@message = @log_message
		,@duration_seconds = @duration_seconds;

	COMMIT TRANSACTION;

	SELECT N'ok' AS [outcome]
		,CONCAT(N'Deleted "', @description, N'".') AS [message];
END;

GO
