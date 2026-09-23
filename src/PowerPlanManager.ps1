[CmdletBinding()]
param([switch]$ListOnly, [switch]$SelfTest, [switch]$LoadOnly, [string]$StartupTestReport)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'PowerPlan.Core.ps1')
$script:AppName = '电源计划管理器 0.2.0'
$script:MainForm = $null
$script:Plans = @()
$script:ActivePlanId = $null
$script:SelectedPlan = $null
$script:UiBusy = $false
$script:Refreshing = $false
$script:PlanList = $null
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
    if ($null -eq $script:PlanList -or $script:PlanList.IsDisposed -or $script:PlanList.SelectedItems.Count -ne 1) { return $null }
    return $script:PlanList.SelectedItems[0].Tag
}
function Update-PlanButtons {
    if ($null -eq $script:MainForm -or $script:MainForm.IsDisposed) { return }
    $available = -not $script:UiBusy -and -not $script:Refreshing
    $plan = Get-SelectedPlan
    foreach ($button in $script:ToolbarButtons) { $button.Enabled = $available }
    foreach ($button in @($script:CreateButton,$script:EditButton,$script:RenameButton,$script:ExportButton)) { $button.Enabled = $available -and ($null -ne $plan) }
    $script:EnableButton.Enabled = $available -and ($null -ne $plan) -and ($plan.Id -ne $script:ActivePlanId)
    $script:DeleteButton.Enabled = $available -and ($null -ne $plan) -and ($plan.Id -ne $script:ActivePlanId) -and ($script:Plans.Count -gt 1)
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
    if ($null -eq $plan) { $script:DetailsBox.Text = '请选择一个电源计划。'; return }
    try { $query = Invoke-PowerCfg -Arguments @('/query',$plan.Id); $script:DetailsBox.Text = $query.StdOut }
    catch { $script:DetailsBox.Text = '无法读取计划详情：' + $_.Exception.Message; throw }
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
        $script:PlanList.BeginUpdate()
        try {
            $script:PlanList.Items.Clear()
            foreach ($plan in $freshPlans) {
                $mark = if ($plan.Id -eq $freshActive) { '当前' } else { '' }
                $row = New-Object System.Windows.Forms.ListViewItem($mark)
                [void]$row.SubItems.Add($plan.Name); [void]$row.SubItems.Add($plan.Id)
                $row.Tag = $plan; [void]$script:PlanList.Items.Add($row)
                if ($plan.Id -eq $PreferredId) { $row.Selected = $true }
            }
        } finally { $script:PlanList.EndUpdate() }
    } catch {
        $script:Plans = @(); $script:ActivePlanId = $null; $script:SelectedPlan = $null
        $script:PlanList.Items.Clear(); $script:DetailsBox.Text = '读取失败，请刷新后再操作。'
        Set-Status ('读取失败：' + $_.Exception.Message); throw
    } finally { $script:Refreshing = $false; Update-PlanButtons }
    Update-PlanDetails
    Set-Status ('已读取 {0} 个计划。当前：{1}' -f $script:Plans.Count,$script:ActivePlanId)
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
    param($InputControl,$Setting,[string]$Value)
    $InputControl.Items.Clear()
    if ($null -ne $Setting.Choices -and $Setting.Choices.Count -gt 0) {
        $InputControl.DropDownStyle = 'DropDownList'; $InputControl.DisplayMember = 'Name'
        foreach ($choice in $Setting.Choices) {
            $display = [pscustomobject]@{Value=$choice.Value; Name=('{0} = {1}' -f $choice.Value,$choice.Name)}
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
        if ($state.Grid.SelectedRows.Count -ne 1 -or $null -eq $state.Grid.SelectedRows[0].Tag) { return }
        $setting = $state.Grid.SelectedRows[0].Tag; $state.CurrentSetting = $setting
        $ac = [string]$setting.AcValue; $dc = [string]$setting.DcValue; $key = Get-SettingKey $setting
        if ($state.Drafts.ContainsKey($key)) { $ac = $state.Drafts[$key].Ac; $dc = $state.Drafts[$key].Dc }
        Set-EditorInput $state.AcInput $setting $ac; Set-EditorInput $state.DcInput $setting $dc
        $acProblem = if ($null -eq $setting.AcValue) { '无法读取接通电源的当前值。' } else { Test-PowerSettingValue $setting $setting.AcValue }
        $dcProblem = if ($null -eq $setting.DcValue) { '无法读取电池的当前值。' } else { Test-PowerSettingValue $setting $setting.DcValue }
        $canEdit = (-not $acProblem -and -not $dcProblem)
        $state.AcInput.Enabled = $canEdit; $state.DcInput.Enabled = $canEdit; $state.ApplyButton.Enabled = $canEdit
        if ($null -ne $setting.Choices -and $setting.Choices.Count -gt 0) { $state.RangeLabel.Text = (@($setting.Choices | ForEach-Object { '{0} = {1}' -f $_.Value,$_.Name }) -join '；') }
        else { $state.RangeLabel.Text = ('范围：{0} 至 {1}；步长：{2}；单位：{3}' -f $setting.Min,$setting.Max,$setting.Increment,$setting.Unit) }
        $state.InfoLabel.Text = if ($canEdit) { '按系统定义校验。切换设置时保留未保存输入。' } else { '此项只读：' + ((@($acProblem,$dcProblem) | Where-Object { $_ } | Select-Object -Unique) -join '；') }
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
    if (-not (Confirm-Action -Owner $Dialog -Message ("计划：{0}`r`n设置：{1}`r`n接通电源：{2} → {3}`r`n使用电池：{4} → {5}`r`n`r`n备份成功后应用，是否继续？" -f $state.Plan.Name,$setting.Name,$setting.AcValue,$ac,$setting.DcValue,$dc))) { return }
    $result = Set-ManagedPowerSetting -PlanId $state.Plan.Id -Setting $setting -AcValue $ac -DcValue $dc
    $setting.AcValue = $ac; $setting.DcValue = $dc; $state.Drafts.Remove((Get-SettingKey $setting))
    $state.Grid.SelectedRows[0].Cells[2].Value = $ac; $state.Grid.SelectedRows[0].Cells[3].Value = $dc
    Show-InfoMessage -Owner $Dialog -Message ('已读回核对。备份：' + $result.BackupPath)
}
function Build-EditSettingsDialog {
    param($Plan,[object[]]$Settings)
    Initialize-Desktop
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = '修改设置：' + $Plan.Name; $dialog.StartPosition = 'CenterParent'
    $dialog.MinimumSize = New-Object System.Drawing.Size(900,560); $dialog.ClientSize = New-Object System.Drawing.Size(980,620)
    # Keep every input and the Apply/Close buttons reachable at minimum size.
    $dialog.MinimumSize = $dialog.Size
    $dialog.Font = New-Object System.Drawing.Font('Microsoft YaHei UI',9)
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = 'Top'; $grid.Height = 390; $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false; $grid.AllowUserToDeleteRows = $false; $grid.MultiSelect = $false
    $grid.SelectionMode = 'FullRowSelect'; $grid.AutoGenerateColumns = $false
    foreach ($column in @(@('设置',230),@('分类',135),@('交流值',70),@('直流值',70),@('单位',65),@('GUID',255))) {
        $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $c.HeaderText = $column[0]; $c.Width = $column[1]; $c.SortMode = 'NotSortable'; [void]$grid.Columns.Add($c)
    }
    foreach ($setting in $Settings) {
        $rowIndex = $grid.Rows.Add([object[]]@($setting.Name,$setting.GroupName,$setting.AcValue,$setting.DcValue,$setting.Unit,$setting.SettingId))
        $grid.Rows[$rowIndex].Tag = $setting
    }
    $info = New-Object System.Windows.Forms.Label
    $info.Location = New-Object System.Drawing.Point(12,400); $info.Size = New-Object System.Drawing.Size(930,35)
    $acLabel = New-Object System.Windows.Forms.Label
    $acLabel.Text = '接通电源'; $acLabel.AutoSize = $true; $acLabel.Location = New-Object System.Drawing.Point(12,450)
    $dcLabel = New-Object System.Windows.Forms.Label
    $dcLabel.Text = '使用电池'; $dcLabel.AutoSize = $true; $dcLabel.Location = New-Object System.Drawing.Point(400,450)
    $acInput = New-Object System.Windows.Forms.ComboBox
    $acInput.Location = New-Object System.Drawing.Point(85,446); $acInput.Width = 290
    $dcInput = New-Object System.Windows.Forms.ComboBox
    $dcInput.Location = New-Object System.Drawing.Point(473,446); $dcInput.Width = 290
    $range = New-Object System.Windows.Forms.Label
    $range.Location = New-Object System.Drawing.Point(12,487); $range.Size = New-Object System.Drawing.Size(930,60)
    $apply = New-Object System.Windows.Forms.Button
    $apply.Text = '应用当前设置'; $apply.Width = 125; $apply.Location = New-Object System.Drawing.Point(820,564)
    $close = New-Object System.Windows.Forms.Button
    $close.Text = '关闭'; $close.Location = New-Object System.Drawing.Point(730,564); $close.DialogResult = 'Cancel'
    $dialog.Controls.AddRange(@($grid,$info,$acLabel,$dcLabel,$acInput,$dcInput,$range,$apply,$close)); $dialog.CancelButton = $close
    $dialog.Tag = [pscustomobject]@{Plan=$Plan; Grid=$grid; AcInput=$acInput; DcInput=$dcInput; ApplyButton=$apply; CloseButton=$close; InfoLabel=$info; RangeLabel=$range; Busy=$false; Loading=$false; Closing=$false; CurrentSetting=$null; Drafts=@{}}
    $grid.Add_SelectionChanged({
        param($sender,$eventArgs)
        $owner = $sender.FindForm()
        try { Update-SettingEditor -Dialog $owner }
        catch { if ($null -ne $owner -and -not $owner.IsDisposed) { $owner.Tag.ApplyButton.Enabled = $false; Show-ErrorMessage $_.Exception.Message $owner } }
    })
    $apply.Add_Click({ param($sender,$eventArgs) $owner = $sender.FindForm(); Invoke-UiAction -Owner $owner -Action { Apply-EditorSetting -Dialog $owner } })
    $dialog.Add_FormClosing({
        param($sender,$eventArgs)
        try {
            Save-EditorDraft $sender
            if ($sender.Tag.Drafts.Count -gt 0 -and -not (Confirm-Action -Owner $sender -Message '还有未应用的修改。放弃这些修改并关闭？')) { $eventArgs.Cancel = $true; return }
            $sender.Tag.Closing = $true
        } catch { $eventArgs.Cancel = $true; Show-ErrorMessage $_.Exception.Message $sender }
    })
    if ($grid.Rows.Count -gt 0) { $grid.Rows[0].Selected = $true }
    Update-SettingEditor $dialog
    return $dialog
}
function Show-EditSettingsDialog {
    $plan = Get-SelectedPlan; if ($null -eq $plan) { return }
    $settings = @(Get-PowerSettings -Plan $plan)
    if ($settings.Count -eq 0) { throw '没有读取到可展示的设置，当前系统语言或设置格式可能不受支持。' }
    $dialog = Build-EditSettingsDialog -Plan $plan -Settings $settings
    try { [void]$dialog.ShowDialog($script:MainForm) } finally { $dialog.Tag.Closing = $true; $dialog.Dispose() }
    Refresh-PlanList -PreferredId $plan.Id
}
function Build-MainForm {
    Initialize-Desktop
    $script:Refreshing = $false; $script:UiBusy = $false
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $script:AppName; $form.StartPosition = 'CenterScreen'
    $form.MinimumSize = New-Object System.Drawing.Size(900,560); $form.ClientSize = New-Object System.Drawing.Size(1120,720)
    $form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI',9)
    $form.Tag = [pscustomobject]@{Busy=$false}; $script:MainForm = $form
    $toolbar = New-Object System.Windows.Forms.FlowLayoutPanel
    $toolbar.Dock = 'Top'; $toolbar.Height = 50; $toolbar.AutoScroll = $true
    $toolbar.Padding = New-Object System.Windows.Forms.Padding(8,8,8,4); $toolbar.WrapContents = $false
    $form.Controls.Add($toolbar); $script:ToolbarButtons = @()
    function Add-ToolbarButton {
        param([string]$Text,[scriptblock]$Handler)
        $button = New-Object System.Windows.Forms.Button
        $button.Text = $Text; $button.AutoSize = $true; $button.Height = 28; $button.Tag = $Handler
        $button.Add_Click({ param($sender,$eventArgs) Invoke-UiAction -Owner $sender.FindForm() -Action $sender.Tag })
        $toolbar.Controls.Add($button); $script:ToolbarButtons += $button; return $button
    }
    $script:RefreshButton = Add-ToolbarButton '刷新' { Refresh-PlanList }
    $script:EnableButton = Add-ToolbarButton '启用选中计划' { Enable-SelectedPlan }
    $script:CreateButton = Add-ToolbarButton '创建副本' { Create-CopiedPlan }
    $script:RenameButton = Add-ToolbarButton '重命名' { Rename-SelectedPlan }
    $script:DeleteButton = Add-ToolbarButton '删除' { Delete-SelectedPlan }
    $script:ExportButton = Add-ToolbarButton '导出备份' { Export-SelectedPlan }
    $script:ImportButton = Add-ToolbarButton '导入计划' { Import-PlanFile }
    $script:EditButton = Add-ToolbarButton '修改设置' { Show-EditSettingsDialog }
    $script:RestoreButton = Add-ToolbarButton '恢复备份' { Restore-PlanBackup }
    $script:ControlPanelButton = Add-ToolbarButton '系统电源选项' { Open-ControlPanel }
    $split = New-Object System.Windows.Forms.SplitContainer
    $split.Dock = 'Fill'; $split.Size = New-Object System.Drawing.Size($form.ClientSize.Width,($form.ClientSize.Height - $toolbar.Height))
    $split.Panel1MinSize = 300; $split.Panel2MinSize = 450; $split.SplitterDistance = 380
    $form.Controls.Add($split); $split.BringToFront()
    $leftLabel = New-Object System.Windows.Forms.Label
    $leftLabel.Text = '本机电源计划（动态读取）'; $leftLabel.Dock = 'Top'; $leftLabel.Height = 28; $leftLabel.Padding = New-Object System.Windows.Forms.Padding(8,8,0,0)
    $split.Panel1.Controls.Add($leftLabel)
    $list = New-Object System.Windows.Forms.ListView
    $list.Dock = 'Fill'; $list.View = 'Details'; $list.FullRowSelect = $true; $list.GridLines = $true; $list.HideSelection = $false; $list.MultiSelect = $false
    [void]$list.Columns.Add('状态',54); [void]$list.Columns.Add('计划名称',170); [void]$list.Columns.Add('GUID',235)
    $list.Add_SelectedIndexChanged({ if (-not $script:Refreshing) { try { Update-PlanDetails } catch { Set-Status ('读取失败：' + $_.Exception.Message) } } })
    $split.Panel1.Controls.Add($list); $list.BringToFront(); $script:PlanList = $list
    $rightLabel = New-Object System.Windows.Forms.Label
    $rightLabel.Text = '选中计划详情'; $rightLabel.Dock = 'Top'; $rightLabel.Height = 28; $rightLabel.Padding = New-Object System.Windows.Forms.Padding(8,8,0,0)
    $split.Panel2.Controls.Add($rightLabel)
    $details = New-Object System.Windows.Forms.TextBox
    $details.Dock = 'Fill'; $details.Multiline = $true; $details.ReadOnly = $true; $details.ScrollBars = 'Both'; $details.WordWrap = $false
    $details.Font = New-Object System.Drawing.Font('Consolas',9); $details.BackColor = [System.Drawing.SystemColors]::Window
    $split.Panel2.Controls.Add($details); $details.BringToFront(); $script:DetailsBox = $details
    $status = New-Object System.Windows.Forms.StatusStrip
    $statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
    $statusLabel.Spring = $true; [void]$status.Items.Add($statusLabel)
    $version = New-Object System.Windows.Forms.ToolStripStatusLabel
    $version.Text = '0.2.0'; [void]$status.Items.Add($version); $form.Controls.Add($status); $script:StatusLabel = $statusLabel
    Update-PlanButtons
    $form.Add_Shown({ param($sender,$eventArgs) Invoke-UiAction -Owner $sender -Action { Refresh-PlanList } })
    $form.Add_FormClosing({ $script:Refreshing = $true })
    return $form
}
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
                $report = [pscustomobject]@{ Title=$script:MainForm.Text; Visible=$script:MainForm.Visible; NativeVisible=[StartupWindowCheck]::IsWindowVisible($script:MainForm.Handle); ConsoleAttached=([StartupWindowCheck]::GetConsoleWindow() -ne [IntPtr]::Zero); Plans=$script:PlanList.Items.Count; Selected=$script:PlanList.SelectedItems.Count; Details=$script:DetailsBox.Text.Length; Status=$script:StatusLabel.Text }
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
