-- Lets Shiner Reports start the SQL Agent job inventory_cost_requests on demand (user decision, 15 October 2026), without
-- giving the portal's login any rights in msdb. finance.start_inventory_cost_job is signed with a certificate; the
-- certificate's user in msdb is in SQLAgentOperatorRole and its login in master has AUTHENTICATE SERVER, so only code
-- signed with it (that one procedure, which starts that one job) gets those rights. The private key is removed after
-- signing, so nothing else can ever be signed with it and no password has to be kept.
--
-- Run as a sysadmin on SHINERSQL18, AFTER deploying sql/procedures/start_inventory_cost_job.sql. Safe to run again,
-- and it MUST be run again after any change to start_inventory_cost_job (ALTER removes the signature): each run drops
-- the old certificate, its login and user, and signs again with a new one.
--
-- Test afterwards (starts the job once; with nothing queued it does nothing):
--   EXECUTE AS LOGIN = N'shiner_reports'; DECLARE @r INT; EXEC @r = data_control.finance.start_inventory_cost_job; SELECT @r AS result; REVERT;
-- result 0 = started (22022 = it was already running). Any other number: check the job history and this script.
-- Then re-run sql/database/agent_job_inventory_cost.sql, which keeps only an hourly backstop schedule.
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @name SYSNAME = N'inventory_cost_job_starter';
DECLARE @password NVARCHAR(100) = CONCAT(N'Ic!', REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), N'aZ9');
DECLARE @public VARBINARY(MAX);
DECLARE @sql NVARCHAR(MAX);

-- 1. Remove any previous setup: msdb user and certificate, master login and certificate, data_control signature and
--    certificate, in that order.
USE [msdb];

IF DATABASE_PRINCIPAL_ID(@name) IS NOT NULL
BEGIN
	IF IS_ROLEMEMBER(N'SQLAgentOperatorRole', @name) = 1
		EXEC (N'ALTER ROLE [SQLAgentOperatorRole] DROP MEMBER [inventory_cost_job_starter];');

	EXEC (N'DROP USER [inventory_cost_job_starter];');
END;

IF CERT_ID(@name) IS NOT NULL
	EXEC (N'DROP CERTIFICATE [inventory_cost_job_starter];');

USE [master];

IF SUSER_ID(@name) IS NOT NULL
	EXEC (N'DROP LOGIN [inventory_cost_job_starter];');

IF CERT_ID(@name) IS NOT NULL
	EXEC (N'DROP CERTIFICATE [inventory_cost_job_starter];');

USE [data_control];

IF EXISTS (
		SELECT 1

		FROM sys.crypt_properties AS cp

		INNER JOIN sys.certificates AS ce
			ON ce.[thumbprint] = cp.[thumbprint]

		WHERE cp.[major_id] = OBJECT_ID(N'finance.start_inventory_cost_job')
			AND ce.[name] = @name
		)
	EXEC (N'DROP SIGNATURE FROM [finance].[start_inventory_cost_job] BY CERTIFICATE [inventory_cost_job_starter];');

IF CERT_ID(@name) IS NOT NULL
	EXEC (N'DROP CERTIFICATE [inventory_cost_job_starter];');

-- 2. A new certificate in data_control; sign the procedure; throw the private key away.
IF OBJECT_ID(N'finance.start_inventory_cost_job', N'P') IS NULL
	THROW 50181, 'Deploy sql/procedures/start_inventory_cost_job.sql first.', 1;

SET @sql = CONCAT(N'CREATE CERTIFICATE [inventory_cost_job_starter] ENCRYPTION BY PASSWORD = ', QUOTENAME(@password, ''''),
		N' WITH SUBJECT = N''Signs finance.start_inventory_cost_job (starts the inventory_cost_requests Agent job)'', EXPIRY_DATE = ''20991231'';');

EXEC (@sql);

SET @sql = CONCAT(N'ADD SIGNATURE TO [finance].[start_inventory_cost_job] BY CERTIFICATE [inventory_cost_job_starter] WITH PASSWORD = ',
		QUOTENAME(@password, ''''), N';');

EXEC (@sql);

ALTER CERTIFICATE [inventory_cost_job_starter] REMOVE PRIVATE KEY;

SET @public = CERTENCODED(CERT_ID(@name));

-- 3. The same certificate (public key only) in master, with a login that may vouch for it across databases.
USE [master];

SET @sql = CONCAT(N'CREATE CERTIFICATE [inventory_cost_job_starter] FROM BINARY = ', CONVERT(NVARCHAR(MAX), @public, 1), N';');

EXEC (@sql);

EXEC (N'CREATE LOGIN [inventory_cost_job_starter] FROM CERTIFICATE [inventory_cost_job_starter];');

EXEC (N'GRANT AUTHENTICATE SERVER TO [inventory_cost_job_starter];');

-- 4. And in msdb, with a user in SQLAgentOperatorRole (may start local jobs).
USE [msdb];

SET @sql = CONCAT(N'CREATE CERTIFICATE [inventory_cost_job_starter] FROM BINARY = ', CONVERT(NVARCHAR(MAX), @public, 1), N';');

EXEC (@sql);

EXEC (N'CREATE USER [inventory_cost_job_starter] FROM CERTIFICATE [inventory_cost_job_starter];');

EXEC (N'ALTER ROLE [SQLAgentOperatorRole] ADD MEMBER [inventory_cost_job_starter];');

USE [data_control];

SELECT OBJECT_SCHEMA_NAME(cp.[major_id]) + N'.' + OBJECT_NAME(cp.[major_id]) AS [signed_procedure]
	,ce.[name] AS [certificate]
	,ce.[pvt_key_encryption_type_desc] AS [private_key]

FROM sys.crypt_properties AS cp

INNER JOIN sys.certificates AS ce
	ON ce.[thumbprint] = cp.[thumbprint]

WHERE ce.[name] = @name;
