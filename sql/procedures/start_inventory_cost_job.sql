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
Version:  1.0
Date:     15/10/2026
=================================================================================================================================================
Starts the SQL Agent job inventory_cost_requests now, so a check or dataset queued from Shiner Reports starts within
seconds (user decision, 15 October 2026: no constant polling). Called by request_inventory_cost_check and
request_inventory_cost straight after they queue a request; not granted to anyone.

The portal's login has no rights in msdb. This procedure is SIGNED with the certificate inventory_cost_job_starter
(sql/database/inventory_cost_job_signing.sql, run by a sysadmin), whose user in msdb is in SQLAgentOperatorRole, so
it can start this one job and nothing else. ALTERing this procedure removes the signature: run the signing script
again after any change.

Returns 0 when the job was started, otherwise the error number without failing the caller: 22022 means the job is
already running (it claims the new request before it stops); anything else (not signed yet, job missing) leaves the
request queued for the job's hourly run.
===============================================================================================================================================*/
BEGIN
	SET NOCOUNT ON;

	BEGIN TRY
		EXEC [msdb].[dbo].[sp_start_job] @job_name = N'inventory_cost_requests';

		RETURN 0;

	END TRY

	BEGIN CATCH
		RETURN ERROR_NUMBER();

	END CATCH;
END;

GO
