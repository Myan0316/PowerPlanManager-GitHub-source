$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceDirectory = Join-Path $projectRoot 'src'
$testDirectory = Join-Path $projectRoot 'tests'
$work = Join-Path $projectRoot 'artifacts\build'
[void][IO.Directory]::CreateDirectory($work)
$outputs = Join-Path $projectRoot 'dist'
$source = Join-Path $sourceDirectory 'PowerPlanManager.ps1'
$launcher = Join-Path $work 'PowerPlanLauncher.exe'
$stage = Join-Path $work 'iexpress-stage'
$sedPath = Join-Path $work 'PowerPlanManager.sed'
$temporaryExe = Join-Path $work 'PowerPlanManager.exe'
$finalExe = Join-Path $outputs '电源计划管理器_0.3.2.exe'
$core = Join-Path $sourceDirectory 'PowerPlan.Core.ps1'
. $core

if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Source file not found: $source" }
$testHost = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
foreach ($testName in @('test-core.ps1','test-transport.ps1','verify-gui-layout.ps1','test-gui.ps1','test-ui.ps1','test-visibility.ps1')) {
    & $testHost -NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File (Join-Path $testDirectory $testName)
    if ($LASTEXITCODE -ne 0) { throw "$testName failed; no release was built." }
}
New-Item -ItemType Directory -Path $outputs -Force | Out-Null
# Only the explicitly listed source files are packed. Keep the staging directory
# and overwrite those files instead of recursively deleting a computed path.
New-Item -ItemType Directory -Path $stage -Force | Out-Null
if (Test-Path -LiteralPath $launcher) { Remove-Item -LiteralPath $launcher -Force }
Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $sourceDirectory 'PowerPlanLauncher.cs'))) -ReferencedAssemblies @('System.dll','System.Windows.Forms.dll') -OutputAssembly $launcher -OutputType WindowsApplication
Copy-Item -LiteralPath $source -Destination (Join-Path $stage 'PowerPlanManager.ps1') -Force
Copy-Item -LiteralPath $launcher -Destination (Join-Path $stage 'PowerPlanLauncher.exe') -Force
Copy-Item -LiteralPath $core -Destination (Join-Path $stage 'PowerPlan.Core.ps1') -Force
Copy-Item -LiteralPath (Join-Path $sourceDirectory 'PowerPlan.UI.ps1') -Destination (Join-Path $stage 'PowerPlan.UI.ps1') -Force

if (Test-Path -LiteralPath $temporaryExe) { Remove-Item -LiteralPath $temporaryExe -Force }
$sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=1
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=PowerPlanManager.exe
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
SourceFiles=SourceFiles
[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=
FriendlyName=Power Plan Manager
AppLaunched=PowerPlanLauncher.exe
[SourceFiles]
SourceFiles0=.\iexpress-stage\
[SourceFiles0]
PowerPlanManager.ps1=
PowerPlanLauncher.exe=
PowerPlan.Core.ps1=
PowerPlan.UI.ps1=
"@
[System.IO.File]::WriteAllText($sedPath, $sed, [System.Text.Encoding]::Default)

$iexpress = Join-Path $env:SystemRoot 'System32\iexpress.exe'
if (-not (Test-Path -LiteralPath $iexpress -PathType Leaf)) { throw "IExpress not found: $iexpress" }
# Relative SED paths avoid IExpress failures in checkout paths containing spaces.
$process = Start-Process -FilePath $iexpress -ArgumentList '/N /Q PowerPlanManager.sed' -WorkingDirectory $work -PassThru -WindowStyle Hidden
if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'IExpress packaging timed out after 30 seconds.' }
if ($process.ExitCode -ne 0) { throw "IExpress failed with exit code $($process.ExitCode)." }
if (-not (Test-Path -LiteralPath $temporaryExe -PathType Leaf)) { throw "IExpress completed but output was not found: $temporaryExe" }

[System.IO.File]::Copy([string]$temporaryExe, [string]$finalExe, $true)
$hash = (Get-FileHash -LiteralPath $finalExe -Algorithm SHA256).Hash
$hashPath = Join-Path $outputs '电源计划管理器_0.3.2.exe.sha256.txt'
[System.IO.File]::WriteAllText($hashPath, "$hash  电源计划管理器_0.3.2.exe`r`n", [System.Text.Encoding]::UTF8)

# Verify the actual embedded files without launching the GUI. Tests of the
# extracted payload prevent a stale/missing dependency from reaching release.
$extract = Join-Path $work ('package-check-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($extract)
$extractProcess = Start-Process -FilePath $finalExe -ArgumentList ('/Q /C /T:"' + $extract + '"') -Wait -PassThru -WindowStyle Hidden
if ($extractProcess.ExitCode -ne 0) { throw 'Package extraction check failed.' }
foreach ($name in @('PowerPlanManager.ps1','PowerPlan.Core.ps1','PowerPlan.UI.ps1','PowerPlanLauncher.exe')) {
    if ((Get-FileHash -LiteralPath (Join-Path $stage $name)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $extract $name)).Hash) { throw "Packaged file differs: $name" }
}
& $testHost -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File (Join-Path $testDirectory 'test-gui.ps1') -SourcePath (Join-Path $extract 'PowerPlanManager.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Packaged GUI test failed.' }
& $testHost -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File (Join-Path $testDirectory 'test-ui.ps1') -SourcePath (Join-Path $extract 'PowerPlanManager.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Packaged UI test failed.' }
& $testHost -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File (Join-Path $testDirectory 'test-visibility.ps1') -SourcePath (Join-Path $extract 'PowerPlanManager.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Packaged hidden settings test failed.' }
& $testHost -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File (Join-Path $testDirectory 'test-core.ps1') -CorePath (Join-Path $extract 'PowerPlan.Core.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Packaged core test failed.' }
Write-Output ('PASS: package payload hashes match; extracted GUI and core pass. ' + $extract)

$startupReportName = 'startup-' + [guid]::NewGuid().ToString('N') + '.json'
$startupReport = Join-Path $work $startupReportName
$startupDirectory = Join-Path $work ('startup-check-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($startupDirectory)
# Keep /C free of nested quotes. The launcher sets its extracted folder as cwd.
# The report lives one level above it so extraction cleanup cannot remove it.
$startupCommand = 'PowerPlanLauncher.exe -StartupTestReport ..\' + $startupReportName
$startupProcess = Start-Process -FilePath $finalExe -ArgumentList ('/Q /T:"' + $startupDirectory + '" /C:"' + $startupCommand + '"') -PassThru -WindowStyle Hidden
if (-not $startupProcess.WaitForExit(30000)) { $startupProcess.Kill(); throw 'Packaged startup did not complete within 30 seconds.' }
if ($startupProcess.ExitCode -ne 0) { throw 'Packaged startup returned an error.' }
if (-not [IO.File]::Exists($startupReport)) { throw 'Packaged startup produced no report.' }
$startupResult = Get-Content -LiteralPath $startupReport -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $startupResult.Visible -or -not $startupResult.NativeVisible -or $startupResult.Title -ne '电源计划管理器 0.3.2' -or $startupResult.Plans -lt 1 -or $startupResult.Selected -ne 1 -or $startupResult.Details -lt 100) { throw 'Packaged main window was hidden or failed to load real plan data.' }
if ($startupResult.ConsoleAttached -ne $false) { throw 'The packaged application unexpectedly attached to a console.' }
if (Get-Process -Name PowerPlanLauncher -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*\Temp\IXP*.TMP\PowerPlanLauncher.exe' }) { throw 'Startup test left a launcher running.' }
Write-Output ('PASS: actual EXE startup created a visible main window with loaded plans; report=' + $startupReport)

& (Join-Path $PSScriptRoot 'publish-release.ps1') -ReleasePath $finalExe
& $testHost -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File (Join-Path $testDirectory 'verify-default-release.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Default release entry verification failed.' }

Write-Output "Built: $finalExe"
Write-Output "SHA256: $hash"
