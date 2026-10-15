USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [finance].[claim_inventory_cost_request]
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     15/10/2026
=================================================================================================================================================
Called by the inventory cost job (scripts/run_inventory_cost.py) to take the next queued request: the oldest check
(finance.inventory_cost_checks, 'requested' -> 'running') or dataset (finance.inventory_cost, 'requested' -> 'loading'),
in the order they were asked for. Returns one row (request_kind check or dataset, request_id, as_of_date), or no
row when nothing is waiting.

A request still running or loading after 3 hours was interrupted (the job stopped); it is marked failed first, so
the person can run it again and a stuck dataset can be deleted.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	DECLARE @stale DATETIME2(0) = DATEADD(HOUR, - 3, SYSDATETIME());
	DECLARE @interrupted NVARCHAR(200) = N'Interrupted: the job stopped before it finished. Run it again.';
	DECLARE @kind NVARCHAR(10);
	DECLARE @id INT;
	DECLARE @as_of_date DATE;
	DECLARE @transaction_started BIT = 0;

	IF @@TRANCOUNT = 0
	BEGIN
		BEGIN TRANSACTION;

		SET @transaction_started = 1;

	END;

	UPDATE [finance].[inventory_cost_checks]

	SET [status] = N'failed'
		,[completed_at] = SYSDATETIME()
		,[message] = @interrupted

	WHERE [status] = N'running'
		AND [started_at] < @stale;

	UPDATE [finance].[inventory_cost]

	SET [status] = N'failed'
		,[completed_at] = SYSDATETIME()
		,[message] = @interrupted

	WHERE [status] = N'loading'
		AND [started_at] < @stale;

	SELECT TOP (1) @kind = queued.[request_kind]
		,@id = queued.[request_id]
		,@as_of_date = queued.[as_of_date]

	FROM (
		SELECT N'check' AS [request_kind]
			,ck.[check_id] AS [request_id]
			,ck.[as_of_date]
			,ck.[requested_at] AS [queued_at]

		FROM [finance].[inventory_cost_checks] AS ck WITH (UPDLOCK, READPAST)

		WHERE ck.[status] = N'requested'


		UNION ALL

		SELECT N'dataset' AS [request_kind]
			,ic.[dataset_id] AS [request_id]
			,ic.[as_of_date]
			,ic.[created_at] AS [queued_at]

		FROM [finance].[inventory_cost] AS ic WITH (UPDLOCK, READPAST)

		WHERE ic.[status] = N'requested'
		) AS queued

	ORDER BY queued.[queued_at]
		,queued.[request_kind]
		,queued.[request_id];

	IF @kind = N'check'
		UPDATE [finance].[inventory_cost_checks]

		SET [status] = N'running'
			,[started_at] = SYSDATETIME()

		WHERE [check_id] = @id;

	IF @kind = N'dataset'
		UPDATE [finance].[inventory_cost]

		SET [status] = N'loading'
			,[started_at] = SYSDATETIME()

		WHERE [dataset_id] = @id;

	IF @transaction_started = 1
		COMMIT TRANSACTION;

	SELECT @kind AS [request_kind]
		,@id AS [request_id]
		,@as_of_date AS [as_of_date]

	WHERE @kind IS NOT NULL;
END;

GO
