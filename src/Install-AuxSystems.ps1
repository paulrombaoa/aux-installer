#Requires -Version 5.1
<#
  Aux Systems Workstation Installer  v0.2
  Source order for every item:  1) bundled file in .\installers\   2) winget   3) direct URL
  WinUtil (Chris Titus): uses .\installers\winutil.ps1 if present, otherwise fetches online.
  Optional override: put systems.json beside the EXE to replace the built-in list.
  Build:  Invoke-PS2EXE .\Install-AuxSystems.ps1 .\AuxInstaller.exe -noConsole -requireAdmin
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------- Paths ----------
$BaseDir = if ($PSScriptRoot) { $PSScriptRoot } else {
    Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
$InstallerDir = Join-Path $BaseDir 'installers'
$LogDir       = Join-Path $env:ProgramData 'AuxInstaller\logs'   # persists after the temp folder is cleaned
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$LogFile      = Join-Path $LogDir ("install-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
$WinUtilLocal = Join-Path $InstallerDir 'winutil.ps1'
$TweaksConfig = Join-Path $InstallerDir 'winutil-tweaks.json'

# ---------- Manifest (edit this to add systems) ----------
# file   = name of the bundled installer inside .\installers\
# args   = silent install switches (VERIFY each one on a VM)
#          for .msi files the script adds "msiexec /i ... /qn /norestart" itself; args = extra properties only
# sha256 = optional; if set, the file is verified before running
$BuiltInManifest = @'
{
  "systems": [
    {
      "id": "gecko",
      "name": "Gecko Accelerograph (Streams + Waves)",
      "apps": [
        { "name": "Streams", "file": "Streams-Setup.exe", "url": "https://REPLACE-ME/Streams-Setup.exe", "args": "/quiet", "sha256": "" },
        { "name": "Waves",   "file": "Waves-Setup.msi",   "url": "https://REPLACE-ME/Waves-Setup.msi",   "args": "", "sha256": "" }
      ]
    }
  ],
  "utilities": [
    { "id": "anydesk", "name": "AnyDesk",             "file": "AnyDesk.exe",          "winget": "AnyDesk.AnyDesk",                "args": "--install \"C:\\Program Files (x86)\\AnyDesk\" --start-with-win --silent", "sha256": "" },
    { "id": "ipscan",  "name": "Advanced IP Scanner", "file": "Advanced_IP_Scanner.exe", "winget": "Famatech.AdvancedIPScanner", "args": "/VERYSILENT /NORESTART", "sha256": "" },
    { "id": "revo",    "name": "Revo Uninstaller",    "file": "revosetup.exe",        "winget": "RevoUninstaller.RevoUninstaller", "args": "/VERYSILENT /NORESTART", "sha256": "" }
  ]
}
'@

$ManifestOverride = Join-Path $BaseDir 'systems.json'
$Manifest = if (Test-Path $ManifestOverride) {
    Get-Content $ManifestOverride -Raw | ConvertFrom-Json
} else {
    $BuiltInManifest | ConvertFrom-Json
}

# ---------- Logging ----------
$script:LogBox = $null
function Write-Log([string]$Msg) {
    $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $Msg
    try { Add-Content -Path $LogFile -Value $line } catch {}
    if ($script:LogBox) {
        $script:LogBox.AppendText($line + "`r`n")
        [System.Windows.Forms.Application]::DoEvents()
    }
}

# ---------- Install helpers ----------
function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Verify hash (if given) and run an installer silently.
function Invoke-Setup([string]$Name, [string]$Path, [string]$InstallArgs, [string]$Sha256, [bool]$DryRun) {
    if ($Sha256) {
        $hash = (Get-FileHash $Path -Algorithm SHA256).Hash
        if ($hash -ne $Sha256) { Write-Log "[$Name] FAILED: SHA256 mismatch (got $hash)"; return $false }
        Write-Log "[$Name] hash verified"
    } else {
        Write-Log "[$Name] note: no sha256 in manifest, file not verified"
    }
    # MSI packages run through msiexec; "args" then holds EXTRA properties (e.g. ALLUSERS=1)
    $isMsi = [IO.Path]::GetExtension($Path) -ieq '.msi'
    $exe   = $Path
    $argLine = $InstallArgs
    if ($isMsi) {
        $exe = 'msiexec.exe'
        $argLine = "/i `"$Path`" /qn /norestart $InstallArgs".Trim()
    }

    if ($DryRun) { Write-Log "[$Name] DRY RUN - would run: $exe $argLine"; return $true }

    $p = if ($argLine) { Start-Process $exe -ArgumentList $argLine -Wait -PassThru }
         else          { Start-Process $exe -Wait -PassThru }
    # 0 = ok, 3010 = ok but reboot required, 1641 = ok, reboot initiated
    if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010 -or $p.ExitCode -eq 1641) {
        Write-Log "[$Name] OK (exit $($p.ExitCode))"; return $true
    }
    Write-Log "[$Name] FAILED (exit $($p.ExitCode))"; return $false
}

function Install-Winget([string]$Name, [string]$Id, [bool]$DryRun) {
    if ($DryRun) { Write-Log "[$Name] DRY RUN - would winget install $Id"; return $true }
    $p = Start-Process winget -Wait -PassThru -WindowStyle Hidden -ArgumentList @(
        'install','--id',$Id,'-e','--silent',
        '--accept-package-agreements','--accept-source-agreements')
    # 0 = ok, -1978335189 = already installed / no upgrade available
    if ($p.ExitCode -eq 0 -or $p.ExitCode -eq -1978335189) {
        Write-Log "[$Name] OK via winget (exit $($p.ExitCode))"; return $true
    }
    Write-Log "[$Name] winget FAILED (exit $($p.ExitCode))"; return $false
}

function Install-Item($Item, [bool]$DryRun) {
    $name = $Item.name

    # 1) bundled file
    if ($Item.file) {
        $local = Join-Path $InstallerDir $Item.file
        if (Test-Path $local) {
            Write-Log "[$name] source: bundled file ($($Item.file))"
            return (Invoke-Setup $name $local $Item.args $Item.sha256 $DryRun)
        }
        Write-Log "[$name] bundled file not found: $($Item.file)"
    }

    # 2) winget
    if ($Item.winget) {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Log "[$name] source: winget ($($Item.winget))"
            if (Install-Winget $name $Item.winget $DryRun) { return $true }
        } else {
            Write-Log "[$name] winget not available"
        }
    }

    # 3) direct URL
    if ($Item.url -and $Item.url -notmatch 'REPLACE-ME') {
        $dl = Join-Path $env:TEMP $Item.file
        Write-Log "[$name] source: download $($Item.url)"
        if ($DryRun) { Write-Log "[$name] DRY RUN - would download"; return $true }
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $Item.url -OutFile $dl -UseBasicParsing
        } catch {
            Write-Log "[$name] FAILED download: $($_.Exception.Message)"; return $false
        }
        return (Invoke-Setup $name $dl $Item.args $Item.sha256 $DryRun)
    }

    Write-Log "[$name] SKIPPED: no bundled file, winget id, or real URL available"
    return $false
}

function Invoke-Tweaks([bool]$DryRun) {
    if (-not (Test-Path $TweaksConfig)) {
        Write-Log "[Tweaks] SKIPPED: winutil-tweaks.json not found in installers\ (export it from WinUtil)"
        return $false
    }
    $useLocal = Test-Path $WinUtilLocal
    Write-Log ("[Tweaks] WinUtil source: " + $(if ($useLocal) { 'bundled winutil.ps1' } else { 'online (christitus.com/win)' }))
    if ($DryRun) { Write-Log "[Tweaks] DRY RUN - skipped"; return $true }

    try {
        Write-Log "[Tweaks] creating restore point"
        Checkpoint-Computer -Description 'AuxInstaller pre-tweaks' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    } catch {
        Write-Log "[Tweaks] restore point not created: $($_.Exception.Message)"
    }

    # Run in a child PowerShell so WinUtil can't take down the installer window.
    $psArgs = if ($useLocal) {
        @('-NoProfile','-ExecutionPolicy','Bypass','-File',$WinUtilLocal,'-Config',$TweaksConfig,'-Run')
    } else {
        $cmd = "& ([ScriptBlock]::Create((Invoke-RestMethod 'https://christitus.com/win'))) -Config '$TweaksConfig' -Run"
        @('-NoProfile','-ExecutionPolicy','Bypass','-Command',$cmd)
    }
    $p = Start-Process powershell -ArgumentList $psArgs -Wait -PassThru
    if ($p.ExitCode -eq 0) { Write-Log "[Tweaks] OK"; return $true }
    Write-Log "[Tweaks] FAILED (exit $($p.ExitCode))"; return $false
}

# ---------- GUI ----------
$form = New-Object Windows.Forms.Form
$form.Text = 'Aux Systems Workstation Installer v0.2'
$form.Size = New-Object Drawing.Size(560, 720)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

function New-Group([string]$Title, [int]$Top, [int]$Height) {
    $g = New-Object Windows.Forms.GroupBox
    $g.Text = $Title
    $g.Location = New-Object Drawing.Point(12, $Top)
    $g.Size = New-Object Drawing.Size(520, $Height)
    $form.Controls.Add($g)
    $g
}

function Add-Checks($Group, $Items) {
    $y = 22
    $list = @()
    foreach ($i in $Items) {
        $cb = New-Object Windows.Forms.CheckBox
        $cb.Text = $i.name
        $cb.Tag = $i
        $cb.AutoSize = $true
        $cb.Location = New-Object Drawing.Point(16, $y)
        $Group.Controls.Add($cb)
        $list += $cb
        $y += 26
    }
    $list
}

$sysH  = [Math]::Max(60, 30 + 26 * @($Manifest.systems).Count)
$gSys  = New-Group 'Workstation is for:' 12 $sysH
$sysCB = Add-Checks $gSys $Manifest.systems

$utilTop = 12 + $sysH + 10
$utilH   = 30 + 26 * @($Manifest.utilities).Count
$gUtil   = New-Group 'Utilities:' $utilTop $utilH
$utilCB  = Add-Checks $gUtil $Manifest.utilities

$optTop = $utilTop + $utilH + 10
$gOpt   = New-Group 'Options:' $optTop 84
$cbTweaks = New-Object Windows.Forms.CheckBox
$cbTweaks.Text = 'Apply Windows tweaks (Chris Titus WinUtil)'
$cbTweaks.AutoSize = $true
$cbTweaks.Location = New-Object Drawing.Point(16, 22)
$gOpt.Controls.Add($cbTweaks)
$cbDry = New-Object Windows.Forms.CheckBox
$cbDry.Text = 'Dry run (log only, install nothing)'
$cbDry.AutoSize = $true
$cbDry.Location = New-Object Drawing.Point(16, 48)
$gOpt.Controls.Add($cbDry)

$btnTop = $optTop + 94
$btn = New-Object Windows.Forms.Button
$btn.Text = 'Install'
$btn.Size = New-Object Drawing.Size(120, 34)
$btn.Location = New-Object Drawing.Point(412, $btnTop)
$form.Controls.Add($btn)

$script:LogBox = New-Object Windows.Forms.TextBox
$script:LogBox.Multiline = $true
$script:LogBox.ReadOnly = $true
$script:LogBox.ScrollBars = 'Vertical'
$script:LogBox.Font = New-Object Drawing.Font('Consolas', 9)
$script:LogBox.Location = New-Object Drawing.Point(12, ($btnTop + 44))
$script:LogBox.Size = New-Object Drawing.Size(520, [Math]::Max(120, 690 - ($btnTop + 44) - 40))
$form.Controls.Add($script:LogBox)

$btn.Add_Click({
    $btn.Enabled = $false
    $dry = $cbDry.Checked
    $ok = 0; $fail = 0

    $selSys  = @($sysCB  | Where-Object Checked | ForEach-Object Tag)
    $selUtil = @($utilCB | Where-Object Checked | ForEach-Object Tag)

    if (-not $selSys -and -not $selUtil -and -not $cbTweaks.Checked) {
        Write-Log 'Nothing selected.'
        $btn.Enabled = $true; return
    }

    Write-Log "Start. DryRun=$dry  Log: $LogFile"
    if (-not (Test-Admin)) { Write-Log 'WARNING: not running as administrator' }

    foreach ($s in $selSys) {
        Write-Log "=== System: $($s.name) ==="
        foreach ($a in $s.apps) {
            if (Install-Item $a $dry) { $ok++ } else { $fail++ }
        }
    }
    if ($selUtil) { Write-Log '=== Utilities ===' }
    foreach ($u in $selUtil) {
        if (Install-Item $u $dry) { $ok++ } else { $fail++ }
    }
    if ($cbTweaks.Checked) {
        Write-Log '=== Tweaks ==='
        if (Invoke-Tweaks $dry) { $ok++ } else { $fail++ }
    }

    Write-Log "Done. OK=$ok  FAILED/SKIPPED=$fail"
    $btn.Enabled = $true
})

[void]$form.ShowDialog()
