#Requires -Version 5.1
<#
.SYNOPSIS
    Installs dsh-arabic into a DeepSeek Harness profile and replaces the fonts
    it ships with Vazirmatn.

.DESCRIPTION
    Two steps, both reversible:
      1. dsh plugin --profile <profile> add dsh-arabic
      2. copy Vazirmatn (400/500/700) over the thmanyah files the plugin serves,
         after backing the originals up under %USERPROFILE%\.dsh\backups.

    The plugin keeps its authored font-family names; only the glyphs change, so
    the whole harness (interface, paragraphs, headings) renders in Vazirmatn.
    A restart of DeepSeek Harness is required.

.PARAMETER Profile
    DSH profile to modify: desktop, web, or any profile under ~/.dsh/profiles.
    Default: the DSH_PROFILE environment variable, else "desktop" when it
    exists, else "web".

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
if (-not (Test-Path $profilesDir)) {
    Fail "No DSH profiles found at $profilesDir. Is DeepSeek Harness installed and has it been run once?"
}

if (-not $Profile) {
    if ($env:DSH_PROFILE) {
        $Profile = $env:DSH_PROFILE
    } elseif (Test-Path (Join-Path $profilesDir 'desktop')) {
        $Profile = 'desktop'
    } elseif (Test-Path (Join-Path $profilesDir 'web')) {
        $Profile = 'web'
    } else {
        $names = (Get-ChildItem $profilesDir -Directory | Select-Object -ExpandProperty Name) -join ', '
        Fail "Could not pick a profile. Pass -Profile (available: $names)."
    }
}
$profileDir = Join-Path $profilesDir $Profile
if (-not (Test-Path $profileDir)) {
    $names = (Get-ChildItem $profilesDir -Directory | Select-Object -ExpandProperty Name) -join ', '
    Fail "Profile '$Profile' does not exist under $profilesDir (available: $names)."
}

$fontsDir = Join-Path $profileDir 'node_modules\dsh-arabic\fonts'
$backupRoot = Join-Path $DshHome 'backups'

# --- restore ----------------------------------------------------------------

if ($Restore) {
    if (-not (Test-Path $fontsDir)) { Fail "dsh-arabic is not installed in profile '$Profile'." }
    $backups = @(Get-ChildItem $backupRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'dsh-arabic-fonts-*' } |
        Sort-Object Name -Descending)
    if ($backups.Count -eq 0) {
        Fail "No font backup found under $backupRoot. Nothing to restore."
    }
    $src = $backups[0].FullName
    Write-Step "Restoring thmanyah fonts from $src"
    foreach ($role in $Roles) {
        $from = Join-Path $src $role
        if (-not (Test-Path $from)) { continue }
        $to = Join-Path $fontsDir $role
        if (Test-Path $to) { Remove-Item $to -Recurse -Force }
        Copy-Item $from $to -Recurse -Force
    }
    foreach ($extra in @('VAZIRMATN.md', 'OFL-Vazirmatn.txt')) {
        $file = Join-Path $fontsDir $extra
        if (Test-Path $file) { Remove-Item $file -Force }
    }
    Write-Host ''
    Write-Host 'Restored the original thmanyah fonts. Restart DeepSeek Harness.' -ForegroundColor Green
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

# --- install the plugin -----------------------------------------------------

Write-Step "Installing dsh-arabic into profile '$Profile'"
& $dshPath plugin --profile $Profile add dsh-arabic
if ($LASTEXITCODE -ne 0) { Fail "dsh plugin add failed with exit code $LASTEXITCODE." }

$packageJson = Join-Path $profileDir 'node_modules\dsh-arabic\package.json'
if (-not (Test-Path $packageJson)) { Fail "dsh-arabic did not appear in $profileDir\node_modules." }
$pluginVersion = (Get-Content $packageJson -Raw | ConvertFrom-Json).version
Write-Step "Installed dsh-arabic $pluginVersion"

if ($NoFonts) {
    Write-Host ''
    Write-Host 'Plugin installed. Restart DeepSeek Harness to load it.' -ForegroundColor Green
    exit 0
}
if (-not (Test-Path $fontsDir)) { Fail "dsh-arabic has no fonts directory at $fontsDir. Use -NoFonts if this build dropped it." }

# --- download Vazirmatn -----------------------------------------------------

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

# --- back up the original fonts --------------------------------------------

$currentRegular = Join-Path $fontsDir 'thmanyahsans\thmanyahsans-Regular.woff2'
$vazirRegular = Join-Path $extract 'Regular.woff2'
$alreadySwapped = $false
if (Test-Path $currentRegular) {
    $alreadySwapped = ((Get-FileHash $currentRegular -Algorithm SHA256).Hash -eq (Get-FileHash $vazirRegular -Algorithm SHA256).Hash)
}

$backup = $null
if ($alreadySwapped) {
    Write-Step 'Fonts are already Vazirmatn; skipping the backup'
} else {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $backupRoot "dsh-arabic-fonts-$stamp"
    New-Item -ItemType Directory -Force -Path $backup | Out-Null
    Copy-Item (Join-Path $fontsDir '*') $backup -Recurse -Force
    Write-Step "Backed up the original fonts to $backup"
}

# --- swap the fonts ---------------------------------------------------------

Write-Step 'Replacing the bundled fonts with Vazirmatn'
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
if ($fontCount -ne 9) { Fail "Expected 9 font files after the swap, found $fontCount." }

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
Write-Host 'Done.' -ForegroundColor Green
Write-Host "  Profile : $Profile"
Write-Host "  Plugin  : dsh-arabic $pluginVersion"
Write-Host "  Fonts   : Vazirmatn v$VazirmatnVersion (400/500/700)"
if ($backup) { Write-Host "  Backup  : $backup" }
Write-Host ''
Write-Host 'Restart DeepSeek Harness completely (quit from the tray, then relaunch).'
Write-Host 'Arabic UI: Settings > General > Language > Arabic.'
