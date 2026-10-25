function Add-FfuDriverModel {
    <#
    .SYNOPSIS
    Adds (or updates) a device model in the driver mapping file.

    .DESCRIPTION
    Each mapping entry links a device (manufacturer, model, machine type) to a
    driver folder below the drivers root. The folder must exist before the entry
    is added. Use -Force to update an existing entry with the same machine type.

    .EXAMPLE
    Add-FfuDriverModel -MappingPath '<STAGING-PATH>\Drivers\DriverMapping.json' `
        -DriversRoot '<STAGING-PATH>\Drivers' -Manufacturer '<MANUFACTURER>' `
        -Model '<MODEL>' -MachineType '<MACHINE-TYPE>'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$MappingPath,
        [Parameter(Mandatory)][string]$DriversRoot,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Manufacturer,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Model,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$MachineType,
        [string]$DriverPath,
        [switch]$Force
    )

    if (-not $DriverPath) { $DriverPath = "$Manufacturer\$Model" }

    $folder = Join-Path $DriversRoot (ConvertTo-FfuFsPath $DriverPath)
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        throw "Driver folder not found: $folder"
    }

    $entries  = [Collections.Generic.List[object]]::new()
    foreach ($e in (Read-FfuDriverMapping -Path $MappingPath)) { $entries.Add($e) }

    $existing = $entries | Where-Object { $_.MachineType -eq $MachineType }
    if ($existing -and -not $Force) {
        throw "Machine type '$MachineType' is already mapped ($($existing.Model)). Use -Force to update."
    }

    $entry = [pscustomobject]@{
        Manufacturer = $Manufacturer
        Model        = $Model
        DriverPath   = $DriverPath
        MachineType  = $MachineType
    }

    if ($PSCmdlet.ShouldProcess($MappingPath, "Map $MachineType -> $DriverPath")) {
        if ($existing) { [void]$entries.Remove($existing) }
        $entries.Add($entry)
        $sorted = @($entries | Sort-Object Manufacturer, Model)
        Write-FfuDriverMapping -Path $MappingPath -Entries $sorted
        $entry
    }
}
