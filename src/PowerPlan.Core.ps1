$script:PowerCfgPath = Join-Path $env:SystemRoot 'System32\powercfg.exe'
$script:LastBackupPath = $null
$script:VisibilityBackupRoot = Join-Path $env:LOCALAPPDATA 'PowerPlanManager\VisibilityBackups'

# Read each node separately: PowerReadSettingAttributes returns a merged group/setting mask.
function Get-PowerAttributeState([string]$GroupId,[string]$SettingId) {
    $group=Resolve-PowerPlanGuid $GroupId
    $path='SYSTEM\CurrentControlSet\Control\Power\PowerSettings'
    if($group -ne 'fea3413e-7e05-4911-9a71-700331f1c294'){$path+='\'+$group}
    elseif(-not $SettingId){return [pscustomobject]@{GroupId=$group;SettingId='';Exists=$false;Kind='Missing';Value=$null;Hidden=$false}}
    if($SettingId){$path+='\'+(Resolve-PowerPlanGuid $SettingId)}
    $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($path,$false)
    try{
        if($null -eq $key){throw '该设置节点不存在，请刷新。'}
        $exists='Attributes' -in $key.GetValueNames()
        $kind=if($exists){[string]$key.GetValueKind('Attributes')}else{'Missing'}
        $value=if($kind -eq 'DWord'){[BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$key.GetValue('Attributes')),0)}else{$null}
        return [pscustomobject]@{GroupId=$group;SettingId=$SettingId;Exists=$exists;Kind=$kind;Value=$value;Hidden=($kind -eq 'DWord' -and ($value -band 1) -ne 0)}
    }finally{if($null -ne $key){$key.Dispose()}}
}
function Set-PowerAttributeValue([string]$GroupId,[string]$SettingId,[uint32]$Value) {
    $group=[guid](Resolve-PowerPlanGuid $GroupId)
    if(-not ('PowerPlanVisibilityNative' -as [type])){
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class PowerPlanVisibilityNative {
    [DllImport("powrprof.dll")] public static extern uint PowerWriteSettingAttributes(ref Guid group, IntPtr setting, uint attributes);
}
'@
    }
    $pointer=[IntPtr]::Zero
    try{
        if($SettingId){$setting=[guid](Resolve-PowerPlanGuid $SettingId);$pointer=[Runtime.InteropServices.Marshal]::AllocHGlobal(16);[Runtime.InteropServices.Marshal]::StructureToPtr($setting,$pointer,$false)}
        $result=[PowerPlanVisibilityNative]::PowerWriteSettingAttributes([ref]$group,$pointer,$Value)
        if($result -ne 0){throw ('显示属性未写入（系统错误 {0}）。权限不足时，请以管理员身份重新打开程序。' -f $result)}
    }finally{if($pointer -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::FreeHGlobal($pointer)}}
}
function Get-VisibilityMachineId {
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
    $key=$null
    try{$key=$base.OpenSubKey('SOFTWARE\Microsoft\Cryptography');$id=[string]$key.GetValue('MachineGuid');if(-not $id){throw '无法确认本机标识，已停止属性修改。'};return $id}finally{if($key){$key.Dispose()};$base.Dispose()}
}
function Write-VisibilityRecord($Record,[string]$Path) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $pending=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{
        [IO.File]::WriteAllText($pending,($Record | ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))
        if([IO.File]::Exists($Path)){[IO.File]::Replace($pending,$Path,($Path+'.bak'))}else{[IO.File]::Move($pending,$Path)}
    }finally{if([IO.File]::Exists($pending)){[IO.File]::Delete($pending)}}
}
function Read-VisibilityRecord([string]$Path) {
    $full=[IO.Path]::GetFullPath($Path);$root=[IO.Path]::GetFullPath($script:VisibilityBackupRoot).TrimEnd('\')+'\'
    if(-not $full.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetExtension($full) -ne '.json'){throw '恢复文件不在本程序的显示属性备份目录中。'}
    if((Get-Item -LiteralPath $full).Length -gt 16384){throw '显示属性备份过大。'}
    $record=[IO.File]::ReadAllText($full) | ConvertFrom-Json
    if($record.Schema -ne 1 -or $record.Machine -ne (Get-VisibilityMachineId)){throw '备份格式不支持或来自其他电脑，不能恢复。'}
    $null=Resolve-PowerPlanGuid $record.GroupId
    if($record.SettingId){$null=Resolve-PowerPlanGuid $record.SettingId}
    $before=ConvertFrom-PowerCfgNumber ([string]$record.Before)
    $after=ConvertFrom-PowerCfgNumber ([string]$record.After)
    if($null -eq $before -or $null -eq $after -or ($before -band 1) -ne 1 -or $after -ne ($before -band [uint64]4294967294) -or $record.Kind -ne 'DWord' -or $record.Phase -notin @('Prepared','Applied','Restored')){throw '显示属性备份无效，不能恢复。'}
    return $record
}
function Assert-PowerAttributeSnapshot($Actual,$Expected) {
    if($Actual.Exists -ne $Expected.Exists -or $Actual.Kind -ne $Expected.Kind -or $Actual.Value -ne $Expected.Value){throw '显示属性已被其他程序改变，已停止覆盖。请刷新后重试。'}
}
function Enable-PowerSettingVisibility($Snapshot,[string]$DisplayName) {
    $mutex=New-Object Threading.Mutex($false,'Local\PowerPlanManager.Visibility');$locked=$false
    try{
        try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
        if(-not $locked){throw '另一个窗口正在修改显示属性，请稍后再试。'}
        $now=Get-PowerAttributeState $Snapshot.GroupId $Snapshot.SettingId
        Assert-PowerAttributeSnapshot $now $Snapshot
        if($now.Kind -ne 'DWord' -or -not $now.Hidden){throw '该节点没有可解除的隐藏标志；属性缺失或类型异常时不会创建或改写。'}
        $after=[uint32]([uint64]$now.Value -band [uint64]4294967294)
        $record=[pscustomobject]@{Schema=1;Machine=(Get-VisibilityMachineId);GroupId=$now.GroupId;SettingId=$now.SettingId;Name=$DisplayName;Kind=$now.Kind;Before=$now.Value;After=$after;Phase='Prepared';Created=[DateTime]::UtcNow.ToString('o')}
        $path=Join-Path $script:VisibilityBackupRoot ([guid]::NewGuid().ToString('N')+'.json')
        Write-VisibilityRecord $record $path
        Assert-PowerAttributeSnapshot (Get-PowerAttributeState $now.GroupId $now.SettingId) $now
        try{
            Set-PowerAttributeValue $now.GroupId $now.SettingId $after
            $readback=Get-PowerAttributeState $now.GroupId $now.SettingId
            if($readback.Kind -ne 'DWord' -or $readback.Value -ne $after){throw '写入后显示属性未得到确认，请刷新核对。'}
            $record.Phase='Applied';Write-VisibilityRecord $record $path
        }catch{throw ($_.Exception.Message+"`r`n属性备份："+$path)}
        return $path
    }finally{if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
function Restore-PowerSettingVisibility([string]$Path) {
    $mutex=New-Object Threading.Mutex($false,'Local\PowerPlanManager.Visibility');$locked=$false
    try{
        try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
        if(-not $locked){throw '另一个窗口正在修改显示属性，请稍后再试。'}
        $record=Read-VisibilityRecord $Path
        if($record.Phase -eq 'Restored'){throw '这份属性备份已经恢复。'}
        $now=Get-PowerAttributeState $record.GroupId $record.SettingId
        if($now.Kind -ne 'DWord' -or $now.Value -ne $record.After){throw '当前属性与本程序修改后的状态不同，不能覆盖外部改动。'}
        Set-PowerAttributeValue $record.GroupId $record.SettingId ([uint32]$record.Before)
        $readback=Get-PowerAttributeState $record.GroupId $record.SettingId
        if($readback.Kind -ne 'DWord' -or $readback.Value -ne $record.Before){throw '恢复后的属性未得到确认，请刷新核对。'}
        $record.Phase='Restored';Write-VisibilityRecord $record $Path
    }finally{if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
}

function Get-PowerCfgEncoding {
    # .NET Framework Default is the system ANSI page; .NET (PS7) Default is UTF-8.
    if ($PSVersionTable.PSVersion.Major -le 5) { return [Text.Encoding]::Default }
    if (-not ('PowerPlanManager.NativeCodePage' -as [type])) {
        Add-Type -TypeDefinition 'namespace PowerPlanManager { public static class NativeCodePage { [System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern uint GetACP(); } }' -ErrorAction Stop
    }
    return [Text.Encoding]::GetEncoding([int][PowerPlanManager.NativeCodePage]::GetACP())
}

function ConvertTo-WindowsProcessArgument {
    param([AllowNull()][AllowEmptyString()][string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return '""' }
    if ($Value.IndexOf([char]0) -ge 0) { throw '命令参数不能包含空字符。' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $slashes++; continue }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (2 * $slashes + 1)))
        } elseif ($slashes -gt 0) { [void]$builder.Append(('\' * $slashes)) }
        [void]$builder.Append($character)
        $slashes = 0
    }
    [void]$builder.Append(('\' * (2 * $slashes)))
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-PowerCfg {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Arguments,
          [switch]$AllowFailure, [ValidateRange(100,120000)][int]$TimeoutMs = 15000)
    if (-not [IO.File]::Exists($script:PowerCfgPath)) { throw "找不到系统工具：$script:PowerCfgPath" }
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $script:PowerCfgPath
    $startInfo.Arguments = (($Arguments | ForEach-Object { ConvertTo-WindowsProcessArgument $_ }) -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = Get-PowerCfgEncoding
    $startInfo.StandardErrorEncoding = $startInfo.StandardOutputEncoding
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw '系统未能启动 powercfg。' }
        # Drain both streams concurrently; sequential ReadToEnd can deadlock.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMs)) {
            try { $process.Kill(); [void]$process.WaitForExit(3000) } catch { }
            throw "powercfg 操作超时（$TimeoutMs 毫秒）。写操作的结果可能未确认；请刷新核对，勿反复点击。"
        }
        if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdoutTask,$stderrTask),3000)) {
            throw 'powercfg 已退出，但读取输出超时；操作结果尚未确认。'
        }
        $result = [pscustomobject]@{ ExitCode=$process.ExitCode; StdOut=$stdoutTask.Result; StdErr=$stderrTask.Result; Arguments=($Arguments -join ' ') }
    } finally { $process.Dispose() }
    if ($result.ExitCode -ne 0 -and -not $AllowFailure) {
        $message = (@($result.StdErr.Trim(),$result.StdOut.Trim()) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`r`n"
        if ([string]::IsNullOrWhiteSpace($message)) { $message = '系统没有返回详细说明。' }
        if ($message -match '(?i)0x522|所需的权限|所需的特权|access is denied|privilege.*not held') {
            $message += ("`r`n" + '请关闭本程序，右键 EXE 选择“以管理员身份运行”后重试。程序不会跳过备份保护。')
        }
        throw "电源操作失败（$($result.ExitCode)）：$message"
    }
    return $result
}

function Resolve-PowerPlanGuid {
    param([Parameter(Mandatory = $true)][string]$Id)
    $parsed = [guid]::Empty
    if ($Id -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' -or
        -not [guid]::TryParseExact($Id,'D',[ref]$parsed) -or $parsed -eq [guid]::Empty) { throw '电源计划或设置 GUID 无效。请刷新后重新选择。' }
    return $parsed.ToString('D')
}

function Get-PlanIdFromText {
    param([string]$Text)
    $found = [regex]::Matches($Text,'(?im)^\s*[^:\r\n]+:\s*(?<id>[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})\s*\(.*\)\s*$')
    $ids = @($found | ForEach-Object { $_.Groups['id'].Value.ToLowerInvariant() })
    if ($ids.Count -ne 1) { throw '无法唯一识别系统返回的电源计划 GUID。' }
    return Resolve-PowerPlanGuid $ids[0]
}

function Get-PowerPlans {
    $result = Invoke-PowerCfg -Arguments @('/list')
    $plans = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}
    foreach ($line in ($result.StdOut -split '\r?\n')) {
        $match = [regex]::Match($line,'(?i)(?<id>[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})\s*\((?<name>.*)\)\s*(?<active>\*)?\s*$')
        if (-not $match.Success) {
            if ($line -match '(?i)[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}') { throw '系统的计划列表格式无法可靠识别，已停止操作。' }
            continue
        }
        $id = Resolve-PowerPlanGuid $match.Groups['id'].Value
        if ($seen.ContainsKey($id)) { throw '系统的计划列表出现重复 GUID，已停止操作。' }
        $seen[$id] = $true
        $plans.Add([pscustomobject]@{ Id=$id; Name=$match.Groups['name'].Value; IsActive=$match.Groups['active'].Success })
    }
    if ($plans.Count -eq 0) { throw '系统没有返回可识别的电源计划。' }
    return $plans.ToArray()
}

function Get-ActivePlanId {
    return Get-PlanIdFromText (Invoke-PowerCfg -Arguments @('/getactivescheme')).StdOut
}

function Get-ManagedPlan {
    param([string]$Id, [AllowNull()][string]$ExpectedName)
    $idValue = Resolve-PowerPlanGuid $Id
    $matches = @(Get-PowerPlans | Where-Object { $_.Id -eq $idValue })
    if ($matches.Count -ne 1) { throw '目标电源计划已不存在或无法唯一识别。请刷新列表。' }
    if ($PSBoundParameters.ContainsKey('ExpectedName') -and $matches[0].Name -cne $ExpectedName) { throw '计划名称已被其他程序修改，请刷新后重试。' }
    return $matches[0]
}

function ConvertFrom-PowerCfgNumber {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return $null }
    $clean = $Value.Trim()
    $number = [uint32]0
    if ($clean -match '(?i)^0x([0-9a-f]{1,8})$') {
        if ([uint32]::TryParse($Matches[1],[Globalization.NumberStyles]::AllowHexSpecifier,[Globalization.CultureInfo]::InvariantCulture,[ref]$number)) { return [uint64]$number }
    } elseif ($clean -match '^[0-9]+$') {
        if ([uint32]::TryParse($clean,[Globalization.NumberStyles]::None,[Globalization.CultureInfo]::InvariantCulture,[ref]$number)) { return [uint64]$number }
    }
    return $null
}

function ConvertFrom-PowerCfgSettings {
    param([Parameter(Mandatory = $true)][string]$Output)
    $settings = New-Object 'System.Collections.Generic.List[object]'
    $groupId = $null; $groupName = ''; $current = $null
    $guidPattern = '[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}'
    foreach ($line in ($Output -split '\r?\n')) {
        $groupMatch = [regex]::Match($line,"(?i)^\s*(?:子组|Subgroup)\s+GUID\s*:\s*(?<id>$guidPattern)\s*(?:\((?<name>.*)\))?\s*$")
        if ($groupMatch.Success) {
            if ($null -ne $current) { $settings.Add($current); $current=$null }
            $groupId = Resolve-PowerPlanGuid $groupMatch.Groups['id'].Value
            $groupName = $groupMatch.Groups['name'].Value
            continue
        }
        if ($line -match '(?i)^\s*(?:子组|Subgroup)\s+GUID\s*:') { throw '系统返回了无法识别的子组标识，已停止编辑。' }
        $settingMatch = [regex]::Match($line,"(?i)^\s*(?:电源设置|Power Setting)\s+GUID\s*:\s*(?<id>$guidPattern)\s*(?:\((?<name>.*)\))?\s*$")
        if ($settingMatch.Success) {
            if ($null -ne $current) { $settings.Add($current) }
            $current = [pscustomobject]@{
                GroupId=$groupId; GroupName=$groupName; SettingId=(Resolve-PowerPlanGuid $settingMatch.Groups['id'].Value)
                Name=$settingMatch.Groups['name'].Value; Unit=''; Min=$null; Max=$null; Increment=$null; AcValue=$null; DcValue=$null
                Choices=(New-Object 'System.Collections.Generic.List[object]'); MetadataError=''; SeenFields=@{}
            }
            continue
        }
        if ($line -match '(?i)^\s*(?:电源设置|Power Setting)\s+GUID\s*:') { throw '系统返回了无法识别的设置标识，已停止编辑。' }
        if ($null -eq $current) { continue }
        $field = [regex]::Match($line,'(?i)^\s*(?<label>最小可能的设置|最大可能的设置|可能的设置增量|当前交流电源设置索引|当前直流电源设置索引|Minimum Possible Setting|Maximum Possible Setting|Possible Settings? [Ii]ncrement|Current AC Power Setting Index|Current DC Power Setting Index)\s*:\s*(?<value>\S+)\s*$')
        if ($field.Success) {
            $label = $field.Groups['label'].Value
            $property = switch -regex ($label) {
                '^(最小|Minimum)' { 'Min'; break }
                '^(最大|Maximum)' { 'Max'; break }
                '^(可能|Possible)' { 'Increment'; break }
                '^(当前交流|Current AC)' { 'AcValue'; break }
                default { 'DcValue' }
            }
            if ($current.SeenFields.ContainsKey($property)) { $current.MetadataError='设置元数据含重复字段，保持只读。' }
            $current.SeenFields[$property]=$true
            $current.$property = ConvertFrom-PowerCfgNumber $field.Groups['value'].Value
            if ($null -eq $current.$property) { $current.MetadataError='设置数值无法可靠识别，保持只读。' }
            continue
        }
        $unit = [regex]::Match($line,'(?i)^\s*(?:可能的设置单位|Possible Settings? Units?)\s*:\s*(?<value>.*)$')
        if ($unit.Success) { $current.Unit=$unit.Groups['value'].Value.Trim(); continue }
        $choice = [regex]::Match($line,'(?i)^\s*(?:可能的设置索引|Possible Setting Index)\s*:\s*(?<value>\S+)\s*$')
        if ($choice.Success) {
            $raw = $choice.Groups['value'].Value
            $value = ConvertFrom-PowerCfgNumber $raw
            $unambiguousHex = ($raw -match '(?i)^[0-9a-f]{1,8}$' -and $raw -match '(?i)[a-f]')
            if ($unambiguousHex) { $value=ConvertFrom-PowerCfgNumber ('0x'+$raw) }
            # The text interface does not specify ambiguous unprefixed two-digit bases.
            if ($raw -notmatch '(?i)^0x' -and -not $unambiguousHex -and ($null -eq $value -or $value -gt 9)) {
                $current.MetadataError='此枚举索引的数字格式无法可靠确认，当前版本保持只读。'
                $value=$null
            }
            if ($null -eq $value) { $current.MetadataError='此枚举索引无法可靠确认，当前版本保持只读。' }
            $current.Choices.Add([pscustomobject]@{ Value=$value; Name=''; RawValue=$raw })
            continue
        }
        $friendly = [regex]::Match($line,'(?i)^\s*(?:可能的设置友好名称|Possible Setting Friendly Name)\s*:\s*(?<value>.*)$')
        if ($friendly.Success -and $current.Choices.Count -gt 0) { $current.Choices[$current.Choices.Count-1].Name=$friendly.Groups['value'].Value; continue }
    }
    if ($null -ne $current) { $settings.Add($current) }
    if ($settings.Count -eq 0) { throw '没有读取到可识别的设置。当前版本只支持中文或英文 powercfg 设置输出，其他语言不会猜测写入。' }
    $seen = @{}
    foreach ($setting in $settings) {
        $key = $setting.GroupId + '/' + $setting.SettingId
        if ($seen.ContainsKey($key)) { throw '设置列表存在重复 GUID，已停止编辑。' }
        $seen[$key]=$true
        if (-not $setting.GroupId -or $null -eq $setting.AcValue -or $null -eq $setting.DcValue) { $setting.MetadataError='没有完整的分组或交流/直流当前值，保持只读。' }
        if ($setting.Choices.Count -gt 0 -and @($setting.Choices | Where-Object { [string]::IsNullOrWhiteSpace($_.Name) }).Count -gt 0) { $setting.MetadataError='枚举名称缺失，保持只读。' }
        $setting.Choices = $setting.Choices.ToArray()
    }
    return $settings.ToArray()
}

function Get-PowerPlanSnapshot {
    param([Parameter(Mandatory = $true)][psobject]$Plan,[switch]$IncludeHidden)
    $id = Resolve-PowerPlanGuid $Plan.Id
    $verb = if ($IncludeHidden) { '/qh' } else { '/query' }
    $result = Invoke-PowerCfg -Arguments @($verb,$id)
    $settings=@();$settingsError=''
    try { $settings=@(ConvertFrom-PowerCfgSettings -Output $result.StdOut) }
    catch { $settingsError=$_.Exception.Message }
    return [pscustomobject]@{
        PlanId=$id
        RawOutput=$result.StdOut
        Settings=$settings
        SettingsError=$settingsError
    }
}

function Get-PowerSettings {
    param([Parameter(Mandatory = $true)][psobject]$Plan,[switch]$IncludeHidden)
    $snapshot = Get-PowerPlanSnapshot -Plan $Plan -IncludeHidden:$IncludeHidden
    if ($snapshot.SettingsError) { throw $snapshot.SettingsError }
    return @($snapshot.Settings)
}

function Test-PowerSettingValue {
    param([psobject]$Setting, [AllowNull()][object]$Value)
    if ($null -eq $Setting) { return '没有选择设置。' }
    $number = ConvertFrom-PowerCfgNumber ([string]$Value)
    if ($null -eq $number -or ([string]$Value).Trim() -notmatch '^\d+$') { return '数值必须是 0 到 4294967295 之间的十进制整数。' }
    if ($Setting.PSObject.Properties['MetadataError'] -and $Setting.MetadataError) { return $Setting.MetadataError }
    if ($null -ne $Setting.Choices -and $Setting.Choices.Count -gt 0) {
        if (@($Setting.Choices | Where-Object { $null -eq $_.Value }).Count -gt 0) { return '枚举元数据不完整，保持只读。' }
        if (@($Setting.Choices | Where-Object { $_.Value -eq $number }).Count -eq 0) { return "只能使用列出的枚举值：$((@($Setting.Choices | ForEach-Object { $_.Value }) -join ', '))。" }
        return $null
    }
    if ($null -eq $Setting.Min -or $null -eq $Setting.Max -or $null -eq $Setting.Increment -or
        $Setting.Min -gt $Setting.Max -or $Setting.Max -gt [uint32]::MaxValue -or $Setting.Increment -lt 1) { return '该设置没有完整可靠的范围和步长，保持只读。' }
    if ($number -lt $Setting.Min -or $number -gt $Setting.Max) { return "数值必须在 $($Setting.Min) 到 $($Setting.Max) 之间。" }
    if (($number - $Setting.Min) % $Setting.Increment -ne 0) { return "数值必须从 $($Setting.Min) 开始按 $($Setting.Increment) 递增。" }
    return $null
}

function Resolve-PlanFilePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.IndexOf([char]0) -ge 0) { throw '文件路径无效。' }
    $full = [IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetExtension($full) -ine '.pow' -or $full.Substring(2).Contains(':')) { throw '请选择普通的 .pow 电源计划文件。' }
    return $full
}

function Assert-PlanFile {
    param([string]$Path)
    if (-not [IO.File]::Exists($Path)) { throw "没有找到电源计划文件：$Path" }
    $file=Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.Length -lt 16 -or $file.Length -gt 64MB) { throw "电源计划文件大小异常：$($file.Length) 字节。" }
}

function Export-ManagedPowerPlan {
    param([Parameter(Mandatory=$true)][string]$Id,[Parameter(Mandatory=$true)][string]$Path,[switch]$Overwrite)
    $plan=Get-ManagedPlan -Id $Id
    $full=Resolve-PlanFilePath $Path
    $directory=[IO.Path]::GetDirectoryName($full)
    if (-not [IO.Directory]::Exists($directory)) { throw '目标文件夹不存在。' }
    if ([IO.Directory]::Exists($full)) { throw '导出目标是文件夹。' }
    if ([IO.File]::Exists($full) -and -not $Overwrite) { throw '目标文件已存在；未得到覆盖确认。' }
    $temporary=Join-Path $directory (([guid]::NewGuid().ToString('N'))+'.pow')
    try {
        Invoke-PowerCfg -Arguments @('/export',$temporary,$plan.Id) | Out-Null
        Assert-PlanFile $temporary
        if ([IO.File]::Exists($full)) {
            if (-not $Overwrite) { throw '导出期间目标文件已出现，未覆盖。' }
            [IO.File]::Replace($temporary,$full,$null)
        } else { [IO.File]::Move($temporary,$full) }
        Assert-PlanFile $full
        return $full
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Backup-PowerPlan {
    param([Parameter(Mandatory=$true)][psobject]$Plan,[string]$BackupRoot)
    $script:LastBackupPath=$null
    if ([string]::IsNullOrWhiteSpace($BackupRoot)) { $BackupRoot=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PowerPlanManager\Backups' }
    $directory=[IO.Path]::GetFullPath($BackupRoot)
    [void][IO.Directory]::CreateDirectory($directory)
    $name='{0}-{1}-{2}.pow' -f (Resolve-PowerPlanGuid $Plan.Id),(Get-Date -Format 'yyyyMMdd-HHmmss-fff'),([guid]::NewGuid().ToString('N'))
    $path=Export-ManagedPowerPlan -Id $Plan.Id -Path (Join-Path $directory $name)
    $script:LastBackupPath=$path
    return $path
}

function Assert-PlanName {
    param([AllowNull()][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name.Length -gt 128 -or $Name -match '[\x00-\x1f\x7f]') { throw '名称须为 1 至 128 个字符，且不能含换行或控制字符。' }
}

function Set-ManagedPowerPlan {
    param([Parameter(Mandatory=$true)][string]$Id)
    $plan=Get-ManagedPlan -Id $Id
    if ((Get-ActivePlanId) -eq $plan.Id) { return $plan }
    Invoke-PowerCfg -Arguments @('/setactive',$plan.Id) | Out-Null
    if ((Get-ActivePlanId) -ne $plan.Id) { throw '启用命令已执行，但活动计划不匹配；可能有其他程序改动，请刷新。' }
    return Get-ManagedPlan -Id $plan.Id
}

function New-ManagedPowerPlan {
    param([Parameter(Mandatory=$true)][string]$SourceId,[Parameter(Mandatory=$true)][string]$Name)
    Assert-PlanName $Name
    $plan=Get-ManagedPlan -Id $SourceId
    $newId=[guid]::NewGuid().ToString('D')
    if ($newId -in @(Get-PowerPlans | ForEach-Object { $_.Id })) { throw '新 GUID 意外冲突，请重试。' }
    try {
        Invoke-PowerCfg -Arguments @('/duplicatescheme',$plan.Id,$newId) | Out-Null
        $created=Get-ManagedPlan -Id $newId
        Invoke-PowerCfg -Arguments @('/changename',$newId,$Name) | Out-Null
        return Get-ManagedPlan -Id $newId -ExpectedName $Name
    } catch { throw "创建流程未完整完成。请刷新检查新 GUID $newId；可能已经生成副本，程序不会自动删除它。`r`n$($_.Exception.Message)" }
}

function Rename-ManagedPowerPlan {
    param([Parameter(Mandatory=$true)][string]$Id,[Parameter(Mandatory=$true)][string]$Name,
          [Parameter(Mandatory=$true)][AllowEmptyString()][string]$ExpectedName,[string]$BackupRoot)
    Assert-PlanName $Name
    $plan=Get-ManagedPlan -Id $Id -ExpectedName $ExpectedName
    if ($plan.Name -ceq $Name) { return $plan }
    $backup=Backup-PowerPlan -Plan $plan -BackupRoot $BackupRoot
    $plan=Get-ManagedPlan -Id $plan.Id -ExpectedName $ExpectedName
    try {
        Invoke-PowerCfg -Arguments @('/changename',$plan.Id,$Name) | Out-Null
        return Get-ManagedPlan -Id $plan.Id -ExpectedName $Name
    } catch { throw "重命名未得到完整确认。请刷新核对；备份：$backup`r`n$($_.Exception.Message)" }
}

function Remove-ManagedPowerPlan {
    param([Parameter(Mandatory=$true)][string]$Id,[Parameter(Mandatory=$true)][AllowEmptyString()][string]$ExpectedName,[string]$BackupRoot)
    $plan=Get-ManagedPlan -Id $Id -ExpectedName $ExpectedName
    if (@(Get-PowerPlans).Count -le 1) { throw '不能删除系统的最后一个电源计划。' }
    if ((Get-ActivePlanId) -eq $plan.Id) { throw '不能删除当前活动计划，请先手动切换。' }
    $backup=Backup-PowerPlan -Plan $plan -BackupRoot $BackupRoot
    $plan=Get-ManagedPlan -Id $plan.Id -ExpectedName $ExpectedName
    if (@(Get-PowerPlans).Count -le 1 -or (Get-ActivePlanId) -eq $plan.Id) { throw "备份期间计划状态已变化，已取消删除。备份：$backup" }
    try {
        Invoke-PowerCfg -Arguments @('/delete',$plan.Id) | Out-Null
        if ($plan.Id -in @(Get-PowerPlans | ForEach-Object { $_.Id })) { throw '删除命令返回后目标计划仍然存在。' }
        return $backup
    } catch { throw "删除未得到完整确认，请刷新核对。备份：$backup`r`n$($_.Exception.Message)" }
}

function Import-ManagedPowerPlan {
    param([Parameter(Mandatory=$true)][string]$Path)
    $full=Resolve-PlanFilePath $Path
    Assert-PlanFile $full
    $newId=[guid]::NewGuid().ToString('D')
    if ($newId -in @(Get-PowerPlans | ForEach-Object { $_.Id })) { throw '新 GUID 意外冲突，请重试。' }
    try {
        Invoke-PowerCfg -Arguments @('/import',$full,$newId) | Out-Null
        return Get-ManagedPlan -Id $newId
    } catch { throw "导入未得到完整确认，请刷新检查新 GUID $newId。程序不会覆盖或自动启用已有计划。`r`n$($_.Exception.Message)" }
}

function Get-ManagedSetting {
    param([psobject]$Plan,[string]$GroupId,[string]$SettingId)
    $group=Resolve-PowerPlanGuid $GroupId
    $setting=Resolve-PowerPlanGuid $SettingId
    $matches=@(Get-PowerSettings -Plan $Plan | Where-Object { $_.GroupId -eq $group -and $_.SettingId -eq $setting })
    if ($matches.Count -eq 0) { $matches=@(Get-PowerSettings -Plan $Plan -IncludeHidden | Where-Object { $_.GroupId -eq $group -and $_.SettingId -eq $setting }) }
    if ($matches.Count -ne 1) { throw '目标设置已不存在或无法唯一识别，请重新打开编辑窗口。' }
    return $matches[0]
}

function Assert-SettingSnapshot {
    param([psobject]$Actual,[object]$Ac,[object]$Dc)
    if ($null -eq $Actual.AcValue -or $null -eq $Actual.DcValue -or $Actual.AcValue -ne $Ac -or $Actual.DcValue -ne $Dc) { throw '设置已被其他程序改变或读取不完整；已停止后续写入，请刷新后重试。' }
}

function Set-ManagedPowerSetting {
    param([Parameter(Mandatory=$true)][string]$PlanId,[Parameter(Mandatory=$true)][psobject]$Setting,
          [Parameter(Mandatory=$true)][object]$AcValue,[Parameter(Mandatory=$true)][object]$DcValue,[string]$BackupRoot)
    $plan=Get-ManagedPlan -Id $PlanId
    $fresh=Get-ManagedSetting -Plan $plan -GroupId $Setting.GroupId -SettingId $Setting.SettingId
    Assert-SettingSnapshot $fresh $Setting.AcValue $Setting.DcValue
    foreach ($pair in @(@('交流',$AcValue),@('直流',$DcValue))) {
        $errorMessage=Test-PowerSettingValue $fresh $pair[1]
        if ($errorMessage) { throw "$($pair[0])值无效：$errorMessage" }
    }
    $targetAc=ConvertFrom-PowerCfgNumber ([string]$AcValue)
    $targetDc=ConvertFrom-PowerCfgNumber ([string]$DcValue)
    $oldAc=$fresh.AcValue; $oldDc=$fresh.DcValue
    if ($oldAc -eq $targetAc -and $oldDc -eq $targetDc) { return [pscustomobject]@{BackupPath=$null; Changed=$false; PlanId=$plan.Id} }
    $backup=Backup-PowerPlan -Plan $plan -BackupRoot $BackupRoot
    $attemptedAc=$false; $attemptedDc=$false
    $expectedAc=$oldAc; $expectedDc=$oldDc
    try {
        foreach ($side in @('Ac','Dc')) {
            $target=if($side -eq 'Ac'){$targetAc}else{$targetDc}
            $old=if($side -eq 'Ac'){$oldAc}else{$oldDc}
            if ($target -eq $old) { continue }
            $plan=Get-ManagedPlan -Id $plan.Id
            $now=Get-ManagedSetting -Plan $plan -GroupId $fresh.GroupId -SettingId $fresh.SettingId
            Assert-SettingSnapshot $now $expectedAc $expectedDc
            $validation=Test-PowerSettingValue $now $target
            if ($validation) { throw "设置范围已变化：$validation" }
            if ($side -eq 'Ac') { $attemptedAc=$true } else { $attemptedDc=$true }
            Invoke-PowerCfg -Arguments @(('/set'+$side.ToLowerInvariant()+'valueindex'),$plan.Id,$fresh.GroupId,$fresh.SettingId,[string]$target) | Out-Null
            if ($side -eq 'Ac') { $expectedAc=$target } else { $expectedDc=$target }
            $now=Get-ManagedSetting -Plan $plan -GroupId $fresh.GroupId -SettingId $fresh.SettingId
            Assert-SettingSnapshot $now $expectedAc $expectedDc
        }
        # Refresh the currently active plan only when it is still the target.
        # Never reactivate a stale cached plan after an external switch.
        if ((Get-ActivePlanId) -eq $plan.Id) { Invoke-PowerCfg -Arguments @('/setactive',$plan.Id) | Out-Null }
        $now=Get-ManagedSetting -Plan $plan -GroupId $fresh.GroupId -SettingId $fresh.SettingId
        Assert-SettingSnapshot $now $targetAc $targetDc
        return [pscustomobject]@{BackupPath=$backup; Changed=$true; PlanId=$plan.Id}
    } catch {
        $originalError=$_.Exception.Message
        $rollback=New-Object 'System.Collections.Generic.List[string]'
        $didRestore=$false
        foreach ($side in @('Dc','Ac')) {
            $attempted=if($side -eq 'Ac'){$attemptedAc}else{$attemptedDc}
            if (-not $attempted) { continue }
            $old=if($side -eq 'Ac'){$oldAc}else{$oldDc}
            $target=if($side -eq 'Ac'){$targetAc}else{$targetDc}
            $property=$side+'Value'
            try {
                $plan=Get-ManagedPlan -Id $plan.Id
                $now=Get-ManagedSetting -Plan $plan -GroupId $fresh.GroupId -SettingId $fresh.SettingId
                if ($now.$property -eq $old) { $rollback.Add("$side 值保持原值"); continue }
                if ($null -eq $now.$property -or $now.$property -ne $target) { $rollback.Add("$side 值已由其他来源改变或无法读取，未覆盖"); continue }
                $validation=Test-PowerSettingValue $now $old
                if ($validation) { $rollback.Add("$side 元数据已变化，无法安全恢复：$validation"); continue }
                Invoke-PowerCfg -Arguments @(('/set'+$side.ToLowerInvariant()+'valueindex'),$plan.Id,$fresh.GroupId,$fresh.SettingId,[string]$old) | Out-Null
                $verify=Get-ManagedSetting -Plan $plan -GroupId $fresh.GroupId -SettingId $fresh.SettingId
                if ($verify.$property -ne $old) { throw '恢复后核对不一致' }
                $didRestore=$true
                $rollback.Add("$side 值已恢复并核对")
            } catch { $rollback.Add("$side 恢复未确认：$($_.Exception.Message)") }
        }
        if ($didRestore) {
            try { if ((Get-ActivePlanId) -eq $plan.Id) { Invoke-PowerCfg -Arguments @('/setactive',$plan.Id) | Out-Null } }
            catch { $rollback.Add("恢复值已写入，但刷新当前计划失败：$($_.Exception.Message)") }
        }
        if ($rollback.Count -eq 0) { $rollback.Add('未开始写入设置值') }
        throw "设置修改未完成：$originalError`r`n$($rollback -join '；')。`r`n备份：$backup"
    }
}
