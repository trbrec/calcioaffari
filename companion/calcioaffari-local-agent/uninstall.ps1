[CmdletBinding()]
param([switch]$Confirm, [switch]$KeepFiles)

$ErrorActionPreference = "SilentlyContinue"
$InstallDir = if ($env:CA_QUALIFICATION_MODE -eq '1' -and [string]$env:CA_INSTALL_DIR_OVERRIDE -match '^[A-Za-z]:\\') {
    [IO.Path]::GetFullPath([string]$env:CA_INSTALL_DIR_OVERRIDE)
} else { Join-Path $env:LOCALAPPDATA "CalcioAffari" }
$TaskName = "CalcioAffari Local Agent"
$WatchdogTaskName = "CalcioAffari Local Agent Watchdog"

$interactive = -not $Confirm
if ($interactive) {
    Add-Type -AssemblyName System.Windows.Forms
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Rimuovere CalcioAffari Local Newsroom, configurazione, log e credenziale cifrata?`n`nOllama e Qwen3 saranno conservati.",
        "Disinstalla CalcioAffari Local Newsroom", "YesNo", "Warning"
    )
    if ($answer -ne "Yes") { exit 0 }
}

& schtasks.exe /End /TN $TaskName 2>$null | Out-Null
& schtasks.exe /End /TN $WatchdogTaskName 2>$null | Out-Null
& schtasks.exe /Delete /TN $TaskName /F 2>$null | Out-Null
& schtasks.exe /Delete /TN $WatchdogTaskName /F 2>$null | Out-Null

$startMenu = Join-Path ([Environment]::GetFolderPath("Programs")) "CalcioAffari"
$desktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "CalcioAffari Local Newsroom.lnk"
Remove-Item $desktopShortcut -Force -ErrorAction SilentlyContinue
Remove-Item $startMenu -Recurse -Force -ErrorAction SilentlyContinue

foreach ($name in @("agent.json", "agent-token.txt", "application-password.txt", "agent.log", "agent.previous.log", "install.log", "upgrade.log", "connection-paused.txt", "agent-paused.txt")) {
    Remove-Item (Join-Path $InstallDir $name) -Force -ErrorAction SilentlyContinue
}

if (-not $KeepFiles -and (Test-Path $InstallDir)) {
    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

if ($interactive) {
    [System.Windows.Forms.MessageBox]::Show(
        "CalcioAffari Local Newsroom è stato rimosso. Ollama e Qwen3 sono stati conservati.",
        "CalcioAffari", "OK", "Information"
    ) | Out-Null
}
