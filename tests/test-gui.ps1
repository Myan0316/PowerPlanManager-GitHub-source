[CmdletBinding()]
param([string]$SourcePath)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourcePath)) { $SourcePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\PowerPlanManager.ps1' }
. $SourcePath -LoadOnly

$script:GuiTestAssertions = 0
$script:GuiTestErrors = New-Object System.Collections.Generic.List[string]
$script:GuiTestInfo = New-Object System.Collections.Generic.List[string]
$script:GuiTestUnhandled = New-Object System.Collections.Generic.List[string]
$script:GuiTestCalls = New-Object System.Collections.Generic.List[string]
$script:GuiTestFailure = ''
$script:GuiTestQueryCount = 0
$script:GuiTestPrompt = 'GUI regression name & ! % (copy)'
$script:GuiTestConfirm = $true
$script:GuiTestImportPath = 'C:\GUI test fixtures\import.pow'
$script:GuiTestExportPath = 'C:\GUI test fixtures\export.pow'

function Assert-Gui([bool]$Condition, [string]$Message) {
    $script:GuiTestAssertions++
    if (-not $Condition) { throw ('GUI assertion {0}: {1}' -f $script:GuiTestAssertions, $Message) }
}
function Show-ErrorMessage { param([string]$Message, $Owner) $script:GuiTestErrors.Add($Message) }
function Show-InfoMessage { param([string]$Message, $Owner) $script:GuiTestInfo.Add($Message) }
function Confirm-Action { param([string]$Message, $Owner) return $script:GuiTestConfirm }
function Show-TextPrompt { param($Title, $Prompt, $InitialValue) return $script:GuiTestPrompt }
function Select-ImportPath { param([switch]$Backup) return $script:GuiTestImportPath }
function Select-ExportPath { param($Plan) return $script:GuiTestExportPath }

function New-TestHandles($Control) {
    $null = $Control.Handle
    foreach ($child in $Control.Controls) { New-TestHandles $child }
}
function Invoke-TestButton($Button) {
    $method = [System.Windows.Forms.Control].GetMethod('OnClick', [Reflection.BindingFlags]'Instance,NonPublic')
    $null = $method.Invoke($Button, @([EventArgs]::Empty))
}
function Select-TestPlan([int]$Index) {
    $script:PlanPicker.SelectedIndex = $Index
}
function Select-TestRow($Grid, [int]$Index) {
    $Grid.ClearSelection()
    $Grid.CurrentCell = $Grid.Rows[$Index].Cells[0]
    $Grid.Rows[$Index].Selected = $true
}
function Get-TestInputValue($InputControl) {
    if ($InputControl.DropDownStyle -eq [System.Windows.Forms.ComboBoxStyle]::DropDownList) {
        if ($null -eq $InputControl.SelectedItem) { return $null }
        return [string]$InputControl.SelectedItem.Value
    }
    return $InputControl.Text
}
function Assert-GuiReady {
    Assert-Gui (-not $script:UiBusy) 'UiBusy must reset after every action.'
    Assert-Gui ($script:RefreshButton.Enabled) 'Refresh must be available after every action.'
    Assert-Gui ($script:GuiTestUnhandled.Count -eq 0) ('Unhandled events: ' + ($script:GuiTestUnhandled -join '; '))
}

$testForm = $null
$editor = $null
$threadExceptionHandler = $null
try {
    $testForm = Build-MainForm
    $threadExceptionHandler = [System.Threading.ThreadExceptionEventHandler]{ param($sender, $eventArgs) $script:GuiTestUnhandled.Add($eventArgs.Exception.ToString()) }
    [System.Windows.Forms.Application]::add_ThreadException($threadExceptionHandler)
    Assert-Gui ($testForm -is [System.Windows.Forms.Form]) 'Main form has the expected type.'
    New-TestHandles $testForm
    Refresh-PlanList
    Assert-Gui ($script:PlanPicker.Items.Count -gt 0) 'Read-only live startup populates plans.'
    Assert-Gui ($script:GuiTestErrors.Count -eq 0) ('Live startup errors: ' + ($script:GuiTestErrors -join '; '))
    $livePlans = @($script:Plans)
    $liveRowCount = 0
    $liveEnums = 0
    $liveRanges = 0

    for ($planIndex = 0; $planIndex -lt $livePlans.Count; $planIndex++) {
        Select-TestPlan $planIndex
        Assert-Gui ((Get-SelectedPlan).Id -eq $livePlans[$planIndex].Id) 'Selecting a plan updates the selection.'
        Assert-Gui ($script:DetailsBox.Text.Contains($livePlans[$planIndex].Id)) 'Selecting a plan loads its own detail text.'
        $settings = @(Get-PowerSettings -Plan $livePlans[$planIndex])
        for ($cycle = 0; $cycle -lt 2; $cycle++) {
            $editor = Build-EditSettingsDialog -Plan $livePlans[$planIndex] -Settings $settings
            Assert-Gui ($editor -is [System.Windows.Forms.Form]) 'Settings builder returns a Form after its local scope exits.'
            New-TestHandles $editor
            $state = $editor.Tag
            $editor.Size = New-Object Drawing.Size(800,500)
            $editor.PerformLayout()
            Assert-Gui ($state.ApplyButton.Right -le $editor.ClientSize.Width -and $state.ApplyButton.Bottom -le $editor.ClientSize.Height) 'Minimum editor size keeps Apply reachable.'
            Assert-Gui ($state.CloseButton.Right -le $editor.ClientSize.Width -and $state.CloseButton.Bottom -le $editor.ClientSize.Height) 'Minimum editor size keeps Close reachable.'
            Assert-Gui ($state.Grid.Rows.Count -gt 0) 'The live settings grid contains rows.'
            for ($rowIndex = 0; $rowIndex -lt $state.Grid.Rows.Count; $rowIndex++) {
                Select-TestRow $state.Grid $rowIndex
                $setting = $state.Grid.Rows[$rowIndex].Tag
                Assert-Gui ((Get-TestInputValue $state.AcInput) -eq [string]$setting.AcValue) ('AC selection follows row: ' + $setting.Name)
                Assert-Gui ((Get-TestInputValue $state.DcInput) -eq [string]$setting.DcValue) ('DC selection follows row: ' + $setting.Name)
                Assert-Gui (-not [string]::IsNullOrWhiteSpace($state.RangeLabel.Text)) ('Range/choice help exists for: ' + $setting.Name)
                if (@($setting.Choices).Count -gt 0 -or (Get-FriendlySetting $setting).Time) {
                    Assert-Gui ($state.AcInput.DropDownStyle -eq [System.Windows.Forms.ComboBoxStyle]::DropDownList) 'Enumeration has a closed choice list.'
                    Assert-Gui ($state.AcInput.Items.Count -ge @($setting.Choices).Count) 'Enumeration includes all choices.'
                    $liveEnums++
                } else {
                    Assert-Gui ($state.AcInput.DropDownStyle -ne [System.Windows.Forms.ComboBoxStyle]::DropDownList) 'Numeric ranges permit text entry.'
                    $liveRanges++
                }
                $liveRowCount++
            }
            $state.Grid.ClearSelection()
            Assert-Gui (-not $state.ApplyButton.Enabled) 'Clearing grid selection disables Apply.'
            $editor.Close()
            $editor.Dispose()
            $editor = $null
            Assert-Gui ($script:GuiTestErrors.Count -eq 0) ('Live selection errors: ' + ($script:GuiTestErrors -join '; '))
            Assert-Gui ($script:GuiTestUnhandled.Count -eq 0) 'No unhandled events during settings selection/disposal.'
        }
    }
    Write-Output ('PASS live GUI: {0} plans, {1} row selections ({2} enum or time preset / {3} numeric), repeated editor open/close.' -f $livePlans.Count, $liveRowCount, $liveEnums, $liveRanges)

    # All subsequent actions are in-memory. No test below invokes a real system
    # mutation, file picker, confirmation box, or external control panel.
    $script:GuiTestPlans = @(
        [pscustomobject]@{ Id='11111111-1111-4111-8111-111111111111'; Name='active (test)'; IsActive=$true },
        [pscustomobject]@{ Id='22222222-2222-4222-8222-222222222222'; Name='inactive & ! % test'; IsActive=$false }
    )
    $script:GuiTestActive = $script:GuiTestPlans[0].Id
    $script:GuiTestSettings = @(
        [pscustomobject]@{ GroupId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'; GroupName='test'; SettingId='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'; Name='numeric'; Min=[uint64]0; Max=[uint64]100; Increment=[uint64]5; Unit='seconds'; AcValue=[uint64]10; DcValue=[uint64]20; Choices=@() },
        [pscustomobject]@{ GroupId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'; GroupName='test'; SettingId='cccccccc-cccc-4ccc-8ccc-cccccccccccc'; Name='enum'; Min=$null; Max=$null; Increment=$null; Unit=''; AcValue=[uint64]0; DcValue=[uint64]2; Choices=@([pscustomobject]@{ Value=[uint64]0; Name='off & ! %' },[pscustomobject]@{ Value=[uint64]2; Name='on (test)' }) }
    )
    function Register-TestCall([string]$Name) {
        $script:GuiTestCalls.Add($Name)
        if ($script:GuiTestFailure -eq $Name) { throw ('Injected ' + $Name + ' failure') }
    }
    function Get-PowerPlans {
        if ($script:GuiTestFailure -eq 'list') { throw 'Injected list failure' }
        return $script:GuiTestPlans
    }
    function Get-ActivePlanId { return $script:GuiTestActive }
    function Get-PowerSettings { param($Plan) return $script:GuiTestSettings }
    function Invoke-PowerCfg {
        param([string[]]$Arguments, [switch]$AllowFailure, [int]$TimeoutMilliseconds, [int]$TimeoutSeconds)
        if ($Arguments[0] -notin @('/query','/qh')) { throw ('Unexpected real-tool request in GUI test: ' + ($Arguments -join ' ')) }
        if ($script:GuiTestFailure -eq 'details') { throw 'Injected details failure' }
        $script:GuiTestQueryCount++
        return [pscustomobject]@{ ExitCode=0; StdOut=('Details for ' + $Arguments[1]); StdErr='' }
    }
    function Get-PowerPlanSnapshot {
        param($Plan,[switch]$IncludeHidden)
        $result=Invoke-PowerCfg -Arguments @('/query',$Plan.Id)
        $parseError=if($script:GuiTestFailure -eq 'parse'){'Injected parse failure'}else{''}
        return [pscustomobject]@{PlanId=$Plan.Id;RawOutput=$result.StdOut;Settings=@($script:GuiTestSettings);SettingsError=$parseError}
    }
    function Set-ManagedPowerPlan {
        param($Id)
        Register-TestCall 'enable'
        $script:GuiTestActive = $Id
    }
    function New-ManagedPowerPlan {
        param($SourceId,$Name)
        Register-TestCall 'create'
        $new = [pscustomobject]@{ Id=[guid]::NewGuid().ToString(); Name=$Name; IsActive=$false }
        $script:GuiTestPlans += $new
        return $new
    }
    function Rename-ManagedPowerPlan {
        param($Id,$Name,$ExpectedName)
        Register-TestCall 'rename'
        ($script:GuiTestPlans | Where-Object Id -eq $Id).Name = $Name
    }
    function Remove-ManagedPowerPlan {
        param($Id,$ExpectedName)
        Register-TestCall 'delete'
        $script:GuiTestPlans = @($script:GuiTestPlans | Where-Object Id -ne $Id)
        return 'C:\GUI test fixtures\backup.pow'
    }
    function Export-ManagedPowerPlan { param($Id,$Path,[switch]$Overwrite) Register-TestCall 'export'; return $Path }
    function Import-ManagedPowerPlan {
        param($Path)
        Register-TestCall 'import'
        $new = [pscustomobject]@{ Id=[guid]::NewGuid().ToString(); Name='imported'; IsActive=$false }
        $script:GuiTestPlans += $new
        return $new
    }
    function Set-ManagedPowerSetting {
        param($PlanId,$Setting,[uint64]$AcValue,[uint64]$DcValue)
        Register-TestCall 'setting'
        $Setting.AcValue = $AcValue
        $Setting.DcValue = $DcValue
        return [pscustomobject]@{ BackupPath='C:\GUI test fixtures\backup.pow'; Changed=$true; PlanId=$PlanId }
    }
    function Show-EditSettingsDialog { Register-TestCall 'editor' }
    function Open-ControlPanel { Register-TestCall 'control-panel' }

    Refresh-PlanList
    Select-TestPlan 0
    Assert-Gui (-not $script:EnableButton.Enabled) 'Current plan cannot be enabled again.'
    Assert-Gui (-not $script:DeleteButton.Enabled) 'Current plan cannot be deleted.'
    $script:PlanPicker.SelectedIndex = -1
    foreach ($button in @($script:EnableButton,$script:CreateButton,$script:RenameButton,$script:DeleteButton,$script:ExportButton,$script:EditButton)) {
        Assert-Gui (-not $button.Enabled) ('No selection disables: ' + $button.Text)
    }
    $queriesBeforeSelection=$script:GuiTestQueryCount
    Select-TestPlan 1
    Assert-Gui ($script:GuiTestQueryCount -eq $queriesBeforeSelection+1) 'Selecting a plan reads settings and details with one query.'
    $script:GuiTestFailure='parse'
    Select-TestPlan 0
    Assert-Gui ($script:DetailsBox.Text.Contains($script:GuiTestPlans[0].Id)) 'Raw technical details remain available when settings parsing fails.'
    Assert-Gui ($testForm.Tag.CommonHost.Controls[0].Text.Contains('Injected parse failure')) 'Settings parse failure appears in the common settings area.'
    $script:GuiTestFailure=''
    Select-TestPlan 1
    Assert-Gui ($script:EnableButton.Enabled -and $script:DeleteButton.Enabled) 'Inactive plan enables switch and delete.'
    $callsBefore = $script:GuiTestCalls.Count
    $script:UiBusy = $true
    $testForm.Tag.Busy = $true
    Invoke-TestButton $script:CreateButton
    Assert-Gui ($script:GuiTestCalls.Count -eq $callsBefore) 'A second click cannot start a write while the main form is busy.'
    $script:UiBusy = $false
    $testForm.Tag.Busy = $false
    Invoke-TestButton $script:EnableButton
    Assert-Gui ($script:GuiTestActive -eq '22222222-2222-4222-8222-222222222222') 'Switch button calls the managed switch operation.'
    Assert-GuiReady
    Invoke-TestButton $script:CreateButton
    Assert-Gui ($script:GuiTestPlans.Count -eq 3) 'Create button adds one copied plan.'
    Assert-GuiReady
    $script:GuiTestPrompt = 'renamed & ! % (copy)'
    Invoke-TestButton $script:RenameButton
    Assert-Gui ((Get-SelectedPlan).Name -eq $script:GuiTestPrompt) 'Rename button updates the selected plan.'
    Assert-GuiReady
    Invoke-TestButton $script:ExportButton
    Assert-Gui ($script:GuiTestCalls.Contains('export')) 'Export button reaches managed export.'
    Invoke-TestButton $script:ImportButton
    Assert-Gui ($script:GuiTestPlans.Count -eq 4) 'Import button adds one plan.'
    Invoke-TestButton $script:RestoreButton
    Assert-Gui ($script:GuiTestPlans.Count -eq 5) 'Restore backup imports as another plan.'
    Invoke-TestButton $script:EditButton
    Assert-Gui ($script:GuiTestCalls.Contains('editor')) 'Edit button opens editor.'
    Invoke-TestButton $script:ControlPanelButton
    Assert-Gui ($script:GuiTestCalls.Contains('control-panel')) 'Control-panel button uses the guarded opener.'
    Invoke-TestButton $script:RefreshButton
    Assert-GuiReady

    $beforeCount = $script:GuiTestPlans.Count
    $script:GuiTestConfirm = $false
    Invoke-TestButton $script:DeleteButton
    Assert-Gui ($script:GuiTestPlans.Count -eq $beforeCount) 'Cancelling deletion preserves plans.'
    $script:GuiTestConfirm = $true
    Invoke-TestButton $script:DeleteButton
    Assert-Gui ($script:GuiTestPlans.Count -eq ($beforeCount-1)) 'Confirmed deletion removes only one selected plan.'
    Assert-GuiReady

    $callsBefore = $script:GuiTestCalls.Count
    $script:GuiTestPrompt = $null
    Invoke-TestButton $script:CreateButton
    Invoke-TestButton $script:RenameButton
    $script:GuiTestImportPath = $null
    $script:GuiTestExportPath = $null
    Invoke-TestButton $script:ImportButton
    Invoke-TestButton $script:RestoreButton
    Invoke-TestButton $script:ExportButton
    Assert-Gui ($script:GuiTestCalls.Count -eq $callsBefore) 'Cancelled prompts and file pickers do not call write services.'
    $script:GuiTestPrompt = 'test name'
    $script:GuiTestImportPath = 'C:\GUI test fixtures\import.pow'
    $script:GuiTestExportPath = 'C:\GUI test fixtures\export.pow'

    foreach ($failureCase in @(@('enable','EnableButton'),@('create','CreateButton'),@('rename','RenameButton'),@('delete','DeleteButton'),@('export','ExportButton'),@('import','ImportButton'),@('import','RestoreButton'),@('editor','EditButton'))) {
        Refresh-PlanList
        for ($idx = 0; $idx -lt $script:PlanPicker.Items.Count; $idx++) {
            if ($script:PlanPicker.Items[$idx].Id -ne $script:GuiTestActive) { Select-TestPlan $idx; break }
        }
        $button = Get-Variable -Name $failureCase[1] -Scope Script -ValueOnly
        $errorsBefore = $script:GuiTestErrors.Count
        $script:GuiTestFailure = $failureCase[0]
        Invoke-TestButton $button
        $script:GuiTestFailure = ''
        Assert-Gui ($script:GuiTestErrors.Count -gt $errorsBefore) ('Operation failure is reported: ' + $failureCase[1])
        Assert-GuiReady
    }
    $script:GuiTestErrors.Clear()
    $script:GuiTestFailure = 'list'
    Invoke-TestButton $script:RefreshButton
    Assert-Gui ($script:GuiTestErrors.Count -eq 1) 'Refresh failure is reported exactly once.'
    foreach ($button in @($script:EnableButton,$script:CreateButton,$script:RenameButton,$script:DeleteButton,$script:ExportButton,$script:EditButton)) {
        Assert-Gui (-not $button.Enabled) ('Refresh failure invalidates stale selection: ' + $button.Text)
    }
    $script:GuiTestFailure = ''
    Invoke-TestButton $script:RefreshButton
    Assert-GuiReady
    $script:GuiTestErrors.Clear()

    $editor = Build-EditSettingsDialog -Plan $script:GuiTestPlans[0] -Settings @()
    New-TestHandles $editor
    Assert-Gui ($editor.Tag.Grid.Rows.Count -eq 0) 'An empty settings result builds an empty editor.'
    Assert-Gui (-not $editor.Tag.ApplyButton.Enabled) 'An empty editor cannot apply values.'
    $editor.Dispose()
    $editor = $null
    $unknownSettings = @(
        [pscustomobject]@{ GroupId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'; GroupName='vendor'; SettingId='dddddddd-dddd-4ddd-8ddd-dddddddddddd'; Name='unknown range'; Min=$null; Max=$null; Increment=$null; Unit=''; AcValue=[uint64]10; DcValue=[uint64]20; Choices=@() },
        [pscustomobject]@{ GroupId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'; GroupName='vendor'; SettingId='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'; Name='missing current value'; Min=[uint64]0; Max=[uint64]100; Increment=[uint64]1; Unit=''; AcValue=$null; DcValue=[uint64]20; Choices=@() }
    )
    $editor = Build-EditSettingsDialog -Plan $script:GuiTestPlans[0] -Settings $unknownSettings
    New-TestHandles $editor
    Assert-Gui ($editor.Tag.Grid.Rows.Count -eq 2) 'Incomplete metadata remains visible for inspection.'
    foreach ($rowIndex in 0,1) {
        Select-TestRow $editor.Tag.Grid $rowIndex
        Assert-Gui (-not $editor.Tag.ApplyButton.Enabled) 'Unknown or incomplete setting metadata remains read-only.'
    }
    $editor.Dispose()
    $editor = $null

    # Exercise actual editor event handlers after Build returns. This catches
    # broken event closures as well as validation and catch-boundary regressions.
    $editor = Build-EditSettingsDialog -Plan $script:GuiTestPlans[0] -Settings $script:GuiTestSettings
    New-TestHandles $editor
    $state = $editor.Tag
    Select-TestRow $state.Grid 0
    $state.AcInput.Text = '15'
    $state.DcInput.Text = '25'
    Select-TestRow $state.Grid 1
    Select-TestRow $state.Grid 0
    Assert-Gui ($state.AcInput.Text -eq '15' -and $state.DcInput.Text -eq '25') 'Unsaved input survives switching to another setting and back.'
    $script:GuiTestConfirm = $false
    $closingEvent = New-Object System.Windows.Forms.FormClosingEventArgs([System.Windows.Forms.CloseReason]::UserClosing, $false)
    $closingMethod = [System.Windows.Forms.Form].GetMethod('OnFormClosing', [Reflection.BindingFlags]'Instance,NonPublic')
    $null = $closingMethod.Invoke($editor, [object[]]@($closingEvent.PSObject.BaseObject))
    Assert-Gui ($closingEvent.Cancel) 'Declining to discard unsaved input cancels editor closing.'
    $script:GuiTestConfirm = $true
    $callsBefore = $script:GuiTestCalls.Count
    foreach ($badValue in @('abc','-1','101','7','4294967296','18446744073709551616','')) {
        $state.AcInput.Text = $badValue
        $state.DcInput.Text = '20'
        $errorsBefore = $script:GuiTestErrors.Count
        Invoke-TestButton $state.ApplyButton
        Assert-Gui ($script:GuiTestErrors.Count -gt $errorsBefore) ('Invalid numeric input produces a controlled error: ' + $badValue)
        Assert-Gui ($script:GuiTestCalls.Count -eq $callsBefore) 'Invalid input must not reach a write service.'
    }
    $state.AcInput.Text = '15'
    $state.DcInput.Text = '25'
    $script:GuiTestConfirm = $false
    Invoke-TestButton $state.ApplyButton
    Assert-Gui ($script:GuiTestCalls.Count -eq $callsBefore) 'Cancelling Apply does not write.'
    $script:GuiTestConfirm = $true
    $script:GuiTestFailure = 'setting'
    $errorsBefore = $script:GuiTestErrors.Count
    Invoke-TestButton $state.ApplyButton
    Assert-Gui ($script:GuiTestErrors.Count -gt $errorsBefore) 'Write failure is caught in the editor.'
    Assert-Gui (-not $state.Busy) 'Editor Busy resets after a failed write.'
    Assert-Gui ($state.ApplyButton.Enabled) 'Editor Apply is available after a failed write.'
    $script:GuiTestFailure = ''
    Invoke-TestButton $state.ApplyButton
    Assert-Gui ($script:GuiTestSettings[0].AcValue -eq 15 -and $script:GuiTestSettings[0].DcValue -eq 25) 'Apply writes the parsed pair through the managed service.'
    $editor.Dispose()
    $editor = $null
    Assert-Gui ($script:GuiTestUnhandled.Count -eq 0) 'No unhandled exceptions from button/selection/close events.'
    Write-Output ('PASS mocked GUI: every toolbar button, cancellation, 8 service failures, failed refresh, 7 invalid values, Apply failure/recovery; {0} assertions total.' -f $script:GuiTestAssertions)
} finally {
    if ($null -ne $editor) { $editor.Dispose() }
    if ($null -ne $testForm) { $testForm.Dispose() }
    if ($null -ne $threadExceptionHandler) { [System.Windows.Forms.Application]::remove_ThreadException($threadExceptionHandler) }
}
