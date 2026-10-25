function Test-FfuDriverMapping {
    <#
    .SYNOPSIS
    Checks the driver mapping against the driver folders.

    .DESCRIPTION
    Reports:
    - MissingFolder   : mapping entry points to a folder that does not exist
    - EmptyFolder     : mapped folder contains no files
    - DuplicateType   : machine type mapped more than once
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

    $entries | Group-Object MachineType | Where-Object Count -gt 1 | ForEach-Object {
        [pscustomobject]@{ Check = 'DuplicateType'; Item = $_.Name; Detail = "$($_.Count) entries" }
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
