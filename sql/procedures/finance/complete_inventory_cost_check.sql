USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [finance].[complete_inventory_cost_check]
	 @check_id INT
	,@unposted_entries INT
	,@uninvoiced_lines INT
	,@unadjusted_entries INT
AS
-- The trusted worker passes the lengths of the warning lists it just inserted, in this
-- same transaction. No separate warning-count queries in NAV or recounts here.
-- Only unposted actual costs block creation; receipts and unadjusted entries remain warnings.

BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	IF @unposted_entries IS NULL
		OR @unposted_entries < 0
		THROW 50141, 'The @unposted_entries parameter must be 0 or more.', 1;

	IF @uninvoiced_lines IS NULL OR @uninvoiced_lines < 0
        OR @unadjusted_entries IS NULL OR @unadjusted_entries < 0
        THROW 50143, 'Warning counts must be 0 or more.', 1;

	UPDATE ck

	SET [status] = N'complete'
		,[completed_at] = SYSDATETIME()
		,[uninvoiced_lines] = @uninvoiced_lines
		,[unadjusted_entries] = @unadjusted_entries
		,[unposted_entries] = @unposted_entries
		,[message] = NULL

	FROM [finance].[inventory_cost_checks] AS ck

	WHERE ck.[check_id] = @check_id
		AND ck.[status] = N'running';

	IF @@ROWCOUNT = 0
		THROW 50142, 'The inventory cost check is not running, so it cannot be completed.', 1;
END;

GO
