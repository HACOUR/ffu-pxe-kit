# Load private helpers first, then public functions
foreach ($scope in 'Private', 'Public') {
    Get-ChildItem -Path (Join-Path $PSScriptRoot $scope) -Filter *.ps1 -ErrorAction SilentlyContinue |
        ForEach-Object { . $_.FullName }
}
Export-ModuleMember -Function (Get-ChildItem (Join-Path $PSScriptRoot 'Public') -Filter *.ps1 -ErrorAction SilentlyContinue).BaseName
