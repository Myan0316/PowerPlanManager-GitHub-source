[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$testDirectory = Join-Path $projectRoot 'tests'
$testHost = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $testHost)) { throw 'Windows PowerShell 5.1 is required.' }
# Mocked writes, subprocess probes and read-only GUI checks only.
# Real power-plan writes require explicitly running tests/test-live.ps1.
foreach ($testName in @('test-core.ps1','test-transport.ps1','verify-gui-layout.ps1','test-gui.ps1')) {
    & $testHost -NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File (Join-Path $testDirectory $testName)
    if ($LASTEXITCODE -ne 0) { throw "$testName failed (exit $LASTEXITCODE)." }
}
Write-Output 'PASS: all default regression suites completed; no real power-plan writes requested.'
