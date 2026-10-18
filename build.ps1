# Builds dist\StoneDispenser-<version>.zip for uploading to CurseForge.
# The zip holds only the StoneDispenser addon folder; the version comes from the .toc.
# Entries are written with forward slashes (Compress-Archive in Windows
# PowerShell 5.1 uses backslashes, which some unzip tools mishandle).

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$root = $PSScriptRoot
$addon = Join-Path $root 'StoneDispenser'
$toc = Get-Content (Join-Path $addon 'StoneDispenser.toc')
$version = ($toc | Where-Object { $_ -match '^## Version:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim() })
if (-not $version) { throw 'No "## Version:" line in StoneDispenser.toc' }

$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$zipPath = Join-Path $dist "StoneDispenser-$version.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath }

$zip = [IO.Compression.ZipFile]::Open($zipPath, 'Create')
try {
    Get-ChildItem $addon -Recurse -File | ForEach-Object {
        $entry = 'StoneDispenser/' + $_.FullName.Substring($addon.Length + 1).Replace('\', '/')
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $entry) | Out-Null
    }
} finally {
    $zip.Dispose()
}
Write-Output $zipPath
