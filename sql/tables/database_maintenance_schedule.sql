USE [data_control];
GO
IF OBJECT_ID(N'dbo.database_maintenance_schedule', N'U') IS NULL
CREATE TABLE dbo.database_maintenance_schedule (
    schedule_id INT NOT NULL PRIMARY KEY CHECK (schedule_id = 1),
    enabled BIT NOT NULL,
    interval_days INT NOT NULL CHECK (interval_days BETWEEN 1 AND 365),
    next_run_at DATETIME2(3) NOT NULL,
    last_success_at DATETIME2(3) NULL
);
-- The initial index run was completed on 2026-09-10. Start the automatic
-- schedule one week from deployment; rerunning this script preserves settings.
IF NOT EXISTS (SELECT 1 FROM dbo.database_maintenance_schedule WHERE schedule_id=1)
    INSERT dbo.database_maintenance_schedule
        (schedule_id,enabled,interval_days,next_run_at)
    VALUES (1,1,7,DATEADD(DAY,7,SYSUTCDATETIME()));
GO
