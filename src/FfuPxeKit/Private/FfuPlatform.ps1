# Thin wrappers around platform calls so they can be mocked in tests
# and skipped cleanly on non-Windows systems.

function Test-FfuIsWindows {
    [OutputType([bool])]
    param()
    [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

function Get-FfuServiceState {
    param([Parameter(Mandatory)][string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) { [string]$svc.Status } else { $null }
}

function Get-FfuShare {
    param([Parameter(Mandatory)][string]$Name)
    Get-SmbShare -Name $Name -ErrorAction SilentlyContinue
}

function Get-FfuFreeSpaceGB {
    [OutputType([double])]
    param([Parameter(Mandatory)][string]$Path)
    $root = [IO.Path]::GetPathRoot($Path)
    [math]::Round(([IO.DriveInfo]::new($root)).AvailableFreeSpace / 1GB, 1)
}

function Get-FfuWdsBootImage {
    param([Parameter(Mandatory)][string]$Name)
    Get-WdsBootImage -ImageName $Name -ErrorAction SilentlyContinue
}
