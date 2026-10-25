function ConvertTo-FfuNetworkApplyScript {
    <#
    .SYNOPSIS
    Patches a copy of FFU Builder's ApplyFFU.ps1 so it can deploy from a network share.

    .DESCRIPTION
    Stock ApplyFFU.ps1 (FFU Builder by rbalsleyMSFT, MIT) only looks for the FFU on a
    USB drive or a local volume labelled "Deploy". This function applies two minimal,
    clearly marked patches:

    1. Get-USBDrive returns $env:FFU_DEPLOY_ROOT when set (e.g. "N:\" = mapped share).
       Without the variable the original USB logic runs unchanged.
    2. The log file name can be overridden with $env:FFU_LOG_NAME, so several devices
       can log to the same share without overwriting each other.

    The patch is applied by pattern; if FFU Builder changes these lines, the function
    stops with an error instead of producing a half-patched script.

    .EXAMPLE
    ConvertTo-FfuNetworkApplyScript -Path X:\mount\ApplyFFU.ps1 -Destination X:\mount\ApplyFFU.ps1
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Destination
    )

    $marker = '# ffu-pxe-kit network patch'
    $text = Get-Content -LiteralPath $Path -Raw

    if ($text -match [regex]::Escape($marker)) {
        throw "Script is already patched: $Path"
    }

    $patches = @(
        @{
            Name    = 'Get-USBDrive'
            Pattern = '(?m)^(\s*function\s+Get-USBDrive\s*\(\s*\)\s*\{)'
            Replace = "`$1`r`n    $marker`r`n    if (`$env:FFU_DEPLOY_ROOT) { return `$env:FFU_DEPLOY_ROOT }"
        },
        @{
            Name    = 'LogFileName'
            Pattern = "(?m)^(\s*)\`$LogFileName\s*=\s*'ScriptLog\.txt'"
            Replace = "`$1$marker`r`n`$1`$LogFileName = if (`$env:FFU_LOG_NAME) { `$env:FFU_LOG_NAME } else { 'ScriptLog.txt' }"
        }
    )

    foreach ($p in $patches) {
        $count = ([regex]::Matches($text, $p.Pattern)).Count
        if ($count -ne 1) {
            throw "Unsupported ApplyFFU.ps1 version: expected exactly one match for '$($p.Name)', found $count."
        }
        $text = [regex]::Replace($text, $p.Pattern, $p.Replace)
    }

    $header = @"
$marker
# Based on ApplyFFU.ps1 from FFU Builder - https://github.com/rbalsleyMSFT/FFU
# Copyright (c) 2023 rbalsleyMSFT - MIT License. Patched by ffu-pxe-kit for network deployment.

"@
    $text = $header + $text

    if ($PSCmdlet.ShouldProcess($Destination, 'Write patched ApplyFFU.ps1')) {
        # ApplyFFU runs in Windows PowerShell 5.1 - write UTF-8 with BOM so non-ASCII stays intact
        [IO.File]::WriteAllText($Destination, $text, [Text.UTF8Encoding]::new($true))
    }
}
