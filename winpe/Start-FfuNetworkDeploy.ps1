<#
.SYNOPSIS
Runs inside WinPE: waits for the network, maps the deployment share and starts
the patched ApplyFFU.ps1 from FFU Builder.

.NOTES
Part of ffu-pxe-kit. No credentials are stored - the password is asked at runtime.
Settings come from X:\ffu-pxe-kit\network.json.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive WinPE console UI')]
param(
    [string]$ConfigPath = 'X:\ffu-pxe-kit\network.json',
    [string]$ApplyScript = 'X:\ApplyFFU.ps1'
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Text) { Write-Host "`n=== $Text ===" -ForegroundColor Cyan }

function Exit-ToShell([string]$Message) {
    Write-Host "`n$Message" -ForegroundColor Red
    Write-Host 'Opening a command prompt for troubleshooting. Type "exit" to reboot.' -ForegroundColor Yellow
    cmd.exe /k
    wpeutil reboot
    exit 1
}

try {
    $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Exit-ToShell "Cannot read $ConfigPath : $($_.Exception.Message)"
}

$share  = $cfg.SharePath
$letter = if ($cfg.DriveLetter) { "$($cfg.DriveLetter)".TrimEnd(':') } else { 'N' }
$root   = "$($letter):\"
$server = ($share -replace '^\\\\', '') -split '\\' | Select-Object -First 1
$timeout = if ($cfg.NetworkTimeoutSeconds) { [int]$cfg.NetworkTimeoutSeconds } else { 120 }

Write-Host 'ffu-pxe-kit - network deployment' -ForegroundColor Green
Write-Host "Share: $share"

# 1. Network
Write-Step "Waiting for network (server $server, max $timeout s)"
$deadline = (Get-Date).AddSeconds($timeout)
$online = $false
while ((Get-Date) -lt $deadline) {
    if (Test-Connection -ComputerName $server -Count 1 -Quiet -ErrorAction SilentlyContinue) { $online = $true; break }
    Start-Sleep -Seconds 3
}
if (-not $online) {
    ipconfig /all
    Exit-ToShell "Server $server not reachable. Check cable/VLAN and whether WinPE has a driver for this network adapter."
}
Write-Host 'Network OK'

# 2. Map share - password is prompted by net use (*), never stored
Write-Step "Connecting $share as $root"
$user = $cfg.UserName
if ([string]::IsNullOrWhiteSpace($user) -or $user -match '<.+>') { $user = Read-Host 'User name (DOMAIN\user or SERVER\user)' }
$mapped = $false
for ($i = 1; $i -le 3 -and -not $mapped; $i++) {
    cmd.exe /c "net use $($letter): `"$share`" /user:$user * /persistent:no"
    $mapped = Test-Path $root
    if (-not $mapped) { Write-Host "Connection failed (attempt $i of 3)." -ForegroundColor Yellow }
}
if (-not $mapped) { Exit-ToShell "Could not connect $share." }

# 3. Sanity check
if (-not (Get-ChildItem -Path "$root*.ffu" -ErrorAction SilentlyContinue)) {
    Exit-ToShell "No .ffu file found in the root of $share."
}

# 4. Hand over to ApplyFFU (patched: uses FFU_DEPLOY_ROOT instead of a USB drive)
$serial = (Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue).SerialNumber
if ([string]::IsNullOrWhiteSpace($serial)) { $serial = $env:COMPUTERNAME }
$serial = ($serial -replace '[^A-Za-z0-9_-]', '')
$env:FFU_DEPLOY_ROOT = $root
$env:FFU_LOG_NAME    = "ScriptLog_$serial.txt"

Write-Step "Starting ApplyFFU (log: $root$env:FFU_LOG_NAME)"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ApplyScript
if ($LASTEXITCODE -ne 0) { Exit-ToShell "ApplyFFU.ps1 ended with exit code $LASTEXITCODE. See $root$env:FFU_LOG_NAME" }
