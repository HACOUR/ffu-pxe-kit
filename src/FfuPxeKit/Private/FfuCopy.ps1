function Invoke-FfuFolderSync {
    # Copies a folder tree. Windows: robocopy (fast, long paths). Elsewhere: Copy-Item (used by tests).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [switch]$Mirror
    )
    if (Test-FfuIsWindows) {
        $mode = if ($Mirror) { '/MIR' } else { '/E' }
        $null = & robocopy.exe $Source $Destination $mode /R:2 /W:2 /NP /NFL /NDL /NJH /NJS
        # robocopy exit codes 0-7 = success, 8+ = failure
        if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE): $Source -> $Destination" }
        return
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | Copy-Item -Destination $Destination -Recurse -Force
    if ($Mirror) {
        $srcItems = Get-ChildItem -LiteralPath $Source -Recurse -Force | ForEach-Object { $_.FullName.Substring($Source.TrimEnd('\','/').Length) }
        Get-ChildItem -LiteralPath $Destination -Recurse -Force | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
            $rel = $_.FullName.Substring($Destination.TrimEnd('\','/').Length)
            if ($srcItems -notcontains $rel) { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
        }
    }
}

function Protect-FfuImage {
    # Deny write/delete on an FFU image for the deployment account (Windows only)
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$UserName)
    if (-not (Test-FfuIsWindows)) { return }
    $null = & icacls.exe $Path /deny "$($UserName):(W,D)"
    if ($LASTEXITCODE -ne 0) { throw "icacls failed for $Path" }
}
