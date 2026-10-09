#Requires -Version 5.1
<#
  Build.ps1 - builds dist\AuxSetup.exe (the single file you hand out).
  Run from the project root in a normal PowerShell:  .\Build.ps1
  Steps: folders -> winutil.ps1 -> installer check + hashes -> ps2exe -> Inno Setup
#>
param(
    [switch]$SkipPackage   # build release\AuxInstaller.exe only, skip the Inno Setup step
)

$ErrorActionPreference = 'Stop'
$Root    = $PSScriptRoot
$Src     = Join-Path $Root 'src\Install-AuxSystems.ps1'
$Iss     = Join-Path $Root 'AuxSetup.iss'
$Release = Join-Path $Root 'release'
$Inst    = Join-Path $Release 'installers'
$ExeOut  = Join-Path $Release 'AuxInstaller.exe'

# Files expected in release\installers\ (names must match the manifest in the script)
$Expected = @(
    'Streams-Setup.exe',
    'Waves-Setup.msi',
    'AnyDesk.exe',
    'Advanced_IP_Scanner.exe',
    'revosetup.exe',
    'winutil.ps1',
    'winutil-tweaks.json'
)

function Step($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }

# ---- 1. Folders ----
Step 1 'Checking folders'
if (-not (Test-Path $Src)) { throw "Missing $Src  (put Install-AuxSystems.ps1 in the src\ folder)" }
New-Item -ItemType Directory -Path $Inst -Force | Out-Null
Write-Host 'OK'

# ---- 2. WinUtil (download once, bundle it) ----
Step 2 'WinUtil'
$winutil = Join-Path $Inst 'winutil.ps1'
if (-not (Test-Path $winutil)) {
    Write-Host 'Downloading winutil.ps1 from the official GitHub release...'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri 'https://github.com/ChrisTitusTech/winutil/releases/latest/download/winutil.ps1' `
                          -OutFile $winutil -UseBasicParsing
        Write-Host 'Downloaded.'
    } catch {
        Write-Warning "Could not download winutil.ps1: $($_.Exception.Message)"
    }
} else {
    Write-Host 'Already present (delete it to refresh).'
}

# ---- 3. Installer check + hashes ----
Step 3 'Checking installers (hashes are for the manifest "sha256" fields)'
$missing = @()
foreach ($f in $Expected) {
    $p = Join-Path $Inst $f
    if (Test-Path $p) {
        $h = (Get-FileHash $p -Algorithm SHA256).Hash
        $mb = [Math]::Round((Get-Item $p).Length / 1MB, 1)
        Write-Host ("  OK       {0,-26} {1,8} MB  {2}" -f $f, $mb, $h)
    } else {
        Write-Host ("  MISSING  {0}" -f $f) -ForegroundColor Yellow
        $missing += $f
    }
}
if ($missing.Count) {
    Write-Warning "$($missing.Count) file(s) missing. The build continues, but those items will need internet at install time."
}

# ---- 4. Compile the GUI to EXE ----
Step 4 'Compiling AuxInstaller.exe (ps2exe)'
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host 'Installing ps2exe module...'
    Install-Module ps2exe -Scope CurrentUser -Force
}
Import-Module ps2exe
Invoke-PS2EXE -inputFile $Src -outputFile $ExeOut -noConsole -requireAdmin `
              -title 'Aux Systems Workstation Installer' -version '0.2.0.0'
if (-not (Test-Path $ExeOut)) { throw 'ps2exe did not produce AuxInstaller.exe' }
Write-Host "Built: $ExeOut"

if ($SkipPackage) { Write-Host "`nSkipPackage set - done." -ForegroundColor Green; return }

# ---- 5. Package into one EXE with Inno Setup ----
Step 5 'Packaging with Inno Setup'
$iscc = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $iscc) { throw 'Inno Setup 6 not found. Install it from jrsoftware.org, then re-run Build.ps1.' }
if (-not (Test-Path $Iss)) { throw "Missing $Iss" }

& $iscc $Iss
if ($LASTEXITCODE -ne 0) { throw "ISCC failed (exit $LASTEXITCODE)" }

# ---- 6. Result ----
Step 6 'Result'
$final = Join-Path $Root 'dist\AuxSetup.exe'
if (Test-Path $final) {
    $mb = [Math]::Round((Get-Item $final).Length / 1MB, 1)
    Write-Host "dist\AuxSetup.exe  ($mb MB)" -ForegroundColor Green
    Write-Host "SHA256: $((Get-FileHash $final -Algorithm SHA256).Hash)"
} else {
    throw 'dist\AuxSetup.exe was not created'
}
