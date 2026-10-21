# Exercises the actual procedure body against local temporary fixture tables only.
$ErrorActionPreference = 'Stop'
$workspace = Split-Path $PSScriptRoot -Parent
$source = Get-Content (Join-Path $workspace 'sql/procedures/dbo/update_pst_table.sql') -Raw
$header = '(?i)CREATE\s+OR\s+ALTER\s+PROCEDURE\s+(?:\[dbo\]|dbo)\s*\.\s*(?:\[update_pst_table\]|update_pst_table)(?!\w)'
if ([regex]::Matches($source, $header).Count -ne 1) { throw 'Expected exactly one refresh procedure header; refusing to execute fixture.' }
$source = [regex]::Replace($source, $header, 'CREATE PROCEDURE #pst_refresh')
$objects = @('potential_sell_through','purchase_orders','sales_orders','inventory','sales','items','brands','exclusions')
foreach ($name in $objects) {
    $target = if ($name -eq 'potential_sell_through') { 'results' } else { $name }
    $object = '(?i)(?:\[dbo\]|dbo)\s*\.\s*(?:\[' + $name + '\]|' + $name + ')(?!\w)'
    $source = [regex]::Replace($source, $object, "#fixture_$target")
}
$source = [regex]::Replace($source, '(?i)(?:\[portal\]|portal)\s*\.\s*(?:\[pst_reports\]|pst_reports)(?!\w)', '#fixture_reports')
$source = [regex]::Replace($source, '(?i)CAST\s*\(\s*GETDATE\s*\(\s*\)\s+AS\s+date\s*\)', "CAST('20261021' AS date)")
$testId = [guid]::NewGuid().ToString('N')
$source = $source.Replace("N'dbo.update_pst_table'", "N'pst-test-refresh-$testId'")
$source = $source.Replace("N'portal.pst-report-edit'", "N'pst-test-edit-$testId'")
if ($source -match '(?i)\b(?:FROM|JOIN|INTO|INSERT|UPDATE|DELETE\s+FROM)\s+\[?(?:dbo|portal)\]?\s*\.') { throw 'Warehouse reference remains in fixture procedure.' }
if ($source -match '(?i)CREATE\s+(?:OR\s+ALTER\s+)?PROCEDURE\s+[^#]') { throw 'Non-temporary procedure remains in fixture.' }
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
