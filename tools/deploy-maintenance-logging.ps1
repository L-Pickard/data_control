$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$sqlParts = @(@'
USE [data_control];
SET XACT_ABORT ON;
DECLARE @lock_result INT;
EXEC @lock_result=sys.sp_getapplock @Resource=N'dbo.database_maintenance_schedule',
    @LockMode='Exclusive',@LockOwner='Session',@LockTimeout=0;
IF @lock_result<0 THROW 51203, 'A scheduled maintenance check is active.', 1;
EXEC @lock_result=sys.sp_getapplock @Resource=N'dbo.maintain_database',
    @LockMode='Exclusive',@LockOwner='Session',@LockTimeout=0;
IF @lock_result<0 THROW 51204, 'Maintenance is active.', 1;
BEGIN TRANSACTION;
GO
'@)
foreach ($relativePath in @(
    'sql/migrations/20260914_unify_maintenance_logs.sql',
    'sql/procedures/maintain_database.sql',
    'sql/procedures/run_daily_maintenance.sql'
)) {
    $sqlParts += Get-Content -LiteralPath (Join-Path $repoRoot $relativePath) -Raw
    $sqlParts += "`nGO`n"
}
$sqlParts += @'
DROP TABLE IF EXISTS dbo.database_maintenance_log;
DROP TABLE IF EXISTS dbo.database_maintenance_schedule;
COMMIT TRANSACTION;
EXEC sys.sp_releaseapplock @Resource=N'dbo.maintain_database',@LockOwner='Session';
EXEC sys.sp_releaseapplock @Resource=N'dbo.database_maintenance_schedule',@LockOwner='Session';
SELECT N'Maintenance logging migration committed' AS result;
'@
$deploymentFile = [System.IO.Path]::GetTempFileName()
try {
    Set-Content -LiteralPath $deploymentFile -Value ($sqlParts -join "`n")
    & (Join-Path $PSScriptRoot 'db-query.ps1') -InputFile $deploymentFile
}
finally {
    Remove-Item -LiteralPath $deploymentFile
}
