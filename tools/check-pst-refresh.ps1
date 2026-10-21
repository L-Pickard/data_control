# Exercises the actual procedure body against local temporary fixture tables only.
$ErrorActionPreference = 'Stop'
$workspace = Split-Path $PSScriptRoot -Parent
$source = Get-Content (Join-Path $workspace 'sql/procedures/dbo/update_pst_table.sql') -Raw
$source = $source.Replace('CREATE OR ALTER PROCEDURE dbo.update_pst_table','CREATE PROCEDURE #pst_refresh')
$objects = @('potential_sell_through','purchase_orders','sales_orders','inventory','sales','items','brands','exclusions')
foreach ($name in $objects) {
    $target = if ($name -eq 'potential_sell_through') { 'results' } else { $name }
    $source = $source.Replace("dbo.$name", "#fixture_$target")
}
$source = $source.Replace('portal.pst_reports','#fixture_reports')
$source = $source.Replace('CAST(GETDATE() AS date)', "CAST('20261021' AS date)")
$testId = [guid]::NewGuid().ToString('N')
$source = $source.Replace("N'dbo.update_pst_table'", "N'pst-test-refresh-$testId'")
$source = $source.Replace("N'portal.pst-report-edit'", "N'pst-test-edit-$testId'")
if ($source -match '(?i)\b(?:FROM|JOIN|INTO|UPDATE|DELETE FROM)\s+(?:dbo|portal)\.') { throw 'Warehouse reference remains in fixture procedure.' }
$definition = Get-Content (Join-Path $workspace 'sql/tables/dbo/potential_sell_through.sql') -Raw
$start = $definition.IndexOf('[brand_id] NVARCHAR')
$end = $definition.IndexOf(',CONSTRAINT [FK_pst_items]')
if ($start -lt 0 -or $end -le $start) { throw 'Cannot locate result column definitions.' }
$resultTable = 'CREATE TABLE #fixture_results(' + $definition.Substring($start,$end-$start) + ',PRIMARY KEY(pst_id,item_id));'
$fixture = Get-Content (Join-Path $workspace 'sql/diagnostics/check_pst_refresh_fixture.sql') -Raw
$assertions = Get-Content (Join-Path $workspace 'sql/diagnostics/check_pst_refresh_assertions.sql') -Raw
$tempFile = Join-Path ([IO.Path]::GetTempPath()) ('pst-refresh-' + $testId + '.sql')
try {
    ($fixture + "`r`n" + $resultTable + "`r`nGO`r`n" + $source + "`r`n" + $assertions) | Set-Content -LiteralPath $tempFile -Encoding utf8
    & (Join-Path $PSScriptRoot 'db-query.ps1') -InputFile $tempFile
} finally { Remove-Item -LiteralPath $tempFile -ErrorAction SilentlyContinue }
