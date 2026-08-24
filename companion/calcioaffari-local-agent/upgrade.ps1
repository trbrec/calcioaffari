[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$InstallDir = if ($env:CA_QUALIFICATION_MODE -eq '1' -and [string]$env:CA_INSTALL_DIR_OVERRIDE -match '^[A-Za-z]:\\') {
    [IO.Path]::GetFullPath([string]$env:CA_INSTALL_DIR_OVERRIDE)
} else { Join-Path $env:LOCALAPPDATA "CalcioAffari" }
$ConfigPath = Join-Path $InstallDir "agent.json"
$SecretPath = Join-Path $InstallDir "agent-token.txt"
$LogPath = Join-Path $InstallDir "upgrade.log"
$TaskName = "CalcioAffari Local Agent"
$WatchdogTaskName = "CalcioAffari Local Agent Watchdog"
$AgentVersion = "1.2.4"
. (Join-Path $PSScriptRoot "common.ps1")

function Write-UpgradeLog {
    param([string]$Level, [string]$Message)
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Add-Content -Path $LogPath -Value ("{0:o} [{1}] {2}" -f (Get-Date), $Level.ToUpperInvariant(), (Protect-CalcioAffariSecretText $Message)) -Encoding UTF8
}

function Stop-ExistingAgent {
    Stop-CalcioAffariScheduledTask -Name $TaskName | Out-Null
    Stop-CalcioAffariScheduledTask -Name $WatchdogTaskName | Out-Null
    $agentPaths = @([IO.Path]::GetFullPath((Join-Path $InstallDir 'agent.ps1'))) + @(
        Get-ChildItem -LiteralPath $InstallDir -Filter 'agent-*.ps1' -File -ErrorAction SilentlyContinue | ForEach-Object FullName
    )
    foreach ($process in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        if ($_.Name -notin @("powershell.exe", "pwsh.exe")) { return $false }
        $commandLine = [string]$_.CommandLine
        return @($agentPaths | Where-Object { $commandLine -like ("*" + $_ + "*") }).Count -gt 0
    })) {
        Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction SilentlyContinue
    }
}

function Register-AgentTasks {
    $agentPath = Get-CalcioAffariAgentPath -InstallDir $InstallDir
    $heartbeatPath = Join-Path $InstallDir "heartbeat.ps1"
    $agentCommand = (Get-CalcioAffariHiddenPowerShellLaunch -InstallDir $InstallDir -ScriptPath $agentPath).Command
    $heartbeatCommand = (Get-CalcioAffariHiddenPowerShellLaunch -InstallDir $InstallDir -ScriptPath $heartbeatPath).Command
    & schtasks.exe /Create /TN $TaskName /SC ONLOGON /TR $agentCommand /RL LIMITED /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Creazione dell'avvio automatico non riuscita." }
    & schtasks.exe /Create /TN $WatchdogTaskName /SC MINUTE /MO 5 /TR $heartbeatCommand /RL LIMITED /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Creazione del controllo automatico non riuscita." }
}

try {
    if (-not (Test-Path $ConfigPath) -or -not (Test-Path $SecretPath)) {
        Write-UpgradeLog "info" "Installazione nuova: configurazione guidata richiesta."
        exit 0
    }
    $wasPaused = Test-Path (Join-Path $InstallDir "agent-paused.txt")
    Write-UpgradeLog "info" "Aggiornamento a v${AgentVersion}: arresto dell'agente precedente."
    Stop-ExistingAgent
    Start-Sleep -Milliseconds 500
    Register-AgentTasks
    if ($wasPaused) {
        Set-CalcioAffariScheduledTaskEnabled -Name $TaskName -Enabled $false | Out-Null
        Set-CalcioAffariScheduledTaskEnabled -Name $WatchdogTaskName -Enabled $false | Out-Null
        Write-UpgradeLog "info" "Aggiornamento completato: pausa preservata."
    }
    else {
        Start-CalcioAffariScheduledTask -Name $TaskName
        Write-UpgradeLog "info" "Aggiornamento completato: agente v$AgentVersion riavviato automaticamente."
    }
    exit 0
}
catch {
    Write-UpgradeLog "error" $_.Exception.Message
    exit 1
}
