USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [finance].[delete_inventory_cost_check]
	 @check_id INT
	,@deleted_by NVARCHAR(256)
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     15/10/2026
=================================================================================================================================================
Permanently deletes an inventory cost check (finance.inventory_cost_checks) and its warning lists
(finance.inventory_cost_receipts and finance.inventory_cost_unadjusted, ON DELETE CASCADE), with a db_log record of what
was deleted and by whom (user request, 15 October 2026). Called by the Shiner Reports portal (Inventory Datasets app,
with its delete permission); the portal passes the signed-in person's name.

Refused for a check a dataset was made from (the dataset keeps its check, so its warnings can always be seen: delete
the dataset first) and for a check that is waiting or running. Returns one row: outcome (ok or refused) and message.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	SET @deleted_by = LTRIM(RTRIM(ISNULL(@deleted_by, N'')));

	IF @deleted_by = N''
		THROW 50201, 'The @deleted_by parameter cannot be blank.', 1;

	IF @@TRANCOUNT > 0
		THROW 50202, 'delete_inventory_cost_check cannot be called inside a transaction.', 1;

	DECLARE @as_of_date DATE;
	DECLARE @status NVARCHAR(20);
	DECLARE @requested_by NVARCHAR(256);
	DECLARE @datasets INT;
	DECLARE @lines INT;
	DECLARE @log_message NVARCHAR(MAX);

	BEGIN TRANSACTION;

	SELECT @as_of_date = ck.[as_of_date]
		,@status = ck.[status]
		,@requested_by = ck.[requested_by]
		,@lines = ISNULL(ck.[uninvoiced_lines], 0) + ISNULL(ck.[unadjusted_entries], 0)

	FROM [finance].[inventory_cost_checks] AS ck WITH (UPDLOCK, HOLDLOCK)

	WHERE ck.[check_id] = @check_id;

	SELECT @datasets = COUNT(*)

	FROM [finance].[inventory_cost_headers] AS ic WITH (UPDLOCK, HOLDLOCK)

	WHERE ic.[check_id] = @check_id;

	IF @status IS NULL
		OR @status IN (N'requested', N'running')
		OR @datasets > 0
	BEGIN
		ROLLBACK TRANSACTION;

		SELECT N'refused' AS [outcome]
			,CASE
				WHEN @status IS NULL
					THEN N'The check could not be found. It may already have been deleted.'
				WHEN @datasets > 0
					THEN N'A dataset was made from this check, so it is kept with the dataset. Delete the dataset first.'
				ELSE N'The check is waiting or running. Wait for it to finish, then delete it.'
				END AS [message];

		RETURN;

	END;

	DELETE

	FROM [finance].[inventory_cost_checks]

	WHERE [check_id] = @check_id;

	SET @log_message = CONCAT(N'Inventory cost check ', @check_id, N' (as of ', CONVERT(NVARCHAR(10), @as_of_date, 23), N', ', @status, N', run by ', @requested_by,
			N', ', @lines, N' warning lines) permanently deleted by ', @deleted_by, N' in Shiner Reports.');

	EXEC [dbo].[write_db_log]
		 @level = N'INFO'
		,@table = N'inventory_cost'
		,@rows = @lines
		,@action = N'delete inventory cost check'
		,@message = @log_message;

	COMMIT TRANSACTION;

	SELECT N'ok' AS [outcome]
		,CONCAT(N'Deleted the check for ', CONVERT(NVARCHAR(10), @as_of_date, 103), N' run by ', @requested_by, N'.') AS [message];
END;

GO
