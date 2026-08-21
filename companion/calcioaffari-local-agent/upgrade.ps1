[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$InstallDir = Join-Path $env:LOCALAPPDATA "CalcioAffari"
$ConfigPath = Join-Path $InstallDir "agent.json"
$SecretPath = Join-Path $InstallDir "agent-token.txt"
$LogPath = Join-Path $InstallDir "upgrade.log"
$TaskName = "CalcioAffari Local Agent"
$WatchdogTaskName = "CalcioAffari Local Agent Watchdog"
$AgentVersion = "1.0.8"
. (Join-Path $PSScriptRoot "common.ps1")

function Write-UpgradeLog {
    param([string]$Level, [string]$Message)
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Add-Content -Path $LogPath -Value ("{0:o} [{1}] {2}" -f (Get-Date), $Level.ToUpperInvariant(), (Protect-CalcioAffariSecretText $Message)) -Encoding UTF8
}

function Stop-ExistingAgent {
    Stop-CalcioAffariScheduledTask -Name $TaskName | Out-Null
    Stop-CalcioAffariScheduledTask -Name $WatchdogTaskName | Out-Null
    $agentPath = [IO.Path]::GetFullPath((Join-Path $InstallDir "agent.ps1"))
    foreach ($process in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -in @("powershell.exe", "pwsh.exe") -and [string]$_.CommandLine -like ("*" + $agentPath + "*")
    })) {
        Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction SilentlyContinue
    }
}

function Register-AgentTasks {
    $agentPath = Join-Path $InstallDir "agent.ps1"
    $taskCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$agentPath`""
    & schtasks.exe /Create /TN $TaskName /SC ONLOGON /TR $taskCommand /RL LIMITED /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Creazione dell'avvio automatico non riuscita." }
    & schtasks.exe /Create /TN $WatchdogTaskName /SC MINUTE /MO 5 /TR $taskCommand /RL LIMITED /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Creazione del controllo automatico non riuscita." }
}

try {
    if (-not (Test-Path $ConfigPath) -or -not (Test-Path $SecretPath)) {
        Write-UpgradeLog "info" "Installazione nuova: configurazione guidata richiesta."
        exit 0
    }
    Write-UpgradeLog "info" "Aggiornamento a v${AgentVersion}: arresto dell'agente precedente."
    Stop-ExistingAgent
    Start-Sleep -Milliseconds 500
    Register-AgentTasks
    Start-CalcioAffariScheduledTask -Name $TaskName
    Write-UpgradeLog "info" "Aggiornamento completato: agente v$AgentVersion riavviato automaticamente."
    exit 0
}
catch {
    Write-UpgradeLog "error" $_.Exception.Message
    exit 1
}
