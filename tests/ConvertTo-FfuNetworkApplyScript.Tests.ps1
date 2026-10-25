BeforeAll {
    $src = Join-Path $PSScriptRoot '..' 'src' 'FfuPxeKit'
    Get-ChildItem (Join-Path $src 'Private'), (Join-Path $src 'Public') -Filter *.ps1 | ForEach-Object { . $_.FullName }

    # Minimal fixture with the same structure as ApplyFFU.ps1 (not the original code)
    $script:fixture = @'
function Get-USBDrive() {
    $USBDriveLetter = 'U'
    return $USBDriveLetter + ":\"
}
$LogFileName = 'ScriptLog.txt'
$USBDrive = Get-USBDrive
$LogFile = $USBDrive + $LogFileName
'@
}

Describe 'ConvertTo-FfuNetworkApplyScript' {
    BeforeEach {
        $in  = Join-Path $TestDrive 'ApplyFFU.ps1'
        $out = Join-Path $TestDrive 'ApplyFFU.patched.ps1'
        Set-Content -LiteralPath $in -Value $fixture
        Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
    }
    AfterEach { Remove-Item Env:FFU_DEPLOY_ROOT, Env:FFU_LOG_NAME -ErrorAction SilentlyContinue }

    It 'uses FFU_DEPLOY_ROOT and FFU_LOG_NAME when set' {
        ConvertTo-FfuNetworkApplyScript -Path $in -Destination $out
        $env:FFU_DEPLOY_ROOT = 'N:\'; $env:FFU_LOG_NAME = 'ScriptLog_SN1.txt'
        . $out
        $USBDrive | Should -Be 'N:\'
        $LogFile  | Should -Be 'N:\ScriptLog_SN1.txt'
    }

    It 'keeps the original USB behaviour without the variables' {
        ConvertTo-FfuNetworkApplyScript -Path $in -Destination $out
        . $out
        $USBDrive | Should -Be 'U:\'
        $LogFile  | Should -Be 'U:\ScriptLog.txt'
    }

    It 'adds the credits header' {
        ConvertTo-FfuNetworkApplyScript -Path $in -Destination $out
        (Get-Content $out -Raw) | Should -Match 'rbalsleyMSFT'
    }

    It 'refuses to patch twice' {
        ConvertTo-FfuNetworkApplyScript -Path $in -Destination $out
        { ConvertTo-FfuNetworkApplyScript -Path $out -Destination $out } | Should -Throw '*already patched*'
    }

    It 'fails on an unknown ApplyFFU version' {
        Set-Content -LiteralPath $in -Value 'function Get-Something() { }'
        { ConvertTo-FfuNetworkApplyScript -Path $in -Destination $out } | Should -Throw '*Unsupported ApplyFFU.ps1 version*'
    }

    It 'does not write with -WhatIf' {
        ConvertTo-FfuNetworkApplyScript -Path $in -Destination $out -WhatIf
        Test-Path $out | Should -BeFalse
    }
}

Describe 'New-FfuNetworkBootImage' {
    It 'refuses to run on non-Windows' {
        Mock Test-FfuIsWindows { $false }
        { New-FfuNetworkBootImage -SourceWim 'x' -WorkPath 'y' -SharePath '\\srv\share' } | Should -Throw '*requires Windows*'
    }
    It 'validates the share path' {
        { New-FfuNetworkBootImage -SourceWim 'x' -WorkPath 'y' -SharePath 'C:\local' } | Should -Throw
    }
}

Describe 'WinPE files' {
    It 'Start-FfuNetworkDeploy.ps1 parses without errors' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..' 'winpe' 'Start-FfuNetworkDeploy.ps1'), [ref]$null, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }
    It 'startnet.cmd starts the network deployment' {
        Get-Content (Join-Path $PSScriptRoot '..' 'winpe' 'startnet.cmd') -Raw | Should -Match 'Start-FfuNetworkDeploy\.ps1'
    }
    It 'Start-FfuNetworkDeploy.ps1 never stores a password' {
        Get-Content (Join-Path $PSScriptRoot '..' 'winpe' 'Start-FfuNetworkDeploy.ps1') -Raw | Should -Not -Match '(?i)password\s*='
    }
}
