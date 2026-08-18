#define AppName "CalcioAffari Local Newsroom"
#define AppVersion "0.8.4"
#define AgentDir SourcePath

[Setup]
AppId={{AC87B486-61CF-4A75-9F6F-B3F7644502A1}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=CalcioAffari
AppPublisherURL=https://calcioaffari.it
DefaultDirName={localappdata}\CalcioAffari
DisableDirPage=yes
DisableProgramGroupPage=yes
OutputDir={#AgentDir}\dist
OutputBaseFilename=CalcioAffari-Local-Newsroom-Setup-v{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Uninstallable=no
CloseApplications=no
SetupLogging=yes
DisableFinishedPage=yes

[Files]
Source: "{#AgentDir}\agent.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\dashboard.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\repair.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\install.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\setup-gui.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\uninstall.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\Apri-CalcioAffari.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\Disinstalla-CalcioAffari.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\version.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\README.md"; DestDir: "{app}"; Flags: ignoreversion

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\setup-gui.ps1"""; WorkingDir: "{app}"; Description: "Configura CalcioAffari Local Newsroom"; Flags: nowait runascurrentuser
