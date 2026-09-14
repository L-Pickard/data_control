# Run the actual procedure against session-local fixtures; no real sales are deleted.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$body = Get-Content -LiteralPath (Join-Path $repoRoot 'sql/procedures/delete_sales_from_date.sql') -Raw
$body = $body.Substring($body.IndexOf('CREATE OR ALTER PROCEDURE'))
$body = $body.Replace('CREATE OR ALTER PROCEDURE [dbo].[delete_sales_from_date]', 'CREATE PROCEDURE #delete_sales_from_date')
$body = $body.Replace('[dbo].[sales]', '#sales').Replace('[dbo].[entities]', '#entities').Replace('[dbo].[write_db_log]', '#write_db_log')
$setup = @'
CREATE TABLE #sales (entity NVARCHAR(20), posting_date DATE NOT NULL);
CREATE TABLE #entities (entity NVARCHAR(20), sales_increment DATE NOT NULL);
CREATE TABLE #results (sales_rows_deleted INT, entities_updated INT);
INSERT #sales VALUES ('A','20260902'),('A','20260908'),('A','20260910'),
    ('B','20260903'),('B','20260907'),('B','20260911'),('C','20260912');
INSERT #entities VALUES ('A','20260901'),('B','20260914'),('C','20260914'),
    ('D','20260901'),('E','20260909');
GO
CREATE PROCEDURE #write_db_log
    @level NVARCHAR(15),@table NVARCHAR(30),@rows INT,
    @action NVARCHAR(MAX),@message NVARCHAR(MAX),@duration_seconds DECIMAL(38,20)
AS
    RETURN;
GO
'@
$assertions = @'
INSERT #results EXEC #delete_sales_from_date @from_date='20260910';
IF NOT EXISTS (SELECT 1 FROM #entities WHERE entity='A' AND sales_increment='20260908')
    THROW 51800, 'Entity A did not use its maximum remaining sales date.', 1;
IF NOT EXISTS (SELECT 1 FROM #entities WHERE entity='B' AND sales_increment='20260907')
    THROW 51801, 'Entity B did not use its own maximum remaining sales date.', 1;
IF EXISTS (SELECT 1 FROM #entities WHERE entity IN ('C','E') AND sales_increment<>'20260909')
    THROW 51807, 'Empty entity cutoff fallback failed.', 1;
IF NOT EXISTS (SELECT 1 FROM #entities WHERE entity='D' AND sales_increment='20260901')
    THROW 51808, 'Empty entity earlier increment was not preserved.', 1;
IF (SELECT COUNT(*) FROM #sales)<>4 OR EXISTS (SELECT 1 FROM #sales WHERE posting_date>='20260910')
    THROW 51802, 'Sales cutoff behavior changed.', 1;
IF NOT EXISTS (SELECT 1 FROM #results WHERE sales_rows_deleted=3 AND entities_updated=3)
    THROW 51803, 'Affected-row counts are incorrect.', 1;
DELETE FROM #results;
INSERT #results EXEC #delete_sales_from_date @from_date='20260912';
IF NOT EXISTS (SELECT 1 FROM #results WHERE sales_rows_deleted=0 AND entities_updated=0)
    THROW 51804, 'A later repeat advanced existing watermarks.', 1;
DELETE FROM #results;
INSERT #results EXEC #delete_sales_from_date @from_date='20260901';
IF EXISTS (SELECT 1 FROM #entities WHERE sales_increment<>'20260831')
    THROW 51805, 'An earlier cutoff did not rewind all watermarks.', 1;
IF NOT EXISTS (SELECT 1 FROM #results WHERE sales_rows_deleted=4 AND entities_updated=5)
    THROW 51806, 'Earlier cutoff row counts are incorrect.', 1;
SELECT N'Per-entity remaining MAX dates, empty entities, repeated calls, deletion boundary and row counts passed' AS result;
'@
$testFile = [System.IO.Path]::GetTempFileName()
try {
    Set-Content -LiteralPath $testFile -Value ($setup + "`n" + $body + "`n" + $assertions)
    & (Join-Path $PSScriptRoot 'db-query.ps1') -InputFile $testFile
}
finally { Remove-Item -LiteralPath $testFile }
