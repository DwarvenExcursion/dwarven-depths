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
    [switch]$Mandatory,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$repo      = Split-Path -Parent $PSScriptRoot
$iss       = Join-Path $repo "installer\dwarven-depths.iss"
$manifest  = Join-Path $repo "site\versions.json"
$notesFile = Join-Path $repo "NOTES.md"
$exportExe = Join-Path (Split-Path -Parent $repo) "GameExports\DwarvenDepths.exe"
$outExe    = Join-Path $repo "dist\DwarvenDepths-$Version-setup.exe"

# Linux is optional: a Windows-only release is still a valid release, so a
# missing Linux export is skipped rather than fatal.
$exportLinux = Join-Path (Split-Path -Parent $repo) "GameExports\DwarvenDepths.x86_64"
$outLinux    = Join-Path $repo "dist\DwarvenDepths-$Version-linux-x86_64.tar.gz"

# Inno installs per-user by default; fall back to the machine-wide path.
$iscc = "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) { $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" }
if (-not (Test-Path $iscc)) { throw "ISCC.exe not found. Install Inno Setup 6." }

# --- guard rails -----------------------------------------------------

if (-not (Test-Path $exportExe)) {
    throw "No Windows export at $exportExe. Export from Godot first."
}

# Refuse to ship an export older than the code. This has bitten once already:
# the export preset wrote to a differently-named file, so the installer kept
# packaging a two-day-old build and shipped it as a new release. Nothing else
# in the pipeline can catch that -- the installer, the hash and the manifest
# are all perfectly consistent with the wrong game.
$exportTime = (Get-Item $exportExe).LastWriteTime
$newestSource = Get-ChildItem (Join-Path $repo "dwarven-depths") -Recurse -File `
        -Include *.gd, *.tscn, *.godot, *.cfg -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\\.godot\\' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($newestSource -and $newestSource.LastWriteTime -gt $exportTime) {
    throw @"
The export is older than the source.

  export : $($exportTime.ToString('yyyy-MM-dd HH:mm'))  $exportExe
  source : $($newestSource.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))  $($newestSource.Name)

Re-export from Godot before releasing. Check that the Windows preset's
export_path is ../../GameExports/DwarvenDepths.exe -- if it writes to any
other filename, this script packages a stale build without noticing.
"@
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

# A note starts at a markdown bullet and continues through any indented
# lines under it, joined into one sentence. Everything else -- headings, and
# the paragraph at the top explaining the format -- is ignored, so the file
# can document itself without that shipping to players as patch notes.
#
# The continuation handling matters: 0.1.1 went out with both of its notes
# truncated at the line break, because an earlier version of this took only
# lines beginning with a dash and silently dropped the wrapped remainder.
$notes = @()
$current = $null
foreach ($raw in Get-Content $notesFile) {
    $line = $raw.TrimEnd()

    if ($line -match '^\s*[-*+]\s+(\S.*)$') {
        if ($current) { $notes += $current }
        $current = $Matches[1].Trim()
    }
    elseif ($current -and $line -match '^\s+\S') {
        $current = "$current " + $line.Trim()
    }
    elseif ($current) {
        $notes += $current
        $current = $null
    }
}
if ($current) { $notes += $current }

if ($notes.Count -eq 0) { throw "NOTES.md has no bullet lines (- like this)." }

# Re-running for a version that already has a manifest is nearly always a
# mistake. Inno stamps every build, so the rebuilt installer is a DIFFERENT
# file with a different SHA-256 -- and rewriting the manifest to describe it
# leaves every installed copy rejecting the download that is actually
# published. This happened once with 0.1.1 and was caught by hand.
if ((Test-Path $manifest) -and -not $Force) {
    $existing = Get-Content $manifest -Raw | ConvertFrom-Json
    if ($existing.latest.version -eq $Version) {
        throw @"
$Version already has a manifest describing a published build.

Rebuilding is not reproducible: Inno Setup stamps each build, so the new
installer has a different SHA-256. Overwriting the manifest with it would
make every installed copy reject the update that is actually on GitHub.

Bump the version, or pass -Force if this release was never published.
"@
    }
}

# --- build -----------------------------------------------------------

Write-Host "Building installer..." -ForegroundColor Cyan
& $iscc "/DAppVersion=$Version" $iss | Select-Object -Last 3
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with $LASTEXITCODE." }
if (-not (Test-Path $outExe)) { throw "Expected $outExe but it is not there." }

$size = (Get-Item $outExe).Length
$sha  = (Get-FileHash $outExe -Algorithm SHA256).Hash.ToLower()

# --- linux (optional) ------------------------------------------------

$haveLinux = Test-Path $exportLinux
if ($haveLinux) {
    if ($newestSource -and $newestSource.LastWriteTime -gt (Get-Item $exportLinux).LastWriteTime) {
        throw "The Linux export is older than the source. Re-export it, or delete " +
              "$exportLinux to cut a Windows-only release."
    }

    Write-Host "Packaging Linux build..." -ForegroundColor Cyan
    # tar.gz rather than zip: it is what a Linux user expects, and it is one
    # file. Note that an archive built on NTFS cannot carry the executable
    # bit, so the install guide tells them to chmod +x.
    tar -czf $outLinux -C (Split-Path -Parent $exportLinux) (Split-Path -Leaf $exportLinux)
    if ($LASTEXITCODE -ne 0) { throw "tar failed with $LASTEXITCODE." }

    $sizeLinux = (Get-Item $outLinux).Length
    $shaLinux  = (Get-FileHash $outLinux -Algorithm SHA256).Hash.ToLower()
} else {
    Write-Host "No Linux export found - cutting a Windows-only release." -ForegroundColor DarkYellow
}

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

# Only Windows carries installerArgs -- it is the only platform that installs
# itself. The Linux entry is a plain archive the player unpacks, so the game
# shows the address instead of a download button there.
$builds = [ordered]@{
    windows = [ordered]@{
        url           = "https://github.com/$repoSlug/releases/download/v$Version/$(Split-Path $outExe -Leaf)"
        size          = $size
        sha256        = $sha
        installerArgs = "/SILENT /NORESTART /CLOSEAPPLICATIONS"
    }
}
if ($haveLinux) {
    $builds["linux"] = [ordered]@{
        url    = "https://github.com/$repoSlug/releases/download/v$Version/$(Split-Path $outLinux -Leaf)"
        size   = $sizeLinux
        sha256 = $shaLinux
    }
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
        builds    = $builds
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
if ($haveLinux) {
    Write-Host "Built  $outLinux" -ForegroundColor Green
    Write-Host ("       {0:N1} MB   sha256 {1}" -f ($sizeLinux / 1MB), $shaLinux.Substring(0, 16))
}
Write-Host "Wrote  $manifest" -ForegroundColor Green
Write-Host ""
Write-Host "Still to do, in this order:" -ForegroundColor Yellow
Write-Host "  1. Create release v$Version on GitHub and upload everything in dist\."
Write-Host "     https://github.com/$repoSlug/releases/new?tag=v$Version"
Write-Host "  2. Commit and push site/versions.json."
Write-Host ""
Write-Host "  The manifest goes LAST. It is what tells every installed copy an"
Write-Host "  update exists, so the download must already be there when it lands."
