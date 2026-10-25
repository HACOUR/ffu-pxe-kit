<#
.SYNOPSIS
Copies drivers + DriverMapping.json (and with -IncludeImage the newest FFU) from FFU Builder
to the PXE staging share, then runs the health check.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = [IO.Path]::Combine($PSScriptRoot, '..', 'config', 'config.json'),
    [switch]$IncludeImage,
    [switch]$Mirror
)
Import-Module ([IO.Path]::Combine($PSScriptRoot, '..', 'src', 'FfuPxeKit', 'FfuPxeKit.psm1')) -Force
Sync-FfuStaging -ConfigPath $ConfigPath -IncludeImage:$IncludeImage -Mirror:$Mirror -WhatIf:$WhatIfPreference | Format-Table -AutoSize
if (-not $WhatIfPreference) { Test-FfuEnvironment -ConfigPath $ConfigPath | Format-Table -AutoSize }
