[CmdletBinding()]
param([switch]$ListOnly, [switch]$SelfTest, [switch]$LoadOnly, [string]$StartupTestReport)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'PowerPlan.Core.ps1')
. (Join-Path $PSScriptRoot 'PowerPlan.UI.ps1')
$script:AppName = '电源计划管理器 0.3.1'
$script:MainForm = $null
$script:Plans = @()
$script:ActivePlanId = $null
$script:SelectedPlan = $null
$script:UiBusy = $false
$script:Refreshing = $false
$script:PlanPicker = $null
$script:DetailsBox = $null
$script:StatusLabel = $null
$script:ToolbarButtons = @()

function Initialize-Desktop {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
}
function Set-Status {
    param([string]$Message)
    if ($null -ne $script:StatusLabel -and -not $script:StatusLabel.IsDisposed) { $script:StatusLabel.Text = $Message }
}
function Show-ErrorMessage {
    param([string]$Message, $Owner = $null)
    if ($null -eq $Owner) { $Owner = [System.Windows.Forms.Form]::ActiveForm }
    [void][System.Windows.Forms.MessageBox]::Show($Owner,$Message,($script:AppName + ' - 操作未完成'),'OK','Error')
}
function Show-InfoMessage {
    param([string]$Message, $Owner = $null)
    if ($null -eq $Owner) { $Owner = [System.Windows.Forms.Form]::ActiveForm }
    [void][System.Windows.Forms.MessageBox]::Show($Owner,$Message,$script:AppName,'OK','Information')
}
function Confirm-Action {
    param([string]$Message, $Owner = $null)
    if ($null -eq $Owner) { $Owner = [System.Windows.Forms.Form]::ActiveForm }
    return ([System.Windows.Forms.MessageBox]::Show($Owner,$Message,$script:AppName,'YesNo','Question','Button2') -eq 'Yes')
}
function Get-SelectedPlan {
    if ($null -eq $script:PlanPicker -or $script:PlanPicker.IsDisposed) { return $null }
    return $script:PlanPicker.SelectedItem
}
function Update-PlanButtons {
    if ($null -eq $script:MainForm -or $script:MainForm.IsDisposed) { return }
    $available = -not $script:UiBusy -and -not $script:Refreshing
    $plan = Get-SelectedPlan
    $script:PlanPicker.Enabled = $available
    $script:MainForm.Tag.CommonHost.Enabled = $available -and ($null -ne $plan)
    foreach ($button in $script:ToolbarButtons) {
        $enabled = $available
        if ($button -in @($script:CreateButton,$script:EditButton,$script:RenameButton,$script:ExportButton)) { $enabled = $available -and ($null -ne $plan) }
        if ($button -eq $script:EnableButton) { $enabled = $available -and ($null -ne $plan) -and ($plan.Id -ne $script:ActivePlanId) }
        if ($button -eq $script:DeleteButton) { $enabled = $available -and ($null -ne $plan) -and ($plan.Id -ne $script:ActivePlanId) -and ($script:Plans.Count -gt 1) }
        if ($button.Enabled -ne $enabled) { $button.Enabled = $enabled }
    }
    $activeSelection = $null -ne $plan -and $plan.Id -eq $script:ActivePlanId
    $buttonText = if ($activeSelection) { '正在使用' } else { '使用这个计划' }
    $buttonName = if ($activeSelection) { 'Badge' } else { 'Primary' }
    if ($script:EnableButton.Text -ne $buttonText) { $script:EnableButton.Text = $buttonText }
    if ($script:EnableButton.Name -ne $buttonName) {
        $script:EnableButton.Name = $buttonName
        Set-ControlPalette $script:EnableButton (Get-UiPalette)
    }
}
function Invoke-UiAction {
    param([scriptblock]$Action, $Owner = $null)
    if ($null -eq $Owner) { $Owner = $script:MainForm }
    if ($null -eq $Owner -or $Owner.IsDisposed -or $Owner.Tag.Busy) { return }
    $Owner.Tag.Busy = $true
    if ($Owner -eq $script:MainForm) { $script:UiBusy = $true; Update-PlanButtons }
    $Owner.UseWaitCursor = $true
    try { $null = & $Action }
    catch { Set-Status ('操作未完成：' + $_.Exception.Message); Show-ErrorMessage -Message $_.Exception.Message -Owner $Owner }
    finally {
        $Owner.Tag.Busy = $false
        if (-not $Owner.IsDisposed) { $Owner.UseWaitCursor = $false }
        if ($Owner -eq $script:MainForm) { $script:UiBusy = $false; Update-PlanButtons }
    }
}
function Update-PlanDetails {
    if ($script:Refreshing -or $null -eq $script:MainForm -or $script:MainForm.IsDisposed) { return }
    $plan = Get-SelectedPlan; $script:SelectedPlan = $plan
    Update-PlanButtons
    $script:MainForm.Tag.BackupPlan.Text = if ($null -ne $plan) { '选中计划：' + $plan.Name } else { '请先在首页选择计划。' }
    if ($null -eq $plan) { Update-HomeSummary -Settings @(); $script:DetailsBox.Text = '请选择一个电源计划。'; return }
    try {
        $snapshot=Get-PowerPlanSnapshot -Plan $plan
        Update-HomeSummary -Settings $snapshot.Settings -SettingsError $snapshot.SettingsError
        $script:DetailsBox.Text=$snapshot.RawOutput
    } catch {
        Update-HomeSummary -Settings @() -SettingsError $_.Exception.Message
        $script:DetailsBox.Text = '无法读取计划详情：' + $_.Exception.Message
        throw
    }
}
function Refresh-PlanList {
    param([string]$PreferredId)
    if (-not $PreferredId -and $null -ne $script:SelectedPlan) { $PreferredId = $script:SelectedPlan.Id }
    $script:Refreshing = $true
    try {
        Set-Status '正在读取电源计划…'
        $freshPlans = @(Get-PowerPlans); $freshActive = Get-ActivePlanId
        if ($freshActive -notin @($freshPlans.Id)) { throw '活动计划已发生变化，请重新刷新。' }
        $script:Plans = $freshPlans; $script:ActivePlanId = $freshActive
        if ($PreferredId -notin @($freshPlans.Id)) { $PreferredId = $freshActive }
        $script:PlanPicker.BeginUpdate()
        try {
            $script:PlanPicker.Items.Clear()
            foreach ($plan in $freshPlans) {
                $display = $plan.Name
                if (@($freshPlans | Where-Object Name -eq $plan.Name).Count -gt 1) { $display += ' [' + $plan.Id + ']' }
                if ($plan.Id -eq $freshActive) { $display += ' · 使用中' }
                $item = [pscustomobject]@{Id=$plan.Id;Name=$plan.Name;DisplayName=$display;IsActive=($plan.Id -eq $freshActive)}
                $index = $script:PlanPicker.Items.Add($item)
                if ($plan.Id -eq $PreferredId) { $script:PlanPicker.SelectedIndex = $index }
            }
        } finally { $script:PlanPicker.EndUpdate() }
    } catch {
        $script:Plans = @(); $script:ActivePlanId = $null; $script:SelectedPlan = $null
        $script:PlanPicker.Items.Clear(); $script:DetailsBox.Text = '读取失败，请刷新后再操作。'
        Update-HomeSummary
        $script:MainForm.Tag.BackupPlan.Text = '计划状态未知，请刷新。'
        Set-Status ('读取失败：' + $_.Exception.Message); throw
    } finally { $script:Refreshing = $false; Update-PlanButtons }
    Update-PlanDetails
    $activeName = @($script:Plans | Where-Object Id -eq $script:ActivePlanId)[0].Name
    Set-Status ('已读取 {0} 个计划。正在使用：{1}' -f $script:Plans.Count,$activeName)
}
function Show-TextPrompt {
    param([string]$Title,[string]$Prompt,[string]$InitialValue = '')
    $dialog = New-Object System.Windows.Forms.Form
    try {
        $dialog.Text = $Title; $dialog.StartPosition = 'CenterParent'; $dialog.FormBorderStyle = 'FixedDialog'
        $dialog.MinimizeBox = $false; $dialog.MaximizeBox = $false
        $dialog.ClientSize = New-Object System.Drawing.Size(480,150)
        $dialog.Font = New-Object System.Drawing.Font('Microsoft YaHei UI',9)
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $Prompt; $label.AutoSize = $true; $label.Location = New-Object System.Drawing.Point(14,14)
        $inputBox = New-Object System.Windows.Forms.TextBox
        $inputBox.Text = $InitialValue; $inputBox.MaxLength = 128; $inputBox.Width = 450; $inputBox.Location = New-Object System.Drawing.Point(14,44)
        $ok = New-Object System.Windows.Forms.Button
        $ok.Text = '确定'; $ok.DialogResult = 'OK'; $ok.Location = New-Object System.Drawing.Point(300,95)
        $cancel = New-Object System.Windows.Forms.Button
        $cancel.Text = '取消'; $cancel.DialogResult = 'Cancel'; $cancel.Location = New-Object System.Drawing.Point(386,95)
        $dialog.Controls.AddRange(@($label,$inputBox,$ok,$cancel)); $dialog.AcceptButton = $ok; $dialog.CancelButton = $cancel
        Set-WindowPalette $dialog (Get-UiPalette)
        if ($dialog.ShowDialog($script:MainForm) -eq 'OK') { return $inputBox.Text.Trim() }
        return $null
    } finally { $dialog.Dispose() }
}
function Select-ExportPath {
    param($Plan)
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    try {
        $dialog.Filter = '电源计划文件 (*.pow)|*.pow'; $dialog.DefaultExt = 'pow'; $dialog.AddExtension = $true
        $dialog.FileName = (($Plan.Name -replace '[\\/:*?"<>|\x00-\x1f]','_') + '.pow')
        $dialog.OverwritePrompt = $false; $dialog.Title = '导出电源计划备份'
        if ($dialog.ShowDialog($script:MainForm) -eq 'OK') { return $dialog.FileName }; return $null
    } finally { $dialog.Dispose() }
}
function Select-ImportPath {
    param([switch]$Backup)
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    try {
        $dialog.Filter = '电源计划文件 (*.pow)|*.pow'; $dialog.CheckFileExists = $true
        $dialog.Title = if ($Backup) { '选择备份（恢复为新计划，不覆盖现有计划）' } else { '导入电源计划（创建新计划）' }
        $backupFolder = Join-Path $env:LOCALAPPDATA 'PowerPlanManager\Backups'
        if ($Backup -and (Test-Path -LiteralPath $backupFolder)) { $dialog.InitialDirectory = $backupFolder }
        if ($dialog.ShowDialog($script:MainForm) -eq 'OK') { return $dialog.FileName }; return $null
    } finally { $dialog.Dispose() }
}
function Enable-SelectedPlan {
    $plan = Get-SelectedPlan; if ($null -eq $plan) { return }
    Set-ManagedPowerPlan -Id $plan.Id | Out-Null
    Refresh-PlanList -PreferredId $plan.Id; Set-Status ('已核对当前启用：' + $plan.Name)
}
function Create-CopiedPlan {
    $plan = Get-SelectedPlan; if ($null -eq $plan) { return }
    $name = Show-TextPrompt '创建电源计划' '新计划名称（复制选中的计划）：' ($plan.Name + ' - 副本')
    if ($null -eq $name) { return }
    $created = New-ManagedPowerPlan -SourceId $plan.Id -Name $name
    Refresh-PlanList -PreferredId $created.Id; Set-Status ('已创建，尚未启用：' + $created.Name)
}
function Rename-SelectedPlan {
    $plan = Get-SelectedPlan; if ($null -eq $plan) { return }
    $name = Show-TextPrompt '重命名电源计划' '请输入新的计划名称：' $plan.Name
    if ($null -eq $name) { return }
    Rename-ManagedPowerPlan -Id $plan.Id -Name $name -ExpectedName $plan.Name | Out-Null
    Refresh-PlanList -PreferredId $plan.Id; Set-Status '已核对计划名称。'
}
function Delete-SelectedPlan {
    $plan = Get-SelectedPlan; if ($null -eq $plan) { return }
    if (-not (Confirm-Action ("删除计划：{0}`r`n{1}`r`n`r`n删除前自动备份，备份失败则停止。" -f $plan.Name,$plan.Id))) { return }
    $backup = Remove-ManagedPowerPlan -Id $plan.Id -ExpectedName $plan.Name
    Refresh-PlanList; Set-Status ('已删除。备份：' + $backup)
}
function Export-SelectedPlan {
    $plan = Get-SelectedPlan; if ($null -eq $plan) { return }
    $path = Select-ExportPath -Plan $plan; if (-not $path) { return }
    $overwrite = Test-Path -LiteralPath $path
    if ($overwrite -and -not (Confirm-Action ('覆盖已有文件？' + "`r`n" + $path))) { return }
    Export-ManagedPowerPlan -Id $plan.Id -Path $path -Overwrite:$overwrite | Out-Null
    Set-Status ('已导出并核对备份：' + $path)
}
function Import-PlanFile {
    $path = Select-ImportPath; if (-not $path) { return }
    $plan = Import-ManagedPowerPlan -Path $path
    Refresh-PlanList -PreferredId $plan.Id; Set-Status ('已导入新计划，未自动启用：' + $plan.Name)
}
function Restore-PlanBackup {
    $path = Select-ImportPath -Backup; if (-not $path) { return }
    if (-not (Confirm-Action ("从备份恢复为新计划，不覆盖现有计划，也不自动启用。`r`n" + $path))) { return }
    $plan = Import-ManagedPowerPlan -Path $path
    Refresh-PlanList -PreferredId $plan.Id; Set-Status ('已恢复为新计划，未自动启用：' + $plan.Name)
}
function Open-ControlPanel {
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\control.exe') -ArgumentList '/name Microsoft.PowerOptions' | Out-Null
}
function Get-SettingKey { param($Setting) return ($Setting.GroupId + '/' + $Setting.SettingId) }
function Read-EditorInput {
    param($InputControl)
    if ($InputControl.DropDownStyle -eq 'DropDownList' -and $null -ne $InputControl.SelectedItem) { return [string]$InputControl.SelectedItem.Value }
    return $InputControl.Text.Trim()
}
function Save-EditorDraft {
    param($Dialog)
    $state = $Dialog.Tag
    if ($state.Loading -or $state.Closing -or $null -eq $state.CurrentSetting) { return }
    $key = Get-SettingKey $state.CurrentSetting
    $ac = Read-EditorInput $state.AcInput; $dc = Read-EditorInput $state.DcInput
    if ($ac -eq [string]$state.CurrentSetting.AcValue -and $dc -eq [string]$state.CurrentSetting.DcValue) { $state.Drafts.Remove($key) }
    else { $state.Drafts[$key] = [pscustomobject]@{Ac=$ac; Dc=$dc} }
}
function Set-EditorInput {
    param($InputControl,$Setting,[string]$Value,[switch]$Raw)
    $InputControl.Items.Clear()
    if ((Get-FriendlySetting $Setting).Time -and -not $Raw) { Set-FriendlyTimeInput $InputControl $Setting $Value; return }
    if ($null -ne $Setting.Choices -and $Setting.Choices.Count -gt 0) {
        $InputControl.DropDownStyle = 'DropDownList'; $InputControl.DisplayMember = 'Name'
        foreach ($choice in $Setting.Choices) {
            $display = [pscustomobject]@{Value=$choice.Value; Name=$choice.Name}
            $index = $InputControl.Items.Add($display)
            if ([string]$choice.Value -eq $Value) { $InputControl.SelectedIndex = $index }
        }
        if ($InputControl.SelectedIndex -lt 0) { $InputControl.SelectedIndex = $InputControl.Items.Add([pscustomobject]@{Value=$Value; Name=('未知当前值：' + $Value)}) }
    } else { $InputControl.DropDownStyle = 'DropDown'; $InputControl.Text = $Value }
}
function Update-SettingEditor {
    param($Dialog)
    if ($null -eq $Dialog -or $Dialog.IsDisposed -or $Dialog.Disposing -or $Dialog.Tag.Closing -or $Dialog.Tag.Loading) { return }
    $state = $Dialog.Tag; Save-EditorDraft $Dialog; $state.Loading = $true
    try {
        $state.CurrentSetting = $null; $state.ApplyButton.Enabled = $false
        $state.AcInput.Enabled = $false; $state.DcInput.Enabled = $false
        $state.InfoLabel.Text = '选择一项设置查看说明。'; $state.RangeLabel.Text = ''; $state.IdLabel.Text = ''; $state.RawToggle.Enabled = $false
        if ($state.Grid.SelectedRows.Count -ne 1 -or $null -eq $state.Grid.SelectedRows[0].Tag) { return }
        $setting = $state.Grid.SelectedRows[0].Tag; $state.CurrentSetting = $setting
        $ac = [string]$setting.AcValue; $dc = [string]$setting.DcValue; $key = Get-SettingKey $setting
        if ($state.Drafts.ContainsKey($key)) { $ac = $state.Drafts[$key].Ac; $dc = $state.Drafts[$key].Dc }
        Set-EditorInput $state.AcInput $setting $ac -Raw:$state.RawInput; Set-EditorInput $state.DcInput $setting $dc -Raw:$state.RawInput
        $acProblem = if ($null -eq $setting.AcValue) { '无法读取接通电源的当前值。' } else { Test-PowerSettingValue $setting $setting.AcValue }
        $dcProblem = if ($null -eq $setting.DcValue) { '无法读取电池的当前值。' } else { Test-PowerSettingValue $setting $setting.DcValue }
        $canEdit = (-not $acProblem -and -not $dcProblem)
        $state.AcInput.Enabled = $canEdit; $state.DcInput.Enabled = $canEdit; $state.ApplyButton.Enabled = $canEdit
        if ($null -ne $setting.Choices -and $setting.Choices.Count -gt 0) { $state.RangeLabel.Text = (@($setting.Choices | ForEach-Object { '{0} = {1}' -f $_.Value,$_.Name }) -join '；') }
        else { $state.RangeLabel.Text = ('范围：{0} 至 {1}；步长：{2}；单位：{3}' -f $setting.Min,$setting.Max,$setting.Increment,$setting.Unit) }
        $friendly = Get-FriendlySetting $setting
        $state.RawToggle.Enabled = $canEdit -and $friendly.Time
        $state.InfoLabel.Text = if ($canEdit) { $friendly.Description + ' 切换分类或设置会保留草稿。' } else { '此项只读：' + ((@($acProblem,$dcProblem) | Where-Object { $_ } | Select-Object -Unique) -join '；') }
        $state.IdLabel.Text = '系统设置：' + $setting.Name + "`r`n" + $setting.SettingId
    } finally { $state.Loading = $false }
}
function Apply-EditorSetting {
    param($Dialog)
    $state = $Dialog.Tag
    if ($null -eq $state.CurrentSetting -or -not $state.ApplyButton.Enabled) { return }
    $setting = $state.CurrentSetting; Save-EditorDraft $Dialog
    $acText = Read-EditorInput $state.AcInput; $dcText = Read-EditorInput $state.DcInput
    [uint64]$ac = 0; [uint64]$dc = 0
    if (-not [uint64]::TryParse($acText,[Globalization.NumberStyles]::None,[Globalization.CultureInfo]::InvariantCulture,[ref]$ac) -or -not [uint64]::TryParse($dcText,[Globalization.NumberStyles]::None,[Globalization.CultureInfo]::InvariantCulture,[ref]$dc)) { throw '请输入有效的非负十进制整数。' }
    $acProblem = Test-PowerSettingValue $setting $ac; $dcProblem = Test-PowerSettingValue $setting $dc
    if ($acProblem -or $dcProblem) { throw ((@($acProblem,$dcProblem) | Where-Object { $_ }) -join "`r`n") }
    if ($ac -eq $setting.AcValue -and $dc -eq $setting.DcValue) { Show-InfoMessage '数值没有变化，无需写入。' $Dialog; return }
    if (-not (Confirm-Action -Owner $Dialog -Message ("计划：{0}`r`n设置：{1}`r`n接通电源：{2} → {3}`r`n使用电池：{4} → {5}`r`n`r`n备份成功后应用，是否继续？" -f $state.Plan.Name,(Get-FriendlySetting $setting).Name,(Format-SettingValue $setting $setting.AcValue),(Format-SettingValue $setting $ac),(Format-SettingValue $setting $setting.DcValue),(Format-SettingValue $setting $dc)))) { return }
    $result = Set-ManagedPowerSetting -PlanId $state.Plan.Id -Setting $setting -AcValue $ac -DcValue $dc
    $setting.AcValue = $ac; $setting.DcValue = $dc; $state.Drafts.Remove((Get-SettingKey $setting))
    $state.Grid.SelectedRows[0].Cells[2].Value = Format-SettingValue $setting $ac; $state.Grid.SelectedRows[0].Cells[3].Value = Format-SettingValue $setting $dc
    Show-InfoMessage -Owner $Dialog -Message ('已读回核对。备份：' + $result.BackupPath)
}
function Build-EditSettingsDialog {
    param($Plan,[object[]]$Settings)
    return New-PowerEditor -Plan $Plan -Settings $Settings
}
function Show-EditSettingsDialog {
    $plan = Get-SelectedPlan; if ($null -eq $plan) { return }
    $settings = @(Get-PowerSettings -Plan $plan)
    if ($settings.Count -eq 0) { throw '没有读取到可展示的设置，当前系统语言或设置格式可能不受支持。' }
    $dialog = Build-EditSettingsDialog -Plan $plan -Settings $settings
    try { [void]$dialog.ShowDialog($script:MainForm) } finally { $dialog.Tag.Closing = $true; $dialog.Dispose() }
    Refresh-PlanList -PreferredId $plan.Id
}
function Build-MainForm { return New-PowerMainForm }
function Start-Application {
    $form = Build-MainForm
    $startupTimer = $null
    if ($StartupTestReport) {
        Add-Type -TypeDefinition 'public static class StartupWindowCheck { [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr hwnd); [System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow(); }'
        $script:StartupReportPath = $StartupTestReport
        $startupTimer = New-Object System.Windows.Forms.Timer
        $startupTimer.Interval = 1500
        $startupTimer.Add_Tick({
            param($sender,$eventArgs)
            $sender.Stop()
            try {
                $report = [pscustomobject]@{ Title=$script:MainForm.Text; Visible=$script:MainForm.Visible; NativeVisible=[StartupWindowCheck]::IsWindowVisible($script:MainForm.Handle); ConsoleAttached=([StartupWindowCheck]::GetConsoleWindow() -ne [IntPtr]::Zero); Plans=$script:PlanPicker.Items.Count; Selected=[int]($script:PlanPicker.SelectedIndex -ge 0); Details=$script:DetailsBox.Text.Length; Status=$script:StatusLabel.Text }
                [IO.File]::WriteAllText($script:StartupReportPath,($report | ConvertTo-Json),(New-Object Text.UTF8Encoding($true)))
            } finally { $script:MainForm.Close() }
        })
        $startupTimer.Start()
    }
    try { [void]$form.ShowDialog() } finally { if ($null -ne $startupTimer) { $startupTimer.Dispose() }; $script:Refreshing = $true; $form.Dispose() }
}
if ($LoadOnly) { return }
if ($ListOnly -or $SelfTest) {
    try {
        $plans = @(Get-PowerPlans); $active = Get-ActivePlanId
        if ($active -notin @($plans.Id)) { throw '当前活动计划不在计划列表中。' }
        if ($ListOnly) { foreach ($plan in $plans) { '{0} {1} [{2}]' -f $(if ($plan.Id -eq $active) {'*'} else {' '}),$plan.Name,$plan.Id } }
        else { 'SelfTest passed: {0} plans; active={1}' -f $plans.Count,$active }
        exit 0
    } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }
}
try { Start-Application } catch { Initialize-Desktop; Show-ErrorMessage $_.Exception.Message; exit 1 }
