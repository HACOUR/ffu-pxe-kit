function Get-FfuKitConfig {
    <#
    .SYNOPSIS
    Reads the ffu-pxe-kit configuration file and validates required keys.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: $Path (copy config/config.example.json to config/config.json)"
    }

    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json

    $required = 'FfuBuilderPath', 'StagingPath', 'DriverMappingPath'
    $missing  = $required | Where-Object { -not $config.PSObject.Properties[$_] -or [string]::IsNullOrWhiteSpace($config.$_) }
    if ($missing) {
        throw "Config is missing required keys: $($missing -join ', ')"
    }

    $placeholders = $config.PSObject.Properties | Where-Object { "$($_.Value)" -match '^<.+>$' }
    if ($placeholders) {
        Write-Warning "Config still contains placeholders: $($placeholders.Name -join ', ')"
    }

    $config
}
