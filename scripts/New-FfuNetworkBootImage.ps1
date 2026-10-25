<#
.SYNOPSIS
Builds the network deployment boot image from the FFU Builder WinPE ISO and adds it to WDS.
Reads share path and user name from config.json. Use -WhatIf for a dry run.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = [IO.Path]::Combine($PSScriptRoot, '..', 'config', 'config.json'),
    [Parameter(Mandatory)][string]$IsoPath,
    [string]$WorkPath = 'C:\Temp\ffu-netboot',
    [string]$NetworkDriverPath,
    [switch]$SkipWdsImport
)
Import-Module ([IO.Path]::Combine($PSScriptRoot, '..', 'src', 'FfuPxeKit', 'FfuPxeKit.psm1')) -Force
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

$iso = Mount-DiskImage -ImagePath $IsoPath -PassThru
try {
    $drive = ($iso | Get-Volume).DriveLetter
    $params = @{
        SourceWim     = "$($drive):\sources\boot.wim"
        WorkPath      = $WorkPath
        SharePath     = $cfg.DeploySharePath
        UserName      = $cfg.DeployUserName
        ImportToWds   = -not $SkipWdsImport
        BootImageName = $(if ($cfg.NetworkBootImageName) { $cfg.NetworkBootImageName } else { 'FFU Network Deploy' })
        WhatIf        = $WhatIfPreference
    }
    if ($NetworkDriverPath) { $params.NetworkDriverPath = $NetworkDriverPath }
    New-FfuNetworkBootImage @params
}
finally {
    Dismount-DiskImage -ImagePath $IsoPath | Out-Null
}
