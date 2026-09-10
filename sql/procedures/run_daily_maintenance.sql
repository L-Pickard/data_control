USE [data_control];
GO
CREATE OR ALTER PROCEDURE dbo.run_daily_maintenance
    @TablesJson NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    IF DB_NAME()<>N'data_control' THROW 51100, 'Maintenance is restricted to data_control.', 1;
    IF @@TRANCOUNT<>0 THROW 51101, 'Run daily maintenance in autocommit mode.', 1;
    IF @TablesJson IS NULL THROW 51102, 'Provide the successfully loaded tables.', 1;

    EXEC dbo.maintain_database @Mode='STATISTICS',@Preview=0,@TablesJson=@TablesJson;

    DECLARE @lock_result INT;
    EXEC @lock_result=sys.sp_getapplock @Resource=N'dbo.database_maintenance_schedule',
        @LockMode='Exclusive',@LockOwner='Session',@LockTimeout=0;
    IF @lock_result<0 THROW 51103, 'Another scheduled maintenance check is active.', 1;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.database_maintenance_schedule WHERE schedule_id=1)
            THROW 51104, 'Maintenance schedule configuration is missing.', 1;
        IF EXISTS (SELECT 1 FROM dbo.database_maintenance_schedule
                   WHERE schedule_id=1 AND enabled=1 AND next_run_at<=SYSUTCDATETIME())
        BEGIN
            -- Check all eligible database tables, including those loaded by
            -- separate scripts. Only the daily statistics scope is load-specific.
            EXEC dbo.maintain_database @Mode='INDEXES',@Preview=0;
            -- Advance only on full success, including a check finding no work.
            -- Exceptions/time limits leave the schedule due for the next run.
            UPDATE dbo.database_maintenance_schedule
            SET last_success_at=SYSUTCDATETIME(),
                next_run_at=DATEADD(DAY,interval_days,SYSUTCDATETIME())
            WHERE schedule_id=1;
            SELECT N'INDEXES_COMPLETED' AS schedule_status;
        END
        ELSE
            SELECT N'NOT_DUE_OR_DISABLED' AS schedule_status;
        EXEC sys.sp_releaseapplock @Resource=N'dbo.database_maintenance_schedule',@LockOwner='Session';
    END TRY
    BEGIN CATCH
        EXEC sys.sp_releaseapplock @Resource=N'dbo.database_maintenance_schedule',@LockOwner='Session';
        THROW;
    END CATCH;
END;
GO
