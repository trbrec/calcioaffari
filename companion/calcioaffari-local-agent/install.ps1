[CmdletBinding()]
param(
    [ValidateSet("Prepare", "Connect")]
    [string]$Phase = "Prepare",
    [string]$StatusPath = (Join-Path $env:TEMP "calcioaffari-install-status.json"),
    [string]$SiteUrl = "https://calcioaffari.it",
    [string]$WordPressUser = "",
    [string]$CredentialPath = "",
    [string]$Model = "qwen3:14b",
    [string]$OllamaUrl = "http://127.0.0.1:11434"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$AgentVersion = "0.8.1"
$InstallDir = Join-Path $env:LOCALAPPDATA "CalcioAffari"
$TaskName = "CalcioAffari Local Agent"
$WatchdogTaskName = "CalcioAffari Local Agent Watchdog"

function Write-Status {
    param([int]$Percent, [string]$Stage, [string]$Message, [bool]$Done = $false, [bool]$Success = $false, [bool]$Indeterminate = $false)
    $payload = @{
        percent = [Math]::Max(0, [Math]::Min(100, $Percent)); stage = $Stage; message = $Message
        done = $Done; success = $Success; indeterminate = $Indeterminate; updated_at = (Get-Date).ToString("o")
    } | ConvertTo-Json -Compress
    $temporary = "$StatusPath.tmp"
    Set-Content -Path $temporary -Value $payload -Encoding UTF8
    Move-Item -Path $temporary -Destination $StatusPath -Force
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

function Test-OllamaApi {
    try { return Invoke-RestMethod -Uri ($OllamaUrl.TrimEnd('/') + "/api/tags") -Method Get -TimeoutSec 5 }
    catch { return $null }
}

function Install-OllamaIfNeeded {
    $ollama = Get-OllamaExecutable
    if ($ollama) { return $ollama }
    Write-Status 12 "Motore IA" "Installazione di Ollama in corso…" $false $false $true
    $winget = Get-Command "winget" -ErrorAction SilentlyContinue
    if ($winget) {
        $arguments = @("install", "--id", "Ollama.Ollama", "--exact", "--accept-source-agreements", "--accept-package-agreements", "--silent")
        $process = Start-Process -FilePath $winget.Source -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -ne 0) {
            Write-Status 18 "Motore IA" "Il metodo automatico non ha risposto: uso l'installer ufficiale…" $false $false $true
        }
    }
    $ollama = Get-OllamaExecutable
    if (-not $ollama) {
        $installer = Join-Path $env:TEMP "OllamaSetup.exe"
        Write-Status 20 "Motore IA" "Download dell'installer ufficiale Ollama…" $false $false $true
        Invoke-WebRequest -Uri "https://ollama.com/download/OllamaSetup.exe" -OutFile $installer -UseBasicParsing
        Write-Status 28 "Motore IA" "Completamento dell'installazione Ollama…" $false $false $true
        $process = Start-Process -FilePath $installer -Wait -PassThru
        Remove-Item $installer -Force -ErrorAction SilentlyContinue
        if ($process.ExitCode -ne 0) { throw "Installazione di Ollama annullata o non riuscita." }
        $ollama = Get-OllamaExecutable
    }
    if (-not $ollama) { throw "Ollama non risulta installato." }
    return $ollama
}

function Start-OllamaAndWait {
    param([string]$OllamaPath)
    if (Test-OllamaApi) { return }
    Write-Status 35 "Motore IA" "Avvio del servizio locale Ollama…" $false $false $true
    Start-Process -FilePath $OllamaPath -ArgumentList "serve" -WindowStyle Hidden | Out-Null
    foreach ($attempt in 1..30) {
        Start-Sleep -Seconds 2
        if (Test-OllamaApi) { return }
    }
    throw "Ollama è installato ma non risponde."
}

function Ensure-Model {
    param([string]$OllamaPath)
    $tags = Test-OllamaApi
    $available = @($tags.models | ForEach-Object { [string]$_.name })
    if ($available -contains $Model -or $available -contains ($Model + ":latest")) {
        Write-Status 95 "Modello IA" "Qwen3 è già presente e pronto."
        return
    }
    Write-Status 45 "Modello IA" "Download di Qwen3 (circa 9,3 GB). Puoi continuare a usare il PC…" $false $false $true
    $process = Start-Process -FilePath $OllamaPath -ArgumentList @("pull", $Model) -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) { throw "Download del modello Qwen3 non riuscito." }
    $tags = Test-OllamaApi
    $available = @($tags.models | ForEach-Object { [string]$_.name })
    if ($available -notcontains $Model -and $available -notcontains ($Model + ":latest")) {
        throw "Qwen3 non risulta disponibile dopo il download."
    }
    Write-Status 95 "Modello IA" "Qwen3 è installato e pronto."
}

function Read-SecureCredential {
    if (-not $WordPressUser.Trim()) { throw "Inserisci il nome utente WordPress dedicato." }
    if (-not $CredentialPath -or -not (Test-Path $CredentialPath)) { throw "Credenziale temporanea non trovata." }
    try { return Get-Content $CredentialPath -Raw -Encoding UTF8 | ConvertTo-SecureString }
    finally { Remove-Item $CredentialPath -Force -ErrorAction SilentlyContinue }
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
        return Invoke-RestMethod -Uri $uri -Method Get -Headers @{
            Authorization = $Authorization; "User-Agent" = "CalcioAffari-Setup/$AgentVersion"
        } -TimeoutSec 30
    }
    catch {
        $response = $_.Exception.Response
        if ($response -and [int]$response.StatusCode -eq 404) {
            throw "Il plugin CalcioAffari News Engine non è ancora attivo sul sito."
        }
        throw "Collegamento al sito non riuscito. Verifica utente e password applicazione."
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
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
    $shortcut.WorkingDirectory = $InstallDir
    $shortcut.Description = $Description
    $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,14"
    $shortcut.Save()
}

function Install-Agent {
    param([SecureString]$SecurePassword)
    Write-Status 60 "Collegamento sito" "Credenziali verificate. Configuro l'avvio automatico…"
    Stop-AgentTasks
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    foreach ($file in @(
        "agent.ps1", "dashboard.ps1", "repair.ps1", "uninstall.ps1", "install.ps1", "setup-gui.ps1",
        "Apri-CalcioAffari.cmd", "Disinstalla-CalcioAffari.cmd", "version.json", "README.md"
    )) {
        $source = Join-Path $PSScriptRoot $file
        if (Test-Path $source) { Copy-Item $source (Join-Path $InstallDir $file) -Force }
    }
    ConvertFrom-SecureString $SecurePassword | Set-Content -Path (Join-Path $InstallDir "application-password.txt") -Encoding UTF8
    @{
        site_url = $SiteUrl.TrimEnd('/'); wordpress_user = $WordPressUser.Trim(); ollama_url = $OllamaUrl.TrimEnd('/')
        model = $Model; worker_name = "$env:COMPUTERNAME-$env:USERNAME"; poll_seconds = 30; agent_version = $AgentVersion
    } | ConvertTo-Json | Set-Content -Path (Join-Path $InstallDir "agent.json") -Encoding UTF8
    Register-AgentTasks
    $startMenu = Join-Path ([Environment]::GetFolderPath("Programs")) "CalcioAffari"
    New-Item -ItemType Directory -Path $startMenu -Force | Out-Null
    $dashboard = Join-Path $InstallDir "dashboard.ps1"
    New-Shortcut (Join-Path $startMenu "CalcioAffari Local Newsroom.lnk") $dashboard "Stato e controllo del motore editoriale locale"
    New-Shortcut (Join-Path ([Environment]::GetFolderPath("Desktop")) "CalcioAffari Local Newsroom.lnk") $dashboard "Stato e controllo del motore editoriale locale"
    & schtasks.exe /Run /TN $TaskName | Out-Null
}

try {
    if ($env:OS -ne "Windows_NT") { throw "Questa applicazione richiede Windows 10 o 11." }
    if (-not $SiteUrl.StartsWith("https://")) { throw "L'indirizzo del sito deve usare HTTPS." }
    if ($OllamaUrl -notmatch '^http://(127\.0\.0\.1|localhost)(:\d+)?$') { throw "Il motore IA deve restare locale." }
    if ($Phase -eq "Prepare") {
        Write-Status 5 "Controllo iniziale" "Verifico i componenti già presenti…"
        $ollama = Install-OllamaIfNeeded
        Start-OllamaAndWait $ollama
        Ensure-Model $ollama
        Write-Status 100 "Motore pronto" "Ollama e Qwen3 sono pronti." $true $true
        exit 0
    }
    Write-Status 10 "Collegamento sito" "Verifico il collegamento sicuro a calcioaffari.it…" $false $false $true
    $securePassword = Read-SecureCredential
    $authorization = Get-AuthorizationHeader $securePassword
    $health = Test-WordPressConnection $authorization
    Install-Agent $securePassword
    Write-Status 100 "Sistema operativo" "Collegamento completato. Modalità: $($health.publication_mode)." $true $true
    exit 0
}
catch {
    Write-Status 100 "Operazione non completata" $_.Exception.Message $true $false
    exit 1
}
