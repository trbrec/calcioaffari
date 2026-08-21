#define AppName "CalcioAffari Local Newsroom"
#define AppVersion "1.1.1"
#define AgentDir SourcePath

[Setup]
AppId={{AC87B486-61CF-4A75-9F6F-B3F7644502A1}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=CalcioAffari
AppPublisherURL=https://calcioaffari.it
DefaultDirName={localappdata}\CalcioAffari
DefaultGroupName=CalcioAffari
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
Uninstallable=yes
UninstallDisplayName={#AppName}
UninstallDisplayIcon={sys}\shell32.dll
VersionInfoVersion={#AppVersion}
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
DisableFinishedPage=yes

[Files]
Source: "{#AgentDir}\agent.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\common.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\dashboard.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\diagnose.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\launcher.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\hidden-launcher.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\repair.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\install.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\setup-gui.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\upgrade.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\uninstall.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\Apri-CalcioAffari.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\Disinstalla-CalcioAffari.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\version.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\AUDIT-1.1.1.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\CalcioAffari Local Newsroom"; Filename: "{sys}\wscript.exe"; Parameters: "//B //NoLogo ""{app}\hidden-launcher.vbs"" ""{app}\launcher.ps1"""; WorkingDir: "{app}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 14
Name: "{group}\Disinstalla CalcioAffari Local Newsroom"; Filename: "{uninstallexe}"
Name: "{autodesktop}\CalcioAffari Local Newsroom"; Filename: "{sys}\wscript.exe"; Parameters: "//B //NoLogo ""{app}\hidden-launcher.vbs"" ""{app}\launcher.ps1"""; WorkingDir: "{app}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 14

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\upgrade.ps1"""; WorkingDir: "{app}"; Flags: runhidden waituntilterminated runascurrentuser
Filename: "{sys}\wscript.exe"; Parameters: "//B //NoLogo ""{app}\hidden-launcher.vbs"" ""{app}\launcher.ps1"""; WorkingDir: "{app}"; Description: "Apri CalcioAffari Local Newsroom"; Flags: nowait runascurrentuser skipifsilent

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\uninstall.ps1"" -Confirm -KeepFiles"; WorkingDir: "{app}"; Flags: runhidden waituntilterminated
