[CmdletBinding()]
param([string]$SourcePath)
$ErrorActionPreference='Stop'
if(-not $SourcePath){$SourcePath=Join-Path (Split-Path -Parent $PSScriptRoot) 'src\PowerPlanManager.ps1'}
. $SourcePath -LoadOnly
$script:Checks=0
function Check([bool]$Condition,[string]$Message){$script:Checks++;if(-not $Condition){throw $Message}}
function Throws([scriptblock]$Action,[string]$Pattern){$caught=$null;try{& $Action | Out-Null}catch{$caught=$_};Check ($null -ne $caught -and $caught.Exception.Message -match $Pattern) ('Expected error: '+$Pattern+'; actual: '+$caught)}

# Verify the real read-only interface before installing fail-closed mutation mocks.
$plan=@(Get-PowerPlans)[0]
$visible=@(Get-PowerSettings $plan);$all=@(Get-PowerSettings $plan -IncludeHidden)
Check ($all.Count -ge $visible.Count) 'Hidden query includes the visible settings.'
foreach($item in $visible){Check ($item.SettingId -in @($all.SettingId)) 'Visible setting must remain in /qh.'}
foreach($item in @($all | Where-Object GroupId -eq 'fea3413e-7e05-4911-9a71-700331f1c294')){
    $attributes=Get-PowerAttributeState $item.GroupId $item.SettingId
    Check ($attributes.Kind -in @('Missing','DWord')) 'Ungrouped attributes resolve to the root setting node.'
}
Write-Output ('READ ONLY: visible={0}; including hidden={1}' -f $visible.Count,$all.Count)
function Show-ErrorMessage {param($Message,$Owner) throw $Message}
$readEditor=New-PowerEditor $plan $visible
try{
    $null=$readEditor.Handle;$readEditor.Tag.IncludeHidden.Checked=$true
    foreach($row in $readEditor.Tag.Grid.Rows){
        $readEditor.Tag.Grid.CurrentCell=$row.Cells[0];$row.Selected=$true
        Check ($readEditor.Tag.CurrentSetting.SettingId -eq $row.Tag.SettingId) 'Every real hidden row selects the matching setting.'
    }
}finally{$readEditor.Tag.Closing=$true;$readEditor.Dispose()}

$script:VisibilityBackupRoot=Join-Path (Split-Path -Parent $PSScriptRoot) ('artifacts\tests\visibility-'+[guid]::NewGuid().ToString('N'))
$script:Group='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
$script:Setting='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
$script:Second='cccccccc-cccc-4ccc-8ccc-cccccccccccc'
$script:Values=@{};$script:Writes=0;$script:WriteFault='';$script:Confirm=$false
function Get-VisibilityMachineId {return 'test-machine'}
function Get-PowerAttributeState([string]$GroupId,[string]$SettingId){
    $null=Resolve-PowerPlanGuid $GroupId;if($SettingId){$null=Resolve-PowerPlanGuid $SettingId}
    $key=$GroupId+'/'+$SettingId
    if(-not $script:Values.ContainsKey($key)){throw 'missing node'}
    $v=$script:Values[$key]
    return [pscustomobject]@{GroupId=$GroupId;SettingId=$SettingId;Exists=$v.Exists;Kind=$v.Kind;Value=$v.Value;Hidden=($v.Kind -eq 'DWord' -and ($v.Value -band 1) -ne 0)}
}
function Set-PowerAttributeValue([string]$GroupId,[string]$SettingId,[uint32]$Value){
    $script:Writes++
    if($script:WriteFault -eq 'denied'){throw 'access denied'}
    if($script:WriteFault -eq 'readback'){return}
    $script:Values[$GroupId+'/'+$SettingId].Value=$Value
}
function Invoke-PowerCfg {throw 'Unexpected powercfg call: no real writes are allowed in this suite.'}
function Reset-Attributes {
    $script:Values=@{}
    foreach($key in @(($script:Group+'/'),($script:Group+'/'+$script:Setting),($script:Group+'/'+$script:Second))){$script:Values[$key]=[pscustomobject]@{Exists=$true;Kind='DWord';Value=[uint32]7}}
    $script:Writes=0;$script:WriteFault=''
}
Reset-Attributes
$snapshot=Get-PowerAttributeState $script:Group $script:Setting
$path=Enable-PowerSettingVisibility $snapshot 'test setting'
Check ($script:Writes -eq 1 -and $script:Values[$script:Group+'/'+$script:Setting].Value -eq 6) 'Reveal clears only the hide bit.'
Check ($script:Values[$script:Group+'/'].Value -eq 7 -and $script:Values[$script:Group+'/'+$script:Second].Value -eq 7) 'Reveal does not change group or sibling.'
$record=Read-VisibilityRecord $path
Check ($record.Before -eq 7 -and $record.After -eq 6 -and $record.Phase -eq 'Applied') 'Original raw node mask is persisted.'
Restore-PowerSettingVisibility $path
Check ($script:Values[$script:Group+'/'+$script:Setting].Value -eq 7) 'Restore returns the exact original attributes.'
Throws {Restore-PowerSettingVisibility $path} '已经恢复'

Reset-Attributes
$script:Values[$script:Group+'/'+$script:Setting].Value=[uint32]2147483649
$path=Enable-PowerSettingVisibility (Get-PowerAttributeState $script:Group $script:Setting) 'high bit'
Check ($script:Values[$script:Group+'/'+$script:Setting].Value -eq 2147483648) 'Unknown high bits survive.'
Restore-PowerSettingVisibility $path
Check ($script:Values[$script:Group+'/'+$script:Setting].Value -eq 2147483649) 'Unknown high bits survive restore.'

Reset-Attributes
$path=Enable-PowerSettingVisibility (Get-PowerAttributeState $script:Group '') 'group'
Check ($script:Values[$script:Group+'/'].Value -eq 6 -and $script:Values[$script:Group+'/'+$script:Setting].Value -eq 7) 'Explicit group reveal does not rewrite children.'
Restore-PowerSettingVisibility $path

Reset-Attributes
$stale=Get-PowerAttributeState $script:Group $script:Setting
$script:Values[$script:Group+'/'+$script:Setting].Value=3
Throws {Enable-PowerSettingVisibility $stale 'stale'} '其他程序'
Check ($script:Writes -eq 0) 'Stale snapshots stop before writing.'
foreach($kind in @('Missing','String')){
    Reset-Attributes;$script:Values[$script:Group+'/'+$script:Setting].Kind=$kind
    $script:Values[$script:Group+'/'+$script:Setting].Exists=($kind -ne 'Missing')
    Throws {Enable-PowerSettingVisibility (Get-PowerAttributeState $script:Group $script:Setting) 'invalid'} '没有可解除'
    Check ($script:Writes -eq 0) 'Missing/non-DWORD values remain untouched.'
}

Reset-Attributes
$root=$script:VisibilityBackupRoot;$script:VisibilityBackupRoot=Join-Path $root 'file-as-directory'
[IO.File]::WriteAllText($script:VisibilityBackupRoot,'blocked')
Throws {Enable-PowerSettingVisibility (Get-PowerAttributeState $script:Group $script:Setting) 'backup failure'} '.'
Check ($script:Writes -eq 0) 'Backup failure stops before native writes.'
$script:VisibilityBackupRoot=$root
foreach($fault in @('denied','readback')){
    Reset-Attributes;$script:WriteFault=$fault
    Throws {Enable-PowerSettingVisibility (Get-PowerAttributeState $script:Group $script:Setting) 'failure'} '属性备份'
    Check ($script:Values[$script:Group+'/'+$script:Setting].Value -eq 7) 'Failed write is not reported as success.'
}
Reset-Attributes
$path=Enable-PowerSettingVisibility (Get-PowerAttributeState $script:Group $script:Setting) 'restore conflict'
$script:Values[$script:Group+'/'+$script:Setting].Value=10;$count=$script:Writes
Throws {Restore-PowerSettingVisibility $path} '外部改动'
Check ($script:Writes -eq $count -and $script:Values[$script:Group+'/'+$script:Setting].Value -eq 10) 'Restore cannot overwrite external changes.'
$record=Read-VisibilityRecord $path;$record.Machine='another-device';Write-VisibilityRecord $record $path
Throws {Restore-PowerSettingVisibility $path} '其他电脑'
$record.Machine='test-machine';$record.Before=31;Write-VisibilityRecord $record $path
Throws {Restore-PowerSettingVisibility $path} '备份无效'
[IO.File]::WriteAllText($path,'broken json')
Throws {Restore-PowerSettingVisibility $path} '.'
Throws {Read-VisibilityRecord (Join-Path $root '..\outside.json')} '备份目录'
Check ($script:Writes -eq $count) 'Tampered backup cases never call native writes.'

# GUI events: reading, filtering and cancelling must not mutate attributes.
Reset-Attributes
function New-TestSetting([string]$Id,[string]$Name){return [pscustomobject]@{GroupId=$script:Group;GroupName='测试分类';SettingId=$Id;Name=$Name;AcValue=60;DcValue=30;Min=0;Max=600;Increment=1;Unit='秒';Choices=@();MetadataError=''}}
$script:Normal=New-TestSetting $script:Second '普通设置'
$script:Hidden=New-TestSetting $script:Setting '隐藏测试'
function Get-PowerSettings {param($Plan,[switch]$IncludeHidden) if($IncludeHidden){return @($script:Normal,$script:Hidden)};return @($script:Normal)}
function Confirm-Action {param($Message,$Owner) $script:LastConfirmation=$Message;return $script:Confirm}
function Show-InfoMessage {param($Message,$Owner)}
function Show-ErrorMessage {param($Message,$Owner) throw $Message}
$editor=New-PowerEditor $plan @($script:Normal)
try{
    $null=$editor.Handle
    Check ($editor.Tag.Grid.Rows.Count -eq 1) 'Hidden settings are optional.'
    $editor.Tag.AcInput.Text='90'
    $editor.Tag.IncludeHidden.Checked=$true
    Check ($editor.Tag.Grid.Rows.Count -eq 2) 'Checkbox includes hidden settings.'
    Check ((Read-EditorInput $editor.Tag.AcInput) -eq '90') 'Visible draft survives loading hidden settings.'
    $editor.Tag.Search.Text='隐藏测试'
    Check ($editor.Tag.Grid.Rows.Count -eq 1 -and $editor.Tag.CurrentSetting.SettingId -eq $script:Setting) 'Search locates hidden setting.'
    $editor.Tag.AcInput.Text='120'
    $editor.Tag.IncludeHidden.Checked=$false
    Check ($editor.Tag.Grid.Rows.Count -eq 0 -and -not $editor.Tag.ApplyButton.Enabled) 'Empty results disable save.'
    $editor.Tag.IncludeHidden.Checked=$true
    Check ((Read-EditorInput $editor.Tag.AcInput) -eq '120') 'Hidden draft survives filtering out and back.'
    Check ($script:Writes -eq 0) 'Program-only hidden checkbox/search never mutate Windows attributes.'
    $managed=Get-ManagedSetting $plan $script:Group $script:Setting
    Check ($managed.SettingId -eq $script:Setting) 'Core can re-read a hidden setting before normal validated AC/DC writes.'
    $dialog=New-VisibilityDialog $plan
    try{
        $null=$dialog.Handle
        $dialog.Tag.Search.Text='隐藏测试'
        Invoke-VisibilityChange $dialog
        Check ($script:Writes -eq 0) 'Cancel reveal does not write.'
        $script:Confirm=$true;Invoke-VisibilityChange $dialog
        Check ($script:Writes -eq 1 -and $script:LastConfirmation.Contains('所有计划')) 'Reveal confirmation explains global scope.'
        Check ($dialog.Tag.Restore.Enabled) 'Restore becomes available after reveal.'
        $script:Confirm=$false;Invoke-VisibilityChange $dialog -Restore
        Check ($script:Writes -eq 1) 'Cancel restore does not write.'
        $script:Confirm=$true;Invoke-VisibilityChange $dialog -Restore
        Check ($script:Writes -eq 2 -and $script:Values[$script:Group+'/'+$script:Setting].Value -eq 7) 'UI restores selected item only.'
    }finally{$dialog.Dispose()}
}finally{$editor.Tag.Closing=$true;$editor.Dispose()}
Write-Output ('PASS: {0} visibility checks; native writes and powercfg mutations mocked.' -f $script:Checks)
