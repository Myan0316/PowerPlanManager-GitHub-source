$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputs = Join-Path $projectRoot 'dist'
$sourceDirectory = Join-Path $projectRoot 'src'
. (Join-Path $sourceDirectory 'PowerPlan.Core.ps1')
$canonical = Join-Path $outputs '电源计划管理器.exe'
$versioned = Join-Path $outputs '电源计划管理器_0.3.1.exe'
if ((Get-FileHash -LiteralPath $canonical).Hash -ne (Get-FileHash -LiteralPath $versioned).Hash) { throw 'Default EXE is stale.' }
$checkDirectory = Join-Path $projectRoot ('artifacts\package-default-check-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($checkDirectory)
$extraction = Start-Process -FilePath $canonical -ArgumentList ('/Q /C /T:"' + $checkDirectory + '"') -PassThru -WindowStyle Hidden
if (-not $extraction.WaitForExit(30000) -or $extraction.ExitCode -ne 0) { throw 'Default EXE extraction failed.' }
foreach ($name in @('PowerPlanManager.ps1','PowerPlan.Core.ps1','PowerPlan.UI.ps1','PowerPlanLauncher.exe')) {
    $expectedPath = if ($name -eq 'PowerPlanLauncher.exe') { Join-Path $projectRoot ('artifacts\build\' + $name) } else { Join-Path $sourceDirectory $name }
    if ((Get-FileHash -LiteralPath $expectedPath).Hash -ne (Get-FileHash -LiteralPath (Join-Path $checkDirectory $name)).Hash) { throw ('Default EXE embeds stale content: ' + $name) }
}
if (Test-Path -LiteralPath (Join-Path $checkDirectory 'PowerPlanManager.cmd')) { throw 'Default EXE still includes the obsolete CMD entry.' }
$gui = [IO.File]::ReadAllText((Join-Path $checkDirectory 'PowerPlanManager.ps1'))
if ($gui.Contains('\"$($_.Value)=$($_.Name)\"')) { throw 'Default EXE contains the reported broken formatter.' }
$testHost = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
& $testHost -NoProfile -NonInteractive -ExecutionPolicy Bypass -STA -File (Join-Path $PSScriptRoot 'test-gui.ps1') -SourcePath (Join-Path $checkDirectory 'PowerPlanManager.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Default EXE GUI regression failed.' }
$startupReportName = 'startup-default-' + [guid]::NewGuid().ToString('N') + '.json'
$startupReport = Join-Path $projectRoot ('artifacts\' + $startupReportName)
$startupDirectory = Join-Path $projectRoot ('artifacts\startup-default-check-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($startupDirectory)
$startupCommand = 'PowerPlanLauncher.exe -StartupTestReport ..\' + $startupReportName
$startup = Start-Process -FilePath $canonical -ArgumentList ('/Q /T:"' + $startupDirectory + '" /C:"' + $startupCommand + '"') -PassThru -WindowStyle Hidden
if (-not $startup.WaitForExit(30000)) { $startup.Kill(); throw 'Default EXE startup timeout.' }
if ($startup.ExitCode -ne 0) { throw 'Default EXE startup returned an error.' }
$state = Get-Content -LiteralPath $startupReport -Raw -Encoding UTF8 | ConvertFrom-Json
if ($state.Title -ne '电源计划管理器 0.3.1' -or -not $state.NativeVisible -or -not $state.Visible -or $state.ConsoleAttached -ne $false -or $state.Plans -lt 1 -or $state.Selected -ne 1) { throw 'Default EXE startup is hidden, stale or attached to a console.' }
Write-Output 'PASS: default EXE matches tested release, contains no CMD entry or broken formatter; GUI is visible and console is absent.'
Write-Output ($state | ConvertTo-Json -Compress)
Write-Output ('REPORT: ' + $startupReport)
