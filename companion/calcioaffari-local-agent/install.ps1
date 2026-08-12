[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SiteUrl,
    [Parameter(Mandatory = $true)][string]$WordPressUser,
    [string]$Model = "qwen3:14b",
    [string]$OllamaUrl = "http://127.0.0.1:11434"
)

$ErrorActionPreference = "Stop"
if (-not $SiteUrl.StartsWith("https://")) { throw "SiteUrl deve usare HTTPS." }
if ($OllamaUrl -notmatch '^http://(127\.0\.0\.1|localhost)(:\d+)?$') { throw "OllamaUrl deve puntare a localhost." }

$installDir = Join-Path $env:LOCALAPPDATA "CalcioAffari"
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot "agent.ps1") (Join-Path $installDir "agent.ps1") -Force

$applicationPassword = Read-Host "Password applicazione WordPress (non la password dell'account)" -AsSecureString
$encrypted = ConvertFrom-SecureString $applicationPassword
Set-Content -Path (Join-Path $installDir "application-password.txt") -Value $encrypted -Encoding UTF8

$config = @{
    site_url = $SiteUrl.TrimEnd('/')
    wordpress_user = $WordPressUser
    ollama_url = $OllamaUrl.TrimEnd('/')
    model = $Model
    worker_name = "$env:COMPUTERNAME-$env:USERNAME"
    poll_seconds = 30
}
$config | ConvertTo-Json | Set-Content -Path (Join-Path $installDir "agent.json") -Encoding UTF8

$ollama = Get-Command "ollama" -ErrorAction SilentlyContinue
if (-not $ollama) {
    Write-Warning "Ollama non è installato o non è nel PATH. Installalo prima di avviare l'agente."
}
else {
    $available = & ollama list 2>$null | Select-String -SimpleMatch $Model
    if (-not $available) { Write-Warning "Il modello $Model non è presente. Esegui: ollama pull $Model" }
}

$agentPath = Join-Path $installDir "agent.ps1"
$taskCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$agentPath`""
& schtasks.exe /Create /TN "CalcioAffari Local Agent" /SC ONLOGON /TR $taskCommand /RL LIMITED /F | Out-Null
& schtasks.exe /Run /TN "CalcioAffari Local Agent" | Out-Null

Write-Host "Agente installato in $installDir" -ForegroundColor Green
Write-Host "Attività pianificata: CalcioAffari Local Agent" -ForegroundColor Green

