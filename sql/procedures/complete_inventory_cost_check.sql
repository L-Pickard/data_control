USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [finance].[complete_inventory_cost_check]
	 @check_id INT
	,@unposted_entries INT
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.0
Date:     15/10/2026
=================================================================================================================================================
Completes a running inventory cost check. Called by the inventory cost job in the same transaction in which it wrote
the check's warning lists (finance.inventory_cost_receipts and finance.inventory_cost_unadjusted), so the counts on the check
are always the number of rows in its lists. @unposted_entries is the number of value entries (any location, on or
before the as-of date) whose actual cost is not posted to the G/L, from NAV; it is the only count that stops a
dataset (is_passed).

Throws if the check is not running (claimed by claim_inventory_cost_request), so a late or repeated call changes
nothing.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	SET XACT_ABORT ON;

	IF @unposted_entries IS NULL
		OR @unposted_entries < 0
		THROW 50141, 'The @unposted_entries parameter must be 0 or more.', 1;

	UPDATE ck

	SET [status] = N'complete'
		,[completed_at] = SYSDATETIME()
		,[uninvoiced_lines] = (
			SELECT COUNT(*)

			FROM [finance].[inventory_cost_receipts] AS rc

			WHERE rc.[check_id] = ck.[check_id]
			)
		,[unadjusted_entries] = (
			SELECT COUNT(*)

			FROM [finance].[inventory_cost_unadjusted] AS ua

			WHERE ua.[check_id] = ck.[check_id]
			)
		,[unposted_entries] = @unposted_entries
		,[message] = NULL

	FROM [finance].[inventory_cost_checks] AS ck

	WHERE ck.[check_id] = @check_id
		AND ck.[status] = N'running';

	IF @@ROWCOUNT = 0
		THROW 50142, 'The inventory cost check is not running, so it cannot be completed.', 1;
END;

GO
