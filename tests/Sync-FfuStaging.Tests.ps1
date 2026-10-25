BeforeAll {
    $src = Join-Path $PSScriptRoot '..' 'src' 'FfuPxeKit'
    Get-ChildItem (Join-Path $src 'Private'), (Join-Path $src 'Public') -Filter *.ps1 | ForEach-Object { . $_.FullName }

    function New-SyncEnv {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $builder = Join-Path $root 'builder'; $staging = Join-Path $root 'staging'
        $m1 = Join-Path $builder 'Drivers' 'Contoso' 'Laptop 14 Gen 1 (MT01)'
        $m2 = Join-Path $builder 'Drivers' 'Microsoft' 'Tablet Pro 9'
        New-Item -ItemType Directory -Force $m1, $m2, (Join-Path $builder 'FFU'), (Join-Path $staging 'Drivers') | Out-Null
        Set-Content (Join-Path $m1 'a.inf') 'x'; Set-Content (Join-Path $m2 'b.inf') 'x'
        '[{"Manufacturer":"Contoso","Model":"Laptop 14 Gen 1 (MT01)","DriverPath":"Contoso\\Laptop 14 Gen 1 (MT01)","MachineType":"MT01"},{"Manufacturer":"Microsoft","Model":"Tablet Pro 9","DriverPath":"Microsoft\\Tablet Pro 9","SystemSku":["SKU_1"]}]' |
            Set-Content (Join-Path $builder 'Drivers' 'DriverMapping.json')
        $old = Join-Path $builder 'FFU' 'old.ffu'; Set-Content $old 'old'; (Get-Item $old).LastWriteTime = (Get-Date).AddDays(-30)
        Set-Content (Join-Path $builder 'FFU' 'new.ffu') 'newimage'
        $cfg = @{ FfuBuilderPath = $builder; StagingPath = $staging; DriverMappingPath = (Join-Path $staging 'Drivers' 'DriverMapping.json'); DeployUserName = 'SRV\deploy' }
        $cfgPath = Join-Path $root 'config.json'; $cfg | ConvertTo-Json | Set-Content $cfgPath
        [pscustomobject]@{ Root = $root; Builder = $builder; Staging = $staging; ConfigPath = $cfgPath }
    }
}

Describe 'Sync-FfuStaging' {
    BeforeEach { $e = New-SyncEnv; Mock Test-FfuIsWindows { $false } }

    It 'copies drivers and the mapping to staging' {
        Sync-FfuStaging -ConfigPath $e.ConfigPath | Out-Null
        Test-Path (Join-Path $e.Staging 'Drivers' 'DriverMapping.json') | Should -BeTrue
        Test-Path (Join-Path $e.Staging 'Drivers' 'Microsoft' 'Tablet Pro 9' 'b.inf') | Should -BeTrue
        (Read-FfuDriverMapping (Join-Path $e.Staging 'Drivers' 'DriverMapping.json')).Count | Should -Be 2
    }

    It 'results in a consistent mapping in staging' {
        Sync-FfuStaging -ConfigPath $e.ConfigPath | Out-Null
        Test-FfuDriverMapping -MappingPath (Join-Path $e.Staging 'Drivers' 'DriverMapping.json') -DriversRoot (Join-Path $e.Staging 'Drivers') | Should -BeNullOrEmpty
    }

    It 'keeps extra staging folders without -Mirror and removes them with -Mirror' {
        $extra = Join-Path $e.Staging 'Drivers' 'Contoso' 'Laptop 14 Gen 1 (Intel) (MT01)'
        New-Item -ItemType Directory -Force $extra | Out-Null
        Sync-FfuStaging -ConfigPath $e.ConfigPath | Out-Null
        Test-Path $extra | Should -BeTrue
        Sync-FfuStaging -ConfigPath $e.ConfigPath -Mirror | Out-Null
        Test-Path $extra | Should -BeFalse
    }

    It 'copies only the newest image with -IncludeImage' {
        $r = Sync-FfuStaging -ConfigPath $e.ConfigPath -IncludeImage
        ($r | Where-Object Item -eq 'Image').Detail | Should -Be 'new.ffu'
        Test-Path (Join-Path $e.Staging 'new.ffu') | Should -BeTrue
        Test-Path (Join-Path $e.Staging 'old.ffu') | Should -BeFalse
    }

    It 'reports an image that is already up to date' {
        Sync-FfuStaging -ConfigPath $e.ConfigPath -IncludeImage | Out-Null
        (Sync-FfuStaging -ConfigPath $e.ConfigPath -IncludeImage | Where-Object Item -eq 'Image').Status | Should -Be 'UpToDate'
    }

    It 'protects a newly copied image on Windows' {
        Mock Protect-FfuImage {}
        Sync-FfuStaging -ConfigPath $e.ConfigPath -IncludeImage | Out-Null
        Should -Invoke Protect-FfuImage -Times 1 -ParameterFilter { $UserName -eq 'SRV\deploy' }
    }

    It 'copies nothing when the source mapping is invalid JSON' {
        Set-Content (Join-Path $e.Builder 'Drivers' 'DriverMapping.json') '[{"DriverPath":"Contoso\Laptop"}]'
        { Sync-FfuStaging -ConfigPath $e.ConfigPath } | Should -Throw '*Invalid JSON*'
        Test-Path (Join-Path $e.Staging 'Drivers' 'Contoso') | Should -BeFalse
    }

    It 'skips drivers when FFU Builder downloads straight into staging' {
        $cfg = Get-Content $e.ConfigPath -Raw | ConvertFrom-Json
        $cfg | Add-Member FfuBuilderDriversPath (Join-Path $e.Staging 'Drivers')
        $cfg | ConvertTo-Json | Set-Content $e.ConfigPath
        Set-Content (Join-Path $e.Staging 'Drivers' 'DriverMapping.json') '[]'
        (Sync-FfuStaging -ConfigPath $e.ConfigPath -Mirror | Where-Object Item -eq 'Drivers').Status | Should -Be 'SameFolder'
    }

    It 'refuses to mirror an empty source' {
        Get-ChildItem (Join-Path $e.Builder 'Drivers') -Directory | Remove-Item -Recurse -Force
        New-Item -ItemType Directory -Force (Join-Path $e.Staging 'Drivers' 'Contoso' 'X') | Out-Null
        { Sync-FfuStaging -ConfigPath $e.ConfigPath -Mirror } | Should -Throw '*Refusing to mirror*'
        Test-Path (Join-Path $e.Staging 'Drivers' 'Contoso' 'X') | Should -BeTrue
    }

    It 'changes nothing with -WhatIf' {
        $r = Sync-FfuStaging -ConfigPath $e.ConfigPath -IncludeImage -WhatIf
        $r.Status | Should -Not -Contain 'Synced'
        Test-Path (Join-Path $e.Staging 'Drivers' 'Contoso') | Should -BeFalse
        Test-Path (Join-Path $e.Staging 'new.ffu') | Should -BeFalse
    }
}

Describe 'GUI script' {
    It 'parses without errors' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..' 'gui' 'FfuPxeKit-Gui.ps1'), [ref]$null, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }
}
