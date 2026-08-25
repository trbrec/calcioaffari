[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$InstallDir = Join-Path $env:LOCALAPPDATA "CalcioAffari"
$ConfigPath = Join-Path $InstallDir "agent.json"
$SecretPath = Join-Path $InstallDir "agent-token.txt"
$TaskName = "CalcioAffari Local Agent"
$WatchdogTaskName = "CalcioAffari Local Agent Watchdog"
$AgentVersion = "1.3.1"
$ConnectionPausePath = Join-Path $InstallDir "connection-paused.txt"
. (Join-Path $PSScriptRoot "common.ps1")

function Write-Step {
    param([string]$Message)
    Write-Host ("[CalcioAffari] " + $Message) -ForegroundColor Cyan
}

function Get-OllamaExecutable {
    $command = Get-Command "ollama" -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($candidate in @(
        (Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"),
        (Join-Path $env:LOCALAPPDATA "Ollama\ollama.exe"),
        (Join-Path $env:ProgramFiles "Ollama\ollama.exe")
    )) {
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

function Test-Ollama {
    param([string]$Url)
    try { return Invoke-RestMethod -Uri ($Url.TrimEnd('/') + "/api/tags") -Method Get -TimeoutSec 5 }
    catch { return $null }
}

function Register-Tasks {
    $agentPath = Get-CalcioAffariAgentPath -InstallDir $InstallDir
    $heartbeatPath = Join-Path $InstallDir "heartbeat.ps1"
    $agentCommand = (Get-CalcioAffariHiddenPowerShellLaunch -InstallDir $InstallDir -ScriptPath $agentPath).Command
    $heartbeatCommand = (Get-CalcioAffariHiddenPowerShellLaunch -InstallDir $InstallDir -ScriptPath $heartbeatPath).Command
    & schtasks.exe /Create /TN $TaskName /SC ONLOGON /TR $agentCommand /RL LIMITED /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Impossibile ricreare l'avvio automatico." }
    & schtasks.exe /Create /TN $WatchdogTaskName /SC MINUTE /MO 5 /TR $heartbeatCommand /RL LIMITED /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Impossibile ricreare il controllo automatico." }
}

if (-not (Test-Path $ConfigPath) -or -not (Test-Path $SecretPath)) {
    throw "Configurazione assente. Riesegui Installa-CalcioAffari.cmd dal pacchetto originale."
}
$config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

Write-Step "Controllo Ollama"
$ollama = Get-OllamaExecutable
if (-not $ollama) {
    Write-Host "Ollama non è installato: avvio dell'installazione automatica."
    $winget = Get-Command "winget" -ErrorAction SilentlyContinue
    if (-not $winget) { throw "Ollama assente e Gestione pacchetti Windows non disponibile. Riesegui l'installer completo." }
    & $winget.Source install --id Ollama.Ollama --exact --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity --silent
    $ollama = Get-OllamaExecutable
    if (-not $ollama) { throw "Installazione Ollama non completata." }
    Set-CalcioAffariDependencyOwnership -InstallDir $InstallDir -OllamaInstalledByCalcioAffari $true -Model ([string]$config.model)
    Disable-CalcioAffariOwnedOllamaAutostart -InstallDir $InstallDir
}

$tags = Test-Ollama ([string]$config.ollama_url)
if (-not $tags) {
    Start-Process -FilePath $ollama -ArgumentList "serve" -WindowStyle Hidden | Out-Null
    foreach ($attempt in 1..30) {
        Start-Sleep -Seconds 2
        $tags = Test-Ollama ([string]$config.ollama_url)
        if ($tags) { break }
    }
}
if (-not $tags) { throw "Ollama non risponde dopo il riavvio." }

$models = @($tags.models | ForEach-Object { [string]$_.name })
if ($models -notcontains ([string]$config.model) -and $models -notcontains (([string]$config.model) + ":latest")) {
    Write-Step "Ripristino del modello $($config.model)"
    & $ollama pull ([string]$config.model)
    if ($LASTEXITCODE -ne 0) { throw "Download del modello non riuscito." }
    Set-CalcioAffariDependencyOwnership -InstallDir $InstallDir -ModelInstalledByCalcioAffari $true -Model ([string]$config.model)
}

Write-Step "Sospensione dei tentativi automatici"
Stop-CalcioAffariScheduledTask -Name $TaskName | Out-Null
Stop-CalcioAffariScheduledTask -Name $WatchdogTaskName | Out-Null
[IO.File]::WriteAllText($ConnectionPausePath, "Verifica del collegamento in corso.", (New-Object Text.UTF8Encoding($false)))

Write-Step "Controllo del collegamento WordPress"
$encryptedToken = [IO.File]::ReadAllText($SecretPath).Trim()
$secureToken = ConvertTo-SecureString -String $encryptedToken
$credential = [System.Management.Automation.PSCredential]::new("calcioaffari", $secureToken)
$plainToken = $credential.GetNetworkCredential().Password
$uri = $config.site_url.TrimEnd('/') + "/wp-admin/admin-ajax.php?action=ca_news_health"
try {
    $health = Invoke-CalcioAffariJsonRequest -Uri $uri -UserAgent "CalcioAffari-Repair/$AgentVersion" -Token $plainToken -Form @{ agent_token = $plainToken } -TimeoutSeconds 30 -ExpectedProperties @("version", "publication_mode", "sources_enabled", "jobs")
}
catch {
    throw (Get-CalcioAffariFriendlyError $_)
}

Remove-Item $ConnectionPausePath -Force -ErrorAction SilentlyContinue
Write-Step "Ripristino dell'avvio automatico"
Register-Tasks
Start-CalcioAffariScheduledTask -Name $TaskName

Write-Host ""
Write-Host "RIPARAZIONE COMPLETATA" -ForegroundColor Green
Write-Host "WordPress collegato; modalità: $($health.publication_mode)."
Write-Host "Puoi chiudere questa finestra."
