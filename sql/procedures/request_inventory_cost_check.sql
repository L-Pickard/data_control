USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [finance].[request_inventory_cost_check]
	 @as_of_date DATE
	,@requested_by_id NVARCHAR(184)
	,@requested_by NVARCHAR(256)
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     15/10/2026
=================================================================================================================================================
Queues an inventory cost check for an as-of date. Called by the Shiner Reports portal (Inventory Datasets app); the
portal passes the signed-in person's id (Windows SID) and name, never anything typed by them.

The check itself is run by the inventory cost job (scripts/run_inventory_cost.py, a SQL Agent job every minute),
which claims the row (claim_inventory_cost_request), reads NAV and completes it (complete_inventory_cost_check). The
portal follows finance.inventory_cost_checks for the result.

Refuses an as-of date in the future, and a second check for a date that already has one queued or running.
Returns one row: outcome (ok or refused), message and check_id.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	SET @requested_by_id = LTRIM(RTRIM(ISNULL(@requested_by_id, N'')));
	SET @requested_by = LTRIM(RTRIM(ISNULL(@requested_by, N'')));

	IF @requested_by_id = N''
		OR @requested_by = N''
		THROW 50121, 'The @requested_by_id and @requested_by parameters cannot be blank.', 1;

	DECLARE @check_id INT;

	IF @as_of_date IS NULL
		OR @as_of_date > CAST(SYSDATETIME() AS DATE)
	BEGIN
		SELECT N'refused' AS [outcome]
			,N'Choose an as-of date that is today or earlier.' AS [message]
			,CAST(NULL AS INT) AS [check_id];

		RETURN;

	END;

	SELECT TOP (1) @check_id = ck.[check_id]

	FROM [finance].[inventory_cost_checks] AS ck

	WHERE ck.[as_of_date] = @as_of_date
		AND ck.[status] IN (N'requested', N'running')

	ORDER BY ck.[check_id];

	IF @check_id IS NOT NULL
	BEGIN
		SELECT N'refused' AS [outcome]
			,N'A check for this date is already waiting or running. Wait for its result.' AS [message]
			,@check_id AS [check_id];

		RETURN;

	END;

	INSERT INTO [finance].[inventory_cost_checks] (
		 [as_of_date]
		,[requested_by_id]
		,[requested_by]
		)
	VALUES (
		 @as_of_date
		,@requested_by_id
		,@requested_by
		);

	SET @check_id = CAST(SCOPE_IDENTITY() AS INT);

	SELECT N'ok' AS [outcome]
		,N'The check has been queued. It usually starts within a minute and takes a few minutes.' AS [message]
		,@check_id AS [check_id];
END;

GO
