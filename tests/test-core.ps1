[CmdletBinding()]
param([string]$CorePath)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($CorePath)) { $CorePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\PowerPlan.Core.ps1' }
. $CorePath

# Every native powercfg invocation is replaced below. This suite never writes
# to Windows power plans or the registry. Test artifacts stay under artifacts/tests/.
$script:TestRoot = Join-Path (Split-Path -Parent $PSScriptRoot) ('artifacts\tests\mock-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:TestRoot)
$script:Results = New-Object 'System.Collections.Generic.List[object]'
$script:IdA = '11111111-1111-4111-8111-111111111111'
$script:IdB = '22222222-2222-4222-8222-222222222222'
$script:GroupId = '7516b95f-f776-4464-8c53-06167f40cc99'
$script:RangeId = '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e'
$script:EnumId = '309dce9b-bef4-4119-9921-a851fb12f0f4'

function Assert-Test([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Assertion failed: $Message" }
}
function Assert-Throws([scriptblock]$Action, [string]$Pattern = '.') {
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_ }
    Assert-Test ($null -ne $caught) 'The operation unexpectedly succeeded.'
    Assert-Test ($caught.Exception.Message -match $Pattern) ('Unexpected error: ' + $caught.Exception.Message)
}
function New-MockPlan([string]$Id, [string]$Name) {
    return [pscustomobject]@{ Id = $Id; Name = $Name; Ac = 60; Dc = 30; EnumAc = 1; EnumDc = 0 }
}
function Reset-Mock {
    $script:State = @{}
    $script:State[$script:IdA] = New-MockPlan $script:IdA '平衡 (默认)'
    $script:State[$script:IdB] = New-MockPlan $script:IdB '测试计划'
    $script:Active = $script:IdA
    $script:Calls = New-Object 'System.Collections.Generic.List[object]'
    $script:Fault = ''
    $script:AcWrites = 0
    $script:DcWrites = 0
    $script:FixtureLanguage = 'en'
    $script:EnumFixture = 'normal'
    $script:FaultConsumed = $false
    $script:CaseRoot = Join-Path $script:TestRoot ([guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($script:CaseRoot)
}
function Invoke-Case([string]$Name, [scriptblock]$Action) {
    Reset-Mock
    try {
        & $Action
        $script:Results.Add([pscustomobject]@{ Name = $Name; Passed = $true; Detail = '' })
        Write-Output "PASS: $Name"
    } catch {
        $script:Results.Add([pscustomobject]@{ Name = $Name; Passed = $false; Detail = $_.Exception.Message; Trace = $_.ScriptStackTrace })
        Write-Output "FAIL: $Name - $($_.Exception.Message)"
    }
}
function Get-MockQuery([string]$Id) {
    $p = $script:State[$Id]
    if ($null -eq $p) { throw 'MOCK: plan not found.' }
    $text = @"
Power Scheme GUID: $Id  ($($p.Name))
  Subgroup GUID: $script:GroupId  (Display)
    Power Setting GUID: $script:RangeId  (Display idle timeout)
      Minimum Possible Setting: 0x00000000
      Maximum Possible Setting: 0x00000e10
      Possible Setting Increment: 0x00000005
      Possible Setting Unit: Seconds
    Current AC Power Setting Index: $('0x{0:x8}' -f $p.Ac)
    Current DC Power Setting Index: $('0x{0:x8}' -f $p.Dc)
    Power Setting GUID: $script:EnumId  (Slide show)
      Possible Setting Index: 000
      Possible Setting Friendly Name: Off
      Possible Setting Index: 001
      Possible Setting Friendly Name: On
    Current AC Power Setting Index: $('0x{0:x8}' -f $p.EnumAc)
    Current DC Power Setting Index: $('0x{0:x8}' -f $p.EnumDc)
"@
    if ($script:EnumFixture -eq 'ambiguous') { $text = $text.Replace('Index: 001', 'Index: 010') }
    if ($script:EnumFixture -eq 'explicithex') { $text = $text.Replace('Index: 001', 'Index: 0x10') }
    if ($script:EnumFixture -eq 'alphahex') { $text = $text.Replace('Index: 001', 'Index: 00a') }
    if ($script:FixtureLanguage -eq 'zh') {
        foreach ($pair in @(
            @('Power Scheme', '电源方案'), @('Subgroup', '子组'), @('Power Setting GUID', '电源设置 GUID'),
            @('Minimum Possible Setting', '最小可能的设置'), @('Maximum Possible Setting', '最大可能的设置'),
            @('Possible Setting Increment', '可能的设置增量'), @('Possible Setting Unit', '可能的设置单位'),
            @('Possible Setting Index', '可能的设置索引'), @('Possible Setting Friendly Name', '可能的设置友好名称'),
            @('Current AC Power Setting Index', '当前交流电源设置索引'), @('Current DC Power Setting Index', '当前直流电源设置索引')
        )) { $text = $text.Replace($pair[0], $pair[1]) }
    }
    if ($script:Fault -eq 'MalformedQuery') { return 'unrecognized output' }
    if ($script:Fault -eq 'MissingDc') { $text = $text -replace '(?m)^.*Current DC.*$', '' }
    return $text
}
function Invoke-PowerCfg {
    param([string[]]$Arguments, [switch]$AllowFailure)
    $script:Calls.Add([pscustomobject]@{ Args = @($Arguments) })
    $verb = $Arguments[0].ToLowerInvariant()
    $out = ''
    switch ($verb) {
        '/list' {
            $out = (@($script:State.Values | Sort-Object Id | ForEach-Object {
                $mark = if ($_.Id -eq $script:Active) { ' *' } else { '' }
                'Power Scheme GUID: {0}  ({1}){2}' -f $_.Id, $_.Name, $mark
            }) -join "`r`n")
            if ($script:Fault -eq 'MalformedList') { $out = 'no parseable plans' }
        }
        '/getactivescheme' { $out = 'Power Scheme GUID: {0} ({1})' -f $script:Active, $script:State[$script:Active].Name }
        '/query' { $out = Get-MockQuery $Arguments[1] }
        '/setactive' {
            if ($script:Fault -eq 'FailActivate') { throw 'MOCK: access denied activation.' }
            if ($script:Fault -ne 'SilentActivate') { $script:Active = $Arguments[1] }
        }
        '/duplicatescheme' {
            if ($script:Fault -eq 'FailDuplicate') { throw 'MOCK: access denied duplicate.' }
            Assert-Test ($Arguments.Count -ge 3) 'Duplicate must use an explicit destination GUID.'
            $id = $Arguments[2]
            Assert-Test (-not $script:State.ContainsKey($id)) 'Duplicate would overwrite an existing plan.'
            $src = $script:State[$Arguments[1]]
            $p = New-MockPlan $id $src.Name
            $p.Ac = $src.Ac; $p.Dc = $src.Dc; $p.EnumAc = $src.EnumAc; $p.EnumDc = $src.EnumDc
            $script:State[$id] = $p
            $out = 'Power Scheme GUID: {0} ({1})' -f $id, $p.Name
        }
        '/changename' {
            if ($script:Fault -eq 'FailRename') { throw 'MOCK: access denied rename.' }
            if ($script:Fault -ne 'SilentRename') { $script:State[$Arguments[1]].Name = $Arguments[2] }
        }
        '/export' {
            if ($script:Fault -eq 'FailExport') { throw 'MOCK: export failed.' }
            if ($script:Fault -ne 'EmptyExport') {
                [IO.File]::WriteAllText($Arguments[1], ($script:State[$Arguments[2]] | ConvertTo-Json), [Text.Encoding]::UTF8)
            }
            if ($script:Fault -eq 'ConflictAfterBackup') { $script:State[$Arguments[2]].Ac = 155 }
            if ($script:Fault -eq 'RenameAfterBackup') { $script:State[$Arguments[2]].Name = 'externally changed' }
            if ($script:Fault -eq 'ActivateAfterBackup') { $script:Active = $Arguments[2] }
        }
        '/import' {
            if ($script:Fault -eq 'FailImport') { throw 'MOCK: invalid power file.' }
            Assert-Test ($Arguments.Count -ge 3) 'Import must use an explicit destination GUID.'
            $id = $Arguments[2]
            Assert-Test (-not $script:State.ContainsKey($id)) 'Import would overwrite an existing plan.'
            $src = Get-Content -LiteralPath $Arguments[1] -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -eq $src.Name -or $null -eq $src.Ac) { throw 'MOCK: invalid power file.' }
            $p = New-MockPlan $id $src.Name
            $p.Ac = $src.Ac; $p.Dc = $src.Dc; $p.EnumAc = $src.EnumAc; $p.EnumDc = $src.EnumDc
            $script:State[$id] = $p
        }
        '/delete' {
            if ($script:Fault -eq 'FailDelete') { throw 'MOCK: delete failed.' }
            Assert-Test ($Arguments[1] -ne $script:Active) 'Attempted to delete active plan.'
            [void]$script:State.Remove($Arguments[1])
        }
        '/setacvalueindex' {
            $script:AcWrites++
            if ($script:Fault -eq 'FailAC' -and $script:AcWrites -eq 1) { throw 'MOCK: AC write failed.' }
            if ($script:Fault -ne 'SilentAC' -or $script:AcWrites -gt 1) {
                if ($Arguments[3] -eq $script:EnumId) { $script:State[$Arguments[1]].EnumAc = [uint32]$Arguments[4] }
                else { $script:State[$Arguments[1]].Ac = [uint32]$Arguments[4] }
            }
        }
        '/setdcvalueindex' {
            $script:DcWrites++
            if ($script:Fault -in @('FailDC', 'FailDCExternalAC') -and $script:DcWrites -eq 1) {
                if ($script:Fault -eq 'FailDCExternalAC') { $script:State[$Arguments[1]].Ac = 155 }
                throw 'MOCK: DC write failed.'
            }
            if ($Arguments[3] -eq $script:EnumId) { $script:State[$Arguments[1]].EnumDc = [uint32]$Arguments[4] }
            else { $script:State[$Arguments[1]].Dc = [uint32]$Arguments[4] }
        }
        default { throw ('MOCK rejects unsupported command: ' + ($Arguments -join ' ')) }
    }
    return [pscustomobject]@{ ExitCode = 0; StdOut = $out; StdErr = ''; Arguments = ($Arguments -join ' ') }
}
function Get-RangeSetting { return @(Get-PowerSettings -Plan (Get-PowerPlans | Where-Object Id -eq $script:IdB) | Where-Object SettingId -eq $script:RangeId)[0] }
function Get-EnumSetting { return @(Get-PowerSettings -Plan (Get-PowerPlans | Where-Object Id -eq $script:IdB) | Where-Object SettingId -eq $script:EnumId)[0] }
function Get-WriteCalls { return @($script:Calls | Where-Object { $_.Args[0] -in @('/setactive', '/changename', '/duplicatescheme', '/import', '/delete', '/setacvalueindex', '/setdcvalueindex') }) }
function Assert-NoWrites { Assert-Test (@(Get-WriteCalls).Count -eq 0) 'A protected failure issued a write command.' }

Invoke-Case 'English list: names, nested parentheses, trailing active marker' {
    $plans = @(Get-PowerPlans)
    Assert-Test ($plans.Count -eq 2 -and $plans[0].Name -eq '平衡 (默认)') 'List parsing damaged names.'
    Assert-Test ($plans[0].IsActive -and -not $plans[1].IsActive) 'Wrong active marker.'
}
Invoke-Case 'Unrecognized list is an explicit failure' {
    $script:Fault = 'MalformedList'
    Assert-Throws { Get-PowerPlans }
}
Invoke-Case 'English range and enum parsing' {
    $range = Get-RangeSetting; $enum = Get-EnumSetting
    Assert-Test ($range.AcValue -eq 60 -and $range.DcValue -eq 30 -and $range.Increment -eq 5) 'Range values mismatch.'
    Assert-Test ($enum.Choices.Count -eq 2 -and $enum.Choices[1].Name -eq 'On') 'Choice parsing failed.'
}
Invoke-Case 'Chinese setting parsing' {
    $script:FixtureLanguage = 'zh'
    $range = Get-RangeSetting; $enum = Get-EnumSetting
    Assert-Test ($range.AcValue -eq 60 -and $range.DcValue -eq 30 -and $enum.Choices.Count -eq 2) 'Chinese values mismatch.'
}
Invoke-Case 'Ambiguous enum index 010 is not writable by guessing' {
    $script:EnumFixture = 'ambiguous'; $enum = Get-EnumSetting
    Assert-Test ($null -ne (Test-PowerSettingValue $enum '10')) 'Ambiguous index accepted as decimal.'
    Assert-Test ($null -ne (Test-PowerSettingValue $enum '16')) 'Ambiguous index accepted as hex.'
}
Invoke-Case 'Explicit hexadecimal enum 0x10 is 16' {
    $script:EnumFixture = 'explicithex'; $enum = Get-EnumSetting
    Assert-Test ($enum.Choices[1].Value -eq 16) 'Hexadecimal enumeration parsed incorrectly.'
}
Invoke-Case 'Hexadecimal enum containing A-F is parsed' {
    $script:EnumFixture = 'alphahex'; $enum = Get-EnumSetting
    Assert-Test ($enum.Choices[1].Value -eq 10) 'Alphabetic hexadecimal index parsed incorrectly.'
}
Invoke-Case 'UInt32 inclusive boundaries' {
    $s = [pscustomobject]@{ Min = 0; Max = [uint64]4294967295; Increment = 1; Choices = @() }
    Assert-Test ($null -eq (Test-PowerSettingValue $s '0')) 'Zero rejected.'
    Assert-Test ($null -eq (Test-PowerSettingValue $s '4294967295')) 'UInt32 maximum rejected.'
}
foreach ($bad in @('-1', '4294967296', '18446744073709551616', '1.5', 'NaN', '1e3', '0x10', '', ' ')) {
    $script:BadValue = $bad
    Invoke-Case ('Invalid numeric input rejected: [' + $bad + ']') {
        $s = Get-RangeSetting
        $caught = $false; $reason = $null
        try { $reason = Test-PowerSettingValue $s $script:BadValue } catch { $caught = $true }
        Assert-Test ($caught -or $null -ne $reason) 'Invalid input was accepted.'
    }
}
Invoke-Case 'Range and step validation includes lower-bound offset' {
    $s = [pscustomobject]@{ Min = 3; Max = 23; Increment = 5; Choices = @() }
    Assert-Test ($null -eq (Test-PowerSettingValue $s '8')) 'Legal offset step rejected.'
    Assert-Test ($null -ne (Test-PowerSettingValue $s '10')) 'Illegal step accepted.'
    Assert-Test ($null -ne (Test-PowerSettingValue $s '24')) 'Outside range accepted.'
}
Invoke-Case 'Enumeration rejects unlisted values' {
    $s = Get-EnumSetting
    Assert-Test ($null -eq (Test-PowerSettingValue $s '1')) 'Legal enum rejected.'
    Assert-Test ($null -ne (Test-PowerSettingValue $s '2')) 'Unlisted enum accepted.'
}
Invoke-Case 'Unknown setting metadata remains read-only' {
    $s = [pscustomobject]@{ Min = $null; Max = $null; Increment = $null; Choices = @() }
    Assert-Test ($null -ne (Test-PowerSettingValue $s '1')) 'Unknown range writable.'
}
Invoke-Case 'Activation is read back and verified' {
    Set-ManagedPowerPlan -Id $script:IdB | Out-Null
    Assert-Test ($script:Active -eq $script:IdB) 'Activation did not happen.'
}
Invoke-Case 'Activation denied never reports success' {
    $script:Fault = 'FailActivate'; Assert-Throws { Set-ManagedPowerPlan -Id $script:IdB }
    Assert-Test ($script:Active -eq $script:IdA) 'Denied activation changed state.'
}
Invoke-Case 'Activation success code but stale readback is rejected' {
    $script:Fault = 'SilentActivate'; Assert-Throws { Set-ManagedPowerPlan -Id $script:IdB }
}
Invoke-Case 'Active plan name containing another GUID does not confuse identity' {
    $script:State[$script:IdA].Name = 'name (' + $script:IdB + ')'
    Assert-Test ((Get-ActivePlanId) -eq $script:IdA) 'Name content confused the active GUID.'
}
Invoke-Case 'Multiple active scheme records are rejected' {
    Assert-Throws { Get-PlanIdFromText ("Power Scheme GUID: $script:IdA (a)`r`nPower Scheme GUID: $script:IdB (b)") }
}
Invoke-Case 'Invalid GUID rejected before native operation' {
    Assert-Throws { Set-ManagedPowerPlan -Id ($script:IdB + ' & calc') }
    Assert-NoWrites
}
Invoke-Case 'Create preserves punctuation, quotes and Unicode in name' {
    $name = '中文 (高效) & ! % "quoted" $() ` \'
    $new = New-ManagedPowerPlan -SourceId $script:IdA -Name $name
    Assert-Test ($new.Name -eq $name -and $script:State[$new.Id].Name -eq $name) 'Name was altered.'
    Assert-Test ($new.Id -notin @($script:IdA, $script:IdB) -and $script:Active -eq $script:IdA) 'Create overwrote/activated an existing plan.'
}
Invoke-Case 'Create duplicate permission error does not create phantom plan' {
    $script:Fault = 'FailDuplicate'; Assert-Throws { New-ManagedPowerPlan -SourceId $script:IdA -Name 'new' }
    Assert-Test ($script:State.Count -eq 2) 'Phantom plan after failed duplicate.'
}
Invoke-Case 'Create naming failure is an error, original plans unchanged' {
    $script:Fault = 'FailRename'; Assert-Throws { New-ManagedPowerPlan -SourceId $script:IdA -Name 'new' }
    Assert-Test ($script:State[$script:IdA].Name -eq '平衡 (默认)' -and $script:State[$script:IdB].Name -eq '测试计划') 'Original plans changed on creation failure.'
}
Invoke-Case 'Blank plan name rejected before mutation' {
    Assert-Throws { New-ManagedPowerPlan -SourceId $script:IdA -Name ' ' }; Assert-NoWrites
}
Invoke-Case 'Rename backs up and verifies' {
    $renamed = Rename-ManagedPowerPlan -Id $script:IdB -Name '新名称 & (副本)' -ExpectedName '测试计划' -BackupRoot $script:CaseRoot
    Assert-Test ($script:State[$script:IdB].Name -eq '新名称 & (副本)') 'Name was not changed.'
    Assert-Test (@(Get-ChildItem -LiteralPath $script:CaseRoot -Filter '*.pow').Count -ge 1) 'Rename backup missing.'
}
Invoke-Case 'Rename backup failure blocks write' {
    $script:Fault = 'FailExport'
    Assert-Throws { Rename-ManagedPowerPlan -Id $script:IdB -Name 'new' -ExpectedName '测试计划' -BackupRoot $script:CaseRoot }; Assert-NoWrites
}
Invoke-Case 'Rename stale name snapshot blocks write' {
    Assert-Throws { Rename-ManagedPowerPlan -Id $script:IdB -Name 'new' -ExpectedName 'stale name' -BackupRoot $script:CaseRoot }; Assert-NoWrites
}
Invoke-Case 'Rename concurrent change during backup blocks write' {
    $script:Fault = 'RenameAfterBackup'
    Assert-Throws { Rename-ManagedPowerPlan -Id $script:IdB -Name 'new' -ExpectedName '测试计划' -BackupRoot $script:CaseRoot }; Assert-NoWrites
}
Invoke-Case 'Rename silent native failure is rejected' {
    $script:Fault = 'SilentRename'
    Assert-Throws { Rename-ManagedPowerPlan -Id $script:IdB -Name 'new' -ExpectedName '测试计划' -BackupRoot $script:CaseRoot }
}
Invoke-Case 'Active plan deletion is blocked without a delete call' {
    Assert-Throws { Remove-ManagedPowerPlan -Id $script:IdA -ExpectedName '平衡 (默认)' -BackupRoot $script:CaseRoot }; Assert-NoWrites
}
Invoke-Case 'Last plan deletion is blocked' {
    [void]$script:State.Remove($script:IdB)
    Assert-Throws { Remove-ManagedPowerPlan -Id $script:IdA -ExpectedName '平衡 (默认)' -BackupRoot $script:CaseRoot }; Assert-NoWrites
}
Invoke-Case 'Delete backup failure blocks delete' {
    $script:Fault = 'FailExport'
    Assert-Throws { Remove-ManagedPowerPlan -Id $script:IdB -ExpectedName '测试计划' -BackupRoot $script:CaseRoot }; Assert-NoWrites
}
Invoke-Case 'Delete rechecks activity after backup' {
    $script:Fault = 'ActivateAfterBackup'
    Assert-Throws { Remove-ManagedPowerPlan -Id $script:IdB -ExpectedName '测试计划' -BackupRoot $script:CaseRoot }; Assert-NoWrites
}
Invoke-Case 'Delete verifies removal and leaves backup' {
    $backup = Remove-ManagedPowerPlan -Id $script:IdB -ExpectedName '测试计划' -BackupRoot $script:CaseRoot
    Assert-Test (-not $script:State.ContainsKey($script:IdB)) 'Plan was not deleted.'
    Assert-Test (Test-Path -LiteralPath $backup -PathType Leaf) 'Deletion backup missing.'
}
Invoke-Case 'Export and import preserve settings without activating' {
    $path = Join-Path $script:CaseRoot 'backup with spaces.pow'
    Export-ManagedPowerPlan -Id $script:IdB -Path $path | Out-Null
    $new = Import-ManagedPowerPlan -Path $path
    Assert-Test ($new.Id -notin @($script:IdA, $script:IdB)) 'Import did not create a new GUID.'
    Assert-Test ($script:State[$new.Id].Ac -eq 60 -and $script:Active -eq $script:IdA) 'Import altered value or activated itself.'
}
Invoke-Case 'Export missing output is an error' {
    $script:Fault = 'EmptyExport'
    Assert-Throws { Export-ManagedPowerPlan -Id $script:IdB -Path (Join-Path $script:CaseRoot 'empty.pow') }
}
Invoke-Case 'Export existing file requires overwrite intent' {
    $path = Join-Path $script:CaseRoot 'existing.pow'; [IO.File]::WriteAllText($path, 'preserve original contents')
    Assert-Throws { Export-ManagedPowerPlan -Id $script:IdB -Path $path }
    Assert-Test ([IO.File]::ReadAllText($path) -eq 'preserve original contents') 'Existing file was damaged.'
}
Invoke-Case 'Failed authorized overwrite preserves old backup' {
    $path = Join-Path $script:CaseRoot 'existing.pow'; [IO.File]::WriteAllText($path, 'preserve original contents')
    $script:Fault = 'FailExport'
    Assert-Throws { Export-ManagedPowerPlan -Id $script:IdB -Path $path -Overwrite }
    Assert-Test ([IO.File]::ReadAllText($path) -eq 'preserve original contents') 'Old backup lost during failed overwrite.'
}
Invoke-Case 'Import missing and truncated file is rejected before write' {
    Assert-Throws { Import-ManagedPowerPlan -Path (Join-Path $script:CaseRoot 'missing.pow') }
    $path = Join-Path $script:CaseRoot 'tiny.pow'; [IO.File]::WriteAllText($path, 'bad')
    Assert-Throws { Import-ManagedPowerPlan -Path $path }; Assert-NoWrites
}
Invoke-Case 'Import corrupt contents reports failure and leaves original state' {
    $path = Join-Path $script:CaseRoot 'corrupt.pow'; [IO.File]::WriteAllText($path, ('x' * 64))
    $script:Fault = 'FailImport'; Assert-Throws { Import-ManagedPowerPlan -Path $path }
    Assert-Test ($script:State.Count -eq 2 -and $script:Active -eq $script:IdA) 'Corrupt import changed original state.'
}
Invoke-Case 'Settings no-op issues no write' {
    $s = Get-RangeSetting
    $result = Set-ManagedPowerSetting -PlanId $script:IdB -Setting $s -AcValue '60' -DcValue '30' -BackupRoot $script:CaseRoot
    Assert-Test (-not $result.Changed) 'No-op reported changed.'; Assert-NoWrites
}
Invoke-Case 'Settings valid AC/DC transaction verifies both values' {
    $s = Get-RangeSetting
    $result = Set-ManagedPowerSetting -PlanId $script:IdB -Setting $s -AcValue '120' -DcValue '65' -BackupRoot $script:CaseRoot
    Assert-Test ($result.Changed -and $script:State[$script:IdB].Ac -eq 120 -and $script:State[$script:IdB].Dc -eq 65) 'Setting transaction incorrect.'
    Assert-Test (Test-Path -LiteralPath $result.BackupPath -PathType Leaf) 'Setting backup missing.'
}
Invoke-Case 'Settings invalid step blocks writes' {
    $s = Get-RangeSetting
    Assert-Throws { Set-ManagedPowerSetting -PlanId $script:IdB -Setting $s -AcValue '121' -DcValue '65' -BackupRoot $script:CaseRoot }; Assert-NoWrites
}
Invoke-Case 'Settings UInt32 overflow blocks writes' {
    $s = Get-RangeSetting
    Assert-Throws { Set-ManagedPowerSetting -PlanId $script:IdB -Setting $s -AcValue '4294967296' -DcValue '65' -BackupRoot $script:CaseRoot }; Assert-NoWrites
}
Invoke-Case 'Settings backup failure blocks both writes' {
    $s = Get-RangeSetting; $script:Fault = 'FailExport'
    Assert-Throws { Set-ManagedPowerSetting -PlanId $script:IdB -Setting $s -AcValue '120' -DcValue '65' -BackupRoot $script:CaseRoot }; Assert-NoWrites
}
Invoke-Case 'Settings stale snapshot blocks write' {
    $s = Get-RangeSetting; $script:State[$script:IdB].Ac = 155
    Assert-Throws { Set-ManagedPowerSetting -PlanId $script:IdB -Setting $s -AcValue '120' -DcValue '65' -BackupRoot $script:CaseRoot }; Assert-NoWrites
}
Invoke-Case 'Settings conflict during backup blocks write' {
    $s = Get-RangeSetting; $script:Fault = 'ConflictAfterBackup'
    Assert-Throws { Set-ManagedPowerSetting -PlanId $script:IdB -Setting $s -AcValue '120' -DcValue '65' -BackupRoot $script:CaseRoot }; Assert-NoWrites
}
Invoke-Case 'AC failure does not issue DC write' {
    $s = Get-RangeSetting; $script:Fault = 'FailAC'
    Assert-Throws { Set-ManagedPowerSetting -PlanId $script:IdB -Setting $s -AcValue '120' -DcValue '65' -BackupRoot $script:CaseRoot }
    Assert-Test ($script:DcWrites -eq 0 -and $script:State[$script:IdB].Ac -eq 60 -and $script:State[$script:IdB].Dc -eq 30) 'AC failure allowed DC or left changed values.'
}
Invoke-Case 'DC failure rolls back this transaction AC change' {
    $s = Get-RangeSetting; $script:Fault = 'FailDC'
    Assert-Throws { Set-ManagedPowerSetting -PlanId $script:IdB -Setting $s -AcValue '120' -DcValue '65' -BackupRoot $script:CaseRoot }
    Assert-Test ($script:State[$script:IdB].Ac -eq 60 -and $script:State[$script:IdB].Dc -eq 30) 'Partial AC write was not rolled back.'
}
Invoke-Case 'Rollback does not overwrite external AC changes' {
    $s = Get-RangeSetting; $script:Fault = 'FailDCExternalAC'
    Assert-Throws { Set-ManagedPowerSetting -PlanId $script:IdB -Setting $s -AcValue '120' -DcValue '65' -BackupRoot $script:CaseRoot }
    Assert-Test ($script:State[$script:IdB].Ac -eq 155 -and $script:State[$script:IdB].Dc -eq 30) 'Rollback overwrote an external change.'
}
Invoke-Case 'Successful native exit with wrong value is never reported as applied' {
    $s = Get-RangeSetting; $script:Fault = 'SilentAC'
    Assert-Throws { Set-ManagedPowerSetting -PlanId $script:IdB -Setting $s -AcValue '120' -DcValue '65' -BackupRoot $script:CaseRoot }
}

$summary = [pscustomobject]@{ Timestamp = (Get-Date).ToString('o'); Total = $script:Results.Count; Passed = @($script:Results | Where-Object Passed).Count; Failed = @($script:Results | Where-Object { -not $_.Passed }).Count; Results = $script:Results.ToArray() }
$reportPath = Join-Path $script:TestRoot 'results.json'
[IO.File]::WriteAllText($reportPath, ($summary | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($true)))
Write-Output ('RESULT: {0}/{1} passed; report={2}' -f $summary.Passed, $summary.Total, $reportPath)
if ($summary.Failed -gt 0) { exit 1 }
