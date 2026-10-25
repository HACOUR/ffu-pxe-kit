function Test-FfuDriverMapping {
    <#
    .SYNOPSIS
    Checks the driver mapping against the driver folders.

    .DESCRIPTION
    Reports:
    - MissingFolder   : mapping entry points to a folder that does not exist
    - EmptyFolder     : mapped folder contains no files
    - DuplicateType   : same device identity (MachineType / SystemId / SystemSku / Model) mapped more than once
    - UnmappedFolder  : model folder exists but is not referenced (often a leftover duplicate)
    Returns nothing when everything is consistent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MappingPath,
        [Parameter(Mandatory)][string]$DriversRoot
    )

    $entries = Read-FfuDriverMapping -Path $MappingPath

    foreach ($e in $entries) {
        $folder = Join-Path $DriversRoot (ConvertTo-FfuFsPath $e.DriverPath)
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
            [pscustomobject]@{ Check = 'MissingFolder'; Item = $e.DriverPath; Detail = "Mapped for $($e.MachineType)" }
        }
        elseif (-not (Get-ChildItem -LiteralPath $folder -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)) {
            [pscustomobject]@{ Check = 'EmptyFolder'; Item = $e.DriverPath; Detail = "No driver files for $($e.MachineType)" }
        }
    }

    # Match key depends on the vendor (same logic as ApplyFFU.ps1):
    # Lenovo = MachineType, Dell/HP/... = SystemId, Microsoft = SystemSku (array), otherwise Model
    $keyed = foreach ($e in $entries) {
        $key = if ($e.PSObject.Properties['MachineType'] -and $e.MachineType) { "MachineType=$($e.MachineType)" }
               elseif ($e.PSObject.Properties['SystemId'] -and $e.SystemId) { "SystemId=$(@($e.SystemId) -join ',')" }
               elseif ($e.PSObject.Properties['SystemSku'] -and $e.SystemSku) { "SystemSku=$(@($e.SystemSku | Sort-Object) -join ',')" }
               else { "Model=$($e.Model)" }
        [pscustomobject]@{ Key = "$($e.Manufacturer)|$key"; Entry = $e }
    }
    $keyed | Group-Object Key | Where-Object Count -gt 1 | ForEach-Object {
        [pscustomobject]@{ Check = 'DuplicateType'; Item = $_.Name; Detail = "$($_.Count) entries: $(($_.Group.Entry.Model) -join '; ')" }
    }

    # Model folders = second level below the drivers root (<Manufacturer>\<Model>)
    $mapped = @($entries | ForEach-Object { (ConvertTo-FfuFsPath $_.DriverPath).TrimEnd([IO.Path]::DirectorySeparatorChar) })
    Get-ChildItem -LiteralPath $DriversRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $make = $_.Name
        Get-ChildItem -LiteralPath $_.FullName -Directory | ForEach-Object {
            $rel = Join-Path $make $_.Name
            if ($mapped -notcontains $rel) {
                [pscustomobject]@{ Check = 'UnmappedFolder'; Item = ($rel -replace '[\\/]', '\'); Detail = 'Not referenced in mapping' }
            }
        }
    }
}
