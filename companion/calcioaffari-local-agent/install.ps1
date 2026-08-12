[CmdletBinding()]
param(
    [string]$SiteUrl = "https://calcioaffari.it",
    [string]$WordPressUser = "",
    [string]$Model = "qwen3:14b",
    [string]$OllamaUrl = "http://127.0.0.1:11434"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$AgentVersion = "0.8.0"
$InstallDir = Join-Path $env:LOCALAPPDATA "CalcioAffari"
$TaskName = "CalcioAffari Local Agent"
$WatchdogTaskName = "CalcioAffari Local Agent Watchdog"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host ("[CalcioAffari] " + $Message) -ForegroundColor Cyan
}

function Get-OllamaExecutable {
    $command = Get-Command "ollama" -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"),
        (Join-Path $env:LOCALAPPDATA "Ollama\ollama.exe"),
        (Join-Path $env:ProgramFiles "Ollama\ollama.exe")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

function Test-OllamaApi {
    try {
        return Invoke-RestMethod -Uri ($OllamaUrl.TrimEnd('/') + "/api/tags") -Method Get -TimeoutSec 5
    }
    catch { return $null }
}

function Start-OllamaAndWait {
    param([string]$OllamaPath)

    if (Test-OllamaApi) { return }
    Start-Process -FilePath $OllamaPath -ArgumentList "serve" -WindowStyle Hidden | Out-Null
    foreach ($attempt in 1..30) {
        Start-Sleep -Seconds 2
        if (Test-OllamaApi) { return }
    }
    throw "Ollama è installato ma non risponde su $OllamaUrl."
}

function Install-OllamaIfNeeded {
    $ollama = Get-OllamaExecutable
    if ($ollama) { return $ollama }

    Write-Step "Installazione automatica del motore IA locale Ollama"
    $winget = Get-Command "winget" -ErrorAction SilentlyContinue
    if ($winget) {
        & $winget.Source install --id Ollama.Ollama --exact --accept-source-agreements --accept-package-agreements --silent
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Installazione silenziosa non completata; verrà aperto l'installer ufficiale."
        }
    }

    $ollama = Get-OllamaExecutable
    if (-not $ollama) {
        $installer = Join-Path $env:TEMP "OllamaSetup.exe"
        Write-Host "Download dell'installer ufficiale Ollama..."
        Invoke-WebRequest -Uri "https://ollama.com/download/OllamaSetup.exe" -OutFile $installer -UseBasicParsing
        Start-Process -FilePath $installer -Wait
        Remove-Item $installer -Force -ErrorAction SilentlyContinue
        $ollama = Get-OllamaExecutable
    }

    if (-not $ollama) { throw "Ollama non risulta installato. Riesegui l'installazione dopo averlo installato." }
    return $ollama
}

function Ensure-Model {
    param([string]$OllamaPath)

    $tags = Test-OllamaApi
    $available = @($tags.models | ForEach-Object { [string]$_.name })
    if ($available -contains $Model -or $available -contains ($Model + ":latest")) { return }

    Write-Step "Download del modello $Model (circa 9,3 GB, soltanto la prima volta)"
    Write-Host "La durata dipende dalla connessione. Non chiudere questa finestra."
    & $OllamaPath pull $Model
    if ($LASTEXITCODE -ne 0) { throw "Download del modello $Model non riuscito." }

    $tags = Test-OllamaApi
    $available = @($tags.models | ForEach-Object { [string]$_.name })
    if ($available -notcontains $Model -and $available -notcontains ($Model + ":latest")) {
        throw "Il modello $Model non risulta disponibile dopo il download."
    }
}

function Read-ApplicationPassword {
    if (-not $WordPressUser) {
        $script:WordPressUser = (Read-Host "Nome utente WordPress dedicato all'agente").Trim()
    }
    if (-not $WordPressUser) { throw "Il nome utente WordPress è obbligatorio." }

    return Read-Host "Password applicazione WordPress (non la password principale)" -AsSecureString
}

function Get-AuthorizationHeader {
    param([SecureString]$SecurePassword)

    $credential = New-Object System.Management.Automation.PSCredential ($WordPressUser, $SecurePassword)
    $plainPassword = $credential.GetNetworkCredential().Password
    if (-not $plainPassword) { throw "La password applicazione è vuota." }
    $basicValue = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${WordPressUser}:$plainPassword"))
    return "Basic $basicValue"
}

function Test-WordPressConnection {
    param([string]$Authorization)

    $uri = $SiteUrl.TrimEnd('/') + "/wp-json/calcioaffari/v1/health"
    try {
        return Invoke-RestMethod -Uri $uri -Method Get -Headers @{ Authorization = $Authorization; "User-Agent" = "CalcioAffari-Setup/$AgentVersion" } -TimeoutSec 30
    }
    catch {
        throw "Collegamento a WordPress non riuscito. Verifica che il plugin sia attivo e che utente/password applicazione siano corretti. Dettaglio: $($_.Exception.Message)"
    }
}

function Stop-AgentTasks {
    & schtasks.exe /End /TN $TaskName 2>$null | Out-Null
    & schtasks.exe /End /TN $WatchdogTaskName 2>$null | Out-Null
}

function Register-AgentTasks {
    $agentPath = Join-Path $InstallDir "agent.ps1"
    $taskCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$agentPath`""

    & schtasks.exe /Create /TN $TaskName /SC ONLOGON /TR $taskCommand /RL LIMITED /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Creazione dell'avvio automatico non riuscita." }

    & schtasks.exe /Create /TN $WatchdogTaskName /SC MINUTE /MO 5 /TR $taskCommand /RL LIMITED /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Creazione del controllo automatico non riuscita." }
}

function New-Shortcut {
    param([string]$Path, [string]$ScriptPath, [string]$Description)

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = (Join-Path $PSHOME "powershell.exe")
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
    $shortcut.WorkingDirectory = $InstallDir
    $shortcut.Description = $Description
    $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,14"
    $shortcut.Save()
}

function Install-Shortcuts {
    $startMenu = Join-Path ([Environment]::GetFolderPath("Programs")) "CalcioAffari"
    New-Item -ItemType Directory -Path $startMenu -Force | Out-Null
    $dashboard = Join-Path $InstallDir "dashboard.ps1"
    New-Shortcut (Join-Path $startMenu "CalcioAffari Local Newsroom.lnk") $dashboard "Stato e controllo del motore editoriale locale"
    New-Shortcut (Join-Path ([Environment]::GetFolderPath("Desktop")) "CalcioAffari Local Newsroom.lnk") $dashboard "Stato e controllo del motore editoriale locale"
}

if ($env:OS -ne "Windows_NT") { throw "Questo installer è destinato a Windows 10/11." }
if (-not $SiteUrl.StartsWith("https://")) { throw "SiteUrl deve usare HTTPS." }
if ($OllamaUrl -notmatch '^http://(127\.0\.0\.1|localhost)(:\d+)?$') { throw "OllamaUrl deve puntare a localhost." }

Write-Host ""
Write-Host "CALCIOAFFARI · LOCAL NEWSROOM" -ForegroundColor White -BackgroundColor DarkGreen
Write-Host "Installazione guidata v$AgentVersion" -ForegroundColor Gray

$ollama = Install-OllamaIfNeeded
Start-OllamaAndWait $ollama
Ensure-Model $ollama

Write-Step "Collegamento sicuro a calcioaffari.it"
$applicationPassword = Read-ApplicationPassword
$authorization = Get-AuthorizationHeader $applicationPassword
$health = Test-WordPressConnection $authorization
Write-Host "WordPress collegato. Modalità editoriale: $($health.publication_mode)" -ForegroundColor Green

Write-Step "Installazione dell'agente e dell'autoripristino"
Stop-AgentTasks
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

$filesToCopy = @(
    "agent.ps1", "dashboard.ps1", "repair.ps1", "uninstall.ps1", "install.ps1",
    "Apri-CalcioAffari.cmd", "Disinstalla-CalcioAffari.cmd", "version.json", "README.md"
)
foreach ($file in $filesToCopy) {
    $source = Join-Path $PSScriptRoot $file
    $destination = Join-Path $InstallDir $file
    if ((Resolve-Path $source).Path -ne (Resolve-Path $destination -ErrorAction SilentlyContinue).Path) {
        Copy-Item $source $destination -Force
    }
}

$encrypted = ConvertFrom-SecureString $applicationPassword
Set-Content -Path (Join-Path $InstallDir "application-password.txt") -Value $encrypted -Encoding UTF8

$config = @{
    site_url = $SiteUrl.TrimEnd('/')
    wordpress_user = $WordPressUser
    ollama_url = $OllamaUrl.TrimEnd('/')
    model = $Model
    worker_name = "$env:COMPUTERNAME-$env:USERNAME"
    poll_seconds = 30
    agent_version = $AgentVersion
}
$config | ConvertTo-Json | Set-Content -Path (Join-Path $InstallDir "agent.json") -Encoding UTF8

Register-AgentTasks
Install-Shortcuts
& schtasks.exe /Run /TN $TaskName | Out-Null

Write-Host ""
Write-Host "INSTALLAZIONE COMPLETATA" -ForegroundColor Green
Write-Host "Il motore parte con Windows, si riavvia automaticamente e conserva le notizie in coda quando il PC è spento."
Write-Host "Apri 'CalcioAffari Local Newsroom' dal desktop per controllarne lo stato."

Start-Process -FilePath (Join-Path $PSHOME "powershell.exe") -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $InstallDir 'dashboard.ps1')`"" | Out-Null
