<#
.SYNOPSIS
    Cuts a release: builds the installer, hashes it, and updates the manifest
    that both the website and every installed copy of the game read.

.DESCRIPTION
    Run this AFTER exporting the Windows build from Godot to ../GameExports.

        pwsh ci\release.ps1 -Version 0.2.0

    It does not touch git and does not publish anything. It prints the two
    steps that need your GitHub account at the end.

    Deliberately PowerShell rather than a CI workflow: exporting from Godot in
    CI needs export templates and an image pinned to 4.7.2, and you already
    export locally. The manifest is the only part that must not be done by
    hand, because a wrong SHA-256 makes every client refuse the update.

.PARAMETER Version
    Semver, no leading v. Must match config/version in project.godot.

.PARAMETER Mandatory
    Marks the release as important. Advisory only -- the panel still lets the
    player postpone it.
#>
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [switch]$Mandatory
)

$ErrorActionPreference = "Stop"

$repo      = Split-Path -Parent $PSScriptRoot
$iss       = Join-Path $repo "installer\dwarven-depths.iss"
$manifest  = Join-Path $repo "site\versions.json"
$notesFile = Join-Path $repo "NOTES.md"
$exportExe = Join-Path (Split-Path -Parent $repo) "GameExports\DwarvenDepths.exe"
$outExe    = Join-Path $repo "dist\DwarvenDepths-$Version-setup.exe"

# Inno installs per-user by default; fall back to the machine-wide path.
$iscc = "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) { $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" }
if (-not (Test-Path $iscc)) { throw "ISCC.exe not found. Install Inno Setup 6." }

# --- guard rails -----------------------------------------------------

if (-not (Test-Path $exportExe)) {
    throw "No Windows export at $exportExe. Export from Godot first."
}

$projectGodot = Get-Content (Join-Path $repo "dwarven-depths\project.godot") -Raw
if ($projectGodot -notmatch '(?m)^config/version="(.+)"$') {
    throw "project.godot has no config/version. Set it under Application > Config."
}
$projectVersion = $Matches[1]
if ($projectVersion -ne $Version) {
    throw "project.godot says $projectVersion but you asked for $Version. " +
          "The game reports its own version from there, so they must agree."
}

if (-not (Test-Path $notesFile)) { throw "NOTES.md not found - write the patch notes first." }

# ONLY lines that are actual markdown bullets. Anything else in the file --
# headings, instructions to yourself, a paragraph explaining the format -- is
# ignored, so the file can carry its own usage notes without them shipping to
# players as patch notes.
$notes = @(Get-Content $notesFile |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -match '^[-*+]\s+\S' } |
    ForEach-Object { $_ -replace '^[-*+]\s+', '' })
if ($notes.Count -eq 0) { throw "NOTES.md has no bullet lines (- like this)." }

# --- build -----------------------------------------------------------

Write-Host "Building installer..." -ForegroundColor Cyan
& $iscc "/DAppVersion=$Version" $iss | Select-Object -Last 3
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with $LASTEXITCODE." }
if (-not (Test-Path $outExe)) { throw "Expected $outExe but it is not there." }

$size = (Get-Item $outExe).Length
$sha  = (Get-FileHash $outExe -Algorithm SHA256).Hash.ToLower()

# --- manifest --------------------------------------------------------

$repoSlug = "DwarvenExcursion/dwarven-depths"
$previous = if (Test-Path $manifest) { Get-Content $manifest -Raw | ConvertFrom-Json } else { $null }

# Roll the outgoing release into history, newest first, never duplicating.
$history = @()
if ($previous) {
    $carry = @($previous.latest) + @($previous.history)
    $history = @($carry |
        Where-Object { $_ -and $_.version -and $_.version -ne $Version } |
        ForEach-Object {
            [ordered]@{ version = $_.version; released = $_.released; notes = @($_.notes) }
        } |
        Select-Object -First 25)
}

$doc = [ordered]@{
    schema  = 1
    game    = "dwarven-depths"
    title   = "Dwarven Depths"
    page    = "https://dwarvenengineering.com/dwarven-depths"
    latest  = [ordered]@{
        version   = $Version
        released  = (Get-Date -Format "yyyy-MM-dd")
        mandatory = [bool]$Mandatory
        notes     = $notes
        builds    = [ordered]@{
            windows = [ordered]@{
                url           = "https://github.com/$repoSlug/releases/download/v$Version/$(Split-Path $outExe -Leaf)"
                size          = $size
                sha256        = $sha
                installerArgs = "/SILENT /NORESTART /CLOSEAPPLICATIONS"
            }
        }
    }
    history = $history
}

# Explicitly BOM-less. Windows PowerShell's -Encoding utf8 writes a BOM, and a
# BOM makes both JSON.parse in the browser and Godot's JSON.parse_string fail.
$json = $doc | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($manifest, $json + "`n", (New-Object System.Text.UTF8Encoding($false)))

# --- what is left for a human ----------------------------------------

Write-Host ""
Write-Host "Built  $outExe" -ForegroundColor Green
Write-Host ("       {0:N1} MB   sha256 {1}" -f ($size / 1MB), $sha.Substring(0, 16))
Write-Host "Wrote  $manifest" -ForegroundColor Green
Write-Host ""
Write-Host "Still to do, in this order:" -ForegroundColor Yellow
Write-Host "  1. Create release v$Version on GitHub and upload that .exe."
Write-Host "     https://github.com/$repoSlug/releases/new?tag=v$Version"
Write-Host "  2. Commit and push site/versions.json."
Write-Host ""
Write-Host "  The manifest goes LAST. It is what tells every installed copy an"
Write-Host "  update exists, so the download must already be there when it lands."
