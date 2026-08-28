#define AppName "CalcioAffari Local Newsroom"
#define AppVersion "1.3.3"
#define AgentDir SourcePath

[Setup]
AppId={{AC87B486-61CF-4A75-9F6F-B3F7644502A1}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=CalcioAffari
AppPublisherURL=https://calcioaffari.it
#ifdef Qualification
DefaultDirName={#QualificationDir}
#else
; Resolve LOCALAPPDATA from the process environment. This remains per-user
; while avoiding a hard dependency on the legacy shell-folder lookup, which
; can be unavailable in hardened/non-interactive Windows sessions.
DefaultDirName={%LOCALAPPDATA}\CalcioAffari
#endif
DefaultGroupName=CalcioAffari
DisableDirPage=yes
DisableProgramGroupPage=yes
OutputDir={#AgentDir}\dist
#ifdef Qualification
OutputBaseFilename=CalcioAffari-Local-Newsroom-Setup-v{#AppVersion}-qualification
#else
OutputBaseFilename=CalcioAffari-Local-Newsroom-Setup-v{#AppVersion}
#endif
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#ifdef Qualification
Uninstallable=no
#else
Uninstallable=yes
#endif
UninstallDisplayName={#AppName}
UninstallDisplayIcon={sys}\shell32.dll
VersionInfoVersion={#AppVersion}
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
DisableFinishedPage=yes

[Files]
Source: "{#AgentDir}\preinstall.ps1"; Flags: dontcopy
; Versioned runtime names make upgrades atomic if a legacy host still has
; agent.ps1 open. Runtime launchers resolve the newest version first.
Source: "{#AgentDir}\agent.ps1"; DestDir: "{app}"; DestName: "agent-{#AppVersion}.ps1"; Flags: ignoreversion
Source: "{#AgentDir}\heartbeat.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\common.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\dashboard.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\diagnose.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\launcher.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\hidden-launcher.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\repair.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\rollback.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\install.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\setup-gui.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\upgrade.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\uninstall.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\Apri-CalcioAffari.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\Disinstalla-CalcioAffari.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\version.json"; DestDir: "{app}"; DestName: "version-{#AppVersion}.json"; Flags: ignoreversion
Source: "{#AgentDir}\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AgentDir}\AUDIT-1.3.3.md"; DestDir: "{app}"; Flags: ignoreversion

#ifndef Qualification
[Icons]
Name: "{group}\CalcioAffari Local Newsroom"; Filename: "{sys}\wscript.exe"; Parameters: "//B //NoLogo ""{app}\hidden-launcher.vbs"" ""{app}\launcher.ps1"""; WorkingDir: "{app}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 14
Name: "{group}\Disinstalla CalcioAffari Local Newsroom"; Filename: "{uninstallexe}"
Name: "{autodesktop}\CalcioAffari Local Newsroom"; Filename: "{sys}\wscript.exe"; Parameters: "//B //NoLogo ""{app}\hidden-launcher.vbs"" ""{app}\launcher.ps1"""; WorkingDir: "{app}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 14
#endif

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\upgrade.ps1"""; WorkingDir: "{app}"; Flags: runhidden waituntilterminated runascurrentuser
Filename: "{sys}\wscript.exe"; Parameters: "//B //NoLogo ""{app}\hidden-launcher.vbs"" ""{app}\launcher.ps1"""; WorkingDir: "{app}"; Description: "Apri CalcioAffari Local Newsroom"; Flags: nowait runascurrentuser skipifsilent

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\uninstall.ps1"" -Confirm -KeepFiles"; WorkingDir: "{app}"; Flags: runhidden waituntilterminated; RunOnceId: "CalcioAffariCleanup"

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
  PowerShell: String;
  Parameters: String;
begin
  Result := '';
  ExtractTemporaryFile('preinstall.ps1');
  PowerShell := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Parameters := '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' +
    ExpandConstant('{tmp}\preinstall.ps1') + '" -InstallDir "' +
    ExpandConstant('{app}') + '"';
  if (not Exec(PowerShell, Parameters, '', SW_HIDE, ewWaitUntilTerminated, ResultCode)) or
     (ResultCode <> 0) then
    Result := 'Impossibile arrestare in sicurezza CalcioAffari Local Newsroom prima dell''aggiornamento.';
end;
