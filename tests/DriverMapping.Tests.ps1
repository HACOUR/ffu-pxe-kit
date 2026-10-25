BeforeAll {
    $src = Join-Path $PSScriptRoot '..' 'src' 'FfuPxeKit'
    Get-ChildItem (Join-Path $src 'Private'), (Join-Path $src 'Public') -Filter *.ps1 | ForEach-Object { . $_.FullName }

    function New-ModelFolder([string]$Root, [string]$Rel, [switch]$Empty) {
        $p = Join-Path $Root (ConvertTo-FfuFsPath $Rel)
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        if (-not $Empty) { Set-Content (Join-Path $p 'driver.inf') 'x' }
    }
}

Describe 'Add-FfuDriverModel' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory $root | Out-Null
        $map = Join-Path $root 'DriverMapping.json'
        New-ModelFolder $root 'Contoso\Laptop 14 Gen 1 (MT01)'
    }

    It 'creates the mapping file with a JSON array for a single entry' {
        Add-FfuDriverModel -MappingPath $map -DriversRoot $root -Manufacturer Contoso -Model 'Laptop 14 Gen 1 (MT01)' -MachineType MT01 | Out-Null
        (Get-Content $map -Raw).TrimStart().StartsWith('[') | Should -BeTrue
        $m = Read-FfuDriverMapping $map
        $m.Count | Should -Be 1
        $m[0].DriverPath | Should -Be 'Contoso\Laptop 14 Gen 1 (MT01)'
    }

    It 'appends a second model' {
        New-ModelFolder $root 'Fabrikam\Notebook 15 G2'
        Add-FfuDriverModel -MappingPath $map -DriversRoot $root -Manufacturer Contoso -Model 'Laptop 14 Gen 1 (MT01)' -MachineType MT01 | Out-Null
        Add-FfuDriverModel -MappingPath $map -DriversRoot $root -Manufacturer Fabrikam -Model 'Notebook 15 G2' -MachineType MT02 | Out-Null
        (Read-FfuDriverMapping $map).Count | Should -Be 2
    }

    It 'refuses a duplicate machine type without -Force' {
        Add-FfuDriverModel -MappingPath $map -DriversRoot $root -Manufacturer Contoso -Model 'Laptop 14 Gen 1 (MT01)' -MachineType MT01 | Out-Null
        { Add-FfuDriverModel -MappingPath $map -DriversRoot $root -Manufacturer Contoso -Model 'Laptop 14 Gen 1 (MT01)' -MachineType MT01 } | Should -Throw '*already mapped*'
    }

    It 'updates an existing entry with -Force' {
        New-ModelFolder $root 'Contoso\Laptop 14 Gen 1 v2'
        Add-FfuDriverModel -MappingPath $map -DriversRoot $root -Manufacturer Contoso -Model 'Laptop 14 Gen 1 (MT01)' -MachineType MT01 | Out-Null
        Add-FfuDriverModel -MappingPath $map -DriversRoot $root -Manufacturer Contoso -Model 'Laptop 14 Gen 1 v2' -MachineType MT01 -Force | Out-Null
        $m = Read-FfuDriverMapping $map
        $m.Count | Should -Be 1
        $m[0].Model | Should -Be 'Laptop 14 Gen 1 v2'
    }

    It 'throws when the driver folder does not exist' {
        { Add-FfuDriverModel -MappingPath $map -DriversRoot $root -Manufacturer Northwind -Model 'Desktop 9' -MachineType MT09 } | Should -Throw '*not found*'
    }

    It 'changes nothing with -WhatIf' {
        Add-FfuDriverModel -MappingPath $map -DriversRoot $root -Manufacturer Contoso -Model 'Laptop 14 Gen 1 (MT01)' -MachineType MT01 -WhatIf
        Test-Path $map | Should -BeFalse
    }
}

Describe 'Test-FfuDriverMapping' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory $root | Out-Null
        $map = Join-Path $root 'DriverMapping.json'
    }

    It 'returns nothing for a consistent setup' {
        New-ModelFolder $root 'Contoso\Laptop 14 Gen 1 (MT01)'
        Add-FfuDriverModel -MappingPath $map -DriversRoot $root -Manufacturer Contoso -Model 'Laptop 14 Gen 1 (MT01)' -MachineType MT01 | Out-Null
        Test-FfuDriverMapping -MappingPath $map -DriversRoot $root | Should -BeNullOrEmpty
    }

    It 'finds a leftover duplicate model folder' {
        New-ModelFolder $root 'Contoso\Laptop 14 Gen 1 (MT01)'
        New-ModelFolder $root 'Contoso\Laptop 14 Gen 1 (Intel) (MT01)'
        Add-FfuDriverModel -MappingPath $map -DriversRoot $root -Manufacturer Contoso -Model 'Laptop 14 Gen 1 (MT01)' -MachineType MT01 | Out-Null
        $r = @(Test-FfuDriverMapping -MappingPath $map -DriversRoot $root)
        $r.Count | Should -Be 1
        $r[0].Check | Should -Be 'UnmappedFolder'
        $r[0].Item  | Should -Be 'Contoso\Laptop 14 Gen 1 (Intel) (MT01)'
    }

    It 'does not report vendors without MachineType as duplicates' {
        New-ModelFolder $root 'Fabrikam\Notebook 14 (aa01)'
        New-ModelFolder $root 'Fabrikam\Notebook 16 (aa02)'
        New-ModelFolder $root 'Microsoft\Tablet Pro 9'
        Write-FfuDriverMapping -Path $map -Entries @(
            [pscustomobject]@{ Manufacturer='Fabrikam'; Model='Notebook 14 (aa01)'; DriverPath='Fabrikam\Notebook 14 (aa01)'; SystemId='aa01' },
            [pscustomobject]@{ Manufacturer='Fabrikam'; Model='Notebook 16 (aa02)'; DriverPath='Fabrikam\Notebook 16 (aa02)'; SystemId='aa02' },
            [pscustomobject]@{ Manufacturer='Microsoft'; Model='Tablet Pro 9'; DriverPath='Microsoft\Tablet Pro 9'; SystemSku=@('SKU_1','SKU_2') }
        )
        Test-FfuDriverMapping -MappingPath $map -DriversRoot $root | Should -BeNullOrEmpty
    }

    It 'reports a duplicate SystemId' {
        New-ModelFolder $root 'Fabrikam\A'; New-ModelFolder $root 'Fabrikam\B'
        Write-FfuDriverMapping -Path $map -Entries @(
            [pscustomobject]@{ Manufacturer='Fabrikam'; Model='A'; DriverPath='Fabrikam\A'; SystemId='aa01' },
            [pscustomobject]@{ Manufacturer='Fabrikam'; Model='B'; DriverPath='Fabrikam\B'; SystemId='aa01' }
        )
        $r = @(Test-FfuDriverMapping -MappingPath $map -DriversRoot $root)
        $r.Check | Should -Contain 'DuplicateType'
        ($r | Where-Object Check -eq 'DuplicateType').Item | Should -Be 'Fabrikam|SystemId=aa01'
    }

    It 'finds missing and empty folders and duplicate machine types' {
        New-ModelFolder $root 'Contoso\A' -Empty
        Write-FfuDriverMapping -Path $map -Entries @(
            [pscustomobject]@{ Manufacturer='Contoso'; Model='A'; DriverPath='Contoso\A'; MachineType='1111' },
            [pscustomobject]@{ Manufacturer='Contoso'; Model='B'; DriverPath='Contoso\B'; MachineType='1111' }
        )
        $checks = (Test-FfuDriverMapping -MappingPath $map -DriversRoot $root).Check
        $checks | Should -Contain 'EmptyFolder'
        $checks | Should -Contain 'MissingFolder'
        $checks | Should -Contain 'DuplicateType'
    }
}
