[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $env:LOCALAPPDATA "CalcioAffari\agent.json")
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$AgentVersion = "1.3.1"
$InstallDir = Split-Path -Parent $ConfigPath
$SecretPath = Join-Path $InstallDir "agent-token.txt"
$TaskName = "CalcioAffari Local Agent"
$LogPath = Join-Path $InstallDir "heartbeat.log"
$UserPausePath = Join-Path $InstallDir "agent-paused.txt"
. (Join-Path $PSScriptRoot "common.ps1")
$AgentPath = Get-CalcioAffariAgentPath -InstallDir $InstallDir

function Write-HeartbeatLog {
    param([string]$Level, [string]$Message)
    if ((Test-Path $LogPath) -and (Get-Item $LogPath).Length -gt (512 * 1024)) {
        Move-Item $LogPath (Join-Path $InstallDir "heartbeat.previous.log") -Force
    }
    Add-Content -Path $LogPath -Value ("{0:o} [{1}] {2}" -f (Get-Date), $Level.ToUpperInvariant(), (Protect-CalcioAffariSecretText $Message)) -Encoding UTF8
}

try {
    if (Test-Path $UserPausePath) { exit 0 }
    if (-not (Test-Path $ConfigPath) -or -not (Test-Path $SecretPath)) { exit 0 }
    $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not ([string]$config.site_url).StartsWith("https://")) { throw "Configurazione sito non valida." }
    $encryptedToken = [IO.File]::ReadAllText($SecretPath).Trim()
    $secureToken = ConvertTo-SecureString -String $encryptedToken
    $credential = [System.Management.Automation.PSCredential]::new("calcioaffari", $secureToken)
    $plainToken = $credential.GetNetworkCredential().Password
    $uri = ([string]$config.site_url).TrimEnd('/') + "/wp-admin/admin-ajax.php?action=ca_news_heartbeat"
    Invoke-CalcioAffariJsonRequest -Uri $uri -UserAgent "CalcioAffari-LocalAgent/$AgentVersion" -Token $plainToken -Form @{ agent_token = $plainToken } -TimeoutSeconds 25 -ExpectedProperties @("ok", "workstation_seen") | Out-Null

    $running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -in @("powershell.exe", "pwsh.exe") -and [string]$_.CommandLine -like ("*" + $AgentPath + "*")
    }).Count -gt 0
    if (-not $running) {
        Start-CalcioAffariScheduledTask -Name $TaskName | Out-Null
        Write-HeartbeatLog "warning" "Agente principale non attivo: riavvio richiesto all'attività pianificata."
    }
}
catch {
    Write-HeartbeatLog "error" $_.Exception.Message
    exit 1
}
