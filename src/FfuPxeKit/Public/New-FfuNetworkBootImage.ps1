function New-FfuNetworkBootImage {
    <#
    .SYNOPSIS
    Builds a WinPE boot image for network FFU deployment and (optionally) adds it to WDS.

    .DESCRIPTION
    Takes the boot.wim of the FFU Builder deploy media, and in a working copy:
    - patches the included ApplyFFU.ps1 (ConvertTo-FfuNetworkApplyScript)
    - adds Start-FfuNetworkDeploy.ps1 and network.json (share, user name - no password)
    - replaces startnet.cmd so WinPE starts the network deployment
    - optionally injects WinPE network drivers
    The source wim is never modified. With -ImportToWds the result is added as a NEW
    WDS boot image, so the existing one stays available.

    Requires Windows, elevated PowerShell, DISM module (and WDS module for -ImportToWds).

    .EXAMPLE
    New-FfuNetworkBootImage -SourceWim '<path>\boot.wim' -WorkPath 'C:\Temp\ffu-netboot' `
        -SharePath '\\<SERVER>\<SHARE>' -UserName '<SERVER>\<DEPLOY-USER>' -ImportToWds -BootImageName 'FFU Network Deploy'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$SourceWim,
        [Parameter(Mandatory)][string]$WorkPath,
        [Parameter(Mandatory)][ValidatePattern('^\\\\[^\\]+\\.+')][string]$SharePath,
        [string]$UserName,
        [ValidatePattern('^[D-Y]$')][string]$DriveLetter = 'N',
        [string]$NetworkDriverPath,
        [switch]$ImportToWds,
        [string]$BootImageName = 'FFU Network Deploy'
    )

    if (-not (Test-FfuIsWindows)) { throw 'New-FfuNetworkBootImage requires Windows (DISM/WDS).' }
    if (-not (Test-Path -LiteralPath $SourceWim)) { throw "Source wim not found: $SourceWim" }

    # Windows PowerShell 5.1: Join-Path accepts only one child path
    $winpeDir = [IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot, '..', '..', '..', 'winpe'))
    $wrapper  = Join-Path $winpeDir 'Start-FfuNetworkDeploy.ps1'
    $startnet = Join-Path $winpeDir 'startnet.cmd'
    foreach ($f in $wrapper, $startnet) { if (-not (Test-Path $f)) { throw "Missing kit file: $f" } }

    $wim   = Join-Path $WorkPath 'boot.wim'
    $mount = Join-Path $WorkPath 'mount'

    if (-not $PSCmdlet.ShouldProcess($wim, "Build network boot image for $SharePath")) {
        Write-Verbose "Source: $SourceWim | Share: $SharePath | User: $UserName | WDS name: $BootImageName"
        [pscustomobject]@{ WhatIf = $true; SourceWim = $SourceWim; WorkWim = $wim; SharePath = $SharePath; UserName = $UserName; ImportToWds = [bool]$ImportToWds; BootImageName = $BootImageName }
        return
    }

    New-Item -ItemType Directory -Force -Path $WorkPath, $mount | Out-Null
    Copy-Item -LiteralPath $SourceWim -Destination $wim -Force
    Set-ItemProperty -LiteralPath $wim -Name IsReadOnly -Value $false

    Mount-WindowsImage -ImagePath $wim -Index 1 -Path $mount | Out-Null
    $save = $false
    try {
        $apply = Join-Path $mount 'ApplyFFU.ps1'
        if (-not (Test-Path $apply)) { throw 'ApplyFFU.ps1 not found in boot image - is this the FFU Builder WinPE?' }
        ConvertTo-FfuNetworkApplyScript -Path $apply -Destination $apply

        $kitDir = Join-Path $mount 'ffu-pxe-kit'
        New-Item -ItemType Directory -Force -Path $kitDir | Out-Null
        Copy-Item $wrapper $kitDir -Force
        $net = [ordered]@{ SharePath = $SharePath; UserName = $UserName; DriveLetter = $DriveLetter; NetworkTimeoutSeconds = 120 }
        [IO.File]::WriteAllText((Join-Path $kitDir 'network.json'), ($net | ConvertTo-Json), [Text.UTF8Encoding]::new($false))

        Copy-Item $startnet (Join-Path $mount 'Windows\System32\startnet.cmd') -Force

        if ($NetworkDriverPath) {
            Add-WindowsDriver -Path $mount -Driver $NetworkDriverPath -Recurse | Out-Null
        }
        $save = $true
    }
    finally {
        if ($save) { Dismount-WindowsImage -Path $mount -Save | Out-Null }
        else { Dismount-WindowsImage -Path $mount -Discard | Out-Null }
    }

    if ($ImportToWds) {
        if (Get-WdsBootImage -ImageName $BootImageName -ErrorAction SilentlyContinue) {
            throw "WDS boot image '$BootImageName' already exists. Choose another -BootImageName or remove it first."
        }
        Import-WdsBootImage -Path $wim -NewImageName $BootImageName | Out-Null
    }

    Get-Item $wim
}
