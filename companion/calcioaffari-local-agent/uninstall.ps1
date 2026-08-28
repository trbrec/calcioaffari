[CmdletBinding()]
param([switch]$Confirm, [switch]$KeepFiles)

$ErrorActionPreference = "SilentlyContinue"
$InstallDir = if ($env:CA_QUALIFICATION_MODE -eq '1' -and [string]$env:CA_INSTALL_DIR_OVERRIDE -match '^[A-Za-z]:\\') {
    [IO.Path]::GetFullPath([string]$env:CA_INSTALL_DIR_OVERRIDE)
} else { Join-Path $env:LOCALAPPDATA "CalcioAffari" }
$TaskName = "CalcioAffari Local Agent"
$WatchdogTaskName = "CalcioAffari Local Agent Watchdog"
$CommonPath = Join-Path $InstallDir "common.ps1"
if (Test-Path -LiteralPath $CommonPath) { . $CommonPath }

$interactive = -not $Confirm
if ($interactive) {
    Add-Type -AssemblyName System.Windows.Forms
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Rimuovere CalcioAffari Local Newsroom, configurazione, log e credenziale cifrata?`n`nOllama e Qwen3 verranno rimossi soltanto se erano stati installati da CalcioAffari.",
        "Disinstalla CalcioAffari Local Newsroom", "YesNo", "Warning"
    )
    if ($answer -ne "Yes") { exit 0 }
}

& schtasks.exe /End /TN $TaskName 2>$null | Out-Null
& schtasks.exe /End /TN $WatchdogTaskName 2>$null | Out-Null
& schtasks.exe /Delete /TN $TaskName /F 2>$null | Out-Null
& schtasks.exe /Delete /TN $WatchdogTaskName /F 2>$null | Out-Null

if (Get-Command Stop-CalcioAffariRuntimeProcesses -ErrorAction SilentlyContinue) {
    Stop-CalcioAffariRuntimeProcesses -InstallDir $InstallDir
}

$dependencyState = if (Get-Command Get-CalcioAffariDependencyState -ErrorAction SilentlyContinue) {
    Get-CalcioAffariDependencyState -InstallDir $InstallDir
} else { $null }
$ownedModel = if ($dependencyState -and [bool]$dependencyState.model_installed_by_calcioaffari) { [string]$dependencyState.model } else { "" }
if ($ownedModel) {
    $ollama = Get-Command "ollama" -ErrorAction SilentlyContinue
    if (-not $ollama) {
        foreach ($candidate in @(
            (Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"),
            (Join-Path $env:LOCALAPPDATA "Ollama\ollama.exe"),
            (Join-Path $env:ProgramFiles "Ollama\ollama.exe")
        )) {
            if (Test-Path -LiteralPath $candidate) { $ollama = [pscustomobject]@{ Source = $candidate }; break }
        }
    }
    if ($ollama) {
        try { Start-Process -FilePath $ollama.Source -ArgumentList @("stop", $ownedModel) -WindowStyle Hidden -Wait | Out-Null } catch { }
        try { Start-Process -FilePath $ollama.Source -ArgumentList @("rm", $ownedModel) -WindowStyle Hidden -Wait | Out-Null } catch { }
    }
}
if ($dependencyState -and [bool]$dependencyState.ollama_installed_by_calcioaffari) {
    if (Get-Command Stop-CalcioAffariOwnedOllamaProcesses -ErrorAction SilentlyContinue) {
        Stop-CalcioAffariOwnedOllamaProcesses -InstallDir $InstallDir
    }
    $winget = Get-Command "winget" -ErrorAction SilentlyContinue
    if ($winget) {
        try {
            Start-Process -FilePath $winget.Source -ArgumentList @("uninstall", "--id", "Ollama.Ollama", "--exact", "--source", "winget", "--silent", "--disable-interactivity", "--accept-source-agreements") -WindowStyle Hidden -Wait | Out-Null
        }
        catch { }
    }
}

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
        "CalcioAffari Local Newsroom è stato rimosso. Le dipendenze installate dall'app sono state rimosse; quelle preesistenti sono state conservate.",
        "CalcioAffari", "OK", "Information"
    ) | Out-Null
}
