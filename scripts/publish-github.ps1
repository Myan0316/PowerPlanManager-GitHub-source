[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    # Publish only committed source that already exists on origin/main.
    $status = @(git status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $status.Count -gt 0) { throw 'Commit and push all source changes before publishing.' }
    $commit = git rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve the source commit.' }
    $origin = git remote get-url origin
    if ($LASTEXITCODE -ne 0 -or $origin -notmatch '^https://github\.com/(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$') { throw 'Expected an HTTPS GitHub origin.' }
    $repository = $Matches.owner + '/' + $Matches.repo
    $api = 'https://api.github.com/repos/' + $repository
    $source = [IO.File]::ReadAllText((Join-Path $projectRoot 'src/PowerPlanManager.ps1'))
    if ($source -notmatch "AppName = '[^']+ (?<version>\d+\.\d+\.\d+)'") { throw 'Cannot determine the application version.' }
    $version = $Matches.version
    $tag = 'v' + $version
    $notes = Join-Path $projectRoot ('docs/RELEASE_NOTES_' + $tag + '.md')
    if (-not (Test-Path -LiteralPath $notes -PathType Leaf)) { throw 'Release notes are required.' }

    # Use the configured credential helper; never print or persist credentials.
    $credentialLines = "protocol=https`nhost=github.com`n`n" | git credential fill
    if ($LASTEXITCODE -ne 0) { throw 'GitHub authentication is required.' }
    $credential = @{}
    foreach ($line in $credentialLines) {
        $pair = $line.Split('=',2)
        if ($pair.Count -eq 2) { $credential[$pair[0]] = $pair[1] }
    }
    if (-not $credential['password']) { throw 'GitHub authentication returned no credential.' }
    $headers = @{ Authorization = 'Bearer ' + $credential['password']; Accept = 'application/vnd.github+json' }
    $branch = Invoke-RestMethod -Uri ($api + '/branches/main') -Headers $headers -TimeoutSec 30
    if ($branch.commit.sha -ne $commit) { throw 'origin/main must match the local source commit.' }
    $releases = @(Invoke-RestMethod -Uri ($api + '/releases?per_page=100') -Headers $headers -TimeoutSec 30)
    if (@($releases | Where-Object tag_name -eq $tag).Count -gt 0) { throw 'This release already exists; inspect it instead of overwriting assets.' }
    $tagRefs = @(Invoke-RestMethod -Uri ($api + '/git/matching-refs/tags/' + $tag) -Headers $headers -TimeoutSec 30)
    if (@($tagRefs | Where-Object ref -eq ('refs/tags/' + $tag)).Count -gt 0) { throw 'This tag already exists; use a new version.' }

    $testHost = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    & $testHost -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'build.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Build or package verification failed; nothing was uploaded.' }
    & $testHost -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'export-source.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Source export failed; nothing was uploaded.' }
    $afterBuild = @(git status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $afterBuild.Count -gt 0 -or (git rev-parse HEAD) -ne $commit) { throw 'Source changed during release preparation.' }

    $releaseDirectory = Join-Path $projectRoot ('artifacts/github-' + $tag + '-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($releaseDirectory)
    $exeName = 'PowerPlanManager-' + $tag + '.exe'
    $exe = Join-Path $releaseDirectory $exeName
    Copy-Item -LiteralPath (Join-Path $projectRoot ('dist/电源计划管理器_' + $version + '.exe')) -Destination $exe
    $hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
    $checksum = $exe + '.sha256.txt'
    [IO.File]::WriteAllText($checksum,($hash + '  ' + $exeName + "`r`n"),(New-Object Text.UTF8Encoding($false)))
    $sourceZip = Join-Path $projectRoot 'dist/PowerPlanManager-GitHub-source.zip'
    $body = [IO.File]::ReadAllText($notes) + "`n`nSource commit: " + $commit + "`nEXE SHA-256: " + $hash
    $payload = @{ tag_name=$tag; target_commitish=$commit; name=('电源计划管理器 ' + $tag); body=$body; draft=$true; prerelease=$false } | ConvertTo-Json
    $release = Invoke-RestMethod -Method Post -Uri ($api + '/releases') -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec 60
    Write-Output ('Created draft release: ' + $release.html_url)
    # An interrupted upload leaves a draft for inspection, never a partial public release.
    $evidence = @()
    foreach ($file in @($exe,$checksum,$sourceZip)) {
        $name = [IO.Path]::GetFileName($file)
        $upload = $release.upload_url -replace '\{.*$', ''
        $asset = Invoke-RestMethod -Method Post -Uri ($upload + '?name=' + [Uri]::EscapeDataString($name)) -Headers $headers -ContentType 'application/octet-stream' -InFile $file -TimeoutSec 60
        $expected = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($asset.state -ne 'uploaded' -or $asset.digest -ne ('sha256:' + $expected)) { throw ('Remote checksum mismatch: ' + $name) }
        $downloadHeaders = @{ Authorization=$headers.Authorization; Accept='application/octet-stream' }
        $download = Join-Path $releaseDirectory ('download-' + $name)
        Invoke-WebRequest -UseBasicParsing -Uri $asset.url -Headers $downloadHeaders -OutFile $download -TimeoutSec 60 | Out-Null
        if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw ('Downloaded asset mismatch: ' + $name) }
        $evidence += [pscustomobject]@{ Name=$name; SHA256=$expected; AssetId=$asset.id; DownloadVerified=$true }
    }
    $branch = Invoke-RestMethod -Uri ($api + '/branches/main') -Headers $headers -TimeoutSec 30
    $finalStatus = @(git status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $finalStatus.Count -gt 0 -or (git rev-parse HEAD) -ne $commit -or $branch.commit.sha -ne $commit) { throw 'Source changed before publication; draft retained.' }
    $published = Invoke-RestMethod -Method Patch -Uri $release.url -Headers $headers -ContentType 'application/json' -Body '{"draft":false,"make_latest":"true"}' -TimeoutSec 60
    $latest = Invoke-RestMethod -Uri ($api + '/releases/latest') -Headers $headers -TimeoutSec 30
    if ($published.draft -or $latest.id -ne $published.id) { throw 'Release is not the latest published release.' }
    [pscustomobject]@{ Commit=$commit; Tag=$tag; URL=$published.html_url; Assets=$evidence } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $releaseDirectory 'verification.json') -Encoding UTF8
    Write-Output ('PASS: published and downloaded all verified assets: ' + $published.html_url)
    Write-Output ('Evidence: ' + $releaseDirectory)
} finally {
    if ($credential) { $credential.Clear() }
    if ($headers) { $headers.Clear() }
    $credentialLines = $null
    Pop-Location
}
