USE [msdb];
GO
-- On-demand only. Existing job ownership, proxy and history are preserved.
-- Run on SQL18 as the job owner/sysadmin after deploying the worker files.
DECLARE @folder NVARCHAR(400)=N'E:\data_control\data_control';
DECLARE @job_id UNIQUEIDENTIFIER, @schedule_id INT;
SELECT @job_id=job_id FROM dbo.sysjobs WHERE name=N'inventory_cost_requests';
IF @job_id IS NULL
    EXEC dbo.sp_add_job @job_name=N'inventory_cost_requests',@enabled=1,
        @owner_login_name=N'SHINER\leo.pickard',@job_id=@job_id OUTPUT;
DECLARE @command NVARCHAR(MAX)=N'Set-Location "'+@folder+N'\scripts"'+NCHAR(13)+NCHAR(10)
    +N'& "'+@folder+N'\venv\Scripts\python.exe" "run_inventory_cost.py"'+NCHAR(13)+NCHAR(10)
    +N'if ($LASTEXITCODE -ne 0) { throw "run_inventory_cost.py failed" }';
IF EXISTS(SELECT 1 FROM dbo.sysjobsteps WHERE job_id=@job_id AND step_id=1)
    EXEC dbo.sp_update_jobstep @job_id=@job_id,@step_id=1,@command=@command,@retry_attempts=0;
ELSE
BEGIN
    EXEC dbo.sp_add_jobstep @job_id=@job_id,@step_name=N'execute_python_program',@subsystem=N'PowerShell',
        @command=@command,@proxy_name=N'LP_PROXY',@on_success_action=1,@on_fail_action=2,@retry_attempts=0;
    EXEC dbo.sp_add_jobserver @job_id=@job_id,@server_name=N'(local)';
END;
-- Detach schedules only from this job. Shared schedules remain attached to other jobs.
WHILE EXISTS(SELECT 1 FROM dbo.sysjobschedules WHERE job_id=@job_id)
BEGIN
    SELECT TOP(1) @schedule_id=schedule_id FROM dbo.sysjobschedules WHERE job_id=@job_id;
    EXEC dbo.sp_detach_schedule @job_id=@job_id,@schedule_id=@schedule_id,@delete_unused_schedule=1;
END;
EXEC dbo.sp_update_job @job_id=@job_id,@enabled=1,
    @description=N'Runs one on-demand inventory check or dataset. No queue, staging table or scheduled polling.';
GO
