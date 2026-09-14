# Exercise the real procedure bodies using session-local tables and procedures.
# Maintenance commands are replaced with harmless statements or a deliberate error.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$parts = @(@'
USE data_control;
CREATE TABLE #db_log (
    log_id BIGINT IDENTITY PRIMARY KEY,[timestamp] DATETIME2(7) NOT NULL,
    notified BIT NOT NULL DEFAULT 0,duration_seconds DECIMAL(38,20) NOT NULL,
    [level] NVARCHAR(15),[table] NVARCHAR(30),[rows] INT,
    [action] NVARCHAR(MAX),[message] NVARCHAR(MAX)
);
CREATE TABLE #control (fail BIT, do_work BIT);
INSERT #control VALUES (0,1);
GO
'@)
foreach ($name in @('write_db_log','maintain_database','run_daily_maintenance')) {
    $body = Get-Content -LiteralPath (Join-Path $repoRoot "sql/procedures/$name.sql") -Raw
    $body = $body.Substring($body.IndexOf('CREATE OR ALTER PROCEDURE'))
    $body = $body -replace '(?im)^GO\s*$', ''
    $body = $body.Replace('CREATE OR ALTER PROCEDURE','CREATE PROCEDURE')
    $body = $body.Replace('[dbo].[write_db_log]','#write_db_log').Replace('dbo.write_db_log','#write_db_log')
    $body = $body.Replace('dbo.run_daily_maintenance','#run_daily_maintenance').Replace('dbo.maintain_database','#maintain_database')
    $body = $body.Replace('[dbo].[db_log]','#db_log').Replace('dbo.db_log','#db_log')
    $body = $body.Replace("N'dbo.database_maintenance_schedule'", "N'test.maintenance.schedule'")
    if ($name -eq 'maintain_database') {
        # Avoid production diagnostics and build one controlled operation instead.
        $start = $body.IndexOf('    INSERT #tables')
        $end = $body.IndexOf('    CREATE TABLE #work', $start)
        $body = $body.Substring(0,$start) + $body.Substring($end)
        $start = $body.IndexOf('    -- Whole-index')
        $end = $body.IndexOf('    IF @Preview=1', $start)
        $fakeWork = @'
    IF @TablesJson IS NULL AND EXISTS (SELECT 1 FROM #control WHERE do_work=1)
        INSERT #work (object_id,target_id,table_name,target_name,action,command)
        SELECT 0,0,N'test_table',N'test_target',N'STATISTICS',
            CASE WHEN fail=1 THEN N'THROW 51999, ''deliberate test failure'', 1;'
                 ELSE N'SET NOCOUNT ON;' END FROM #control;
'@
        $body = $body.Substring(0,$start) + $fakeWork + "`n" + $body.Substring($end)
        $body = $body.Replace('    SELECT @run AS run_id,status,COUNT(*) AS actions FROM #work GROUP BY status;', '')
    }
    $body = $body.Replace("SELECT N'INDEXES_COMPLETED' AS schedule_status;", 'PRINT N''Index check completed'';')
    $body = $body.Replace("SELECT N'NOT_DUE_OR_DISABLED' AS schedule_status;", 'PRINT N''Index check skipped'';')
    $parts += $body
    $parts += "`nGO`n"
}
$parts += @'
EXEC #maintain_database @Preview=0;
IF NOT EXISTS (SELECT 1 FROM #db_log WHERE [level]='SUCCESS' AND JSON_VALUE([message],'$.status')='SUCCESS'
    AND JSON_VALUE([message],'$.finished_at_utc') IS NOT NULL AND duration_seconds>=0)
    THROW 51900, 'Successful action logging failed.', 1;
UPDATE #control SET fail=1;
BEGIN TRY
    EXEC #maintain_database @Preview=0;
    THROW 51901, 'Expected action failure.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>51999 THROW;
END CATCH;
IF NOT EXISTS (SELECT 1 FROM #db_log WHERE [level]='FAILURE' AND JSON_VALUE([message],'$.error_message')='deliberate test failure')
    THROW 51902, 'Failure logging failed.', 1;
UPDATE #control SET fail=0,do_work=0;
EXEC #run_daily_maintenance @TablesJson=N'[]';
IF (SELECT COUNT(*) FROM #db_log WHERE [action]=N'database maintenance: index check completed')<>1
    THROW 51903, 'First empty check did not record completion.', 1;
EXEC #run_daily_maintenance @TablesJson=N'[]';
IF (SELECT COUNT(*) FROM #db_log WHERE [action]=N'database maintenance: index check completed')<>1
    THROW 51904, 'A recent success did not prevent another check.', 1;
UPDATE #db_log SET [message]=N'{"completed_at_utc":"2000-01-01T00:00:00"}'
WHERE [action]=N'database maintenance: index check completed';
EXEC #run_daily_maintenance @TablesJson=N'[]',@IndexesEnabled=0;
IF (SELECT COUNT(*) FROM #db_log WHERE [action]=N'database maintenance: index check completed')<>1
    THROW 51905, 'Disabled indexes ran.', 1;
EXEC #run_daily_maintenance @TablesJson=N'[]';
IF (SELECT COUNT(*) FROM #db_log WHERE [action]=N'database maintenance: index check completed')<>2
    THROW 51906, 'An overdue check was skipped.', 1;
UPDATE #db_log SET [message]=N'{"completed_at_utc":"2000-01-01T00:00:00"}'
WHERE [action]=N'database maintenance: index check completed';
UPDATE #control SET fail=1,do_work=1;
BEGIN TRY
    EXEC #run_daily_maintenance @TablesJson=N'[]';
    THROW 51907, 'Expected scheduled check failure.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>51999 THROW;
END CATCH;
IF (SELECT COUNT(*) FROM #db_log WHERE [action]=N'database maintenance: index check completed')<>2
    THROW 51908, 'Failed check advanced the schedule.', 1;
UPDATE #control SET fail=0;
EXEC #run_daily_maintenance @TablesJson=N'[]';
IF (SELECT COUNT(*) FROM #db_log WHERE [action]=N'database maintenance: index check completed')<>3
    THROW 51909, 'Failed check was not retried.', 1;
DECLARE @before BIGINT=(SELECT COUNT(*) FROM #db_log);
-- No proposed work avoids result sets, while still exercising preview's early return.
UPDATE #control SET do_work=0;
EXEC #maintain_database @Preview=1;
IF (SELECT COUNT(*) FROM #db_log)<>@before THROW 51910, 'Preview wrote logs.', 1;
GO
SELECT N'All maintenance logging and scheduling checks passed' AS result;
'@
$testFile = [System.IO.Path]::GetTempFileName()
try {
    Set-Content -LiteralPath $testFile -Value ($parts -join "`n")
    & (Join-Path $PSScriptRoot 'db-query.ps1') -InputFile $testFile
}
finally { Remove-Item -LiteralPath $testFile }
