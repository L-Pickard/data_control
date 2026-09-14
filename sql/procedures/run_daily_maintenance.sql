USE [data_control];
GO
CREATE OR ALTER PROCEDURE dbo.run_daily_maintenance
    @TablesJson NVARCHAR(MAX),
    @IndexIntervalDays INT = 7,
    @IndexesEnabled BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    IF DB_NAME()<>N'data_control' THROW 51100, 'Maintenance is restricted to data_control.', 1;
    IF @@TRANCOUNT<>0 THROW 51101, 'Run daily maintenance in autocommit mode.', 1;
    IF @TablesJson IS NULL THROW 51102, 'Provide the successfully loaded tables.', 1;
    IF @IndexIntervalDays IS NULL OR @IndexIntervalDays NOT BETWEEN 1 AND 365 OR @IndexesEnabled IS NULL
        THROW 51104, 'Provide an interval of 1 to 365 days and an enabled flag.', 1;

    EXEC dbo.maintain_database @Mode='STATISTICS',@Preview=0,@TablesJson=@TablesJson;

    DECLARE @lock_result INT, @last_success DATETIME2(7), @completed DATETIME2(7),
        @started DATETIME2(7), @message NVARCHAR(MAX), @duration DECIMAL(38,20);
    EXEC @lock_result=sys.sp_getapplock @Resource=N'dbo.database_maintenance_schedule',
        @LockMode='Exclusive',@LockOwner='Session',@LockTimeout=0;
    IF @lock_result<0 THROW 51103, 'Another scheduled maintenance check is active.', 1;
    BEGIN TRY
        SELECT @last_success=MAX(TRY_CONVERT(DATETIME2(7),JSON_VALUE(
            CASE WHEN ISJSON([message])=1 THEN [message] ELSE N'{}' END,'$.completed_at_utc')))
        FROM dbo.db_log
        WHERE [action]=N'database maintenance: index check completed' AND [level]=N'SUCCESS';
        IF @IndexesEnabled=1 AND (@last_success IS NULL OR DATEADD(DAY,@IndexIntervalDays,@last_success)<=SYSUTCDATETIME())
        BEGIN
            -- Check all eligible database tables, including those loaded by
            -- separate scripts. Only the daily statistics scope is load-specific.
            SET @started=SYSUTCDATETIME();
            EXEC dbo.maintain_database @Mode='INDEXES',@Preview=0;
            -- Advance only on full success, including a check finding no work.
            -- Exceptions/time limits leave the schedule due for the next run.
            SET @completed=SYSUTCDATETIME();
            SET @message=(SELECT @completed AS completed_at_utc FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
            SET @duration=DATEDIFF_BIG(MICROSECOND,@started,@completed)/1000000.0;
            EXEC dbo.write_db_log @level=N'SUCCESS',
                @action=N'database maintenance: index check completed',
                @message=@message,@duration_seconds=@duration;
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
