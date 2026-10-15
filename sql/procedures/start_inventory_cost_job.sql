USE [data_control]

GO

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO

CREATE OR ALTER PROCEDURE [finance].[start_inventory_cost_job]
AS
/*===============================================================================================================================================
Project:  data_control Data Warehouse
Language: TSQL
Author:   Leo Pickard
Version:  1.2
Date:     15/10/2026
=================================================================================================================================================
Starts the SQL Agent job inventory_cost_requests now, so a check or dataset queued from Shiner Reports starts within
seconds (user decision, 15 October 2026: no constant polling). Called by request_inventory_cost_check and
request_inventory_cost straight after they queue a request; not granted to anyone.

It calls msdb.dbo.start_inventory_cost_requests_job (created by sql/database/inventory_cost_job_starter.sql, run by a
sysadmin), which starts that one job by its fixed name WITH EXECUTE AS OWNER; the portal's login has EXECUTE on that
procedure and nothing else in msdb. (A certificate-signed version was tried first: a signature does not reach into
msdb's own sp_start_job, which then could not see the job.)

Returns 0 when the job was started, otherwise the error number without failing the caller: 22022 means the job is
already running (it claims the new request before it stops); anything else (not signed yet, job missing, no rights)
leaves the request for the job's hourly run and is written to db_log as a WARNING (table inventory_cost, action
'start inventory cost job') with SQL Server's message, so a failed start can be diagnosed.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	BEGIN TRY
		EXEC [msdb].[dbo].[start_inventory_cost_requests_job];

		RETURN 0;

	END TRY

	BEGIN CATCH
		DECLARE @error INT = ERROR_NUMBER();
		DECLARE @message NVARCHAR(MAX) = CONCAT(N'The inventory_cost_requests job could not be started (error ', @error, N'): ', ERROR_MESSAGE(),
				N' The request stays queued for the job''s scheduled run. Caller: ', ORIGINAL_LOGIN(), N'.');

		IF @error <> 22022
			EXEC [dbo].[write_db_log]
				 @level = N'WARNING'
				,@table = N'inventory_cost'
				,@action = N'start inventory cost job'
				,@message = @message;

		RETURN @error;

	END CATCH;
END;

GO
