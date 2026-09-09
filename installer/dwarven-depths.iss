; ============================================================
;  Dwarven Depths - Windows installer
;  Inno Setup 6.  https://jrsoftware.org/isdl.php
;
;  Build:
;      iscc /DAppVersion=0.1.0 installer\dwarven-depths.iss
;
;  The same installer does first-time installs AND in-place upgrades.
;  That is what lets the game update itself: it downloads this exe and
;  runs it with /SILENT.
; ============================================================

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#define AppName    "Dwarven Depths"
#define Publisher  "Dwarven Engineering"
#define AppURL     "https://dwarvenengineering.com/dwarven-depths"
#define ExeName    "DwarvenDepths.exe"

; Godot export output. CLAUDE.md puts it at ../GameExports relative to the
; repo root, which is one level further up from this file. CI overrides this
; with /DSourceDir=build\windows.
#ifndef SourceDir
  #define SourceDir "..\..\GameExports"
#endif

[Setup]
; Identifies the application to Windows. It MUST stay the same forever --
; change it and every future installer looks like a different program, so
; upgrades stop replacing the old install and players end up with two.
AppId={{342DF46D-2CF2-4E0E-94AF-10BBBE62235A}

AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#Publisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}

; Per-user install, so no UAC prompt when the GAME launches the installer.
; An elevation dialog the player did not ask for is how an auto-updater gets
; mistaken for malware. The cost is that this installs per-user.
PrivilegesRequired=lowest
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=auto

OutputDir=..\dist
OutputBaseFilename=DwarvenDepths-{#AppVersion}-setup
UninstallDisplayIcon={app}\{#ExeName}
UninstallDisplayName={#AppName}

; The Godot export is a single ~98 MB exe with the pck embedded, and lzma2
; barely dents an already-compressed payload -- but it costs nothing here.
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible

; Let the installer close the running game rather than failing on a locked
; file. The updater passes /CLOSEAPPLICATIONS to use this.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#SourceDir}\{#ExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}";           Filename: "{app}\{#ExeName}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}";     Filename: "{app}\{#ExeName}"; Tasks: desktopicon

[Run]
; Offer to launch after a normal install. Skipped on a silent upgrade, where
; the game handles its own relaunch. runasoriginaluser keeps the game out of
; any elevated context.
Filename: "{app}\{#ExeName}"; Description: "Launch {#AppName}"; \
  Flags: nowait postinstall skipifsilent runasoriginaluser

[UninstallDelete]
; Installers the updater downloaded and left in the user data folder.
Type: filesandordirs; Name: "{userappdata}\Godot\app_userdata\{#AppName}\update"
