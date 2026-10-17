; Last.fm Scrobbler — Inno Setup script
; Compile via build.ps1, or manually:
;   ISCC.exe /DAppVersion=1.2.0 setup.iss

#ifndef AppVersion
  #define AppVersion "1.1.100"
#endif

; Beta channel (ISCC /DBeta): separate AppId, folder and name so it installs
; side-by-side with the release build. Pairs with -p:Beta=true in the csproj.
#ifdef Beta
  #define AppName      "Last.fm Scrobbler Beta"
  #define AppIdGuid    "{C7D3E0F2-8A4B-4C1D-A2E3-7F6B1C2D3E4F}"
  #define InstallDir   "LastFmScrobblerBeta"
  #define OutputBase   "LastFmScrobbler-Setup-Beta"
  #define OldStartup   "Last.fm Scrobbler Beta.lnk"
#else
  #define AppName      "Last.fm Scrobbler"
  #define AppIdGuid    "{B4F2A9D1-7E3C-4A8F-9B2D-6C5E0A1F3D82}"
  #define InstallDir   "LastFmScrobbler"
  #define OutputBase   "LastFmScrobbler-Setup"
  #define OldStartup   "Last.fm Scrobbler.lnk"
#endif
#define AppPublisher "Dagkan Bayramoglu"
#define AppURL       "https://github.com/dagkan/lastfm-scrobbler"
#define AppExeName   "LastFmScrobbler.exe"

[Setup]
AppId={{#AppIdGuid}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
DefaultDirName={autopf}\{#InstallDir}
DefaultGroupName={#AppName}
AllowNoIcons=yes
LicenseFile=..\LICENSE
OutputDir=.
OutputBaseFilename={#OutputBase}-{#AppVersion}
SetupIconFile=..\app.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
UninstallDisplayIcon={app}\{#AppExeName}
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName}
; Allow silent installs (used by the in-app auto-updater)
CloseApplications=yes
RestartApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon";  Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\portable\LastFmScrobbler.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}";              Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}";    Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}";        Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
; Interactive install: show "Launch app" checkbox at the end of the wizard.
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
; Silent / auto-update: always launch the new exe so the user doesn't have to.
Filename: "{app}\{#AppExeName}"; Flags: nowait runasoriginaluser; Check: WizardSilent

[InstallDelete]
; Older versions offered a separate installer-managed "Start with Windows" task that
; created this shortcut. The app's own Settings checkbox is now the single source of
; truth (it manages the HKCU Run key directly), so remove any leftover from an upgrade.
Type: files; Name: "{autostartup}\{#OldStartup}"
