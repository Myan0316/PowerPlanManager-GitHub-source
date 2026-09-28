[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$artifactRoot = Join-Path $projectRoot 'artifacts'
$outputRoot = Join-Path $projectRoot 'dist'
$stage = Join-Path $artifactRoot ('source-export-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($stage)
[void][IO.Directory]::CreateDirectory($outputRoot)

# Explicit public source roots; do not include Git history or local evidence.
$files = New-Object 'System.Collections.Generic.List[string]'
foreach ($name in @('README.md','LICENSE','.gitignore','.gitattributes','.editorconfig')) { $files.Add($name) }
foreach ($directory in @('src','scripts','tests','docs')) {
    $entries = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot $directory) -Recurse -Force)
    if (@($entries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) { throw 'Source export does not follow reparse points.' }
    foreach ($file in ($entries | Where-Object { -not $_.PSIsContainer })) {
        if ($file.Extension -notin @('.ps1','.cs','.cmd','.md')) { throw ('Unexpected source file type: ' + $file.Name) }
        $files.Add($file.FullName.Substring($projectRoot.Length + 1))
    }
}
$manifest = New-Object 'System.Collections.Generic.List[string]'
foreach ($relativePath in ($files | Sort-Object)) {
    $source = Join-Path $projectRoot $relativePath
    $destination = Join-Path $stage $relativePath
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
    [IO.File]::Copy($source,$destination,$false)
    $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $hash) { throw 'Source changed during export.' }
    $manifest.Add($hash + '  ' + $relativePath.Replace('\','/'))
}
[IO.File]::WriteAllLines((Join-Path $stage 'SOURCE_MANIFEST.sha256'),$manifest,(New-Object Text.UTF8Encoding($false)))
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$pending = Join-Path $outputRoot ([guid]::NewGuid().ToString('N') + '.pending')
$archive = Join-Path $outputRoot 'PowerPlanManager-GitHub-source.zip'
try {
    $zip = [IO.Compression.ZipFile]::Open($pending,[IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($relativePath in @($files.ToArray()) + @('SOURCE_MANIFEST.sha256')) {
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip,(Join-Path $stage $relativePath),$relativePath.Replace('\','/'),
                [IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $zip.Dispose() }
    if ([IO.File]::Exists($archive)) {
        $previousArchive = Join-Path $artifactRoot ('source-export-previous-' + [guid]::NewGuid().ToString('N') + '.zip')
        [IO.File]::Replace($pending,$archive,$previousArchive)
    }
    else { [IO.File]::Move($pending,$archive) }
} finally { if ([IO.File]::Exists($pending)) { [IO.File]::Delete($pending) } }
Write-Output ('Exported {0} public files plus checksum manifest: {1}' -f $files.Count,$archive)
