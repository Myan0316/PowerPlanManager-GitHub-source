$ErrorActionPreference = 'Stop'
$artifactDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\tests'
[void][IO.Directory]::CreateDirectory($artifactDirectory)
Start-Transcript -LiteralPath (Join-Path $artifactDirectory 'live-admin-transcript.txt') -Force | Out-Null
try {
    & (Join-Path $PSScriptRoot 'test-live.ps1') -ExecuteWrites -IncludeActivation
} catch {
    $_ | Out-String | Write-Output
    exit 1
} finally { Stop-Transcript | Out-Null }
