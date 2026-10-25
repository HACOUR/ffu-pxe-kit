function Test-FfuEnvironment {
    <#
    .SYNOPSIS
    Health check for an FFU/PXE deployment server. Read-only - changes nothing.

    .DESCRIPTION
    Checks configuration, folders, FFU Builder, WDS service, boot image,
    staging share, free disk space, FFU images and the driver mapping.
    Each result has a Status of Pass, Warn, Fail or Skip.
    Windows-only checks are skipped on other platforms.

    .EXAMPLE
    Test-FfuEnvironment -ConfigPath .\config\config.json | Format-Table
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [int]$MaxImageAgeDays = 45
    )

    function ConvertTo-FfuResult([string]$Check, [string]$Status, [string]$Detail) {
        [pscustomobject]@{ Check = $Check; Status = $Status; Detail = $Detail }
    }

    try {
        $cfg = Get-FfuKitConfig -Path $ConfigPath -WarningAction SilentlyContinue
        ConvertTo-FfuResult 'Config' 'Pass' $ConfigPath
    }
    catch {
        ConvertTo-FfuResult 'Config' 'Fail' $_.Exception.Message
        return
    }

    $isPlaceholder = { param($v) [string]::IsNullOrWhiteSpace("$v") -or "$v" -match '<.+>' }
    $onWindows     = Test-FfuIsWindows

    # Folders
    foreach ($key in 'FfuBuilderPath', 'StagingPath', 'WdsRemoteInstallPath') {
        $value = $cfg.$key
        if (& $isPlaceholder $value) { ConvertTo-FfuResult "Path:$key" 'Skip' 'Not configured'; continue }
        if (Test-Path -LiteralPath $value -PathType Container) { ConvertTo-FfuResult "Path:$key" 'Pass' $value }
        else { ConvertTo-FfuResult "Path:$key" 'Fail' "Not found: $value" }
    }

    # FFU Builder
    if (-not (& $isPlaceholder $cfg.FfuBuilderPath)) {
        $builder = Join-Path $cfg.FfuBuilderPath 'BuildFFUVM.ps1'
        if (Test-Path -LiteralPath $builder) { ConvertTo-FfuResult 'FfuBuilder' 'Pass' 'BuildFFUVM.ps1 found' }
        else { ConvertTo-FfuResult 'FfuBuilder' 'Fail' "BuildFFUVM.ps1 not found in $($cfg.FfuBuilderPath)" }
    }

    # Windows-only checks
    if (-not $onWindows) {
        foreach ($c in 'Service:WDSServer', 'BootImage', 'Share', 'FreeSpace') { ConvertTo-FfuResult $c 'Skip' 'Windows only' }
    }
    else {
        $state = Get-FfuServiceState -Name 'WDSServer'
        if (-not $state) { ConvertTo-FfuResult 'Service:WDSServer' 'Fail' 'WDS not installed' }
        elseif ($state -eq 'Running') { ConvertTo-FfuResult 'Service:WDSServer' 'Pass' 'Running' }
        else { ConvertTo-FfuResult 'Service:WDSServer' 'Fail' "State: $state" }

        if (& $isPlaceholder $cfg.BootImageName) { ConvertTo-FfuResult 'BootImage' 'Skip' 'Not configured' }
        elseif (Get-FfuWdsBootImage -Name $cfg.BootImageName) { ConvertTo-FfuResult 'BootImage' 'Pass' $cfg.BootImageName }
        else { ConvertTo-FfuResult 'BootImage' 'Fail' "Boot image not registered in WDS: $($cfg.BootImageName)" }

        if (& $isPlaceholder $cfg.StagingShareName) { ConvertTo-FfuResult 'Share' 'Skip' 'Not configured' }
        else {
            $share = Get-FfuShare -Name $cfg.StagingShareName
            if (-not $share) { ConvertTo-FfuResult 'Share' 'Fail' "Share not found: $($cfg.StagingShareName)" }
            elseif ($share.Path -ne $cfg.StagingPath) { ConvertTo-FfuResult 'Share' 'Warn' "Share points to $($share.Path), config says $($cfg.StagingPath)" }
            else { ConvertTo-FfuResult 'Share' 'Pass' "$($cfg.StagingShareName) -> $($share.Path)" }
        }

        if (& $isPlaceholder $cfg.StagingPath) { ConvertTo-FfuResult 'FreeSpace' 'Skip' 'Not configured' }
        else {
            $free = Get-FfuFreeSpaceGB -Path $cfg.StagingPath
            $min  = if ($cfg.MinFreeSpaceGB) { [double]$cfg.MinFreeSpaceGB } else { 50 }
            if ($free -ge $min) { ConvertTo-FfuResult 'FreeSpace' 'Pass' "$free GB free (min $min GB)" }
            else { ConvertTo-FfuResult 'FreeSpace' 'Warn' "Only $free GB free (min $min GB)" }
        }
    }

    # FFU images
    if (-not (& $isPlaceholder $cfg.StagingPath) -and (Test-Path -LiteralPath $cfg.StagingPath)) {
        $ffus = @(Get-ChildItem -LiteralPath $cfg.StagingPath -Filter *.ffu -File -Recurse -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending)
        if (-not $ffus) { ConvertTo-FfuResult 'FfuImages' 'Warn' 'No .ffu image found' }
        else {
            $age = [int]((Get-Date) - $ffus[0].LastWriteTime).TotalDays
            $status = if ($age -le $MaxImageAgeDays) { 'Pass' } else { 'Warn' }
            ConvertTo-FfuResult 'FfuImages' $status "$($ffus.Count) image(s), newest $age day(s) old"
        }
    }

    # Driver mapping
    if (& $isPlaceholder $cfg.DriverMappingPath) { ConvertTo-FfuResult 'DriverMapping' 'Skip' 'Not configured' }
    elseif (-not (Test-Path -LiteralPath $cfg.DriverMappingPath)) { ConvertTo-FfuResult 'DriverMapping' 'Fail' "Not found: $($cfg.DriverMappingPath)" }
    else {
        $root     = Split-Path -Parent $cfg.DriverMappingPath
        try {
            $findings = @(Test-FfuDriverMapping -MappingPath $cfg.DriverMappingPath -DriversRoot $root -ErrorAction Stop)
            if (-not $findings) { ConvertTo-FfuResult 'DriverMapping' 'Pass' 'Consistent' }
            else { $findings | ForEach-Object { ConvertTo-FfuResult "DriverMapping:$($_.Check)" 'Warn' $_.Item } }
        }
        catch { ConvertTo-FfuResult 'DriverMapping' 'Fail' $_.Exception.Message }
    }
}
