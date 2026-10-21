# Read-only SQL verification using synthetic rows; never executes the refresh procedure.
$ErrorActionPreference = 'Stop'
$workspace = Split-Path $PSScriptRoot -Parent
$source = Get-Content (Join-Path $workspace 'sql/procedures/dbo/update_pst_table.sql') -Raw
$firstAlias = $source.IndexOf('AS [shipped_last_360_days]')
$start = $source.LastIndexOf(',ISNULL((', $firstAlias)
$lastAlias = 'AS [shipped_1-30_days]'
$end = $source.IndexOf($lastAlias) + $lastAlias.Length
if ($start -lt 0 -or $firstAlias -lt 0 -or $end -le $start) { throw 'Cannot locate shipped expressions.' }
$expressions = $source.Substring($start + 1, $end - $start - 1)
$expressions = $expressions.Replace('FROM [dbo].[sales] AS sl', 'FROM @sales AS sl')
$expressions = $expressions.Replace("dbo.fnc_is_pst_exclusion(@pst_id, 'sales', sl.[entity], sl.[customer_id]) = 0", 'sl.[is_excluded] = 0')
if ($expressions.Contains('[dbo].[sales]') -or $expressions.Contains('fnc_is_pst_exclusion')) { throw 'Fixture replacement incomplete.' }
$tableDefinition = Get-Content (Join-Path $workspace 'sql/tables/dbo/potential_sell_through.sql') -Raw
$averageColumns = [regex]::Matches($tableDefinition, '\[shipped_(?:6M|12M)_30_day_avg\] AS CAST\([^\r\n]+ PERSISTED')
if ($averageColumns.Count -ne 2) { throw 'Expected two persisted average definitions.' }
$computedDdl = 'ALTER TABLE #actual ADD ' + (($averageColumns | ForEach-Object Value) -join ',') + ';'
$fixture = @'
DECLARE @today date='2026-10-21';
DECLARE @entity_table TABLE(entity nvarchar(20));
INSERT @entity_table VALUES(N'Shiner Ltd');
DECLARE @sales TABLE(item_id nvarchar(20),entity nvarchar(20),posting_date date,quantity decimal(38,20),is_excluded bit);
;WITH days AS (SELECT 0 AS n UNION ALL SELECT n+1 FROM days WHERE n<361)
INSERT @sales SELECT N'TEST',N'Shiner Ltd',DATEADD(day,-n,@today),1,0 FROM days OPTION(MAXRECURSION 400);
INSERT @sales VALUES
 (N'TEST',N'Shiner Ltd',DATEADD(day,-1,@today),-0.25,0),
 (N'TEST',N'Shiner Ltd',DATEADD(day,-1,@today),10000,1),
 (N'TEST',N'Shiner LLC',DATEADD(day,-1,@today),10000,0),
 (N'OTHER',N'Shiner Ltd',DATEADD(day,-1,@today),10000,0);
SELECT it.item_id,
'@
$checks = @'
IF NOT EXISTS(SELECT 1 FROM #actual WHERE item_id=N'TEST'
 AND shipped_last_360_days=359.75 AND shipped_last_180_days=179.75
 AND [shipped_1-30_days]=29.75 AND [shipped_31-60_days]=30 AND [shipped_61-90_days]=30
 AND [shipped_91-120_days]=30 AND [shipped_121-150_days]=30 AND [shipped_151-180_days]=30
 AND [shipped_181-210_days]=30 AND [shipped_211-240_days]=30 AND [shipped_241-270_days]=30
 AND [shipped_271-300_days]=30 AND [shipped_301-330_days]=30 AND [shipped_331-360_days]=30
 AND ABS(shipped_6M_30_day_avg-CAST(179.75 AS decimal(38,20))/6.0)<0.0000000001
 AND ABS(shipped_12M_30_day_avg-CAST(359.75 AS decimal(38,20))/12.0)<0.0000000001)
 THROW 50700,'Shipped boundaries, filters, fractions or averages failed.',1;
IF NOT EXISTS(SELECT 1 FROM #actual WHERE item_id=N'EMPTY' AND shipped_last_360_days=0
 AND shipped_last_180_days=0 AND [shipped_1-30_days]=0 AND [shipped_331-360_days]=0
 AND shipped_6M_30_day_avg=0 AND shipped_12M_30_day_avg=0)
 THROW 50701,'Empty item must return zeros.',1;
IF (SELECT COUNT(*) FROM tempdb.sys.computed_columns WHERE object_id=OBJECT_ID(N'tempdb..#actual')
 AND is_persisted=1 AND precision=38 AND scale=20)<>2
 THROW 50702,'Both averages must be persisted DECIMAL(38,20).',1;
UPDATE #actual SET shipped_last_180_days=60,shipped_last_360_days=240 WHERE item_id=N'TEST';
IF NOT EXISTS(SELECT 1 FROM #actual WHERE item_id=N'TEST' AND shipped_6M_30_day_avg=10 AND shipped_12M_30_day_avg=20)
 THROW 50703,'Computed averages did not follow the updated totals.',1;
SELECT N'PASS: all 360 days/band boundaries, today and older-day exclusion, company/item/exclusion filters, fractional returns, empty item and both averages' AS result;
DROP TABLE #actual;
'@
$tempFile = Join-Path ([IO.Path]::GetTempPath()) ('pst-shipped-' + [guid]::NewGuid().ToString('N') + '.sql')
try {
    ($fixture + "`r`n" + $expressions + "`r`nINTO #actual FROM (VALUES(N'TEST'),(N'EMPTY')) AS it(item_id);`r`n" + $computedDdl + "`r`nGO`r`n" + $checks) | Set-Content -LiteralPath $tempFile -Encoding utf8
    & (Join-Path $PSScriptRoot 'db-query.ps1') -InputFile $tempFile
} finally { Remove-Item -LiteralPath $tempFile -ErrorAction SilentlyContinue }
