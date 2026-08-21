[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $env:LOCALAPPDATA "CalcioAffari\agent.json"),
    [switch]$Once
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$AgentVersion = "1.1.0"
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
    param(
        $Config,
        $Job,
        [string]$Prompt,
        [string]$SystemPrompt = "",
        $Format = $null,
        [double]$Temperature = -1,
        [int]$NumPredict = 0
    )
    Ensure-OllamaApi ([string]$Config.ollama_url)
    $uri = $Config.ollama_url.TrimEnd('/') + "/api/generate"
    if ([string]::IsNullOrWhiteSpace($SystemPrompt)) { $SystemPrompt = [string]$Job.system_prompt }
    if ($null -eq $Format) { $Format = $Job.schema }
    if ($Temperature -lt 0) { $Temperature = [double]$Job.generation.temperature }
    if ($NumPredict -le 0) { $NumPredict = [int]$Job.generation.num_predict }
    $request = @{
        model = [string]$Config.model
        system = $SystemPrompt
        prompt = $Prompt
        format = $Format
        stream = $false
        think = $false
        keep_alive = "10m"
        options = @{
            temperature = $Temperature
            num_ctx = [int]$Job.generation.num_ctx
            num_predict = $NumPredict
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
    if ($body -match '(?i)<h[1-6]\b') {
        $issues += "sottotitoli non ammessi in un breve articolo di agenzia"
    }
    if ($combined -match '(?i)\b(?:una|diverse) font[ei] giornalistic[ae]\b') {
        $issues += "attribuzione generica: indicare la testata presente nelle prove"
    }
    if ($combined -match '(?i)\b(?:intorno|pari)\s+(?:a|ai|alle)\s+una fonte giornalistica\b|\bstagione scorso\b|\bal Juventus\b') {
        $issues += "errore grammaticale o frase corrotta"
    }
    if ($null -ne $Result.PSObject.Properties["safety_flags"] -and $null -ne $Result.safety_flags) {
        foreach ($flag in @($Result.safety_flags)) {
            if ([string]$flag -match '(?i)prove insufficienti|mappatura.+incompleta|affermazion.+non supportat|storie.+distinte|fatti.+inventat') {
                $issues += ("segnalazione bloccante: {0}" -f [string]$flag)
            }
        }
    }
    $claimIds = @()
    if ($null -eq $Result.PSObject.Properties["claims"] -or @($Result.claims).Count -eq 0) {
        $issues += "mappatura delle affermazioni assente"
    }
    else {
        foreach ($claim in @($Result.claims)) {
            $sources = if ($null -ne $claim.PSObject.Properties["source_ids"]) { @($claim.source_ids) } else { @() }
            $quotes = if ($null -ne $claim.PSObject.Properties["evidence_quotes"]) { @($claim.evidence_quotes) } else { @() }
            if ([string]::IsNullOrWhiteSpace([string]$claim.text) -or $sources.Count -eq 0 -or $quotes.Count -eq 0) {
                $issues += "claim privo di testo, fonte o estratto-prova"
                continue
            }
            foreach ($sourceId in $sources) {
                $claimIds += [int]$sourceId
                $matchingQuotes = @($quotes | Where-Object { [int]$_.source_id -eq [int]$sourceId -and -not [string]::IsNullOrWhiteSpace([string]$_.quote) })
                if ($matchingQuotes.Count -eq 0) { $issues += "estratto-prova mancante per una fonte dichiarata" }
            }
        }
    }
    $declaredIds = if ($null -ne $Result.PSObject.Properties["source_ids"]) { @($Result.source_ids | ForEach-Object { [int]$_ } | Sort-Object -Unique) } else { @() }
    $usedIds = @($claimIds | Sort-Object -Unique)
    if (($declaredIds -join ',') -ne ($usedIds -join ',')) {
        $issues += "source_ids non coincide con l'unione delle fonti dei claim"
    }
    return @($issues)
}

function Get-CalcioAffariAuditIssues {
    param($Audit)

    $issues = @()
    if ($null -eq $Audit) { return @("revisione di grounding assente") }
    foreach ($field in @("approved", "single_story", "language_ok", "grammar_ok", "source_grounded")) {
        if ($null -eq $Audit.PSObject.Properties[$field] -or -not [bool]$Audit.$field) {
            $issues += ("audit non superato: {0}" -f $field)
        }
    }
    foreach ($issue in @($Audit.issues)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$issue)) { $issues += [string]$issue }
    }
    foreach ($claim in @($Audit.unsupported_claims)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$claim)) { $issues += ("affermazione non supportata: {0}" -f [string]$claim) }
    }
    return @($issues | Select-Object -Unique)
}

function Invoke-CalcioAffariGroundingAudit {
    param($Config, $Job, $Result)

    $stringArray = @{ type = "array"; items = @{ type = "string" } }
    $auditSchema = @{
        type = "object"
        additionalProperties = $false
        required = @("approved", "single_story", "language_ok", "grammar_ok", "source_grounded", "issues", "unsupported_claims")
        properties = @{
            approved = @{ type = "boolean" }
            single_story = @{ type = "boolean" }
            language_ok = @{ type = "boolean" }
            grammar_ok = @{ type = "boolean" }
            source_grounded = @{ type = "boolean" }
            issues = $stringArray
            unsupported_claims = $stringArray
        }
    }
    $auditSystem = "Sei il revisore indipendente di CalcioAffari. Non riscrivere l'articolo. Confronta ogni frase, nome, ruolo, club, cifra, data, citazione e stato dell'operazione esclusivamente con le PROVE. Segna source_grounded=false se anche un solo dettaglio non è esplicitamente sostenuto. Segna single_story=false se il testo fonde operazioni distinte. Segna grammar_ok=false per italiano innaturale, preposizioni errate, frasi corrotte o attribuzioni generiche. Segna approved=true soltanto quando tutti gli altri controlli sono true e gli array issues e unsupported_claims sono vuoti. Restituisci soltanto JSON conforme allo schema."
    $articleJson = $Result | ConvertTo-Json -Depth 100 -Compress
    $auditPrompt = ([string]$Job.prompt) + "`n`nARTICOLO DA VERIFICARE:`n" + $articleJson
    return Invoke-OllamaStructuredRequest $Config $Job $auditPrompt $auditSystem $auditSchema 0 900
}

function Set-CalcioAffariEditorialAudit {
    param($Result, $Audit)

    $metadata = [pscustomobject]@{
        approved = [bool]$Audit.approved
        single_story = [bool]$Audit.single_story
        language_ok = [bool]$Audit.language_ok
        grammar_ok = [bool]$Audit.grammar_ok
        source_grounded = [bool]$Audit.source_grounded
        issues = @($Audit.issues)
        unsupported_claims = @($Audit.unsupported_claims)
        verifier = "qwen3-local-grounding-v1"
        app_version = $AgentVersion
    }
    if ($null -eq $Result.PSObject.Properties["editorial_audit"]) {
        $Result | Add-Member -NotePropertyName "editorial_audit" -NotePropertyValue $metadata
    }
    else {
        $Result.PSObject.Properties["editorial_audit"].Value = $metadata
    }
    return $Result
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
    $audit = Invoke-CalcioAffariGroundingAudit $Config $Job $result
    $issues = @((@(Get-CalcioAffariEditorialIssues $result) + @(Get-CalcioAffariAuditIssues $audit)) | Select-Object -Unique)
    if ($issues.Count -gt 0) {
        Write-AgentLog "warning" "Job #$($Job.id): controllo di grounding non superato ($($issues -join '; ')). Eseguo un'unica nuova stesura dai dati originali."
        $repairPrompt = ([string]$Job.prompt) + "`n`nCONTROLLO REDAZIONALE OBBLIGATORIO: la prima stesura non è utilizzabile perché $($issues -join '; '). Produci una sola nuova stesura completa esclusivamente dalle prove originali. Elimina ogni dettaglio non esplicitamente sostenuto, tratta una sola operazione, attribuisci le informazioni alla testata indicata nelle prove e usa soltanto paragrafi senza sottotitoli. Titolo, sommario e corpo devono essere in italiano naturale. Il corpo deve contenere almeno 80 parole sostanziali, senza riempitivi o ripetizioni."
        $result = Invoke-OllamaStructuredRequest $Config $Job $repairPrompt
        $result = Remove-CalcioAffariInlineUrls $result
        $audit = Invoke-CalcioAffariGroundingAudit $Config $Job $result
        $remainingIssues = @((@(Get-CalcioAffariEditorialIssues $result) + @(Get-CalcioAffariAuditIssues $audit)) | Select-Object -Unique)
        if ($remainingIssues.Count -gt 0) {
            $reason = ($remainingIssues -join '; ')
            Write-AgentLog "error" "Job #$($Job.id): seconda stesura messa in quarantena ($reason). Nessun articolo viene creato."
            throw (New-CalcioAffariException "CA_EDITORIAL_QUARANTINE" ("Quarantena editoriale: {0}" -f $reason))
        }
    }
    $result = Set-CalcioAffariEditorialAudit $result $audit
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
