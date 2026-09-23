[CmdletBinding()]
param(
    [string]$CorePath,
    [switch]$ExecuteWrites,
    [switch]$IncludeActivation
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($CorePath)) { $CorePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\PowerPlan.Core.ps1' }
. $CorePath
if ($ExecuteWrites) {
    $testIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $testPrincipal = New-Object Security.Principal.WindowsPrincipal($testIdentity)
    if (-not $testPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Live write tests require elevation because powercfg export requires backup privileges. No test plans were created by this run.' }
}
$script:NativePowerCfg = ${function:Invoke-PowerCfg}
$script:LiveRoot = Join-Path (Split-Path -Parent $PSScriptRoot) ('artifacts\tests\live-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:LiveRoot)
$script:LiveLog = New-Object 'System.Collections.Generic.List[object]'
$script:OwnedIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$script:OriginalIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$script:LivePhase = 'ReadOnly'
$script:LiveFailNextDc = $false
$script:OriginalActive = Get-ActivePlanId
$originalPlans = @(Get-PowerPlans)
$originals = @($originalPlans | ForEach-Object {
    [void]$script:OriginalIds.Add($_.Id)
    [pscustomobject]@{
        Id = $_.Id
        Name = $_.Name
        Query = (Invoke-PowerCfg -Arguments @('/query', $_.Id)).StdOut
        FullQuery = (Invoke-PowerCfg -Arguments @('/qh', $_.Id)).StdOut
    }
})
$baseline = [pscustomobject]@{ RecordedAt = (Get-Date).ToString('o'); Active = $script:OriginalActive; Plans = $originals }
[IO.File]::WriteAllText((Join-Path $script:LiveRoot 'before.json'), ($baseline | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($true)))

function Write-LiveResult([string]$Name, [string]$Status, [string]$Detail) {
    $script:LiveLog.Add([pscustomobject]@{ At = (Get-Date).ToString('o'); Name = $Name; Status = $Status; Detail = $Detail })
    Write-Output ('{0}: {1} {2}' -f $Status, $Name, $Detail)
}
function Assert-Live([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-LivePath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = [IO.Path]::GetFullPath($script:LiveRoot).TrimEnd('\') + '\'
    Assert-Live ($full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) ('File path escaped the isolated test directory: ' + $full)
}
function Get-ComparableQuery([string]$Text) {
    # Only the scheme header contains the new GUID/name; all setting metadata,
    # including hidden settings, must be identical before activation is allowed.
    $lines = $Text -split "`r?`n"
    $firstGroup = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '(?i)^\s*(Subgroup|子组)\s+GUID\s*:') { $firstGroup = $index; break }
    }
    Assert-Live ($firstGroup -ge 0) 'Query has no recognizable settings groups.'
    return ($lines[$firstGroup..($lines.Count - 1)] -join "`n")
}

# Defense in depth: every production operation still goes through this wrapper.
# No destructive operation may target an original plan. The sole exception is
# restoring the original active GUID during the explicitly enabled switch test.
function Invoke-PowerCfg {
    param([string[]]$Arguments, [switch]$AllowFailure)
    $verb = $Arguments[0].ToLowerInvariant()
    if ($verb -in @('/list', '/getactivescheme', '/query', '/qh')) {
        return & $script:NativePowerCfg -Arguments $Arguments -AllowFailure:$AllowFailure
    }
    Assert-Live $ExecuteWrites.IsPresent 'Write test gate is closed. Use -ExecuteWrites intentionally.'
    switch ($verb) {
        '/duplicatescheme' {
            Assert-Live ($Arguments.Count -eq 3) 'Duplicate must supply a destination GUID.'
            Assert-Live ($Arguments[1] -eq $script:OriginalActive) 'Only the original active plan may be the duplicate source.'
            Assert-Live (-not $script:OriginalIds.Contains($Arguments[2])) 'Refusing to duplicate onto an original GUID.'
            Assert-Live ($Arguments[2] -match '^[0-9a-fA-F-]{36}$') 'Invalid duplicate GUID.'
            [void]$script:OwnedIds.Add($Arguments[2])
        }
        '/import' {
            Assert-Live ($Arguments.Count -eq 3) 'Import must supply a destination GUID.'
            Assert-LivePath $Arguments[1]
            Assert-Live (-not $script:OriginalIds.Contains($Arguments[2])) 'Refusing to import onto an original GUID.'
            [void]$script:OwnedIds.Add($Arguments[2])
        }
        '/export' {
            Assert-LivePath $Arguments[1]
            Assert-Live ($script:OwnedIds.Contains($Arguments[2])) 'This test exports only its own temporary plans.'
        }
        '/setactive' {
            Assert-Live $IncludeActivation.IsPresent 'Activation test is not enabled.'
            Assert-Live ($script:LivePhase -in @('Activation', 'Cleanup')) 'Activation outside the guarded test phase.'
            Assert-Live (($Arguments[1] -eq $script:OriginalActive) -or $script:OwnedIds.Contains($Arguments[1])) 'Refusing to activate an unrelated plan.'
            if ($Arguments[1] -eq $script:OriginalActive) {
                $current = Get-ActivePlanId
                Assert-Live (($current -eq $script:OriginalActive) -or $script:OwnedIds.Contains($current)) 'Another app changed the active plan; refusing to overwrite its selection.'
            }
        }
        { $_ -in @('/changename', '/setacvalueindex', '/setdcvalueindex', '/delete') } {
            Assert-Live ($script:OwnedIds.Contains($Arguments[1]) -and -not $script:OriginalIds.Contains($Arguments[1])) ('Refusing to mutate a plan not created by this test: ' + $Arguments[1])
            $current = Get-ActivePlanId
            Assert-Live ($Arguments[1] -ne $current) 'Refusing to modify or delete an active test plan.'
        }
        default { throw ('Live test rejects unsupported command: ' + ($Arguments -join ' ')) }
    }
    if ($verb -eq '/setdcvalueindex' -and $script:LiveFailNextDc) {
        $script:LiveFailNextDc = $false
        throw 'INTENTIONAL TEST FAILURE: DC rejected after AC write.'
    }
    return & $script:NativePowerCfg -Arguments $Arguments -AllowFailure:$AllowFailure
}

Write-LiveResult 'Original state saved' 'PASS' ('{0} original plans; active={1}; snapshot={2}' -f $originals.Count, $script:OriginalActive, (Join-Path $script:LiveRoot 'before.json'))
if (-not $ExecuteWrites) {
    Write-LiveResult 'Write integration suite' 'SKIP' 'Read-only inspection completed. Execute with -ExecuteWrites to test isolated copies.'
    [IO.File]::WriteAllText((Join-Path $script:LiveRoot 'results.json'), ($script:LiveLog.ToArray() | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($true)))
    exit 0
}

$operationFailed = $false
try {
    $script:LivePhase = 'Create'
    $name = 'PPM Test 中文 (临时) & ! % "quote" ' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $copy = New-ManagedPowerPlan -SourceId $script:OriginalActive -Name $name
    Assert-Live ($script:OwnedIds.Contains($copy.Id)) 'The duplicate GUID was not tracked.'
    Assert-Live ($copy.Name -eq $name) 'Special characters in new plan name did not round trip.'
    Assert-Live ((Get-ActivePlanId) -eq $script:OriginalActive) 'Creating a copy changed the active plan.'
    $sourceFull = (Invoke-PowerCfg -Arguments @('/qh', $script:OriginalActive)).StdOut
    $copyFull = (Invoke-PowerCfg -Arguments @('/qh', $copy.Id)).StdOut
    Assert-Live ((Get-ComparableQuery $copyFull) -ceq (Get-ComparableQuery $sourceFull)) 'Copy differs from original settings before modification.'
    Write-LiveResult 'Create copy with special-character name and verify all settings' 'PASS' $copy.Id

    if ($IncludeActivation) {
        $script:LivePhase = 'Activation'
        Assert-Live ((Get-ActivePlanId) -eq $script:OriginalActive) 'Active plan changed externally before switch test.'
        Set-ManagedPowerPlan -Id $copy.Id | Out-Null
        Assert-Live ((Get-ActivePlanId) -eq $copy.Id) 'Temporary equivalent copy did not activate.'
        Set-ManagedPowerPlan -Id $script:OriginalActive | Out-Null
        Assert-Live ((Get-ActivePlanId) -eq $script:OriginalActive) 'Original active plan was not restored.'
        Write-LiveResult 'Activate equivalent copy and immediately restore original' 'PASS' 'No settings were edited until the original plan was active again.'
    } else { Write-LiveResult 'Activation round trip' 'SKIP' 'Use -IncludeActivation to enable the guarded switch test.' }

    $script:LivePhase = 'ModifyInactive'
    $newName = 'PPM 重命名 (功能测试) & ' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $copy = Rename-ManagedPowerPlan -Id $copy.Id -Name $newName -ExpectedName $copy.Name -BackupRoot $script:LiveRoot
    Assert-Live ($copy.Name -eq $newName) 'Rename readback mismatch.'
    Write-LiveResult 'Rename inactive test plan with backup' 'PASS' $copy.Name

    $settings = @(Get-PowerSettings -Plan $copy)
    $candidate = @($settings | Where-Object { $_.SettingId -eq '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e' -and $null -ne $_.AcValue -and $null -ne $_.DcValue })
    Assert-Live ($candidate.Count -eq 1) 'Display idle timeout is unavailable; test refuses to guess another system setting.'
    $setting = $candidate[0]
    $nextAc = if ($setting.AcValue -ne 600) { '600' } else { '660' }
    $nextDc = if ($setting.DcValue -ne 480) { '480' } else { '540' }
    Assert-Live ($null -eq (Test-PowerSettingValue $setting $nextAc)) 'Selected test value is outside supported metadata.'
    $edit = Set-ManagedPowerSetting -PlanId $copy.Id -Setting $setting -AcValue $nextAc -DcValue $nextDc -BackupRoot $script:LiveRoot
    Assert-Live $edit.Changed 'Editing the test plan incorrectly returned unchanged.'
    $afterSetting = @(Get-PowerSettings -Plan $copy | Where-Object { $_.GroupId -eq $setting.GroupId -and $_.SettingId -eq $setting.SettingId })[0]
    Assert-Live ($afterSetting.AcValue -eq [uint32]$nextAc -and $afterSetting.DcValue -eq [uint32]$nextDc) 'Setting readback differs from requested edit.'
    Assert-Live ((Get-ActivePlanId) -eq $script:OriginalActive) 'Inactive edit affected active selection.'
    Write-LiveResult 'Edit inactive AC and DC display timeouts, verify readback and backup' 'PASS' ('AC {0} -> {1}; DC {2} -> {3}' -f $setting.AcValue, $afterSetting.AcValue, $setting.DcValue, $afterSetting.DcValue)

    $script:LiveFailNextDc = $true
    $rollbackCaught = $false
    try { Set-ManagedPowerSetting -PlanId $copy.Id -Setting $afterSetting -AcValue ([string]($afterSetting.AcValue + 60)) -DcValue ([string]($afterSetting.DcValue + 60)) -BackupRoot $script:LiveRoot | Out-Null }
    catch { $rollbackCaught = $_.Exception.Message -match 'INTENTIONAL TEST FAILURE' }
    $script:LiveFailNextDc = $false
    Assert-Live $rollbackCaught 'Intentional partial failure was not surfaced.'
    $rollbackState = @(Get-PowerSettings -Plan $copy | Where-Object SettingId -eq $setting.SettingId)[0]
    Assert-Live ($rollbackState.AcValue -eq $afterSetting.AcValue -and $rollbackState.DcValue -eq $afterSetting.DcValue) 'Real AC write was not rolled back after rejected DC write.'
    Write-LiveResult 'Actual AC write rolls back after injected DC failure' 'PASS' 'Both values returned to their previous values.'

    $enum = @(Get-PowerSettings -Plan $copy | Where-Object SettingId -eq '309dce9b-bef4-4119-9921-a851fb12f0f4')[0]
    Assert-Live ($null -ne $enum -and $enum.Choices.Count -ge 2) 'Slide show enum unavailable.'
    $enumAc = @($enum.Choices | Where-Object Value -ne $enum.AcValue)[0].Value
    Set-ManagedPowerSetting -PlanId $copy.Id -Setting $enum -AcValue ([string]$enumAc) -DcValue ([string]$enum.DcValue) -BackupRoot $script:LiveRoot | Out-Null
    $enumAfter = @(Get-PowerSettings -Plan $copy | Where-Object SettingId -eq $enum.SettingId)[0]
    Assert-Live ($enumAfter.AcValue -eq $enumAc -and $enumAfter.DcValue -eq $enum.DcValue) 'Enum change or unchanged DC did not round trip.'
    Write-LiveResult 'Edit slide show enum and preserve unchanged DC' 'PASS' ([string]$enumAc)

    $exportPath = Join-Path $script:LiveRoot 'export with spaces.pow'
    Export-ManagedPowerPlan -Id $copy.Id -Path $exportPath | Out-Null
    Assert-Live ((Get-Item -LiteralPath $exportPath).Length -ge 16) 'Export is missing or truncated.'
    $restored = Import-ManagedPowerPlan -Path $exportPath
    Assert-Live ($restored.Id -ne $copy.Id -and $script:OwnedIds.Contains($restored.Id)) 'Import did not create a separate tracked GUID.'
    $exportedQuery = (Invoke-PowerCfg -Arguments @('/qh', $copy.Id)).StdOut
    $restoredQuery = (Invoke-PowerCfg -Arguments @('/qh', $restored.Id)).StdOut
    Assert-Live ((Get-ComparableQuery $exportedQuery) -ceq (Get-ComparableQuery $restoredQuery)) 'Imported settings differ from exported settings.'
    Assert-Live ((Get-ActivePlanId) -eq $script:OriginalActive) 'Import activated a plan.'
    Write-LiveResult 'Export and import round trip, verify all settings' 'PASS' $restored.Id

    $backupRestored = Import-ManagedPowerPlan -Path $edit.BackupPath
    $restoredSetting = @(Get-PowerSettings -Plan $backupRestored | Where-Object { $_.GroupId -eq $setting.GroupId -and $_.SettingId -eq $setting.SettingId })[0]
    Assert-Live ($restoredSetting.AcValue -eq $setting.AcValue -and $restoredSetting.DcValue -eq $setting.DcValue) 'Automatic backup failed to recover original values.'
    Write-LiveResult 'Restore automatic pre-edit backup into new plan' 'PASS' $backupRestored.Id

    $damagedPath = Join-Path $script:LiveRoot 'corrupt.pow'
    [IO.File]::WriteAllText($damagedPath, ('invalid-power-plan-' * 5), [Text.Encoding]::UTF8)
    $corruptFailed = $false
    try { Import-ManagedPowerPlan -Path $damagedPath | Out-Null } catch { $corruptFailed = $true; $corruptError = $_.Exception.Message }
    Assert-Live $corruptFailed 'Corrupt .pow import unexpectedly succeeded.'
    Write-LiveResult 'Corrupt .pow import is rejected' 'PASS' $corruptError

    foreach ($plan in @($backupRestored, $restored, $copy)) {
        $deleteBackup = Remove-ManagedPowerPlan -Id $plan.Id -ExpectedName $plan.Name -BackupRoot $script:LiveRoot
        Assert-Live ($plan.Id -notin @(Get-PowerPlans | Select-Object -ExpandProperty Id)) 'Deletion did not remove temporary plan.'
        Assert-Live (Test-Path -LiteralPath $deleteBackup -PathType Leaf) 'Deletion backup is missing.'
        Write-LiveResult 'Delete owned inactive test plan with backup' 'PASS' $plan.Id
    }
} catch {
    $operationFailed = $true
    Write-LiveResult 'Live write integration stopped' 'FAIL' ($_.Exception.Message + ' | ' + $_.ScriptStackTrace)
} finally {
    $script:LivePhase = 'Cleanup'
    try {
        $current = Get-ActivePlanId
        if ($script:OwnedIds.Contains($current)) {
            if ($IncludeActivation) {
                Set-ManagedPowerPlan -Id $script:OriginalActive | Out-Null
                Write-LiveResult 'Conditional cleanup of active test copy' 'PASS' 'Restored original because the active GUID was owned by this run.'
            } else { throw 'An external action activated a test copy. Cleanup will not switch plans without -IncludeActivation.' }
        } elseif ($current -ne $script:OriginalActive) {
            $operationFailed = $true
            Write-LiveResult 'External activity change' 'FAIL' 'Another plan is active. Left that selection untouched and did not force restoration.'
        }
    } catch { $operationFailed = $true; Write-LiveResult 'Conditional activation cleanup' 'FAIL' $_.Exception.Message }

    foreach ($ownedId in @($script:OwnedIds)) {
        try {
            $remaining = @(Get-PowerPlans | Where-Object Id -eq $ownedId)
            if ($remaining.Count -eq 0) { continue }
            Assert-Live (-not $script:OriginalIds.Contains($ownedId)) 'Cleanup encountered original GUID.'
            Assert-Live ((Get-ActivePlanId) -ne $ownedId) 'Cleanup refuses to delete an active plan.'
            Remove-ManagedPowerPlan -Id $ownedId -ExpectedName $remaining[0].Name -BackupRoot $script:LiveRoot | Out-Null
            Write-LiveResult 'Cleanup owned temporary plan' 'PASS' $ownedId
        } catch { $operationFailed = $true; Write-LiveResult 'Cleanup failed; temporary GUID retained' 'FAIL' ($ownedId + ' ' + $_.Exception.Message) }
    }

    try {
        $afterPlans = @(Get-PowerPlans)
        Assert-Live ($afterPlans.Count -eq $originals.Count) 'Final plan count differs from baseline.'
        Assert-Live ((Get-ActivePlanId) -eq $script:OriginalActive) 'Final active plan differs from baseline.'
        foreach ($original in $originals) {
            $currentPlan = @($afterPlans | Where-Object Id -eq $original.Id)
            Assert-Live ($currentPlan.Count -eq 1 -and $currentPlan[0].Name -ceq $original.Name) ('Original plan is missing/renamed: ' + $original.Id)
            $query = (Invoke-PowerCfg -Arguments @('/query', $original.Id)).StdOut
            $fullQuery = (Invoke-PowerCfg -Arguments @('/qh', $original.Id)).StdOut
            Assert-Live ($query -ceq $original.Query -and $fullQuery -ceq $original.FullQuery) ('Original plan settings changed: ' + $original.Id)
        }
        Write-LiveResult 'Final original-state comparison' 'PASS' 'All original GUIDs, names, visible/hidden setting output and active selection match the initial snapshot.'
    } catch { $operationFailed = $true; Write-LiveResult 'Final original-state comparison' 'FAIL' $_.Exception.Message }

    $report = [pscustomobject]@{ FinishedAt = (Get-Date).ToString('o'); Passed = (-not $operationFailed); OriginalActive = $script:OriginalActive; OwnedGuids = @($script:OwnedIds); Results = $script:LiveLog.ToArray() }
    $reportPath = Join-Path $script:LiveRoot 'results.json'
    [IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($true)))
    Write-Output ('REPORT: ' + $reportPath)
}
if ($operationFailed) { exit 1 }
