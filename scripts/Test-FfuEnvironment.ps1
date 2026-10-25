<#
.SYNOPSIS
Runs the ffu-pxe-kit health check and prints a summary. Read-only.
Exit code: 0 = no failures, 1 = at least one Fail.
#>
param(
    [string]$ConfigPath = [IO.Path]::Combine($PSScriptRoot, '..', 'config', 'config.json')
)
Import-Module ([IO.Path]::Combine($PSScriptRoot, '..', 'src', 'FfuPxeKit', 'FfuPxeKit.psm1')) -Force
$results = Test-FfuEnvironment -ConfigPath $ConfigPath
$results | Format-Table -AutoSize
$summary = $results | Group-Object Status | ForEach-Object { "$($_.Name): $($_.Count)" }
Write-Output ($summary -join "  ")
if ($results.Status -contains 'Fail') { exit 1 } else { exit 0 }
