<#
.SYNOPSIS
Small window with buttons for the daily ffu-pxe-kit tasks (Windows only).
Start: right-click > Run with PowerShell, or a desktop shortcut:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<path>\gui\FfuPxeKit-Gui.ps1"
#>
param([string]$ConfigPath = [IO.Path]::Combine($PSScriptRoot, '..', 'config', 'config.json'))

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Import-Module ([IO.Path]::Combine($PSScriptRoot, '..', 'src', 'FfuPxeKit', 'FfuPxeKit.psm1')) -Force

$form = New-Object System.Windows.Forms.Form
$form.Text = 'ffu-pxe-kit (beta)'
$form.Size = New-Object System.Drawing.Size(760, 520)
$form.StartPosition = 'CenterScreen'

$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true; $log.ScrollBars = 'Vertical'; $log.ReadOnly = $true
$log.Font = New-Object System.Drawing.Font('Consolas', 9)
$log.Location = New-Object System.Drawing.Point(10, 60); $log.Size = New-Object System.Drawing.Size(725, 410)
$log.Anchor = 'Top, Bottom, Left, Right'
$form.Controls.Add($log)

function Add-GuiLog([string]$Text) { $log.AppendText("$Text`r`n"); [System.Windows.Forms.Application]::DoEvents() }

function Invoke-Action([string]$Title, [scriptblock]$Action) {
    $form.Cursor = 'WaitCursor'
    Add-GuiLog "=== $Title - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
    try { Add-GuiLog ((& $Action | Format-Table -AutoSize | Out-String -Width 200).TrimEnd()) }
    catch { Add-GuiLog "ERROR: $($_.Exception.Message)" }
    finally { $form.Cursor = 'Default'; Add-GuiLog '' }
}

$buttons = @(
    @{ Text = 'Sync drivers';               Action = { Sync-FfuStaging -ConfigPath $ConfigPath } },
    @{ Text = 'Sync drivers + newest image'; Action = { Sync-FfuStaging -ConfigPath $ConfigPath -IncludeImage } },
    @{ Text = 'Health check';               Action = { Test-FfuEnvironment -ConfigPath $ConfigPath } }
)
$x = 10
foreach ($b in $buttons) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $b.Text; $btn.Location = New-Object System.Drawing.Point($x, 15); $btn.Size = New-Object System.Drawing.Size(230, 32)
    # Keep title/action on the button itself. GetNewClosure() would move the handler into a
    # separate module scope where the script's functions (Invoke-Action) are not visible.
    $btn.Tag = $b
    $btn.Add_Click({ Invoke-Action $this.Tag.Text $this.Tag.Action })   # $this = clicked button
    $form.Controls.Add($btn)
    $x += 240
}

Add-GuiLog "Config: $ConfigPath"
[void]$form.ShowDialog()
