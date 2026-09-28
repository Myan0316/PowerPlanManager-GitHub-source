[CmdletBinding()]
param([string]$SourcePath)
$ErrorActionPreference='Stop'
if(-not $SourcePath){$SourcePath=Join-Path (Split-Path -Parent $PSScriptRoot) 'src\PowerPlanManager.ps1'}
. $SourcePath -LoadOnly
$script:UiAssertions=0
function Check([bool]$Condition,[string]$Message){$script:UiAssertions++;if(-not $Condition){throw $Message}}
function Handles($Control){$null=$Control.Handle;foreach($child in $Control.Controls){Handles $child};$Control.PerformLayout()}
function Confirm-Action {param($Message,$Owner) return $script:ConfirmUi}
function Show-InfoMessage {param($Message,$Owner)}
function Show-ErrorMessage {param($Message,$Owner) throw $Message}
$testRoot=Join-Path (Split-Path -Parent $PSScriptRoot) ('artifacts\tests\ui-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$script:AppearancePath=Join-Path $testRoot 'appearance.json'
$form=Build-MainForm
$editor=$null
try{
    Handles $form;Refresh-PlanList
    Check ($form.Tag.CommonHost.Controls.Count -gt 0) 'Home provides settings or a useful unavailable state.'
    $originalSettings=$form.Tag.HomeSettings
    foreach($mode in @('Light','Dark')){
        foreach($accent in @($script:AccentChoices.Id)){
            $script:Appearance.Mode=$mode;$script:Appearance.Accent=$accent;Update-AppTheme -Force
            $p=Get-UiPalette
            $a=Get-UiLuminance $p.Accent;$b=Get-UiLuminance $p.OnAccent
            $ratio=([Math]::Max($a,$b)+0.05)/([Math]::Min($a,$b)+0.05)
            Check ($ratio -ge 4.5) ('Accent text contrast: '+$mode+'/'+$accent)
            Check ([object]::ReferenceEquals($form.Tag.HomeSettings,$originalSettings)) 'Changing themes must preserve the data model.'
        }
    }
    $script:SystemDark=$true
    function Get-SystemAppearance {return [pscustomobject]@{Dark=$script:SystemDark;Accent=[Drawing.Color]::FromArgb(71,130,165)}}
    $script:Appearance.Mode='System';$script:Appearance.Accent='System';Update-AppTheme -Force
    Check ((Get-UiPalette).Dark) 'System dark mode follows the provider.'
    $script:SystemDark=$false;Update-AppTheme
    Check (-not (Get-UiPalette).Dark) 'System light mode updates without changing preferences.'
    Check ((Get-UiPalette).Accent.R -eq 71) 'System accent follows the provider.'
    $script:Appearance.Mode='Dark';$script:SystemDark=$false
    Check ((Get-UiPalette).Dark) 'Manual dark mode overrides system mode.'
    $form.Tag.ModePicker.SelectedIndex=1;$form.Tag.AccentPicker.SelectedIndex=2
    Read-Appearance
    Check ($script:Appearance.Mode -eq 'Light' -and $script:Appearance.Accent -eq 'Forest') 'UI preference changes persist and reload.'
    [IO.File]::WriteAllText($script:AppearancePath,'{"Mode":"Unknown","Accent":"Ocean"}')
    Read-Appearance;Check ($script:Appearance.Mode -eq 'System') 'Unknown preferences fall back safely.'
    [IO.File]::WriteAllText($script:AppearancePath,'broken json')
    Read-Appearance;Check ($script:Appearance.Accent -eq 'System') 'Corrupt preferences do not block startup.'
    $savedPath=$script:AppearancePath;$script:AppearancePath=$testRoot
    $form.Tag.AccentPicker.SelectedIndex=3
    Check ($form.Tag.AppearanceHint.Text.Contains('保存失败')) 'Preference write failure is visible, not silent success.'
    $script:AppearancePath=$savedPath
    $time=[pscustomobject]@{GroupId='7516b95f-f776-4464-8c53-06167f40cc99';GroupName='显示';SettingId='3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e';Name='Display timeout';Min=[uint64]0;Max=[uint64]4294967295;Increment=[uint64]1;Unit='秒';AcValue=[uint64]123;DcValue=[uint64]0;Choices=@()}
    $other=[pscustomobject]@{GroupId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';GroupName='其他';SettingId='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';Name='Unknown seconds';Min=[uint64]0;Max=[uint64]1000;Increment=[uint64]1;Unit='秒';AcValue=[uint64]0;DcValue=[uint64]5;Choices=@()}
    Check ((Format-SettingValue $time 0) -eq '从不') 'Known timeout zero is Never.'
    Check ((Format-SettingValue $other 0) -eq '0 秒') 'Unknown zero semantics are not guessed.'
    $editor=Build-EditSettingsDialog -Plan (Get-SelectedPlan) -Settings @($time,$other)
    Handles $editor;$state=$editor.Tag
    $editor.Show();[Windows.Forms.Application]::DoEvents()
    Check ($state.RawToggle.Visible -and $state.RawToggle.Enabled) 'Known editable time settings show the raw input toggle.'
    Check ((Read-EditorInput $state.AcInput) -eq '123') 'Non-preset current seconds survive the friendly dropdown.'
    $state.AcInput.SelectedIndex=@($state.AcInput.Items.Value).IndexOf([uint64]600)
    $state.Categories.SelectedIndex=2;$state.Categories.SelectedIndex=1
    Check ((Read-EditorInput $state.AcInput) -eq '600') 'Draft survives changing categories.'
    $state.RawToggle.Checked=$true
    Check ($state.AcInput.Text -eq '600') 'Raw mode retains seconds, not minutes.'
    $state.AcInput.Text='bad';$state.RawToggle.Checked=$false
    Check ((Read-EditorInput $state.AcInput) -eq 'bad') 'Invalid unsaved raw input is retained rather than silently replaced.'
    $state.RawToggle.Checked=$true;$state.AcInput.Text='600';$state.DcInput.Text='0'
    $script:UiWrites=0;$script:ConfirmUi=$false
    function Set-ManagedPowerSetting {param($PlanId,$Setting,$AcValue,$DcValue) $script:UiWrites++;Check ($AcValue -eq 600 -and $DcValue -eq 0) 'Friendly inputs submit exact seconds.';return [pscustomobject]@{BackupPath='test.pow'}}
    Apply-EditorSetting $editor;Check ($script:UiWrites -eq 0) 'Cancel preview never calls write service.'
    $script:ConfirmUi=$true;Apply-EditorSetting $editor
    Check ($script:UiWrites -eq 1 -and $time.AcValue -eq 600) 'Save routes once through the protected service.'
    $state.Categories.SelectedIndex=2
    Check ($state.Grid.Rows.Count -eq 1 -and $state.CurrentSetting.SettingId -eq $other.SettingId) 'Category selection identifies the correct setting.'
    Check (-not $state.RawToggle.Visible) 'Settings without friendly time presets hide the inapplicable toggle.'
    $state.AcInput.Text='7';Save-EditorDraft $editor
    $script:Appearance.Mode='Dark';Set-WindowPalette $editor (Get-UiPalette)
    Check ($state.AcInput.Text -eq '7' -and $state.Drafts.Count -gt 0) 'Theme change keeps unsaved input.'
    $state.Categories.SelectedIndex=1
    Check ($state.RawToggle.Visible) 'Returning to a time setting restores the toggle.'
    $state.Grid.ClearSelection()
    Check (-not $state.RawToggle.Visible) 'Clearing selection hides the toggle.'
    Write-Output ('PASS: {0} UI checks; theme persistence/fallback/system changes, contrast, time conversion and category drafts; writes mocked.' -f $script:UiAssertions)
}finally{if($null -ne $editor){$editor.Dispose()};$form.Dispose()}
