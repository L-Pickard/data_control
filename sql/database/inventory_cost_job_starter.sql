-- Lets Shiner Reports start the SQL Agent job inventory_cost_requests the moment finance asks for a check or dataset
-- (user decision, 15 October 2026), and nothing else in msdb.
--
--   msdb.dbo.start_inventory_cost_requests_job  starts that one job by its fixed name, takes no parameters, and runs
--                                               WITH EXECUTE AS OWNER, so msdb's own checks inside sp_start_job pass.
--   msdb user [shiner_reports]                  the portal's login, with EXECUTE on that procedure only: no roles, so
--                                               it cannot see, create, change or start any other job.
--
-- data_control.finance.start_inventory_cost_job (called by the request procedures) calls the msdb procedure.
--
-- This replaces the certificate signing tried first (inventory_cost_job_signing.sql, now deleted): a signature does not
-- reach into msdb's own sp_start_job, which then could not see the job (error 14262). This script also removes that
-- setup: the signature, the certificates in data_control, master and msdb, the certificate login and its msdb user.
--
-- Run as a sysadmin on SHINERSQL18. Safe to run again. Then test as the portal would (queues a real check):
--   EXECUTE AS LOGIN = N'shiner_reports';
--   EXEC data_control.finance.request_inventory_cost_check @as_of_date = '2026-10-12', @requested_by_id = N'start-test', @requested_by = N'Start test';
--   REVERT;
-- "The check has started" = it works. Then re-run sql/database/agent_job_inventory_cost.sql (hourly backstop only).
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @certificate SYSNAME = N'inventory_cost_job_starter';

-- 1. Remove the certificate setup, if it is there.
USE [msdb];

IF DATABASE_PRINCIPAL_ID(@certificate) IS NOT NULL
BEGIN
	IF IS_ROLEMEMBER(N'SQLAgentOperatorRole', @certificate) = 1
		EXEC (N'ALTER ROLE [SQLAgentOperatorRole] DROP MEMBER [inventory_cost_job_starter];');

	EXEC (N'DROP USER [inventory_cost_job_starter];');
END;

IF CERT_ID(@certificate) IS NOT NULL
	EXEC (N'DROP CERTIFICATE [inventory_cost_job_starter];');

USE [master];

IF SUSER_ID(@certificate) IS NOT NULL
	EXEC (N'DROP LOGIN [inventory_cost_job_starter];');

IF CERT_ID(@certificate) IS NOT NULL
	EXEC (N'DROP CERTIFICATE [inventory_cost_job_starter];');

USE [data_control];

IF EXISTS (
		SELECT 1

		FROM sys.crypt_properties AS cp

		INNER JOIN sys.certificates AS ce
			ON ce.[thumbprint] = cp.[thumbprint]

		WHERE cp.[major_id] = OBJECT_ID(N'finance.start_inventory_cost_job')
			AND ce.[name] = @certificate
		)
	EXEC (N'DROP SIGNATURE FROM [finance].[start_inventory_cost_job] BY CERTIFICATE [inventory_cost_job_starter];');

IF CERT_ID(@certificate) IS NOT NULL
	EXEC (N'DROP CERTIFICATE [inventory_cost_job_starter];');

-- 2. The procedure in msdb that starts the one job.
USE [msdb];

EXEC (N'CREATE OR ALTER PROCEDURE [dbo].[start_inventory_cost_requests_job]
WITH EXECUTE AS OWNER
AS
-- Starts the SQL Agent job inventory_cost_requests (data_control inventory cost checks and datasets) for Shiner
-- Reports. Fixed job name, no parameters. Created by data_control sql/database/inventory_cost_job_starter.sql.
-- Returns 0 when started; otherwise raises the error (22022 = the job is already running).
BEGIN
	SET NOCOUNT ON;

	EXEC [dbo].[sp_start_job] @job_name = N''inventory_cost_requests'';

	RETURN 0;
END;');

-- 3. The portal's login may run that procedure, and nothing else in msdb.
IF SUSER_ID(N'shiner_reports') IS NULL
	THROW 50191, 'The login shiner_reports does not exist on this server.', 1;

IF DATABASE_PRINCIPAL_ID(N'shiner_reports') IS NULL
	EXEC (N'CREATE USER [shiner_reports] FOR LOGIN [shiner_reports];');

EXEC (N'GRANT EXECUTE ON [dbo].[start_inventory_cost_requests_job] TO [shiner_reports];');

-- What the portal's login now has in msdb (expected: CONNECT, and EXECUTE on start_inventory_cost_requests_job only).
SELECT pe.[class_desc]
	,COALESCE(OBJECT_NAME(pe.[major_id]), N'(database)') AS [object]
	,pe.[permission_name]
	,pe.[state_desc]

FROM sys.database_permissions AS pe

WHERE pe.[grantee_principal_id] = DATABASE_PRINCIPAL_ID(N'shiner_reports')

UNION ALL

SELECT N'ROLE'
	,r.[name]
	,N'MEMBER'
	,N''

FROM sys.database_role_members AS rm

INNER JOIN sys.database_principals AS r
	ON r.[principal_id] = rm.[role_principal_id]

WHERE rm.[member_principal_id] = DATABASE_PRINCIPAL_ID(N'shiner_reports');
