param(
    [string]$Query,
    [string]$InputFile,
    [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Query) -and [string]::IsNullOrWhiteSpace($InputFile)) {
    throw 'Provide -Query or -InputFile.'
}

if (-not [string]::IsNullOrWhiteSpace($Query) -and -not [string]::IsNullOrWhiteSpace($InputFile)) {
    throw 'Provide either -Query or -InputFile, not both.'
}

$password = [Environment]::GetEnvironmentVariable('CODEX_SQL_PASSWORD', 'Process')
if ([string]::IsNullOrEmpty($password)) {
    $password = [Environment]::GetEnvironmentVariable('CODEX_SQL_PASSWORD', 'User')
}

$secretPaths = @(
    (Join-Path $PSScriptRoot '.codex-sql.env'),
    (Join-Path (Split-Path -Parent $PSScriptRoot) '.codex-sql.env')
)

foreach ($localSecretPath in $secretPaths) {
    if (([string]::IsNullOrEmpty($password) -or $password -notlike '*`*') -and (Test-Path -LiteralPath $localSecretPath)) {
        $localSecret = Get-Content -LiteralPath $localSecretPath -Raw
        foreach ($line in ($localSecret -split "\r?\n")) {
            if ($line -match '^\s*CODEX_SQL_PASSWORD=(.*)\s*$') {
                $password = $Matches[1].Trim()
                break
            }
        }
    }
}

if ([string]::IsNullOrEmpty($password)) {
    throw 'CODEX_SQL_PASSWORD is not set.'
}

if (-not [string]::IsNullOrWhiteSpace($InputFile)) {
    $Query = Get-Content -LiteralPath $InputFile -Raw
}

$builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
$builder['Data Source'] = 'tcp:source_d'
$builder['Initial Catalog'] = 'data_control'
$builder['User ID'] = 'codex_assistant'
$builder['Password'] = $password
$builder['Encrypt'] = $false
$builder['TrustServerCertificate'] = $true
$builder['Connect Timeout'] = 10
$builder['Application Name'] = 'Codex sandbox db-query'

$connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)

$connection.Open()
try {
    $batches = [System.Text.RegularExpressions.Regex]::Split($Query, '(?im)^\s*GO\s*(?:--.*)?$')
    foreach ($batch in $batches) {
        if ([string]::IsNullOrWhiteSpace($batch)) {
            continue
        }

        $command = $connection.CreateCommand()
        $command.CommandText = $batch
        $command.CommandTimeout = $TimeoutSeconds

        $reader = $command.ExecuteReader()
        try {
            if ($reader.FieldCount -gt 0) {
                $table = [System.Data.DataTable]::new()
                $table.Load($reader)
                $table | Format-Table -AutoSize
            }
        }
        finally {
            $reader.Close()
        }
    }
}
finally {
    $connection.Close()
}
