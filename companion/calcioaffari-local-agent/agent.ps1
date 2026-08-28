[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $env:LOCALAPPDATA "CalcioAffari\agent.json"),
    [switch]$Once
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$AgentVersion = "1.3.3"
$ConnectionPausePath = Join-Path (Split-Path -Parent $ConfigPath) "connection-paused.txt"
$UserPausePath = Join-Path (Split-Path -Parent $ConfigPath) "agent-paused.txt"
$script:TerminalJobs = @{}
$script:ModelTouched = $false
$script:LastGpuDeferral = ""
$script:JobInferenceCalls = 0
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
    $siteUrl = [string]$config.site_url
    if (-not ($siteUrl.StartsWith("https://") -or $siteUrl -match '^http://(?:127\.0\.0\.1|localhost)(?::\d+)?$')) {
        throw "site_url deve usare HTTPS; HTTP è consentito soltanto sul loopback di test."
    }
    if ([string]$config.ollama_url -notmatch '^http://(127\.0\.0\.1|localhost)(:\d+)?$') {
        throw "ollama_url deve restare locale (localhost)."
    }

    $plainToken = ""
    if ($siteUrl -match '^http://(?:127\.0\.0\.1|localhost)(?::\d+)?$' -and $env:CA_STAGING_AGENT_TOKEN -match '^[A-Za-z0-9]{48}$') {
        $plainToken = [string]$env:CA_STAGING_AGENT_TOKEN
    }
    else {
        $secretPath = Join-Path (Split-Path -Parent $ConfigPath) "agent-token.txt"
        if (-not (Test-Path $secretPath)) { throw "Codice di collegamento non trovato. Riesegui la configurazione." }
        $encryptedToken = [IO.File]::ReadAllText($secretPath).Trim()
        $secureToken = ConvertTo-SecureString -String $encryptedToken
        $credential = [System.Management.Automation.PSCredential]::new("calcioaffari", $secureToken)
        $plainToken = $credential.GetNetworkCredential().Password
    }
    $profile = Get-CalcioAffariConfiguredProfile $config
    Set-CalcioAffariProcessProfile $profile
    return @{ Config = $config; Profile = $profile; AgentToken = $plainToken }
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

function New-CalcioAffariOllamaRequest {
    param(
        $Config,
        $Job,
        [string]$Prompt,
        [string]$SystemPrompt,
        $Format,
        [double]$Temperature,
        [int]$NumPredict
    )
    $profile = Get-CalcioAffariConfiguredProfile $Config
    $options = @{
        temperature = $Temperature
        num_ctx = [int]$Job.generation.num_ctx
        num_predict = $NumPredict
        seed = 20260812
    }
    if ([int]$profile.NumThread -gt 0) { $options.num_thread = [int]$profile.NumThread }
    return @{
        model = [string]$Config.model
        system = $SystemPrompt
        prompt = $Prompt
        format = $Format
        stream = $false
        think = $false
        keep_alive = [string]$profile.KeepAlive
        options = $options
    }
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
    $profile = Get-CalcioAffariConfiguredProfile $Config
    $script:JobInferenceCalls++
    if ($script:JobInferenceCalls -gt [int]$profile.MaxInferenceCalls) {
        throw (New-CalcioAffariException "CA_INFERENCE_BUDGET" ("Job #{0}: superato il budget massimo di {1} inferenze; job messo in quarantena senza ulteriore carico locale." -f $Job.id, $profile.MaxInferenceCalls))
    }

    Ensure-OllamaApi ([string]$Config.ollama_url)
    $script:ModelTouched = $true
    $uri = $Config.ollama_url.TrimEnd('/') + "/api/generate"
    if ([string]::IsNullOrWhiteSpace($SystemPrompt)) { $SystemPrompt = [string]$Job.system_prompt }
    if ($null -eq $Format) { $Format = $Job.schema }
    if ($Temperature -lt 0) { $Temperature = [double]$Job.generation.temperature }
    if ($NumPredict -le 0) { $NumPredict = [int]$Job.generation.num_predict }
    $request = New-CalcioAffariOllamaRequest $Config $Job $Prompt $SystemPrompt $Format $Temperature $NumPredict
    $requestJson = $request | ConvertTo-Json -Depth 100 -Compress
    $client = $null
    $message = $null
    $content = $null
    $responseMessage = $null
    $cancellation = $null
    try {
        Add-Type -AssemblyName System.Net.Http
        $client = [System.Net.Http.HttpClient]::new()
        $client.Timeout = [Threading.Timeout]::InfiniteTimeSpan
        $cancellation = [Threading.CancellationTokenSource]::new()
        $cancellation.CancelAfter([TimeSpan]::FromSeconds(900))
        $message = [System.Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post, $uri)
        $content = [System.Net.Http.StringContent]::new($requestJson, [Text.Encoding]::UTF8, "application/json")
        $message.Content = $content
        $sendTask = $client.SendAsync($message, [Net.Http.HttpCompletionOption]::ResponseContentRead, $cancellation.Token)
        $preemptReason = ""
        while (-not $sendTask.IsCompleted) {
            if (Test-Path $UserPausePath) {
                $preemptReason = "pausa richiesta dall'utente"
                break
            }
            if ([bool]$profile.DeferOnExternalGpuLoad) {
                $externalGpu = Get-CalcioAffariExternalGpuLoad -Threshold ([int]$profile.GpuBusyThreshold)
                if ($externalGpu) {
                    $preemptReason = ("carico GPU esterno rilevato da {0} (PID {1}, circa {2}%)" -f $externalGpu.ProcessName, $externalGpu.ProcessId, $externalGpu.Utilization)
                    break
                }
            }
            Start-Sleep -Seconds ([Math]::Max(1, [int]$profile.ResourceCheckSeconds))
        }
        if ($preemptReason) {
            $cancellation.Cancel()
            try { $sendTask.Wait(3000) | Out-Null } catch { }
            Stop-CalcioAffariModel -Model ([string]$Config.model)
            $script:ModelTouched = $false
            throw (New-CalcioAffariException "CA_RESOURCE_PREEMPTED" ("Elaborazione interrotta in sicurezza: {0}. Qwen3 è stato scaricato e il job verrà ripreso più tardi." -f $preemptReason))
        }
        $responseMessage = $sendTask.GetAwaiter().GetResult()
        $responseText = $responseMessage.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if (-not $responseMessage.IsSuccessStatusCode) {
            throw (New-CalcioAffariException "CA_OLLAMA_REQUEST" ("Ollama ha restituito HTTP {0}: {1}" -f [int]$responseMessage.StatusCode, $responseText.Substring(0, [Math]::Min(500, $responseText.Length))))
        }
        $response = $responseText | ConvertFrom-Json
    }
    catch {
        $code = Get-CalcioAffariErrorCode $_
        if ($code -in @("CA_RESOURCE_PREEMPTED", "CA_OLLAMA_REQUEST")) { throw }
        if ($cancellation -and $cancellation.IsCancellationRequested) {
            throw (New-CalcioAffariException "CA_OLLAMA_REQUEST" "Ollama non ha completato l'elaborazione entro 15 minuti.")
        }
        throw (New-CalcioAffariException "CA_OLLAMA_REQUEST" ("Ollama non ha completato l'elaborazione: {0}" -f $_.Exception.Message))
    }
    finally {
        if ($responseMessage) { $responseMessage.Dispose() }
        if ($content) { $content.Dispose() }
        if ($message) { $message.Dispose() }
        if ($cancellation) { $cancellation.Dispose() }
        if ($client) { $client.Dispose() }
    }
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

function Test-CalcioAffariClaimRepresented {
    param([string]$Claim, [string]$Article)

    $normalize = {
        param([string]$Value)
        $value = $Value.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
        $value = -join ($value.ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne [Globalization.UnicodeCategory]::NonSpacingMark })
        return ([regex]::Replace($value, '[^\p{L}\p{N}]+', ' ')).Trim()
    }
    $claimText = & $normalize $Claim
    $articleText = & $normalize $Article
    if ($claimText.Length -lt 12) { return $false }
    if ($articleText.Contains($claimText)) { return $true }
    $tokens = @($claimText -split '\s+' | Where-Object { $_.Length -ge 4 } | Sort-Object -Unique)
    if ($tokens.Count -lt 3) { return $false }
    $matched = @($tokens | Where-Object { $articleText -match ('(?:^|\s)' + [regex]::Escape($_) + '(?:\s|$)') }).Count
    return ($matched / $tokens.Count) -ge 0.8
}

function Get-CalcioAffariEditorialIssues {
    param($Result, [int]$MinimumWordCount = 45)

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
    $MinimumWordCount = [Math]::Max(30, [Math]::Min(80, $MinimumWordCount))
    if ((Get-CalcioAffariArticleWordCount $Result) -lt $MinimumWordCount) {
        $issues += "testo inferiore al minimo assoluto di $MinimumWordCount parole"
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
            if (-not (Test-CalcioAffariClaimRepresented ([string]$claim.text) $combined)) {
                $issues += "claim strutturato non rintracciabile nel testo dell'articolo"
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
    $auditSystem = "Sei il revisore indipendente di CalcioAffari. Non riscrivere l'articolo. Valuta il significato giornalistico, non la coincidenza letterale: una parafrasi fedele è sostenuta, mentre nomi, ruoli, club, cifre, date, citazioni e stato dell'operazione non possono andare oltre le PROVE. Non contestare normali connettivi grammaticali che non aggiungono fatti. Segna source_grounded=false per ogni nuova informazione materiale, previsione, conseguenza ipotetica o formula generica presentata come fatto. Segna single_story=false se il testo fonde operazioni distinte. Segna grammar_ok=false per italiano innaturale, preposizioni errate, frasi corrotte o attribuzioni generiche. Segna approved=true soltanto quando tutti gli altri controlli sono true e gli array issues e unsupported_claims sono vuoti. Restituisci soltanto JSON conforme allo schema."
    $articleJson = $Result | ConvertTo-Json -Depth 100 -Compress
    $auditPrompt = ([string]$Job.prompt) + "`n`nARTICOLO DA VERIFICARE:`n" + $articleJson
    return Invoke-OllamaStructuredRequest $Config $Job $auditPrompt $auditSystem $auditSchema 0 480
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

function Get-CalcioAffariAbsoluteMinimum {
    param($Job)

    $minimum = 45
    if ($Job.validation -and [int]$Job.validation.article_absolute_min_words -gt 0) {
        $minimum = [int]$Job.validation.article_absolute_min_words
    }
    return [Math]::Max(30, [Math]::Min(80, $minimum))
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

    $script:JobInferenceCalls = 0
    $profile = Get-CalcioAffariConfiguredProfile $Config
    $limits = Get-CalcioAffariLengthLimits $Job
    $absoluteMinimum = Get-CalcioAffariAbsoluteMinimum $Job
    $result = Invoke-OllamaStructuredRequest $Config $Job ([string]$Job.prompt)
    $result = Remove-CalcioAffariInlineUrls $result
    $audit = Invoke-CalcioAffariGroundingAudit $Config $Job $result
    $issues = @((@(Get-CalcioAffariEditorialIssues $result $absoluteMinimum) + @(Get-CalcioAffariAuditIssues $audit)) | Select-Object -Unique)
    $revision = 0
    while ($issues.Count -gt 0 -and $revision -lt [int]$profile.MaxRevisions) {
        $revision++
        Write-AgentLog "warning" "Job #$($Job.id): controllo di grounding non superato ($($issues -join '; ')). Eseguo l'unica riscrittura guidata consentita dai dati originali."
        $repairPrompt = ([string]$Job.prompt) + "`n`nCONTROLLO REDAZIONALE OBBLIGATORIO, RISCRITTURA UNICA: la stesura precedente non è utilizzabile perché $($issues -join '; '). Produci una nuova stesura completa esclusivamente dalle prove originali. Rimuovi ogni frase contestata invece di attenuarla o sostituirla con una formula generica. Non aggiungere previsioni, sviluppi attesi, conseguenze, dubbi non presenti nelle prove o frasi di chiusura. Tratta una sola operazione, attribuisci le informazioni alla testata indicata nelle prove e usa soltanto paragrafi senza sottotitoli. Titolo, sommario e corpo devono essere in italiano naturale. Il corpo deve contenere almeno $absoluteMinimum parole sostanziali; fermati appena hai esaurito i fatti dimostrabili, senza riempitivi o ripetizioni."
        $result = Invoke-OllamaStructuredRequest $Config $Job $repairPrompt
        $result = Remove-CalcioAffariInlineUrls $result
        $audit = Invoke-CalcioAffariGroundingAudit $Config $Job $result
        $issues = @((@(Get-CalcioAffariEditorialIssues $result $absoluteMinimum) + @(Get-CalcioAffariAuditIssues $audit)) | Select-Object -Unique)
    }
    if ($issues.Count -gt 0) {
        $reason = ($issues -join '; ')
        Write-AgentLog "error" "Job #$($Job.id): stesura non conforme dopo la riscrittura guidata; quarantena ($reason). Nessun articolo viene creato."
        throw (New-CalcioAffariException "CA_EDITORIAL_QUARANTINE" ("Quarantena editoriale: {0}" -f $reason))
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
    return (Get-CalcioAffariErrorCode $ErrorRecord) -in @("CA_NETWORK", "CA_TIMEOUT", "CA_OLLAMA_REQUEST", "CA_RESOURCE_PREEMPTED", "CA_HTTP_429", "CA_HTTP_500", "CA_HTTP_502", "CA_HTTP_503", "CA_HTTP_504")
}

function Send-CalcioAffariJobFailure {
    param(
        $Runtime,
        $Job,
        [Parameter(Mandatory = $true)][string]$Message,
        [bool]$Retryable
    )

    $safeMessage = $Message.Substring(0, [Math]::Min(1000, $Message.Length))
    Invoke-CalcioAffariApi $Runtime "POST" ("jobs/{0}/fail" -f $Job.id) @{
        lease_token = [string]$Job.lease_token
        error = $safeMessage
        retryable = $Retryable
    } | Out-Null

    if ($Retryable) {
        Write-AgentLog "warning" "Job #$($Job.id) restituito a WordPress per un nuovo tentativo controllato."
    }
    else {
        $script:TerminalJobs[[string]$Job.id] = [DateTimeOffset]::UtcNow
        Write-AgentLog "warning" "Job #$($Job.id) chiuso definitivamente da WordPress; non verrà rigenerato dall'agente."
    }
}

function Assert-CalcioAffariJobNotRequeued {
    param($Job)
    $key = [string]$Job.id
    if (-not $script:TerminalJobs.ContainsKey($key)) { return }
    $age = [DateTimeOffset]::UtcNow - [DateTimeOffset]$script:TerminalJobs[$key]
    if ($age.TotalHours -lt 6) {
        throw (New-CalcioAffariException "CA_SERVER_REQUEUED_TERMINAL" ("WordPress ha rimesso in coda il job terminale #{0}. Agente sospeso prima di richiamare Qwen3." -f $Job.id))
    }
    $script:TerminalJobs.Remove($key)
}

function Invoke-AgentCycle {
    param($Runtime)

    $claim = Invoke-CalcioAffariApi $Runtime "POST" "jobs/claim" @{
        worker_name = [string]$Runtime.Config.worker_name
        model = [string]$Runtime.Config.model
    }
    if ($null -eq $claim.job) { return $false }

    $job = $claim.job
    Assert-CalcioAffariJobNotRequeued $job
    $attemptLabel = if ($job.attempt -and $job.max_attempts) { " (tentativo $($job.attempt)/$($job.max_attempts))" } else { "" }
    Write-AgentLog "info" "Elaborazione job #$($job.id)$attemptLabel con $($Runtime.Config.model)."
    try { $result = Invoke-Ollama $Runtime.Config $job }
    catch {
        $message = $_.Exception.Message
        Write-AgentLog "error" "Job #$($job.id): $message"
        $retryable = Test-RetryableAgentError $_
        try {
            Send-CalcioAffariJobFailure $Runtime $job $message $retryable
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
        $rejection = $_.Exception.Message
        $serverCode = Get-CalcioAffariServerErrorCode $_
        Write-AgentLog "error" "WordPress ha rifiutato il risultato del job #$($job.id): $rejection"
        if ((Get-CalcioAffariErrorCode $_) -eq "CA_HTTP_400" -and $serverCode -match '^ca_news_') {
            # The completion endpoint validates the result, stores the terminal
            # rejection in the queue, clears the lease, then returns the named
            # editorial error. Remember it locally as a circuit breaker in case
            # a later server reconciliation incorrectly admits it again.
            $script:TerminalJobs[[string]$job.id] = [DateTimeOffset]::UtcNow
            Write-AgentLog "warning" "Job #$($job.id) respinto definitivamente da WordPress ($serverCode)."
        }
        else {
            try {
                Send-CalcioAffariJobFailure $Runtime $job ("Risultato non completato: {0}" -f $rejection) (Test-RetryableAgentError $_)
            }
            catch {
                $returnError = $_.Exception.Message
                Write-AgentLog "error" "Impossibile chiudere il job rifiutato #$($job.id): $returnError"
                throw (New-CalcioAffariException "CA_TERMINAL_FAIL_NOT_ACKNOWLEDGED" ("WordPress ha rifiutato il risultato e non ha confermato la chiusura del job #{0}. Elaborazione sospesa per evitare un ciclo continuo." -f $job.id))
            }
        }
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
    if (Test-Path $UserPausePath) {
        Write-AgentLog "info" "Agente in pausa su richiesta dell'utente."
        exit 0
    }
    if (Test-Path $ConnectionPausePath) {
        Write-AgentLog "warning" "Collegamento sospeso: apri l'app e completa nuovamente Collega il sito."
        exit 2
    }
    $runtime = $null
    $consecutiveErrors = 0
    do {
        try {
            if ($null -eq $runtime) {
                $runtime = Load-AgentConfig
                $idleDelay = [int]$runtime.Profile.PollSeconds
                $burstJobs = 0
            }
            $externalGpu = $null
            if (-not $script:ModelTouched -and [bool]$runtime.Profile.DeferOnExternalGpuLoad) {
                $externalGpu = Get-CalcioAffariExternalGpuLoad -Threshold ([int]$runtime.Profile.GpuBusyThreshold)
            }
            if ($externalGpu) {
                $signature = "{0}:{1}" -f $externalGpu.ProcessId, $externalGpu.ProcessName
                if ($signature -ne $script:LastGpuDeferral) {
                    Write-AgentLog "info" ("GPU già occupata da {0} (PID {1}, circa {2}%): nessun job acquisito." -f $externalGpu.ProcessName, $externalGpu.ProcessId, $externalGpu.Utilization)
                    $script:LastGpuDeferral = $signature
                }
                $worked = $false
                $gpuDeferred = $true
            }
            else {
                if ($script:LastGpuDeferral) {
                    Write-AgentLog "info" "GPU nuovamente disponibile: controllo della coda ripristinato."
                    $script:LastGpuDeferral = ""
                }
                $worked = Invoke-AgentCycle $runtime
                $gpuDeferred = $false
            }
            $consecutiveErrors = 0
            if ($gpuDeferred) {
                $burstJobs = 0
                $delay = [Math]::Max(60, [int]$runtime.Profile.PollSeconds)
            }
            elseif ($worked) {
                $idleDelay = [int]$runtime.Profile.PollSeconds
                $burstJobs++
                if ($burstJobs -ge [int]$runtime.Profile.MaxBurstJobs) {
                    if ($script:ModelTouched) {
                        Stop-CalcioAffariModel -Model ([string]$runtime.Config.model)
                        $script:ModelTouched = $false
                        Write-AgentLog "info" "Raffica completata: Qwen3 scaricato dalla memoria."
                    }
                    $burstJobs = 0
                    $delay = [int]$runtime.Profile.CooldownSeconds
                }
                else { $delay = [int]$runtime.Profile.ActiveDelaySeconds }
            }
            else {
                if ($script:ModelTouched) {
                    Stop-CalcioAffariModel -Model ([string]$runtime.Config.model)
                    $script:ModelTouched = $false
                    Write-AgentLog "info" "Coda vuota: Qwen3 scaricato dalla memoria."
                }
                $burstJobs = 0
                $delay = $idleDelay
                $idleDelay = [Math]::Min([int]$runtime.Profile.IdleMaxSeconds, [Math]::Max([int]$runtime.Profile.PollSeconds, $idleDelay * 2))
            }
        }
        catch {
            $agentError = $_.Exception.Message
            Write-AgentLog "error" $agentError
            $errorCode = Get-CalcioAffariErrorCode $_
            if ($errorCode -in @("CA_SERVER_REQUEUED_TERMINAL", "CA_TERMINAL_FAIL_NOT_ACKNOWLEDGED")) {
                [IO.File]::WriteAllText($ConnectionPausePath, $agentError, (New-Object Text.UTF8Encoding($false)))
                Write-AgentLog "warning" "Elaborazione automatica sospesa per evitare un ciclo continuo."
                break
            }
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
    if ($script:ModelTouched) {
        try {
            $config = if ($runtime) { $runtime.Config } else { $null }
            if ($config) { Stop-CalcioAffariModel -Model ([string]$config.model) }
        }
        catch { }
        $script:ModelTouched = $false
    }
    if ($hasMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
