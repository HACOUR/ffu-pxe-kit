BeforeAll {
    $src = Join-Path $PSScriptRoot '..' 'src' 'FfuPxeKit'
    Get-ChildItem (Join-Path $src 'Private'), (Join-Path $src 'Public') -Filter *.ps1 | ForEach-Object { . $_.FullName }

    function New-TestEnv {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $builder = Join-Path $root 'builder'; $staging = Join-Path $root 'staging'; $reminst = Join-Path $root 'reminst'
        $model = Join-Path $staging 'Drivers' 'Contoso' 'Laptop 14 Gen 1 (MT01)'
        New-Item -ItemType Directory -Force $builder, $reminst, $model | Out-Null
        Set-Content (Join-Path $builder 'BuildFFUVM.ps1') '#'
        Set-Content (Join-Path $model 'driver.inf') 'x'
        Set-Content (Join-Path $staging 'image.ffu') 'x'
        $map = Join-Path $staging 'Drivers' 'DriverMapping.json'
        '[{"Manufacturer":"Contoso","Model":"Laptop 14 Gen 1 (MT01)","DriverPath":"Contoso\\Laptop 14 Gen 1 (MT01)","MachineType":"MT01"}]' | Set-Content $map
        $cfg = [ordered]@{
            FfuBuilderPath = $builder; StagingPath = $staging; StagingShareName = 'Staging'
            WdsRemoteInstallPath = $reminst; BootImageName = 'FFU Deploy'; DriverMappingPath = $map
            KeepImages = 3; MinFreeSpaceGB = 50
        }
        $cfgPath = Join-Path $root 'config.json'
        $cfg | ConvertTo-Json | Set-Content $cfgPath
        [pscustomobject]@{ Root = $root; ConfigPath = $cfgPath; Staging = $staging; Map = $map }
    }

    function Get-Status($results, $check) { ($results | Where-Object Check -eq $check).Status }
}

Describe 'Test-FfuEnvironment' {
    Context 'healthy Windows server (mocked)' {
        BeforeEach {
            $envi = New-TestEnv
            Mock Test-FfuIsWindows { $true }
            Mock Get-FfuServiceState { 'Running' }
            Mock Get-FfuWdsBootImage { [pscustomobject]@{ ImageName = 'FFU Deploy' } }
            Mock Get-FfuShare { [pscustomobject]@{ Path = $envi.Staging } }
            Mock Get-FfuFreeSpaceGB { 200 }
        }

        It 'reports no failures and no warnings' {
            $r = Test-FfuEnvironment -ConfigPath $envi.ConfigPath
            $r.Status | Should -Not -Contain 'Fail'
            $r.Status | Should -Not -Contain 'Warn'
            Get-Status $r 'Service:WDSServer' | Should -Be 'Pass'
            Get-Status $r 'DriverMapping' | Should -Be 'Pass'
        }

        It 'fails when WDS is stopped' {
            Mock Get-FfuServiceState { 'Stopped' }
            Get-Status (Test-FfuEnvironment -ConfigPath $envi.ConfigPath) 'Service:WDSServer' | Should -Be 'Fail'
        }

        It 'fails when the boot image is missing' {
            Mock Get-FfuWdsBootImage { $null }
            Get-Status (Test-FfuEnvironment -ConfigPath $envi.ConfigPath) 'BootImage' | Should -Be 'Fail'
        }

        It 'warns on low disk space' {
            Mock Get-FfuFreeSpaceGB { 10 }
            Get-Status (Test-FfuEnvironment -ConfigPath $envi.ConfigPath) 'FreeSpace' | Should -Be 'Warn'
        }

        It 'warns when the share points elsewhere' {
            Mock Get-FfuShare { [pscustomobject]@{ Path = 'X:\other' } }
            Get-Status (Test-FfuEnvironment -ConfigPath $envi.ConfigPath) 'Share' | Should -Be 'Warn'
        }

        It 'warns about an old FFU image' {
            (Get-Item (Join-Path $envi.Staging 'image.ffu')).LastWriteTime = (Get-Date).AddDays(-90)
            Get-Status (Test-FfuEnvironment -ConfigPath $envi.ConfigPath) 'FfuImages' | Should -Be 'Warn'
        }

        It 'reports an unmapped duplicate driver folder' {
            $dup = Join-Path $envi.Staging 'Drivers' 'Contoso' 'Laptop 14 Gen 1 (Intel) (MT01)'
            New-Item -ItemType Directory -Force $dup | Out-Null
            $r = Test-FfuEnvironment -ConfigPath $envi.ConfigPath
            Get-Status $r 'DriverMapping:UnmappedFolder' | Should -Be 'Warn'
        }

        It 'fails with a clear message when the mapping is invalid JSON' {
            Set-Content $envi.Map '[{"DriverPath":"Contoso\Laptop"}]'
            $r = @(Test-FfuEnvironment -ConfigPath $envi.ConfigPath | Where-Object Check -like 'DriverMapping*')
            $r.Count | Should -Be 1
            $r[0].Status | Should -Be 'Fail'
            $r[0].Detail | Should -BeLike '*Invalid JSON*'
        }

        It 'fails when BuildFFUVM.ps1 is missing' {
            Remove-Item (Join-Path $envi.Root 'builder' 'BuildFFUVM.ps1')
            Get-Status (Test-FfuEnvironment -ConfigPath $envi.ConfigPath) 'FfuBuilder' | Should -Be 'Fail'
        }
    }

    Context 'non-Windows / config problems' {
        It 'skips Windows-only checks on other platforms' {
            $envi = New-TestEnv
            Mock Test-FfuIsWindows { $false }
            $r = Test-FfuEnvironment -ConfigPath $envi.ConfigPath
            Get-Status $r 'Service:WDSServer' | Should -Be 'Skip'
            Get-Status $r 'Share' | Should -Be 'Skip'
        }

        It 'returns only a Config failure when the config is missing' {
            $r = @(Test-FfuEnvironment -ConfigPath (Join-Path $TestDrive 'missing.json'))
            $r.Count | Should -Be 1
            $r[0].Status | Should -Be 'Fail'
        }

        It 'skips placeholder values from the example config' {
            Mock Test-FfuIsWindows { $true }
            Mock Get-FfuServiceState { 'Running' }
            $example = Join-Path $PSScriptRoot '..' 'config' 'config.example.json'
            $r = Test-FfuEnvironment -ConfigPath $example
            Get-Status $r 'Path:StagingPath' | Should -Be 'Skip'
            Get-Status $r 'BootImage' | Should -Be 'Skip'
        }
    }
}
