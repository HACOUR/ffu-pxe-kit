function Sync-FfuStaging {
    <#
    .SYNOPSIS
    Copies drivers, DriverMapping.json and (optionally) the newest FFU from FFU Builder
    to the PXE staging share.

    .DESCRIPTION
    FFU Builder downloads drivers and updates DriverMapping.json in its own folder
    (<FfuBuilderPath>\Drivers). For network deployment these must be in the staging share.
    - Drivers: copied (or mirrored with -Mirror, which also removes folders no longer in the source)
    - DriverMapping.json: always taken from FFU Builder
    - -IncludeImage: copies the newest .ffu from <FfuBuilderPath>\FFU to the staging root
      (existing images are kept) and protects it against write/delete by the deploy account
    Run Test-FfuEnvironment afterwards. Supports -WhatIf.

    .EXAMPLE
    Sync-FfuStaging -ConfigPath .\config\config.json -IncludeImage -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [switch]$IncludeImage,
        [switch]$Mirror
    )

    $cfg = Get-FfuKitConfig -Path $ConfigPath -WarningAction SilentlyContinue
    $srcDrivers = if ($cfg.PSObject.Properties['FfuBuilderDriversPath'] -and $cfg.FfuBuilderDriversPath) { $cfg.FfuBuilderDriversPath } else { Join-Path $cfg.FfuBuilderPath 'Drivers' }
    $srcFfu     = if ($cfg.PSObject.Properties['FfuCapturePath'] -and $cfg.FfuCapturePath) { $cfg.FfuCapturePath } else { Join-Path $cfg.FfuBuilderPath 'FFU' }
    $dstDrivers = Split-Path -Parent $cfg.DriverMappingPath
    $result = [System.Collections.Generic.List[object]]::new()

    if (-not (Test-Path -LiteralPath $srcDrivers -PathType Container)) { throw "FFU Builder drivers folder not found: $srcDrivers" }
    $srcMapping = Join-Path $srcDrivers 'DriverMapping.json'
    if (Test-Path -LiteralPath $srcMapping) {
        Read-FfuDriverMapping -Path $srcMapping | Out-Null   # throws on invalid JSON - nothing is copied then
    }
    else {
        Write-Warning "No DriverMapping.json in $srcDrivers - devices will fall back to manual driver selection."
    }

    $models = @(Get-ChildItem -LiteralPath $srcDrivers -Directory | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory })

    # FFU Builder can download straight into the staging folder - then there is nothing to copy
    $norm = { param($p) [IO.Path]::GetFullPath($p).TrimEnd('\', '/') }
    $sameFolder = (& $norm $srcDrivers) -eq (& $norm $dstDrivers)
    if ($sameFolder) {
        $result.Add([pscustomobject]@{ Item = 'Drivers'; Status = 'SameFolder'; Detail = "FFU Builder already downloads into $dstDrivers - nothing to sync" })
    }
    elseif ($Mirror -and $models.Count -eq 0) {
        throw "Refusing to mirror: source $srcDrivers contains no model folders - this would delete all drivers in $dstDrivers."
    }
    $action = if ($Mirror) { 'Mirror drivers (removes extra folders in staging)' } else { 'Copy drivers' }
    if ($sameFolder) { }
    elseif ($PSCmdlet.ShouldProcess($dstDrivers, "$action from $srcDrivers ($($models.Count) model folder(s))")) {
        Invoke-FfuFolderSync -Source $srcDrivers -Destination $dstDrivers -Mirror:$Mirror
        $result.Add([pscustomobject]@{ Item = 'Drivers'; Status = 'Synced'; Detail = "$($models.Count) model folder(s) -> $dstDrivers" })
    }
    else { $result.Add([pscustomobject]@{ Item = 'Drivers'; Status = 'WhatIf'; Detail = "$($models.Count) model folder(s) -> $dstDrivers" }) }

    if ($IncludeImage) {
        $newest = Get-ChildItem -LiteralPath $srcFfu -Filter *.ffu -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $newest) {
            $result.Add([pscustomobject]@{ Item = 'Image'; Status = 'Skipped'; Detail = "No .ffu found in $srcFfu" })
        }
        else {
            $target = Join-Path $cfg.StagingPath $newest.Name
            if ((Test-Path -LiteralPath $target) -and (Get-Item -LiteralPath $target).Length -eq $newest.Length) {
                $result.Add([pscustomobject]@{ Item = 'Image'; Status = 'UpToDate'; Detail = $newest.Name })
            }
            elseif ($PSCmdlet.ShouldProcess($target, "Copy newest image $($newest.Name) ($([math]::Round($newest.Length/1GB,1)) GB)")) {
                Copy-Item -LiteralPath $newest.FullName -Destination $target -Force
                if ($cfg.PSObject.Properties['DeployUserName'] -and $cfg.DeployUserName -and $cfg.DeployUserName -notmatch '<.+>') {
                    Protect-FfuImage -Path $target -UserName $cfg.DeployUserName
                }
                $result.Add([pscustomobject]@{ Item = 'Image'; Status = 'Synced'; Detail = $newest.Name })
            }
            else { $result.Add([pscustomobject]@{ Item = 'Image'; Status = 'WhatIf'; Detail = $newest.Name }) }
        }
    }

    $result
}
