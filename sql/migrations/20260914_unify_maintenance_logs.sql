-- Run through tools/deploy-maintenance-logging.ps1, which deploys procedures
-- and removes the old tables in the same transaction as this history copy.
IF @@TRANCOUNT=0 THROW 51200, 'Use tools/deploy-maintenance-logging.ps1.', 1;
IF OBJECT_ID(N'dbo.database_maintenance_log',N'U') IS NOT NULL
BEGIN
    INSERT dbo.db_log ([timestamp],duration_seconds,[level],[table],[action],[message])
    SELECT CONVERT(DATETIME2(7),m.started_at AT TIME ZONE 'UTC' AT TIME ZONE 'GMT Standard Time'),
        COALESCE(DATEDIFF_BIG(MICROSECOND,m.started_at,m.finished_at)/1000000.0,0),
        CASE m.status WHEN 'SUCCESS' THEN N'SUCCESS' WHEN 'FAILED' THEN N'FAILURE' ELSE N'INFO' END,
        LEFT(m.table_name,30),N'database maintenance: '+m.action,
        (SELECT m.log_id AS legacy_maintenance_log_id,m.run_id,m.mode,m.action,
            m.schema_name,m.table_name,m.target_name,m.command,m.page_count,
            m.fragmentation_before,m.density_before,m.modifications_before,
            m.started_at AS started_at_utc,m.finished_at AS finished_at_utc,
            m.status,m.error_message FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)
    FROM dbo.database_maintenance_log m;

    IF @@ROWCOUNT<>(SELECT COUNT(*) FROM dbo.database_maintenance_log)
        THROW 51201, 'Maintenance history copy was incomplete.', 1;
END;
IF OBJECT_ID(N'dbo.database_maintenance_schedule',N'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.database_maintenance_schedule WHERE enabled<>1 OR interval_days<>7)
        THROW 51202, 'Schedule settings changed; review procedure defaults before migration.', 1;
    -- Keep the previous settings as an audit record, including the original due date.
    INSERT dbo.db_log ([timestamp],duration_seconds,[level],[action],[message])
    SELECT SYSDATETIME(),0,N'INFO',N'database maintenance: schedule migrated',
        (SELECT s.* FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)
    FROM dbo.database_maintenance_schedule s;

    INSERT dbo.db_log ([timestamp],duration_seconds,[level],[action],[message])
    SELECT CONVERT(DATETIME2(7),last_success_at AT TIME ZONE 'UTC' AT TIME ZONE 'GMT Standard Time'),
        0,N'SUCCESS',N'database maintenance: index check completed',
        (SELECT last_success_at AS completed_at_utc,N'legacy schedule' AS source
         FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)
    FROM dbo.database_maintenance_schedule WHERE last_success_at IS NOT NULL;
END;
