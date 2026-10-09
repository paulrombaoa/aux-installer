# Aux Systems Workstation Installer

One file (`AuxSetup.exe`) that installs the software for an auxiliary system workstation
(Gecko Accelerograph: Streams + Waves to start), plus optional utilities and Windows tweaks.
Bundled installers are used first; winget / download is the fallback.

## 1. Project layout

```
C:\AuxInstaller\
  Build.ps1
  AuxSetup.iss
  src\
    Install-AuxSystems.ps1
  release\                      <- created/filled by you + Build.ps1
    installers\
      Streams-Setup.exe
      Waves-Setup.msi
      AnyDesk.exe
      Advanced_IP_Scanner.exe
      revosetup.exe
      winutil.ps1               <- Build.ps1 downloads this
      winutil-tweaks.json       <- exported from WinUtil (you make this)
  dist\
    AuxSetup.exe                <- final single file
```

If your installers have different file names, change the `file` values in the manifest
inside `src\Install-AuxSystems.ps1` and the `$Expected` list in `Build.ps1`.

## 2. One-time prerequisites (on the build PC)

1. Windows 10/11, PowerShell 5.1+
2. Inno Setup 6 (jrsoftware.org)
3. Internet for the first build (ps2exe module, winutil.ps1)

## 3. Get the files

1. Put `Install-AuxSystems.ps1` in `src\`; `Build.ps1` and `AuxSetup.iss` in the root.
2. Drop the installers into `release\installers\` using the names above.
3. Make the tweaks config: run WinUtil (`irm christitus.com/win | iex`), open the Tweaks tab,
   choose the tweaks you want, use the Config / Export button, and save as
   `release\installers\winutil-tweaks.json`.

## 4. Fill in silent switches (VERIFY on a test run)

In the manifest, each item has `args`. Defaults are guesses until confirmed:
- Streams: `/S` is a placeholder.
- Waves (.msi): the script runs `msiexec /i ... /qn /norestart` itself; `args` is only for extra MSI properties (e.g. `ALLUSERS=1`), usually empty.
- AnyDesk: `--install "C:\Program Files (x86)\AnyDesk" --start-with-win --silent`
- Advanced IP Scanner, Revo: `/VERYSILENT /NORESTART`

Optionally paste each file's SHA256 (printed by `Build.ps1` step 3) into `sha256`.

## 5. Test in stages

1. **Script only, dry run**
   ```
   Set-ExecutionPolicy -Scope Process Bypass
   cd C:\AuxInstaller
   .\src\Install-AuxSystems.ps1
   ```
   Tick everything + Dry run + Install. Expect `DRY RUN` lines and no errors.
2. **Real run of one utility** (e.g. Revo) with Dry run off. Confirm it installs.
3. **Real run of Streams, then Waves.** Confirm each launches.
4. **Tweaks last.** A restore point is created first. Review the tweak list before running.
5. **Build:** `.\Build.ps1`. Expected: step 3 lists your files, step 4 builds `release\AuxInstaller.exe`,
   step 6 shows `dist\AuxSetup.exe`.
6. **Packaged behavior:** AuxSetup.exe shows a small progress window while it unpacks, then the installer GUI opens. Closing the GUI cleans up the temp files.
7. **Offline test:** disconnect the network, run `dist\AuxSetup.exe` alone (copied to another folder
   or PC). The GUI should appear and installs should say "source: bundled file".

## 6. Adding another system later

Copy the Gecko block in `$BuiltInManifest` (or a `systems.json` beside the EXE), change the
id/name/apps, drop the installers in `release\installers\`, add names to `$Expected` in
`Build.ps1`, rebuild, and bump the version in the script header, `Build.ps1`, and `AuxSetup.iss`.

## 7. Logs and troubleshooting

- Logs: `C:\ProgramData\AuxInstaller\logs\install-<timestamp>.log`
- "bundled file not found": the file name in `installers\` doesn't match the manifest.
- SmartScreen / antivirus warnings are common for unsigned ps2exe and Inno EXEs. Internal
  distribution: tell workmates to expect it, or sign the EXE with a code-signing certificate.
- `AuxInstaller.exe` starts but nothing extracted from the package: confirm `release\installers\`
  contents were present at compile time, then rebuild.
