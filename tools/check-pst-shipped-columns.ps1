# Kept as the original entry point; the full refresh fixture also verifies every shipped band.
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'check-pst-refresh.ps1')
