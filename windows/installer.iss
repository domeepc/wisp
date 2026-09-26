; Windows installer for Wisp (Inno Setup 6). Built by the release workflow
; after `flutter build windows --release`:
;   iscc /DAppVersion=1.2.0 windows\installer.iss
; Output: build\installers\wisp-<version>-windows-setup.exe

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
; Never change AppId: it's how upgrades find the installed copy.
AppId={{81ABD3B9-0AB4-4584-B34C-49431DC07330}
AppName=Wisp
AppVersion={#AppVersion}
AppPublisher=Wisp
DefaultDirName={autopf}\Wisp
DefaultGroupName=Wisp
DisableProgramGroupPage=yes
; Installs for the current user unless they choose all users.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\build\installers
OutputBaseFilename=wisp-{#AppVersion}-windows-setup
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\wisp.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Wisp"; Filename: "{app}\wisp.exe"
Name: "{autodesktop}\Wisp"; Filename: "{app}\wisp.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\wisp.exe"; Description: "Open Wisp"; Flags: nowait postinstall skipifsilent
