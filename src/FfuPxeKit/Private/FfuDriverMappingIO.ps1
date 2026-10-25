function ConvertTo-FfuFsPath {
    # Mapping stores Windows-style relative paths ("<Manufacturer>\<Model>"); normalize for the local file system
    param([Parameter(Mandatory)][string]$RelativePath)
    $RelativePath -replace '[\\/]', [IO.Path]::DirectorySeparatorChar
}

function Read-FfuDriverMapping {
    [CmdletBinding()]
    [OutputType([System.Array])]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return ,@() }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return ,@() }
    try { $data = $raw | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Invalid JSON in driver mapping '$Path': $($_.Exception.Message)" }
    ,@($data)
}

function Write-FfuDriverMapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entries
    )
    # Always write a JSON array (PS 5.1 would collapse a single element), UTF-8 without BOM
    $json = ConvertTo-Json -InputObject @($Entries) -Depth 5
    if ($Entries.Count -eq 1 -and -not $json.TrimStart().StartsWith('[')) { $json = "[`n$json`n]" }
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}
