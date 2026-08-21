[CmdletBinding()]
param(
    [ValidateSet("Prepare", "Connect")]
    [string]$Phase = "Prepare",
    [string]$StatusPath = (Join-Path $env:TEMP "calcioaffari-install-status.json"),
    [string]$SiteUrl = "https://calcioaffari.it",
    [string]$PairingCodePath = "",
    [string]$Model = "qwen3:14b",
    [string]$OllamaUrl = "http://127.0.0.1:11434"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$AgentVersion = "1.1.1"
$InstallDir = Join-Path $env:LOCALAPPDATA "CalcioAffari"
$ConnectionPausePath = Join-Path $InstallDir "connection-paused.txt"
$InstallLogPath = Join-Path $InstallDir "install.log"
$TaskName = "CalcioAffari Local Agent"
$WatchdogTaskName = "CalcioAffari Local Agent Watchdog"
. (Join-Path $PSScriptRoot "common.ps1")

function Write-InstallLog {
    param([string]$Level, [string]$Message)
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    $safeMessage = Protect-CalcioAffariSecretText $Message
    Add-Content -Path $InstallLogPath -Value ("{0:o} [{1}] {2}" -f (Get-Date), $Level.ToUpperInvariant(), $safeMessage) -Encoding UTF8
}

function Write-Status {
    param([int]$Percent, [string]$Stage, [string]$Message, [bool]$Done = $false, [bool]$Success = $false, [bool]$Indeterminate = $false)
    $Message = Protect-CalcioAffariSecretText $Message
    $payload = @{
        percent = [Math]::Max(0, [Math]::Min(100, $Percent)); stage = $Stage; message = $Message
        done = $Done; success = $Success; indeterminate = $Indeterminate; updated_at = (Get-Date).ToString("o")
    } | ConvertTo-Json -Compress
    $temporary = "$StatusPath.tmp"
    Set-Content -Path $temporary -Value $payload -Encoding UTF8
    Move-Item -Path $temporary -Destination $StatusPath -Force
    $signature = "$Stage|$Message"
    if ($signature -ne $script:LastStatusSignature) {
        Write-InstallLog "info" "$Stage - $Message"
        $script:LastStatusSignature = $signature
    }
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
        $signature = Get-AuthenticodeSignature -FilePath $installer
        if ($signature.Status -ne "Valid" -or -not $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch '(?i)Ollama') {
            Remove-Item $installer -Force -ErrorAction SilentlyContinue
            throw "Firma digitale dell'installer Ollama non valida. Installazione interrotta per sicurezza."
        }
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
    Write-Status 45 "Modello IA" "Download di Qwen3: inizializzazione…" $false $false $true
    $outputPath = Join-Path $env:TEMP ("calcioaffari-ollama-" + [Guid]::NewGuid().ToString("N") + ".out")
    $errorPath = $outputPath + ".err"
    $process = Start-Process -FilePath $OllamaPath -ArgumentList @("pull", $Model) -PassThru -WindowStyle Hidden -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath
    while (-not $process.HasExited) {
        Start-Sleep -Milliseconds 500
        $output = ""
        if (Test-Path $outputPath) { $output += [IO.File]::ReadAllText($outputPath) }
        if (Test-Path $errorPath) { $output += [IO.File]::ReadAllText($errorPath) }
        $matches = [regex]::Matches($output, '(?<percent>\d{1,3})\s*%')
        if ($matches.Count -gt 0) {
            $downloadPercent = [Math]::Max(0, [Math]::Min(100, [int]$matches[$matches.Count - 1].Groups['percent'].Value))
            $overall = 45 + [int][Math]::Floor($downloadPercent * 0.48)
            Write-Status $overall "Modello IA" ("Download Qwen3: {0}%" -f $downloadPercent) $false $false $false
        }
    }
    $process.WaitForExit()
    $errorText = if (Test-Path $errorPath) { [IO.File]::ReadAllText($errorPath).Trim() } else { "" }
    Remove-Item $outputPath, $errorPath -Force -ErrorAction SilentlyContinue
    if ($process.ExitCode -ne 0) {
        $detail = if ($errorText) { $errorText.Substring(0, [Math]::Min(500, $errorText.Length)) } else { "nessun dettaglio restituito da Ollama" }
        throw "Download del modello Qwen3 non riuscito: $detail"
    }
    $tags = Test-OllamaApi
    $available = @($tags.models | ForEach-Object { [string]$_.name })
    if ($available -notcontains $Model -and $available -notcontains ($Model + ":latest")) {
        throw "Qwen3 non risulta disponibile dopo il download."
    }
    Write-Status 95 "Modello IA" "Qwen3 è installato e pronto."
}

function Read-SecurePairingCode {
    if (-not $PairingCodePath -or -not (Test-Path $PairingCodePath)) { throw "Codice di collegamento temporaneo non trovato." }
    try {
        $encrypted = [IO.File]::ReadAllText($PairingCodePath).Trim()
        if (-not $encrypted) { throw "Codice di collegamento vuoto." }
        return ConvertTo-SecureString -String $encrypted
    }
    finally { Remove-Item $PairingCodePath -Force -ErrorAction SilentlyContinue }
}

function Test-WordPressConnection {
    param([SecureString]$SecurePairingCode)

    $credential = [System.Management.Automation.PSCredential]::new("calcioaffari", $SecurePairingCode)
    $plainCode = $credential.GetNetworkCredential().Password.Trim()
    if (-not $plainCode) { throw "Inserisci il codice generato nel pannello CalcioAffari." }
    if ($plainCode -notmatch '^[A-Za-z0-9]{48}$') { throw "Il codice deve contenere esattamente i 48 caratteri generati da WordPress, senza virgolette o spazi." }
    $ajaxUri = $SiteUrl.TrimEnd('/') + "/wp-admin/admin-ajax.php?action=ca_news_health"
    try {
        $health = Invoke-CalcioAffariJsonRequest -Uri $ajaxUri -UserAgent "CalcioAffari-Setup/$AgentVersion" -Token $plainCode -Form @{ agent_token = $plainCode } -TimeoutSeconds 30 -ExpectedProperties @("version", "publication_mode", "sources_enabled", "jobs")
        if ([version][string]$health.version -lt [version]"0.8.7") {
            throw (New-CalcioAffariException "CA_PLUGIN_OUTDATED" "Aggiorna CalcioAffari News Engine alla versione 0.8.7 o successiva.")
        }
        return $health
    }
    catch {
        $friendly = Get-CalcioAffariFriendlyError $_
        throw (New-CalcioAffariException (Get-CalcioAffariErrorCode $_) $friendly)
    }
}

function Stop-AgentTasks {
    Stop-CalcioAffariScheduledTask -Name $TaskName | Out-Null
    Stop-CalcioAffariScheduledTask -Name $WatchdogTaskName | Out-Null
}

function Register-AgentTasks {
    $agentPath = Join-Path $InstallDir "agent.ps1"
    $taskCommand = (Get-CalcioAffariHiddenPowerShellLaunch -InstallDir $InstallDir -ScriptPath $agentPath).Command
    & schtasks.exe /Create /TN $TaskName /SC ONLOGON /TR $taskCommand /RL LIMITED /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Creazione dell'avvio automatico non riuscita." }
    & schtasks.exe /Create /TN $WatchdogTaskName /SC MINUTE /MO 5 /TR $taskCommand /RL LIMITED /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Creazione del controllo automatico non riuscita." }
}

function New-Shortcut {
    param([string]$Path, [string]$ScriptPath, [string]$Description)
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $launch = Get-CalcioAffariHiddenPowerShellLaunch -InstallDir $InstallDir -ScriptPath $ScriptPath
    $shortcut.TargetPath = $launch.FilePath
    $shortcut.Arguments = $launch.Arguments
    $shortcut.WorkingDirectory = $InstallDir
    $shortcut.Description = $Description
    $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,14"
    $shortcut.Save()
}

function Install-Agent {
    param([SecureString]$SecurePairingCode)
    Write-Status 60 "Collegamento sito" "Codice verificato. Configuro l'avvio automatico…"
    Stop-AgentTasks
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    foreach ($file in @(
        "agent.ps1", "common.ps1", "dashboard.ps1", "diagnose.ps1", "launcher.ps1", "hidden-launcher.vbs", "repair.ps1", "uninstall.ps1", "install.ps1", "setup-gui.ps1", "upgrade.ps1",
        "Apri-CalcioAffari.cmd", "Disinstalla-CalcioAffari.cmd", "version.json", "README.md", "AUDIT-1.1.1.md"
    )) {
        $source = Join-Path $PSScriptRoot $file
        $destination = Join-Path $InstallDir $file
        if ((Test-Path $source) -and ([IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath($destination))) { Copy-Item $source $destination -Force }
    }
    $encryptedToken = ConvertFrom-SecureString $SecurePairingCode
    [IO.File]::WriteAllText((Join-Path $InstallDir "agent-token.txt"), $encryptedToken, (New-Object Text.UTF8Encoding($false)))
    Remove-Item (Join-Path $InstallDir "application-password.txt") -Force -ErrorAction SilentlyContinue
    @{
        site_url = $SiteUrl.TrimEnd('/'); ollama_url = $OllamaUrl.TrimEnd('/')
        model = $Model; worker_name = "$env:COMPUTERNAME-$env:USERNAME"; poll_seconds = 30; agent_version = $AgentVersion
        api_transport = "ajax-token"
    } | ConvertTo-Json | Set-Content -Path (Join-Path $InstallDir "agent.json") -Encoding UTF8
    Remove-Item $ConnectionPausePath -Force -ErrorAction SilentlyContinue
    Register-AgentTasks
    $startMenu = Join-Path ([Environment]::GetFolderPath("Programs")) "CalcioAffari"
    New-Item -ItemType Directory -Path $startMenu -Force | Out-Null
    $launcher = Join-Path $InstallDir "launcher.ps1"
    New-Shortcut (Join-Path $startMenu "CalcioAffari Local Newsroom.lnk") $launcher "Stato e controllo del motore editoriale locale"
    New-Shortcut (Join-Path ([Environment]::GetFolderPath("Desktop")) "CalcioAffari Local Newsroom.lnk") $launcher "Stato e controllo del motore editoriale locale"
    Start-CalcioAffariScheduledTask -Name $TaskName
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
    Write-Status 10 "Collegamento sito" "Arresto i vecchi tentativi e verifico il nuovo codice…" $false $false $true
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    [IO.File]::WriteAllText($ConnectionPausePath, "Collegamento sospeso durante la riconfigurazione.", (New-Object Text.UTF8Encoding($false)))
    Stop-AgentTasks
    $securePairingCode = Read-SecurePairingCode
    $health = Test-WordPressConnection $securePairingCode
    Install-Agent $securePairingCode
    Write-Status 100 "Sistema operativo" "Collegamento completato. Modalità: $($health.publication_mode)." $true $true
    exit 0
}
catch {
    Write-InstallLog "error" $_.Exception.ToString()
    Write-Status 100 "Operazione non completata" $_.Exception.Message $true $false
    exit 1
}
