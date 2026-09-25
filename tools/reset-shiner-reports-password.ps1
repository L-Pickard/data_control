<#
.SYNOPSIS
Sets a new password for the SQL login [shiner_reports] on shinersql18 using your own Windows login.

.DESCRIPTION
The password is never written to disk, printed or passed on a command line.
- Default: you are prompted twice (hidden input).
- -Generate: a random 32-character password is created and copied to the clipboard only, so you can paste it
  straight into the server's app configuration or your password manager; clear the clipboard afterwards.
Requires ALTER ANY LOGIN (or sysadmin) for your Windows account. The login keeps its password policy settings.

.EXAMPLE
.\tools\reset-shiner-reports-password.ps1 -Generate
.\tools\reset-shiner-reports-password.ps1 -Unlock
#>
param(
    [string]$Server = 'tcp:shinersql18',
    [string]$Login = 'shiner_reports',
    [switch]$Generate,
    [switch]$Unlock
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security

function ConvertTo-PlainText([Security.SecureString]$secure) {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

if ($Generate) {
    # Letters, digits and symbols that are safe in connection strings (no ; = ' " { }).
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%^*()-_+.,~'.ToCharArray()
    do {
        $bytes = [byte[]]::new(32)
        [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
        $password = -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
    } until ($password -cmatch '[A-Z]' -and $password -cmatch '[a-z]' -and $password -match '\d' -and $password -match '[^A-Za-z0-9]')
}
else {
    $first = Read-Host "New password for $Login" -AsSecureString
    $second = Read-Host 'Confirm password' -AsSecureString
    $password = ConvertTo-PlainText $first
    if ($password -ne (ConvertTo-PlainText $second)) { throw 'Passwords do not match; nothing was changed.' }
    if ($password.Length -lt 16) { throw 'Use at least 16 characters; nothing was changed.' }
    if ($password.Length -gt 128) { throw 'Use at most 128 characters; nothing was changed.' }
}

$builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
$builder['Data Source'] = $Server
$builder['Initial Catalog'] = 'master'
$builder['Integrated Security'] = $true
$builder['Encrypt'] = $true
# The local machine does not yet trust the server certificate chain (see the portal's AGENTS.md).
$builder['TrustServerCertificate'] = $true
$builder['Application Name'] = 'reset-shiner-reports-password'

# ALTER LOGIN cannot take a parameter directly: quote the bound value with QUOTENAME inside dynamic SQL,
# so the password is never concatenated into the command text sent from PowerShell.
$sql = @"
IF SUSER_ID(@login) IS NULL THROW 51000, 'Login not found.', 1;
DECLARE @statement NVARCHAR(MAX) = N'ALTER LOGIN ' + QUOTENAME(@login) + N' WITH PASSWORD = ' + QUOTENAME(@password, N'''')
    + CASE WHEN @unlock = 1 THEN N' UNLOCK' ELSE N'' END + N';';
EXEC sys.sp_executesql @statement;
"@
try {
    $connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    $connection.Open()
    $command = $connection.CreateCommand()
    $command.CommandText = $sql
    $null = $command.Parameters.Add([System.Data.SqlClient.SqlParameter]::new('@login', [Data.SqlDbType]::NVarChar, 128))
    $command.Parameters['@login'].Value = $Login
    $null = $command.Parameters.Add([System.Data.SqlClient.SqlParameter]::new('@password', [Data.SqlDbType]::NVarChar, 128))
    $command.Parameters['@password'].Value = $password
    $null = $command.Parameters.Add([System.Data.SqlClient.SqlParameter]::new('@unlock', [Data.SqlDbType]::Bit))
    $command.Parameters['@unlock'].Value = [bool]$Unlock
    $null = $command.ExecuteNonQuery()
}
finally {
    if ($connection) { $connection.Dispose() }
}

if ($Generate) {
    Set-Clipboard -Value $password
    Write-Output "Password for $Login changed. The new password is on the clipboard only - paste it where it is needed, then clear the clipboard (Set-Clipboard -Value ' ')."
}
else {
    Write-Output "Password for $Login changed."
}
$password = $null
