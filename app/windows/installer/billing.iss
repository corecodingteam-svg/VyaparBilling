; Inno Setup script for the Windows installer (Billing-Setup.exe).
; Build: flutter build windows --release, then  iscc /DAppVersion=1.0.0 windows\installer\billing.iss  (run from the app folder).
; The CI workflow (.github/workflows/build-apps.yml) does both and uploads the result.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define AppName "Billing"
#define AppExe "billing_app.exe"
#define BuildDir "..\..\build\windows\x64\runner\Release"

[Setup]
; Fixed so a newer installer upgrades the installed app instead of installing a second copy.
AppId={{6F0B7C0E-3D0A-4C58-9B0B-5C1F6B7E2A41}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Advaitamaa
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\..\build\installer
OutputBaseFilename=Billing-Setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Works without administrator rights (installs for the current user) unless the person chooses otherwise.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern
UninstallDisplayIcon={app}\{#AppExe}
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"
Name: "startup"; Description: "Start {#AppName} when I sign in to Windows (for a counter PC)"; GroupDescription: "Options:"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; The Visual C++ runtime that Flutter apps need; the CI workflow downloads it next to this script.
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall skipifsourcedoesntexist

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon
Name: "{userstartup}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: startup

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing the Visual C++ runtime..."; Flags: skipifdoesntexist waituntilterminated; Check: NeedsRuntime
Filename: "{app}\{#AppExe}"; Description: "Open {#AppName}"; Flags: nowait postinstall skipifsilent

[Code]
// The Visual C++ 2015-2022 runtime is registered here once installed.
function NeedsRuntime: Boolean;
var
  Installed: Cardinal;
begin
  Result := not (RegQueryDWordValue(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', Installed) and (Installed = 1));
end;
