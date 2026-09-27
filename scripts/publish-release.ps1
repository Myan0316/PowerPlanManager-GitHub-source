[CmdletBinding()]
param([string]$ReleasePath)
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $projectDirectory 'dist'
$sourceDirectory = Join-Path $projectDirectory 'src'
if (-not $ReleasePath) { $ReleasePath = Join-Path $outputDirectory '电源计划管理器_0.3.1.exe' }
$releaseHash = (Get-FileHash -LiteralPath $ReleasePath -Algorithm SHA256).Hash
$archiveDirectory = Join-Path $projectDirectory ('artifacts\release-archive\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
$projectPrefix = [IO.Path]::GetFullPath($projectDirectory).TrimEnd('\') + '\'
foreach ($target in @($outputDirectory,$archiveDirectory)) {
    if (-not [IO.Path]::GetFullPath($target).StartsWith($projectPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Publication path escaped the project directory.' }
}
[void][IO.Directory]::CreateDirectory($archiveDirectory)

function Publish-File {
    param([string]$Source,[string]$Destination)
    $expected = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
    if ([IO.File]::Exists($Destination) -and (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -eq $expected) { return }
    $pending = Join-Path $outputDirectory ([guid]::NewGuid().ToString('N') + '.pending')
    $old = Join-Path $archiveDirectory ([IO.Path]::GetFileName($Destination))
    $movedOld = $false
    try {
        [IO.File]::Copy($Source,$pending,$false)
        if ((Get-FileHash -LiteralPath $pending -Algorithm SHA256).Hash -ne $expected) { throw 'Staged release checksum mismatch.' }
        if ([IO.File]::Exists($Destination)) { [IO.File]::Move($Destination,$old); $movedOld = $true }
        [IO.File]::Move($pending,$Destination)
    } catch {
        if ($movedOld -and -not [IO.File]::Exists($Destination)) { [IO.File]::Move($old,$Destination) }
        throw
    } finally { if ([IO.File]::Exists($pending)) { [IO.File]::Delete($pending) } }
}

# Keep the default name and source entry in sync with the tested versioned EXE.
# A running old process remains untouched; users must close and reopen it.
$canonical = Join-Path $outputDirectory '电源计划管理器.exe'
Publish-File -Source $ReleasePath -Destination $canonical
Publish-File -Source (Join-Path $sourceDirectory 'PowerPlan.Core.ps1') -Destination (Join-Path $outputDirectory 'PowerPlan.Core.ps1')
Publish-File -Source (Join-Path $sourceDirectory 'PowerPlan.UI.ps1') -Destination (Join-Path $outputDirectory 'PowerPlan.UI.ps1')
Publish-File -Source (Join-Path $sourceDirectory 'PowerPlanManager.ps1') -Destination (Join-Path $outputDirectory '电源计划管理器.ps1')
[IO.File]::WriteAllText((Join-Path $outputDirectory '电源计划管理器.exe.sha256.txt'), ($releaseHash + "  电源计划管理器.exe`r`n"),(New-Object Text.UTF8Encoding($true)))
if ((Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash -ne $releaseHash) { throw 'Default EXE differs from versioned EXE.' }
Write-Output ('PASS: default EXE and versioned EXE are identical: ' + $releaseHash)
Write-Output ('Previous publication archived at: ' + $archiveDirectory)
