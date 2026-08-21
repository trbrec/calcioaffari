[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $env:LOCALAPPDATA "CalcioAffari\agent.json"),
    [switch]$Once
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$AgentVersion = "1.0.10"
$ConnectionPausePath = Join-Path (Split-Path -Parent $ConfigPath) "connection-paused.txt"
. (Join-Path $PSScriptRoot "common.ps1")

function Write-AgentLog {
    param([string]$Level, [string]$Message)
    $Message = Protect-CalcioAffariSecretText $Message

    $directory = Split-Path -Parent $ConfigPath
    if (-not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $logPath = Join-Path $directory "agent.log"
    if ((Test-Path $logPath) -and (Get-Item $logPath).Length -gt (5 * 1024 * 1024)) {
        Move-Item $logPath (Join-Path $directory "agent.previous.log") -Force
    }
    Add-Content -Path $logPath -Value ("{0:o} [{1}] {2}" -f (Get-Date), $Level.ToUpperInvariant(), $Message) -Encoding UTF8
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
    param([string]$OllamaUrl)
    try {
        Invoke-RestMethod -Uri ($OllamaUrl.TrimEnd('/') + "/api/tags") -Method Get -TimeoutSec 5 | Out-Null
        return $true
    }
    catch { return $false }
}

function Ensure-OllamaApi {
    param([string]$OllamaUrl)

    if (Test-OllamaApi $OllamaUrl) { return }
    $ollama = Get-OllamaExecutable
    if (-not $ollama) { throw "Ollama non risulta installato." }

    Write-AgentLog "warning" "Ollama non risponde: tentativo di avvio automatico."
    Start-Process -FilePath $ollama -ArgumentList "serve" -WindowStyle Hidden | Out-Null
    foreach ($attempt in 1..12) {
        Start-Sleep -Seconds 2
        if (Test-OllamaApi $OllamaUrl) { return }
    }
    throw "Ollama non risponde su $OllamaUrl dopo il tentativo di riavvio."
}

function Load-AgentConfig {
    if (-not (Test-Path $ConfigPath)) { throw "Configurazione non trovata: $ConfigPath" }
    $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not ([string]$config.site_url).StartsWith("https://")) { throw "site_url deve usare HTTPS." }
    if ([string]$config.ollama_url -notmatch '^http://(127\.0\.0\.1|localhost)(:\d+)?$') {
        throw "ollama_url deve restare locale (localhost)."
    }

    $secretPath = Join-Path (Split-Path -Parent $ConfigPath) "agent-token.txt"
    if (-not (Test-Path $secretPath)) { throw "Codice di collegamento non trovato. Riesegui la configurazione." }
    $encryptedToken = [IO.File]::ReadAllText($secretPath).Trim()
    $secureToken = ConvertTo-SecureString -String $encryptedToken
    $credential = [System.Management.Automation.PSCredential]::new("calcioaffari", $secureToken)
    return @{ Config = $config; AgentToken = $credential.GetNetworkCredential().Password }
}

function Invoke-CalcioAffariApi {
    param($Runtime, [string]$Method, [string]$Path, $Body = $null)

    $site = $Runtime.Config.site_url.TrimEnd('/')
    $normalized = $Path.Trim('/')
    if ($normalized -eq "jobs/claim") {
        $uri = $site + "/wp-admin/admin-ajax.php?action=ca_news_claim"
    }
    elseif ($normalized -match '^jobs/(?<id>\d+)/(?<operation>complete|fail)$') {
        $uri = $site + "/wp-admin/admin-ajax.php?action=ca_news_" + $Matches.operation + "&id=" + $Matches.id
    }
    else {
        throw "Percorso API non supportato: $Path"
    }
    $form = @{ agent_token = [string]$Runtime.AgentToken }
    if ($null -ne $Body) { $form.payload = ($Body | ConvertTo-Json -Depth 100 -Compress) }
    $expected = switch ($normalized) {
        "jobs/claim" { @("job") }
        default { @("ok") }
    }
    return Invoke-CalcioAffariJsonRequest -Uri $uri -UserAgent "CalcioAffari-LocalAgent/$AgentVersion" -Token ([string]$Runtime.AgentToken) -Form $form -TimeoutSeconds 90 -ExpectedProperties $expected
}

function Invoke-OllamaStructuredRequest {
    param($Config, $Job, [string]$Prompt)
    Ensure-OllamaApi ([string]$Config.ollama_url)
    $uri = $Config.ollama_url.TrimEnd('/') + "/api/generate"
    $request = @{
        model = [string]$Config.model
        system = [string]$Job.system_prompt
        prompt = $Prompt
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
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json; charset=utf-8" -Body ($request | ConvertTo-Json -Depth 100 -Compress) -TimeoutSec 900
    }
    catch { throw (New-CalcioAffariException "CA_OLLAMA_REQUEST" ("Ollama non ha completato l'elaborazione: {0}" -f $_.Exception.Message)) }
    if (-not $response.response) { throw "Ollama non ha restituito alcun testo." }
    $text = ([string]$response.response).Trim()
    if ($text -match '(?s)^```(?:json)?\s*(.*?)\s*```$') { $text = $Matches[1].Trim() }
    try { return ($text | ConvertFrom-Json) }
    catch { throw (New-CalcioAffariException "CA_MODEL_OUTPUT" "Qwen3 ha restituito un risultato non conforme al formato editoriale richiesto.") }
}

function Get-CalcioAffariArticleWordCount {
    param($Result)

    if ($null -eq $Result -or $null -eq $Result.PSObject.Properties["body_html"]) { return 0 }
    $plain = [regex]::Replace([string]$Result.body_html, '<[^>]+>', ' ')
    $plain = [System.Net.WebUtility]::HtmlDecode($plain)
    $plain = [regex]::Replace($plain, '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($plain)) { return 0 }
    return @($plain -split '\s+' | Where-Object { $_ -ne '' }).Count
}

function Get-CalcioAffariEditorialIssues {
    param($Result)

    $issues = @()
    if ($null -eq $Result) { return @("risultato assente") }
    $title = if ($null -ne $Result.PSObject.Properties["title"]) { [string]$Result.title } else { "" }
    $body = if ($null -ne $Result.PSObject.Properties["body_html"]) { [string]$Result.body_html } else { "" }
    $plainBody = [System.Net.WebUtility]::HtmlDecode([regex]::Replace($body, '<[^>]+>', ' '))
    $combined = "$title $plainBody"
    if ($combined -match '[\u3400-\u9FFF\u3040-\u30FF\uAC00-\uD7AF\u0400-\u04FF\u0600-\u06FF]') {
        $issues += "alfabeto non supportato"
    }

    $englishTitleSignals = @('the', 'with', 'from', 'after', 'ahead', 'signing', 'signs', 'joins', 'agrees', 'agreement', 'reach', 'reaches', 'complete', 'completes', 'could', 'would', 'linked', 'move', 'loan', 'target')
    $signalCount = 0
    foreach ($signal in $englishTitleSignals) {
        if ($title -match ("(?i)\b" + [regex]::Escape($signal) + "\b")) { $signalCount++ }
    }
    if ($title -match '(?i)\b(set to|signs for|deal agreed|close to signing|completes signing)\b' -or $signalCount -ge 2) {
        $issues += "titolo non tradotto in italiano"
    }
    $englishBodyCount = 0
    foreach ($signal in @('the', 'and', 'with', 'from', 'that', 'this', 'after', 'have', 'has', 'will', 'their', 'his', 'her', 'for', 'into')) {
        if ($plainBody -match ("(?i)\b" + [regex]::Escape($signal) + "\b")) { $englishBodyCount++ }
    }
    $italianBodyCount = 0
    foreach ($signal in @('il', 'lo', 'la', 'gli', 'le', 'di', 'del', 'della', 'che', 'con', 'per', 'una', 'un', 'ha', 'sono')) {
        if ($plainBody -match ("(?i)\b" + [regex]::Escape($signal) + "\b")) { $italianBodyCount++ }
    }
    if ($englishBodyCount -ge 6 -and $englishBodyCount -gt ($italianBodyCount * 2)) {
        $issues += "corpo non tradotto in italiano"
    }
    if ((Get-CalcioAffariArticleWordCount $Result) -lt 80) {
        $issues += "testo inferiore al minimo redazionale di 80 parole"
    }
    return @($issues)
}

function Get-CalcioAffariLengthLimits {
    param($Job)

    $minimum = 160
    $maximum = 360
    if ($Job.validation) {
        if ([int]$Job.validation.article_min_words -gt 0) { $minimum = [int]$Job.validation.article_min_words }
        if ([int]$Job.validation.article_max_words -ge $minimum) { $maximum = [int]$Job.validation.article_max_words }
    }
    return @{ Minimum = $minimum; Maximum = $maximum }
}

function Remove-CalcioAffariInlineUrls {
    param($Result)

    if ($null -eq $Result) { return $Result }
    foreach ($field in @("title", "excerpt", "body_html")) {
        $property = $Result.PSObject.Properties[$field]
        if ($null -eq $property) { continue }
        $value = [string]$property.Value
        if ($field -eq "body_html") {
            $value = [regex]::Replace($value, '(?is)<a\b[^>]*>(.*?)</a>', '$1')
        }
        $value = [regex]::Replace($value, '(?i)\bhttps?://[^\s<>"'']+', '')
        $value = [regex]::Replace($value, '(?i)[\(\[]\s*(?:source[_\s-]*id|job[_\s-]*id|id)\s*[:#]?\s*\d+\s*[\)\]]', '')
        $value = [regex]::Replace($value, '(?i)\b(?:www\.)?[a-z0-9-]+(?:\.[a-z0-9-]+){1,3}\b', 'una fonte giornalistica')
        $value = [regex]::Replace($value, '[ \t]{2,}', ' ').Trim()
        $property.Value = $value
    }
    return $Result
}

function Invoke-Ollama {
    param($Config, $Job)

    $limits = Get-CalcioAffariLengthLimits $Job
    $result = Invoke-OllamaStructuredRequest $Config $Job ([string]$Job.prompt)
    $result = Remove-CalcioAffariInlineUrls $result
    $issues = @(Get-CalcioAffariEditorialIssues $result)
    if ($issues.Count -gt 0) {
        Write-AgentLog "warning" "Job #$($Job.id): controllo redazionale non superato ($($issues -join '; ')). Eseguo un'unica nuova stesura dai dati originali."
        $repairPrompt = ([string]$Job.prompt) + "`n`nCONTROLLO REDAZIONALE OBBLIGATORIO: la prima stesura non è utilizzabile perché $($issues -join '; '). Produci una nuova stesura completa esclusivamente dalle prove originali. Titolo, sommario e corpo devono essere in italiano naturale. Il corpo deve contenere almeno 80 parole sostanziali, senza aggiungere fatti, riempitivi, ripetizioni o un sottotitolo uguale al titolo."
        $result = Invoke-OllamaStructuredRequest $Config $Job $repairPrompt
        $result = Remove-CalcioAffariInlineUrls $result
        $remainingIssues = @(Get-CalcioAffariEditorialIssues $result)
        if ($remainingIssues.Count -gt 0) {
            Write-AgentLog "warning" "Job #$($Job.id): anche la seconda stesura richiede quarantena ($($remainingIssues -join '; ')). WordPress applicherà il blocco editoriale."
        }
    }
    $wordCount = Get-CalcioAffariArticleWordCount $result

    if ($wordCount -lt $limits.Minimum -or $wordCount -gt $limits.Maximum) {
        $warning = "Lunghezza editoriale fuori target: $wordCount parole (obiettivo $($limits.Minimum)-$($limits.Maximum))."
        $flags = @()
        if ($null -ne $result.PSObject.Properties["safety_flags"] -and $null -ne $result.safety_flags) {
            $flags = @($result.safety_flags)
        }
        $flags += $warning
        if ($null -eq $result.PSObject.Properties["safety_flags"]) {
            $result | Add-Member -NotePropertyName "safety_flags" -NotePropertyValue @($flags)
        }
        else {
            $result.PSObject.Properties["safety_flags"].Value = @($flags)
        }
        Write-AgentLog "warning" "Job #$($Job.id): $warning La bozza originale viene inviata a WordPress in revisione senza riscritture artificiali e senza rifiutare il job."
    }
    else {
        Write-AgentLog "info" "Job #$($Job.id): lunghezza editoriale nel target ($wordCount parole)."
    }
    return $result
}

function Test-RetryableAgentError {
    param($ErrorRecord)
    return (Get-CalcioAffariErrorCode $ErrorRecord) -in @("CA_NETWORK", "CA_TIMEOUT", "CA_OLLAMA_REQUEST", "CA_HTTP_429", "CA_HTTP_500", "CA_HTTP_502", "CA_HTTP_503", "CA_HTTP_504")
}

function Invoke-AgentCycle {
    param($Runtime)

    $claim = Invoke-CalcioAffariApi $Runtime "POST" "jobs/claim" @{
        worker_name = [string]$Runtime.Config.worker_name
        model = [string]$Runtime.Config.model
    }
    if ($null -eq $claim.job) { return $false }

    $job = $claim.job
    $attemptLabel = if ($job.attempt -and $job.max_attempts) { " (tentativo $($job.attempt)/$($job.max_attempts))" } else { "" }
    Write-AgentLog "info" "Elaborazione job #$($job.id)$attemptLabel con $($Runtime.Config.model)."
    try { $result = Invoke-Ollama $Runtime.Config $job }
    catch {
        $message = $_.Exception.Message
        Write-AgentLog "error" "Job #$($job.id): $message"
        $retryable = Test-RetryableAgentError $_
        try {
            Invoke-CalcioAffariApi $Runtime "POST" ("jobs/{0}/fail" -f $job.id) @{
                lease_token = [string]$job.lease_token
                error = $message.Substring(0, [Math]::Min(1000, $message.Length))
                retryable = $retryable
            } | Out-Null
        }
        catch {
            Write-AgentLog "error" "Impossibile restituire il job al sito: $($_.Exception.Message)"
        }
        return $true
    }

    try {
        $completed = Invoke-CalcioAffariApi $Runtime "POST" ("jobs/{0}/complete" -f $job.id) @{
            lease_token = [string]$job.lease_token
            model = [string]$Runtime.Config.model
            result = $result
        }
        Write-AgentLog "info" "Job #$($job.id) completato; articolo #$($completed.article.post_id), stato $($completed.article.post_status)."
    }
    catch {
        Write-AgentLog "error" "WordPress ha rifiutato il risultato del job #$($job.id): $($_.Exception.Message)"
    }
    return $true
}

if ($env:CALCIOAFFARI_AGENT_TEST_MODE -eq "1") { return }

$mutex = New-Object System.Threading.Mutex($false, "Local\CalcioAffariNewsAgent")
$hasMutex = $false
try {
    try {
        $hasMutex = $mutex.WaitOne(0, $false)
    }
    catch [System.Threading.AbandonedMutexException] {
        $hasMutex = $true
    }
    if (-not $hasMutex) { exit 0 }

    Write-AgentLog "info" "Agente v$AgentVersion avviato."
    if (Test-Path $ConnectionPausePath) {
        Write-AgentLog "warning" "Collegamento sospeso: apri l'app e completa nuovamente Collega il sito."
        exit 2
    }
    $runtime = $null
    $consecutiveErrors = 0
    do {
        try {
            if ($null -eq $runtime) { $runtime = Load-AgentConfig }
            Ensure-OllamaApi ([string]$runtime.Config.ollama_url)
            $worked = Invoke-AgentCycle $runtime
            $consecutiveErrors = 0
            $delay = if ($worked) { 3 } else { [Math]::Max(20, [int]$runtime.Config.poll_seconds) }
        }
        catch {
            $agentError = $_.Exception.Message
            Write-AgentLog "error" $agentError
            $errorCode = Get-CalcioAffariErrorCode $_
            if ($errorCode -in @("CA_AUTH_INVALID", "CA_SITEGROUND_BLOCK")) {
                [IO.File]::WriteAllText($ConnectionPausePath, $agentError, (New-Object Text.UTF8Encoding($false)))
                Write-AgentLog "warning" "Retry automatici sospesi per evitare un nuovo blocco dell'IP."
                break
            }
            $runtime = $null
            $consecutiveErrors++
            $delay = [Math]::Min(300, [Math]::Pow(2, [Math]::Min(7, $consecutiveErrors)) * 15)
            Write-AgentLog "warning" ("Nuovo tentativo tra {0} secondi." -f [int]$delay)
        }
        if ($Once) { break }
        Start-Sleep -Seconds $delay
    } while ($true)
}
finally {
    if ($hasMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
