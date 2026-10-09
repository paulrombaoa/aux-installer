; AuxSetup.iss - packs the whole release\ folder into ONE exe (dist\AuxSetup.exe).
; It unpacks to a temp folder, runs AuxInstaller.exe, waits for it to close, then Inno
; deletes the temp files. Nothing is installed on the PC by this wrapper itself.
;
; Expected layout next to this .iss file:
;   release\AuxInstaller.exe              (built by Build.ps1 with ps2exe)
;   release\installers\Streams-Setup.exe
;   release\installers\Waves-Setup.msi
;   release\installers\AnyDesk.exe
;   release\installers\Advanced_IP_Scanner.exe
;   release\installers\revosetup.exe
;   release\installers\winutil.ps1
;   release\installers\winutil-tweaks.json

[Setup]
AppName=Aux Systems Workstation Installer
AppVersion=0.2
CreateAppDir=no
Uninstallable=no
PrivilegesRequired=admin
OutputDir=dist
OutputBaseFilename=AuxSetup
Compression=lzma2/fast
SolidCompression=yes
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
DisableFinishedPage=yes
DisableWelcomePage=yes

[Files]
Source: "release\*"; DestDir: "{tmp}\AuxSetup"; Flags: ignoreversion recursesubdirs createallsubdirs

[Run]
Filename: "{tmp}\AuxSetup\AuxInstaller.exe"; WorkingDir: "{tmp}\AuxSetup"; Flags: waituntilterminated
