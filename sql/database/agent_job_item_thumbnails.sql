USE [msdb];

GO

-- SQL Server Agent job that keeps the SQL18 thumbnail folder filled: scripts/make_item_thumbnails.py copies new
-- marketing thumbnails from the NAS, makes the missing ones from product photos and adds them to the image
-- catalogue. A run with nothing to do takes a few seconds.
--
-- BEFORE RUNNING THIS SCRIPT, set the two paths below to where Python and this repository are on SHINERSQL18.
-- The job is created DISABLED: run it once by hand (Start Job at Step), check the result in dbo.db_log, then
-- enable it. Needs a sysadmin (or SQLAgentOperatorRole plus rights to create CmdExec steps). Safe to run again:
-- the job is replaced, its history is kept.
--
-- The step runs as the SQL Server Agent service account (or a CmdExec proxy if you attach one). That account needs:
--   * read on \\shinersql02\item_docs and on the NAS thumbnail folder
--   * modify on the SQL18 thumbnail folder (\\SHINERSQL18\001 Master Thumbnail Images)
--   * in data_control: SELECT on items, sales, item_images, item_image_locations; CREATE TABLE and ALTER on
--     schema dbo (the staging table); EXECUTE on dbo.merge_item_thumbnail_locations; INSERT on dbo.db_log
DECLARE @python NVARCHAR(400) = N'C:\data_control\venv\Scripts\python.exe';   -- <-- set this
DECLARE @repository NVARCHAR(400) = N'C:\data_control';                       -- <-- and this

DECLARE @job_name SYSNAME = N'data_control: item thumbnails';
DECLARE @schedule_name SYSNAME = N'data_control: item thumbnails hourly';
DECLARE @command NVARCHAR(MAX) = N'"' + @python + N'" "' + @repository + N'\scripts\make_item_thumbnails.py"';
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
	,@description = N'Copies new marketing thumbnails to the SQL18 thumbnail folder, makes missing thumbnails from product photos and adds them to data_control''s image catalogue. Logs to data_control.dbo.db_log (table item_thumbnails).'
	,@job_id = @job_id OUTPUT;

-- A non-zero exit code from Python fails the step.
EXEC [dbo].[sp_add_jobstep] @job_id = @job_id
	,@step_name = N'make missing item thumbnails'
	,@subsystem = N'CmdExec'
	,@command = @command
	,@cmdexec_success_code = 0
	,@on_success_action = 1
	,@on_fail_action = 2
	,@retry_attempts = 0;

-- Every hour at half past, 05:30 to 19:30, every day: after the morning image refresh (finished by about 04:45)
-- and clear of the sales (on the hour) and preorders (four minutes past) loads.
EXEC [dbo].[sp_add_jobschedule] @job_id = @job_id
	,@name = @schedule_name
	,@enabled = 1
	,@freq_type = 4
	,@freq_interval = 1
	,@freq_subday_type = 8
	,@freq_subday_interval = 1
	,@active_start_time = 53000
	,@active_end_time = 193000;

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
