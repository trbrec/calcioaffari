[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$InstallDir = Join-Path $env:LOCALAPPDATA "CalcioAffari"
$ConfigPath = Join-Path $InstallDir "agent.json"
$SecretPath = Join-Path $InstallDir "agent-token.txt"
$TaskName = "CalcioAffari Local Agent"
$WatchdogTaskName = "CalcioAffari Local Agent Watchdog"
$AgentVersion = "0.8.5"

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
    $agentPath = Join-Path $InstallDir "agent.ps1"
    $taskCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$agentPath`""
    & schtasks.exe /Create /TN $TaskName /SC ONLOGON /TR $taskCommand /RL LIMITED /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Impossibile ricreare l'avvio automatico." }
    & schtasks.exe /Create /TN $WatchdogTaskName /SC MINUTE /MO 5 /TR $taskCommand /RL LIMITED /F | Out-Null
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
    & $winget.Source install --id Ollama.Ollama --exact --accept-source-agreements --accept-package-agreements --silent
    $ollama = Get-OllamaExecutable
    if (-not $ollama) { throw "Installazione Ollama non completata." }
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
}

Write-Step "Ripristino dell'avvio automatico"
& schtasks.exe /End /TN $TaskName 2>$null | Out-Null
& schtasks.exe /End /TN $WatchdogTaskName 2>$null | Out-Null
Register-Tasks
& schtasks.exe /Run /TN $TaskName | Out-Null

Write-Step "Controllo del collegamento WordPress"
$encryptedToken = [IO.File]::ReadAllText($SecretPath).Trim()
$secureToken = ConvertTo-SecureString -String $encryptedToken
$credential = [System.Management.Automation.PSCredential]::new("calcioaffari", $secureToken)
$plainToken = $credential.GetNetworkCredential().Password
$uri = $config.site_url.TrimEnd('/') + "/wp-admin/admin-ajax.php?action=ca_news_health"
$body = @{ agent_token = $plainToken }
$health = Invoke-RestMethod -Uri $uri -Method Post -Headers @{ "User-Agent" = "CalcioAffari-Repair/$AgentVersion"; "X-CalcioAffari-Token" = $plainToken } -ContentType "application/x-www-form-urlencoded; charset=utf-8" -Body $body -TimeoutSec 30

Write-Host ""
Write-Host "RIPARAZIONE COMPLETATA" -ForegroundColor Green
Write-Host "WordPress collegato; modalità: $($health.publication_mode)."
Write-Host "Puoi chiudere questa finestra."
