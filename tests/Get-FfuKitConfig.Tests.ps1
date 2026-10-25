BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'src' 'FfuPxeKit' 'Private' 'Get-FfuKitConfig.ps1')
}

Describe 'Get-FfuKitConfig' {
    It 'reads the example config' {
        $path = Join-Path $PSScriptRoot '..' 'config' 'config.example.json'
        $cfg = Get-FfuKitConfig -Path $path -WarningAction SilentlyContinue
        $cfg.KeepImages | Should -Be 3
    }

    It 'warns about remaining placeholders' {
        $path = Join-Path $PSScriptRoot '..' 'config' 'config.example.json'
        Get-FfuKitConfig -Path $path -WarningVariable w -WarningAction SilentlyContinue | Out-Null
        $w | Should -Not -BeNullOrEmpty
    }

    It 'throws when the file is missing' {
        { Get-FfuKitConfig -Path (Join-Path $TestDrive 'nope.json') } | Should -Throw '*not found*'
    }

    It 'throws when required keys are missing' {
        $p = Join-Path $TestDrive 'bad.json'
        '{ "StagingPath": "C:\\x" }' | Set-Content $p
        { Get-FfuKitConfig -Path $p } | Should -Throw '*missing required keys*'
    }
}
