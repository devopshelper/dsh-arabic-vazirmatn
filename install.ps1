#Requires -Version 5.1
<#
.SYNOPSIS
    Installs dsh-arabic into every DeepSeek Harness profile and replaces the
    fonts it ships with Vazirmatn.

.DESCRIPTION
    Two steps per profile, both reversible:
      1. dsh plugin --profile <profile> add dsh-arabic
      2. copy Vazirmatn (400/500/700) over the thmanyah files the plugin serves,
         after backing the originals up under %USERPROFILE%\.dsh\backups.

    By default every profile under ~/.dsh/profiles is handled (desktop, web,
    headless, anything else). Use -Profile to limit the run.

    The plugin keeps its authored font-family names; only the glyphs change, so
    the whole harness (interface, paragraphs, headings) renders in Vazirmatn.
    A restart of DeepSeek Harness is required.

.PARAMETER Profile
    One profile, or several separated by commas: -Profile desktop,web.
    Default: every profile found under ~/.dsh/profiles.

.PARAMETER DshHome
    DSH home directory. Default: DSH_HOME environment variable, else
    %USERPROFILE%\.dsh.

.PARAMETER NoFonts
    Install the plugin only, leave the fonts alone.

.PARAMETER Restore
    Put the backed-up thmanyah fonts back (undo the font swap).

.PARAMETER Restart
    Quit and relaunch DeepSeek Harness after installing. Do not use this when
    the script itself runs inside a DSH terminal: it kills that session.

.EXAMPLE
    irm https://raw.githubusercontent.com/devopshelper/dsh-arabic-vazirmatn/main/install.ps1 | iex

.EXAMPLE
    .\install.ps1 -Profile web

.EXAMPLE
    .\install.ps1 -Profile desktop,web

.EXAMPLE
    .\install.ps1 -Restore
#>
[CmdletBinding()]
param(
    [string]$Profile,
    [string]$DshHome,
    [switch]$NoFonts,
    [switch]$Restore,
    [switch]$Restart
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

$VazirmatnVersion = '33.003'
$VazirmatnZipUrl = 'https://github.com/rastikerdar/vazirmatn/releases/download/v33.003/vazirmatn-v33.003.zip'
$VazirmatnZipSha256 = '0A9AFD41967E6F57096A56A181A23F81A2B999B62F1F2A4E4B26736580854FDB'

$Weights = @(
    @{ Name = 'Regular'; Entry = 'fonts/webfonts/Vazirmatn-Regular.woff2' }
    @{ Name = 'Medium';  Entry = 'fonts/webfonts/Vazirmatn-Medium.woff2' }
    @{ Name = 'Bold';    Entry = 'fonts/webfonts/Vazirmatn-Bold.woff2' }
)
$Roles = @('thmanyahsans', 'thmanyahseriftext', 'thmanyahserifdisplay')

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Fail([string]$Message) { Write-Host "ERROR: $Message" -ForegroundColor Red; exit 1 }

# --- paths ------------------------------------------------------------------

if (-not $DshHome) {
    if ($env:DSH_HOME) { $DshHome = $env:DSH_HOME } else { $DshHome = Join-Path $env:USERPROFILE '.dsh' }
}
$DshHome = [IO.Path]::GetFullPath($DshHome)
$profilesDir = Join-Path $DshHome 'profiles'
$backupRoot = Join-Path $DshHome 'backups'
if (-not (Test-Path $profilesDir)) {
    Fail "No DSH profiles found at $profilesDir. Is DeepSeek Harness installed and has it been run once?"
}

$available = @(Get-ChildItem $profilesDir -Directory | Sort-Object Name | Select-Object -ExpandProperty Name)
if ($available.Count -eq 0) { Fail "No profiles under $profilesDir." }

if ($Profile) {
    $targets = @($Profile.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
} else {
    $targets = $available
}
$targets = @($targets | Select-Object -Unique)
if ($targets.Count -eq 0) { Fail "No profile selected." }

$missing = @($targets | Where-Object { $available -notcontains $_ })
if ($missing.Count -gt 0) {
    Fail "Profile(s) not found: $($missing -join ', '). Available: $($available -join ', ')."
}

function Get-FontsDir([string]$Name) {
    return Join-Path (Join-Path $profilesDir $Name) 'node_modules\dsh-arabic\fonts'
}

function Find-Backup([string]$Name) {
    if (-not (Test-Path $backupRoot)) { return $null }
    $dirs = @(Get-ChildItem $backupRoot -Directory | Sort-Object Name -Descending)
    $specific = @($dirs | Where-Object { $_.Name -like "dsh-arabic-fonts-$Name-*" })
    if ($specific.Count -gt 0) { return $specific[0].FullName }
    # Older runs (before per-profile names) used dsh-arabic-fonts-<timestamp>.
    $legacy = @($dirs | Where-Object { $_.Name -match '^dsh-arabic-fonts-\d{8}-\d{6}$' })
    if ($legacy.Count -gt 0) { return $legacy[0].FullName }
    return $null
}

function Restore-ProfileFonts([string]$Name) {
    $fontsDir = Get-FontsDir $Name
    if (-not (Test-Path $fontsDir)) {
        Write-Host "    ${Name}: dsh-arabic is not installed, skipping"
        return
    }
    $backup = Find-Backup $Name
    if (-not $backup) {
        Write-Host "    ${Name}: no font backup found, skipping" -ForegroundColor Yellow
        return
    }
    foreach ($role in $Roles) {
        $from = Join-Path $backup $role
        if (-not (Test-Path $from)) { continue }
        $to = Join-Path $fontsDir $role
        if (Test-Path $to) { Remove-Item $to -Recurse -Force }
        Copy-Item $from $to -Recurse -Force
    }
    foreach ($extra in @('VAZIRMATN.md', 'OFL-Vazirmatn.txt')) {
        $file = Join-Path $fontsDir $extra
        if (Test-Path $file) { Remove-Item $file -Force }
    }
    Write-Host "    ${Name}: restored from $backup"
}

# --- restore ----------------------------------------------------------------

if ($Restore) {
    Write-Step "Restoring the original thmanyah fonts"
    foreach ($name in $targets) { Restore-ProfileFonts $name }
    Write-Host ''
    Write-Host 'Restore finished. Restart DeepSeek Harness.' -ForegroundColor Green
    exit 0
}

# --- locate the DSH CLI -----------------------------------------------------

$dshPath = $null
$cmd = Get-Command dsh -ErrorAction SilentlyContinue
if ($cmd) { $dshPath = $cmd.Source }
if (-not $dshPath) {
    $candidate = Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness\resources\runtime\cli\bin\dsh.cmd'
    if (Test-Path $candidate) { $dshPath = $candidate }
}
if (-not $dshPath) {
    Fail "The 'dsh' command was not found on PATH. Install DeepSeek Harness, or add its dsh.cmd to PATH."
}

# --- download Vazirmatn once ------------------------------------------------

$extract = $null
if (-not $NoFonts) {
    $work = Join-Path $env:TEMP 'dsh-arabic-vazirmatn'
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $zipPath = Join-Path $work "vazirmatn-v$VazirmatnVersion.zip"

    Write-Step "Downloading Vazirmatn v$VazirmatnVersion"
    Invoke-WebRequest -Uri $VazirmatnZipUrl -OutFile $zipPath -UseBasicParsing
    $actualHash = (Get-FileHash $zipPath -Algorithm SHA256).Hash
    if ($actualHash -ne $VazirmatnZipSha256) {
        Remove-Item $zipPath -Force
        Fail "Vazirmatn archive checksum mismatch (got $actualHash). Aborting before touching any font."
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $extract = Join-Path $work 'fonts'
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $extract | Out-Null

    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        foreach ($weight in $Weights) {
            $entry = $zip.Entries | Where-Object { $_.FullName -eq $weight.Entry }
            if (-not $entry) { Fail "Missing $($weight.Entry) in the Vazirmatn archive." }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $extract ($weight.Name + '.woff2')), $true)
        }
        $license = $zip.Entries | Where-Object { $_.FullName -eq 'OFL.txt' }
        if ($license) { [IO.Compression.ZipFileExtensions]::ExtractToFile($license, (Join-Path $work 'OFL.txt'), $true) }
    } finally {
        $zip.Dispose()
    }
}

# --- install, profile by profile --------------------------------------------

$failed = @()
$done = @()

foreach ($name in $targets) {
    Write-Step "Profile: $name"
    try {
        & $dshPath plugin --profile $name add dsh-arabic
        if ($LASTEXITCODE -ne 0) { throw "dsh plugin add failed with exit code $LASTEXITCODE" }

        $packageJson = Join-Path (Join-Path $profilesDir $name) 'node_modules\dsh-arabic\package.json'
        if (-not (Test-Path $packageJson)) { throw "dsh-arabic did not appear in node_modules" }
        $pluginVersion = (Get-Content $packageJson -Raw | ConvertFrom-Json).version
        Write-Host "    dsh-arabic $pluginVersion"

        if ($NoFonts) { $done += $name; continue }

        $fontsDir = Get-FontsDir $name
        if (-not (Test-Path $fontsDir)) { throw "dsh-arabic has no fonts directory (use -NoFonts if this build dropped it)" }

        $currentRegular = Join-Path $fontsDir 'thmanyahsans\thmanyahsans-Regular.woff2'
        $vazirRegular = Join-Path $extract 'Regular.woff2'
        $alreadySwapped = $false
        if (Test-Path $currentRegular) {
            $alreadySwapped = ((Get-FileHash $currentRegular -Algorithm SHA256).Hash -eq (Get-FileHash $vazirRegular -Algorithm SHA256).Hash)
        }

        if ($alreadySwapped) {
            Write-Host "    fonts are already Vazirmatn, backup kept"
        } else {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $backup = Join-Path $backupRoot "dsh-arabic-fonts-$name-$stamp"
            New-Item -ItemType Directory -Force -Path $backup | Out-Null
            Copy-Item (Join-Path $fontsDir '*') $backup -Recurse -Force
            Write-Host "    backed up fonts to $backup"
        }

        foreach ($role in $Roles) {
            $dir = Join-Path $fontsDir $role
            if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            foreach ($weight in $Weights) {
                Copy-Item (Join-Path $extract ($weight.Name + '.woff2')) (Join-Path $dir ($role + '-' + $weight.Name + '.woff2'))
            }
        }

        $note = @"
# Vazirmatn override

The woff2 files in these role folders are **Vazirmatn v$VazirmatnVersion**
(weights 400/500/700), copied unmodified from the upstream release and renamed
to the filenames dsh-arabic's font loader expects. The same face serves all
three roles: interface, reading text and headings.

- Upstream: https://github.com/rastikerdar/vazirmatn
- License: SIL Open Font License 1.1 (see OFL-Vazirmatn.txt)
- Installed by: dsh-arabic-vazirmatn

To restore the original thmanyah cuts run:

    install.ps1 -Restore

Updating or reinstalling the dsh-arabic package restores its own fonts; re-run
the installer afterwards.
"@
        Set-Content -Path (Join-Path $fontsDir 'VAZIRMATN.md') -Value $note -Encoding ASCII
        if (Test-Path (Join-Path $work 'OFL.txt')) {
            Copy-Item (Join-Path $work 'OFL.txt') (Join-Path $fontsDir 'OFL-Vazirmatn.txt') -Force
        }

        $fontCount = @(Get-ChildItem $fontsDir -Recurse -File -Filter '*.woff2').Count
        if ($fontCount -ne 9) { throw "expected 9 font files after the swap, found $fontCount" }

        $done += $name
    } catch {
        Write-Host "    FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $failed += $name
    }
}

# --- restart ----------------------------------------------------------------

if ($Restart) {
    Write-Step 'Restarting DeepSeek Harness'
    Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    $exe = Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness\DeepSeek Harness.exe'
    if (Test-Path $exe) {
        Start-Process $exe
    } else {
        Write-Host 'DeepSeek Harness.exe not found; start it manually.' -ForegroundColor Yellow
    }
}

Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host "Failed profiles: $($failed -join ', ')" -ForegroundColor Red
}
if ($done.Count -gt 0) {
    Write-Host "Done: $($done -join ', ')" -ForegroundColor Green
    Write-Host "  Fonts   : Vazirmatn v$VazirmatnVersion (400/500/700)$(if ($NoFonts) { ' - skipped' })"
    Write-Host "  Backups : $backupRoot"
    Write-Host ''
    Write-Host 'Restart DeepSeek Harness completely (quit from the tray, then relaunch).'
    Write-Host 'Arabic UI: Settings > General > Language > Arabic.'
}
if ($failed.Count -gt 0) { exit 1 }
exit 0
