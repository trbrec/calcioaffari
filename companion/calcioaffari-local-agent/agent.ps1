[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $env:LOCALAPPDATA "CalcioAffari\agent.json"),
    [switch]$Once
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Write-AgentLog {
    param([string]$Level, [string]$Message)
    $directory = Split-Path -Parent $ConfigPath
    if (-not (Test-Path $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $logPath = Join-Path $directory "agent.log"
    if ((Test-Path $logPath) -and (Get-Item $logPath).Length -gt (5 * 1024 * 1024)) {
        Move-Item $logPath (Join-Path $directory "agent.previous.log") -Force
    }
    Add-Content -Path $logPath -Value ("{0:o} [{1}] {2}" -f (Get-Date), $Level.ToUpperInvariant(), $Message)
}

function Load-AgentConfig {
    if (-not (Test-Path $ConfigPath)) { throw "Configurazione non trovata: $ConfigPath" }
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    if (-not $config.site_url.StartsWith("https://")) { throw "site_url deve usare HTTPS." }
    if ($config.ollama_url -notmatch '^http://(127\.0\.0\.1|localhost)(:\d+)?$') { throw "ollama_url deve restare locale (localhost)." }
    $secretPath = Join-Path (Split-Path -Parent $ConfigPath) "application-password.txt"
    if (-not (Test-Path $secretPath)) { throw "Password applicazione non trovata." }
    $securePassword = Get-Content $secretPath -Raw | ConvertTo-SecureString
    $credential = [PSCredential]::new([string]$config.wordpress_user, $securePassword)
    $plainPassword = $credential.GetNetworkCredential().Password
    $basicValue = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($config.wordpress_user):$plainPassword"))
    return @{ Config = $config; Authorization = "Basic $basicValue" }
}

function Invoke-CalcioAffariApi {
    param($Runtime, [string]$Method, [string]$Path, $Body = $null)
    $uri = $Runtime.Config.site_url.TrimEnd('/') + "/wp-json/calcioaffari/v1/" + $Path.TrimStart('/')
    $parameters = @{
        Uri = $uri
        Method = $Method
        Headers = @{ Authorization = $Runtime.Authorization; "User-Agent" = "CalcioAffari-LocalAgent/0.7.0" }
        ContentType = "application/json; charset=utf-8"
        TimeoutSec = 90
    }
    if ($null -ne $Body) { $parameters.Body = ($Body | ConvertTo-Json -Depth 100 -Compress) }
    return Invoke-RestMethod @parameters
}

function Invoke-Ollama {
    param($Config, $Job)
    $uri = $Config.ollama_url.TrimEnd('/') + "/api/generate"
    $request = @{
        model = [string]$Config.model
        system = [string]$Job.system_prompt
        prompt = [string]$Job.prompt
        format = $Job.schema
        stream = $false
        think = $false
        keep_alive = "10m"
        options = @{
            temperature = [double]$Job.generation.temperature
            num_ctx = [int]$Job.generation.num_ctx
            num_predict = [int]$Job.generation.num_predict
            seed = 20260812
        }
    }
    $response = Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json; charset=utf-8" -Body ($request | ConvertTo-Json -Depth 100 -Compress) -TimeoutSec 900
    if (-not $response.response) { throw "Ollama non ha restituito alcun testo." }
    return ($response.response | ConvertFrom-Json)
}

function Invoke-AgentCycle {
    param($Runtime)
    $claim = Invoke-CalcioAffariApi $Runtime "POST" "jobs/claim" @{
        worker_name = [string]$Runtime.Config.worker_name
        model = [string]$Runtime.Config.model
    }
    if ($null -eq $claim.job) { return $false }

    $job = $claim.job
    Write-AgentLog "info" "Elaborazione job #$($job.id) con $($Runtime.Config.model)."
    try {
        $result = Invoke-Ollama $Runtime.Config $job
        $completed = Invoke-CalcioAffariApi $Runtime "POST" ("jobs/{0}/complete" -f $job.id) @{
            lease_token = [string]$job.lease_token
            model = [string]$Runtime.Config.model
            result = $result
        }
        Write-AgentLog "info" "Job #$($job.id) completato; articolo #$($completed.article.post_id), stato $($completed.article.post_status)."
    }
    catch {
        $message = $_.Exception.Message
        Write-AgentLog "error" "Job #$($job.id): $message"
        try {
            Invoke-CalcioAffariApi $Runtime "POST" ("jobs/{0}/fail" -f $job.id) @{
                lease_token = [string]$job.lease_token
                error = $message.Substring(0, [Math]::Min(1000, $message.Length))
                retryable = $true
            } | Out-Null
        }
        catch { Write-AgentLog "error" "Impossibile restituire il job al sito: $($_.Exception.Message)" }
    }
    return $true
}

$runtime = Load-AgentConfig
Write-AgentLog "info" "Agente avviato per $($runtime.Config.site_url)."

do {
    try {
        $worked = Invoke-AgentCycle $runtime
        $delay = if ($worked) { 3 } else { [Math]::Max(20, [int]$runtime.Config.poll_seconds) }
    }
    catch {
        Write-AgentLog "error" $_.Exception.Message
        $delay = 60
    }
    if ($Once) { break }
    Start-Sleep -Seconds $delay
} while ($true)
