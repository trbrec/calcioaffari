#define AppName "CalcioAffari Local Newsroom"
#define AppVersion "0.8.0"
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

[Files]
Source: "{#AgentDir}\agent.ps1"; DestDir: "{tmp}\CalcioAffari-Newsroom"; Flags: ignoreversion deleteafterinstall
Source: "{#AgentDir}\dashboard.ps1"; DestDir: "{tmp}\CalcioAffari-Newsroom"; Flags: ignoreversion deleteafterinstall
Source: "{#AgentDir}\repair.ps1"; DestDir: "{tmp}\CalcioAffari-Newsroom"; Flags: ignoreversion deleteafterinstall
Source: "{#AgentDir}\install.ps1"; DestDir: "{tmp}\CalcioAffari-Newsroom"; Flags: ignoreversion deleteafterinstall
Source: "{#AgentDir}\uninstall.ps1"; DestDir: "{tmp}\CalcioAffari-Newsroom"; Flags: ignoreversion deleteafterinstall
Source: "{#AgentDir}\Apri-CalcioAffari.cmd"; DestDir: "{tmp}\CalcioAffari-Newsroom"; Flags: ignoreversion deleteafterinstall
Source: "{#AgentDir}\Disinstalla-CalcioAffari.cmd"; DestDir: "{tmp}\CalcioAffari-Newsroom"; Flags: ignoreversion deleteafterinstall
Source: "{#AgentDir}\version.json"; DestDir: "{tmp}\CalcioAffari-Newsroom"; Flags: ignoreversion deleteafterinstall
Source: "{#AgentDir}\README.md"; DestDir: "{tmp}\CalcioAffari-Newsroom"; Flags: ignoreversion deleteafterinstall

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{tmp}\CalcioAffari-Newsroom\install.ps1"""; WorkingDir: "{tmp}\CalcioAffari-Newsroom"; Description: "Installa e configura CalcioAffari Local Newsroom"; Flags: waituntilterminated
