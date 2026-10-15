USE [msdb];

GO

-- SQL Server Agent job that runs the inventory cost checks and datasets finance queues in Shiner Reports (Inventory
-- Datasets app): scripts/run_inventory_cost.py claims each queued request from data_control's [finance] tables, reads
-- NAV (SQL02, SQL04) for it and writes the result. With nothing queued it only asks SQL18 whether anything is waiting
-- and exits in a second or two, without touching NAV or writing to db_log; a check or dataset takes a few minutes.
--
-- Matches the existing data_control jobs on SHINERSQL18 (checked 15 October 2026): a PowerShell step under the
-- LP_PROXY proxy, run from E:\data_control\data_control with its venv, owner SHINER\leo.pickard; the schedule is
-- every minute from 06:00 to 20:00 like owtanet_ftp_file_processing's constant_daytime_check (every 2 minutes).
--
-- BEFORE RUNNING: pull this repository on SHINERSQL18 so scripts/run_inventory_cost.py and
-- shinerutils/updates/inventory_cost.py exist in E:\data_control\data_control. The job is created DISABLED: run it once
-- by hand (Start Job at Step) with nothing queued (it should succeed and log nothing), then enable it. Needs a
-- sysadmin. Safe to run again: the job is replaced, its history is kept.
--
-- LP_PROXY runs as SHINER\leo.pickard (checked 15 October 2026), which reads NAV for the other loaders and is
-- db_owner in data_control, so it can run the [finance] procedures and replace finance.inventory_cost_staging. If the
-- proxy ever moves to a service account, that account needs: read on NAV_LIVE (SQL02) and BC_LIVE_USA (SQL04); in
-- data_control, EXECUTE on claim_inventory_cost_request, complete_inventory_cost_check, build_inventory_cost and
-- fail_inventory_cost_request, INSERT on finance.inventory_cost_receipts and inventory_cost_unadjusted, CREATE TABLE
-- and ALTER on schema [finance], SELECT on dbo.items and INSERT on dbo.db_log.
DECLARE @folder NVARCHAR(400) = N'E:\data_control\data_control';

DECLARE @job_name SYSNAME = N'inventory_cost_requests';
DECLARE @schedule_name SYSNAME = N'inventory_cost_requests_every_minute';
DECLARE @command NVARCHAR(MAX) = N'Set-Location "' + @folder + N'\scripts"' + NCHAR(13) + NCHAR(10) + NCHAR(13) + NCHAR(10)
	+ N'& "' + @folder + N'\venv\Scripts\python.exe" "run_inventory_cost.py"' + NCHAR(13) + NCHAR(10)
	+ N'if ($LASTEXITCODE -ne 0) { throw "run_inventory_cost.py failed with exit code $LASTEXITCODE" }';
DECLARE @job_id UNIQUEIDENTIFIER;

BEGIN TRANSACTION;

SELECT @job_id = [job_id]

FROM [dbo].[sysjobs]

WHERE [name] = @job_name;

IF @job_id IS NOT NULL
	EXEC [dbo].[sp_delete_job] @job_id = @job_id
		,@delete_history = 0
		,@delete_unused_schedule = 1;

SET @job_id = NULL;

EXEC [dbo].[sp_add_job] @job_name = @job_name
	,@enabled = 0
	,@owner_login_name = N'SHINER\leo.pickard'
	,@description = N'Runs the inventory cost checks and datasets queued in Shiner Reports (data_control [finance] tables), reading NAV on SQL02 and SQL04. Logs to data_control.dbo.db_log (table inventory_cost) only when it handles a request.'
	,@job_id = @job_id OUTPUT;

-- A non-zero exit code from Python fails the step (the throw above).
EXEC [dbo].[sp_add_jobstep] @job_id = @job_id
	,@step_name = N'execute_python_program'
	,@subsystem = N'PowerShell'
	,@command = @command
	,@proxy_name = N'LP_PROXY'
	,@on_success_action = 1
	,@on_fail_action = 2
	,@retry_attempts = 0;

-- Every minute, 06:00 to 20:00, every day.
EXEC [dbo].[sp_add_jobschedule] @job_id = @job_id
	,@name = @schedule_name
	,@enabled = 1
	,@freq_type = 4
	,@freq_interval = 1
	,@freq_subday_type = 4
	,@freq_subday_interval = 1
	,@active_start_time = 60000
	,@active_end_time = 200000;

EXEC [dbo].[sp_add_jobserver] @job_id = @job_id
	,@server_name = N'(local)';

COMMIT TRANSACTION;

SELECT j.[name]
	,j.[enabled]
	,s.[step_name]
	,s.[subsystem]
	,s.[command]

FROM [dbo].[sysjobs] AS j

INNER JOIN [dbo].[sysjobsteps] AS s
	ON s.[job_id] = j.[job_id]

WHERE j.[job_id] = @job_id;

GO
