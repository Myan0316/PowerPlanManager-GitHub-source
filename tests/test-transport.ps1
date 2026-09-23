[CmdletBinding()]
param([string]$CorePath)
$ErrorActionPreference = 'Stop'
if (-not $CorePath) { $CorePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\PowerPlan.Core.ps1' }
. $CorePath
$testDir = Join-Path (Split-Path -Parent $PSScriptRoot) ('artifacts\tests\transport-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testDir)
$testExe = Join-Path $testDir 'ArgumentProbe.exe'
$testCode = @'
using System;
using System.Text;
using System.Threading;
public static class ArgumentProbe {
    public static int Main(string[] args) {
        if (args[0] == "sleep") { Thread.Sleep(30000); return 0; }
        if (args[0] == "flood") {
            Console.Out.Write(new string('O', 262144));
            Console.Error.Write(new string('E', 262144));
            return 0;
        }
        if (args[0] == "fail") { Console.Error.Write("probe failure"); return 7; }
        for (int i = 1; i < args.Length; i++) Console.WriteLine(Convert.ToBase64String(Encoding.UTF8.GetBytes(args[i])));
        return 0;
    }
}
'@
Add-Type -TypeDefinition $testCode -OutputAssembly $testExe -OutputType ConsoleApplication
$script:PowerCfgPath = $testExe
$values = [string[]]@('', 'normal', '中文名字', 'with spaces', '"quoted"', 'C:\with space\', 'ends\\', 'a\"b', '& ! % $ ; ( ) `')
$result = Invoke-PowerCfg -Arguments (@('echo') + $values)
$lines = $result.StdOut -split "`r?`n"
if ($lines.Count -ne ($values.Count + 1)) { throw 'Argument count mismatch.' }
for ($i=0; $i -lt $values.Count; $i++) {
    $roundtrip = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($lines[$i]))
    if ($roundtrip -cne $values[$i]) { throw ('Argument mismatch at index ' + $i) }
}
Write-Output 'PASS: 9 actual process arguments, including quotes, spaces, empty, Unicode and shell punctuation.'
$result = Invoke-PowerCfg -Arguments @('flood')
if ($result.StdOut.Length -ne 262144 -or $result.StdErr.Length -ne 262144) { throw 'Concurrent stream output was truncated.' }
Write-Output 'PASS: concurrently drain 256 KiB stdout and 256 KiB stderr without deadlock.'
$result = Invoke-PowerCfg -Arguments @('fail') -AllowFailure
if ($result.ExitCode -ne 7 -or $result.StdErr -ne 'probe failure') { throw 'Failed process result was lost.' }
$failed = $false
try { Invoke-PowerCfg -Arguments @('fail') | Out-Null } catch { $failed = $_.Exception.Message -match 'probe failure' }
if (-not $failed) { throw 'Native failure did not become a controlled error.' }
Write-Output 'PASS: nonzero exit is propagated, and AllowFailure retains diagnostics.'
$watch = [Diagnostics.Stopwatch]::StartNew()
$timedOut = $false
try { Invoke-PowerCfg -Arguments @('sleep') -TimeoutMs 250 | Out-Null } catch { $timedOut = $_.Exception.Message -match '超时' }
$watch.Stop()
if (-not $timedOut -or $watch.Elapsed.TotalSeconds -gt 10) { throw 'Timeout failed to terminate the test child promptly.' }
if (@(Get-Process -Name ArgumentProbe -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $testExe }).Count -gt 0) { throw 'Timed-out child was not terminated.' }
Write-Output ('PASS: timeout controlled in {0} ms and child terminated.' -f $watch.ElapsedMilliseconds)
