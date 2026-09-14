USE [data_control];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.maintain_database
    @Mode VARCHAR(20) = 'STATISTICS',
    @Preview BIT = 1,
    @TablesJson NVARCHAR(MAX) = NULL, -- dbo table names; NULL = all eligible tables
    @OnlyModified BIT = 1,
    @FullScan BIT = 0,
    @MinPageCount INT = 1000,
    @ReorganizePercent FLOAT = 10,
    @RebuildPercent FLOAT = 30,
    @MinPageDensity FLOAT = 75,
    @MaxDop INT = 2,
    @LockTimeoutMs INT = 5000,
    @TimeLimitSeconds INT = 900 -- stop starting commands; not a query timeout
AS
BEGIN
    SET NOCOUNT ON;
    SET ANSI_WARNINGS ON;
    SET ANSI_PADDING ON;
    SET ARITHABORT ON;
    SET CONCAT_NULL_YIELDS_NULL ON;
    SET NUMERIC_ROUNDABORT OFF;
    IF DB_NAME() <> N'data_control' THROW 51000, 'Maintenance is restricted to data_control.', 1;
    IF @Preview=0 AND @@TRANCOUNT <> 0 THROW 51001, 'Run maintenance outside a transaction (use autocommit).', 1;
    SET @Mode = UPPER(@Mode);
    IF @Mode IS NULL OR @Mode NOT IN ('STATISTICS', 'INDEXES')
        THROW 51002, 'Mode must be STATISTICS or INDEXES.', 1;
    IF @Preview IS NULL OR @OnlyModified IS NULL OR @FullScan IS NULL
       OR @MinPageCount IS NULL OR @MinPageCount < 1
       OR @ReorganizePercent IS NULL OR @ReorganizePercent < 0
       OR @RebuildPercent IS NULL OR @RebuildPercent < @ReorganizePercent OR @RebuildPercent > 100
       OR @MinPageDensity IS NULL OR @MinPageDensity < 0 OR @MinPageDensity > 100
       OR @MaxDop IS NULL OR @MaxDop < 1 OR @MaxDop > 64
       OR @LockTimeoutMs IS NULL OR @LockTimeoutMs < 0
       OR @TimeLimitSeconds IS NULL OR @TimeLimitSeconds < 1
        THROW 51003, 'Invalid maintenance options.', 1;
    IF @TablesJson IS NOT NULL AND (ISJSON(@TablesJson) <> 1 OR LEFT(LTRIM(@TablesJson), 1) <> '[')
        THROW 51004, 'TablesJson must be a JSON array of dbo table names.', 1;

    CREATE TABLE #tables (object_id INT PRIMARY KEY, table_name SYSNAME);
    INSERT #tables
    SELECT t.object_id, t.name FROM sys.tables t
    WHERE t.schema_id = SCHEMA_ID(N'dbo') AND t.is_ms_shipped = 0
      AND t.is_memory_optimized = 0 AND t.temporal_type = 0
      AND t.name NOT IN (N'db_log') AND t.name NOT LIKE N'%[_]staging'
      AND NOT EXISTS (SELECT 1 FROM sys.indexes i WHERE i.object_id=t.object_id AND i.index_id=1 AND i.is_disabled=1)
      AND (@TablesJson IS NULL OR t.name IN (SELECT value FROM OPENJSON(@TablesJson)));
    IF @TablesJson IS NOT NULL AND EXISTS (
        SELECT 1 FROM OPENJSON(@TablesJson) j
        WHERE j.type <> 1 OR NOT EXISTS (SELECT 1 FROM #tables t WHERE t.table_name=j.value)
    ) THROW 51005, 'TablesJson contains an unknown or ineligible dbo table.', 1;
    IF @Mode='INDEXES' AND COALESCE(HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','VIEW DATABASE STATE'),0)=0
       AND EXISTS (SELECT 1 FROM #tables WHERE COALESCE(HAS_PERMS_BY_NAME(N'dbo.'+QUOTENAME(table_name),'OBJECT','CONTROL'),0)=0)
        THROW 51008, 'Index diagnostics require VIEW DATABASE STATE in data_control, or CONTROL on each selected table. Statistics mode does not require this permission.', 1;

    CREATE TABLE #work (
        id INT IDENTITY PRIMARY KEY, object_id INT, target_id INT,
        table_name SYSNAME, target_name SYSNAME, action VARCHAR(20),
        command NVARCHAR(MAX), page_count BIGINT NULL, fragmentation FLOAT NULL,
        density FLOAT NULL, modifications BIGINT NULL, status VARCHAR(20) DEFAULT 'PLANNED'
    );
    -- Whole-index maintenance only for nonpartitioned, enabled rowstore indexes.
    IF @Mode = 'INDEXES'
    INSERT #work (object_id,target_id,table_name,target_name,action,command,page_count,fragmentation,density)
    SELECT t.object_id,i.index_id,t.table_name,i.name,a.action,
        N'ALTER INDEX '+QUOTENAME(i.name)+N' ON dbo.'+QUOTENAME(t.table_name)+N' '+a.action
        + CASE WHEN a.action='REBUILD' THEN N' WITH (MAXDOP = '+CONVERT(NVARCHAR(10),@MaxDop)+N');' ELSE N';' END,
        p.page_count,p.avg_fragmentation_in_percent,p.avg_page_space_used_in_percent
    FROM #tables t
    JOIN sys.indexes i ON i.object_id=t.object_id
    CROSS APPLY sys.dm_db_index_physical_stats(DB_ID(),t.object_id,i.index_id,NULL,'SAMPLED') p
    CROSS APPLY (SELECT CASE WHEN p.avg_fragmentation_in_percent>=@RebuildPercent
        OR i.allow_page_locks=0 THEN 'REBUILD' ELSE 'REORGANIZE' END AS action) a
    WHERE i.type IN (1,2) AND i.is_disabled=0 AND i.is_hypothetical=0
      AND p.index_level=0 AND p.alloc_unit_type_desc='IN_ROW_DATA'
      AND p.page_count>=@MinPageCount
      AND (p.avg_fragmentation_in_percent>=@ReorganizePercent OR p.avg_page_space_used_in_percent<@MinPageDensity)
      AND (SELECT COUNT(*) FROM sys.partitions z WHERE z.object_id=i.object_id AND z.index_id=i.index_id)=1;

    -- Both modes include column and index statistics. Recheck after rebuilds below.
    INSERT #work (object_id,target_id,table_name,target_name,action,command,modifications)
    SELECT t.object_id,s.stats_id,t.table_name,s.name,'STATISTICS',
        N'UPDATE STATISTICS dbo.'+QUOTENAME(t.table_name)+N' '+QUOTENAME(s.name)
        + CASE WHEN @FullScan=1 THEN N' WITH FULLSCAN;' ELSE N';' END,p.modification_counter
    FROM #tables t JOIN sys.stats s ON s.object_id=t.object_id
    OUTER APPLY sys.dm_db_stats_properties(s.object_id,s.stats_id) p
    WHERE (@OnlyModified=0 OR p.last_updated IS NULL OR p.modification_counter>0)
      AND NOT EXISTS (SELECT 1 FROM sys.indexes i WHERE i.object_id=s.object_id AND i.index_id=s.stats_id AND i.is_disabled=1);

    UPDATE #work SET command=N'SET LOCK_TIMEOUT '+CONVERT(NVARCHAR(12),@LockTimeoutMs)+N'; '+command;
    IF @Preview=1
    BEGIN
        SELECT * FROM #work ORDER BY id;
        RETURN;
    END;
    DECLARE @run UNIQUEIDENTIFIER=NEWID(), @started DATETIME2=SYSUTCDATETIME(),
        @lock_result INT, @id INT=0,
        @command NVARCHAR(MAX), @log_id BIGINT, @action VARCHAR(20),
        @object INT, @target INT, @error NVARCHAR(2048), @action_started DATETIME2(7);
    EXEC @lock_result=sys.sp_getapplock @Resource=N'dbo.maintain_database',
        @LockMode='Exclusive',@LockOwner='Session',@LockTimeout=0;
    IF @lock_result<0 THROW 51006, 'Another maintenance run is active.', 1;
    BEGIN TRY
        WHILE EXISTS (SELECT 1 FROM #work WHERE id>@id)
        BEGIN
            SELECT TOP (1) @id=id,@command=command,@action=action,@object=object_id,@target=target_id
            FROM #work WHERE id>@id ORDER BY id;
            IF DATEDIFF(SECOND,@started,SYSUTCDATETIME())>=@TimeLimitSeconds
            BEGIN
                UPDATE #work SET status='TIME_LIMIT' WHERE id>=@id;
                BREAK;
            END;
            IF @OnlyModified=1 AND @action='STATISTICS' AND EXISTS (
                SELECT 1 FROM sys.dm_db_stats_properties(@object,@target)
                WHERE last_updated IS NOT NULL AND modification_counter=0
            )
            BEGIN
                UPDATE #work SET status='ALREADY_CURRENT' WHERE id=@id;
                CONTINUE;
            END;
            SET @action_started=SYSUTCDATETIME();
            INSERT dbo.db_log ([timestamp],duration_seconds,[level],[table],[action],[message])
            SELECT SYSDATETIME(),0,N'INFO',LEFT(table_name,30),N'database maintenance: '+action,
                (SELECT @run AS run_id,@Mode AS mode,N'dbo' AS schema_name,
                    table_name,target_name,command,page_count,
                    fragmentation AS fragmentation_before,density AS density_before,
                    modifications AS modifications_before,@action_started AS started_at_utc,
                    N'RUNNING' AS status
                 FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)
            FROM #work WHERE id=@id;
            SET @log_id=SCOPE_IDENTITY();
            BEGIN TRY
                EXEC sys.sp_executesql @command;
                UPDATE dbo.db_log
                SET [level]=N'SUCCESS',
                    duration_seconds=DATEDIFF_BIG(MICROSECOND,@action_started,SYSUTCDATETIME())/1000000.0,
                    [message]=JSON_MODIFY(JSON_MODIFY([message],'$.status',N'SUCCESS'),
                        '$.finished_at_utc',CONVERT(NVARCHAR(33),SYSUTCDATETIME(),126))
                WHERE log_id=@log_id;
                UPDATE #work SET status='SUCCESS' WHERE id=@id;
            END TRY
            BEGIN CATCH
                SET @error=ERROR_MESSAGE();
                UPDATE dbo.db_log
                SET [level]=N'FAILURE',
                    duration_seconds=DATEDIFF_BIG(MICROSECOND,@action_started,SYSUTCDATETIME())/1000000.0,
                    [message]=JSON_MODIFY(JSON_MODIFY(JSON_MODIFY([message],'$.status',N'FAILED'),
                        '$.finished_at_utc',CONVERT(NVARCHAR(33),SYSUTCDATETIME(),126)),
                        '$.error_message',@error)
                WHERE log_id=@log_id;
                THROW;
            END CATCH;
        END;
        EXEC sys.sp_releaseapplock @Resource=N'dbo.maintain_database',@LockOwner='Session';
    END TRY
    BEGIN CATCH
        EXEC sys.sp_releaseapplock @Resource=N'dbo.maintain_database',@LockOwner='Session';
        THROW;
    END CATCH;
    SELECT @run AS run_id,status,COUNT(*) AS actions FROM #work GROUP BY status;
    IF EXISTS (SELECT 1 FROM #work WHERE status='TIME_LIMIT')
        THROW 51007, 'Maintenance time limit reached; some actions were deferred. See completed actions in db_log.', 1;
END;
GO
