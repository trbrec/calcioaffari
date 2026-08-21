$ErrorActionPreference = "Stop"

function Protect-CalcioAffariSecretText {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return "" }
    return [regex]::Replace($Text, '(?<![A-Za-z0-9])[A-Za-z0-9]{48}(?![A-Za-z0-9])', '[CODICE_RIMOSSO]')
}

function Protect-CalcioAffariLogFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path $Path)) { return }
    try {
        $original = [IO.File]::ReadAllText($Path)
        $safe = Protect-CalcioAffariSecretText $original
        if ($safe -ne $original) {
            [IO.File]::WriteAllText($Path, $safe, (New-Object Text.UTF8Encoding($false)))
        }
    }
    catch { }
}

function New-CalcioAffariException {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message,
        [int]$HttpStatus = 0
    )
    $exception = New-Object System.InvalidOperationException($Message)
    $exception.Data["CaCode"] = $Code
    $exception.Data["HttpStatus"] = $HttpStatus
    return $exception
}

function Get-CalcioAffariErrorCode {
    param($ErrorRecord)
    if ($ErrorRecord -and $ErrorRecord.Exception -and $ErrorRecord.Exception.Data.Contains("CaCode")) {
        return [string]$ErrorRecord.Exception.Data["CaCode"]
    }
    return "CA_UNKNOWN"
}

function Test-CalcioAffariAntiBotBody {
    param([string]$Body)
    return [bool]($Body -match '(?i)sgcaptcha|siteground.{0,40}(anti.?bot|captcha)|/\.well-known/sgcaptcha/')
}

function ConvertFrom-CalcioAffariResponse {
    param(
        [int]$StatusCode,
        [string]$ContentType,
        [string]$Body,
        [string[]]$ExpectedProperties = @()
    )

    if ($StatusCode -eq 202 -or $StatusCode -eq 403 -or (Test-CalcioAffariAntiBotBody $Body)) {
        throw (New-CalcioAffariException "CA_SITEGROUND_BLOCK" "SiteGround ha bloccato l'IP prima che la richiesta raggiungesse WordPress." $StatusCode)
    }
    if ($StatusCode -eq 401) {
        throw (New-CalcioAffariException "CA_AUTH_INVALID" "Il codice di collegamento è stato revocato o sostituito." $StatusCode)
    }
    if ($StatusCode -eq 400 -and $Body.Trim() -eq "0") {
        throw (New-CalcioAffariException "CA_PLUGIN_ENDPOINT_MISSING" "CalcioAffari News Engine non è attivo oppure il suo endpoint non è stato registrato da WordPress." $StatusCode)
    }
    if ($StatusCode -lt 200 -or $StatusCode -ge 300) {
        $serverCode = ""
        $serverMessage = ""
        if (-not [string]::IsNullOrWhiteSpace($Body) -and -not $Body.TrimStart().StartsWith("<")) {
            try {
                $errorPayload = $Body | ConvertFrom-Json
                if ($errorPayload.PSObject.Properties["code"]) { $serverCode = [string]$errorPayload.code }
                if ($errorPayload.PSObject.Properties["message"]) { $serverMessage = [string]$errorPayload.message }
            }
            catch { }
        }
        $message = if (-not [string]::IsNullOrWhiteSpace($serverMessage)) {
            if ($serverCode) { "{0} ({1}, HTTP {2})." -f $serverMessage.TrimEnd('.'), $serverCode, $StatusCode }
            else { "{0} (HTTP {1})." -f $serverMessage.TrimEnd('.'), $StatusCode }
        }
        else { "WordPress ha restituito HTTP {0}." -f $StatusCode }
        $exception = New-CalcioAffariException ("CA_HTTP_{0}" -f $StatusCode) $message $StatusCode
        if ($serverCode) { $exception.Data["ServerCode"] = $serverCode }
        throw $exception
    }
    if ([string]::IsNullOrWhiteSpace($Body)) {
        throw (New-CalcioAffariException "CA_EMPTY_RESPONSE" "WordPress ha restituito una risposta vuota." $StatusCode)
    }
    if ($ContentType -match '(?i)text/html' -or $Body.TrimStart().StartsWith("<")) {
        throw (New-CalcioAffariException "CA_HTML_RESPONSE" "Il server ha restituito una pagina HTML al posto dei dati dell'applicazione." $StatusCode)
    }

    try { $decoded = $Body | ConvertFrom-Json }
    catch { throw (New-CalcioAffariException "CA_INVALID_JSON" "WordPress ha restituito dati non validi." $StatusCode) }

    foreach ($property in $ExpectedProperties) {
        if ($null -eq $decoded.PSObject.Properties[$property]) {
            throw (New-CalcioAffariException "CA_INVALID_RESPONSE" ("La risposta WordPress non contiene '{0}'." -f $property) $StatusCode)
        }
    }
    return $decoded
}

function Get-CalcioAffariHttpClient {
    if ($script:CalcioAffariHttpClient) { return $script:CalcioAffariHttpClient }
    Add-Type -AssemblyName System.Net.Http
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
    $script:CalcioAffariHttpClient = New-Object System.Net.Http.HttpClient($handler)
    return $script:CalcioAffariHttpClient
}

function New-CalcioAffariFormContent {
    param(
        [Parameter(Mandatory = $true)][string]$Token,
        [hashtable]$Form = @{}
    )

    Add-Type -AssemblyName System.Net.Http
    $pairs = New-Object 'System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string]]'
    $pairs.Add([System.Collections.Generic.KeyValuePair[string,string]]::new("agent_token", $Token))
    foreach ($key in $Form.Keys) {
        if ($key -eq "agent_token") { continue }
        $value = $Form[$key]
        if ($null -eq $value) { $value = "" }
        elseif ($value -isnot [string]) { $value = $value | ConvertTo-Json -Depth 100 -Compress }
        $pairs.Add([System.Collections.Generic.KeyValuePair[string,string]]::new([string]$key, [string]$value))
    }

    # ToArray is intentional: Windows PowerShell 5.1 otherwise expands the generic
    # list and tries to bind the first KeyValuePair as the whole constructor argument.
    return [System.Net.Http.FormUrlEncodedContent]::new($pairs.ToArray())
}

function Invoke-CalcioAffariJsonRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$UserAgent,
        [Parameter(Mandatory = $true)][string]$Token,
        [hashtable]$Form = @{},
        [int]$TimeoutSeconds = 30,
        [string[]]$ExpectedProperties = @()
    )

    $client = Get-CalcioAffariHttpClient
    $request = New-Object System.Net.Http.HttpRequestMessage([Net.Http.HttpMethod]::Post, $Uri)
    $request.Headers.TryAddWithoutValidation("User-Agent", $UserAgent) | Out-Null
    $request.Headers.TryAddWithoutValidation("X-CalcioAffari-Token", $Token) | Out-Null

    $request.Content = New-CalcioAffariFormContent -Token $Token -Form $Form
    $cancellation = New-Object System.Threading.CancellationTokenSource
    $cancellation.CancelAfter([TimeSpan]::FromSeconds([Math]::Max(1, $TimeoutSeconds)))
    try {
        try { $response = $client.SendAsync($request, $cancellation.Token).GetAwaiter().GetResult() }
        catch [System.Threading.Tasks.TaskCanceledException] {
            throw (New-CalcioAffariException "CA_TIMEOUT" "Il collegamento a WordPress ha superato il tempo massimo." 0)
        }
        catch {
            if ((Get-CalcioAffariErrorCode $_) -ne "CA_UNKNOWN") { throw }
            throw (New-CalcioAffariException "CA_NETWORK" ("WordPress non è raggiungibile: {0}" -f $_.Exception.Message) 0)
        }
        try {
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $contentType = if ($response.Content.Headers.ContentType) { [string]$response.Content.Headers.ContentType.MediaType } else { "" }
            return ConvertFrom-CalcioAffariResponse -StatusCode ([int]$response.StatusCode) -ContentType $contentType -Body $body -ExpectedProperties $ExpectedProperties
        }
        finally { $response.Dispose() }
    }
    finally {
        $cancellation.Dispose()
        $request.Dispose()
    }
}

function Get-CalcioAffariFriendlyError {
    param($ErrorRecord)
    switch (Get-CalcioAffariErrorCode $ErrorRecord) {
        "CA_AUTH_INVALID" { return "Codice non valido o sostituito. Generane uno nuovo in WordPress > CalcioAffari." }
        "CA_SITEGROUND_BLOCK" { return "SiteGround ha bloccato l'IP di questo PC. Apri SiteGround > Centro assistenza > Risolvere problemi nel sito > calcioaffari.it > SBLOCCA IP, poi riprova." }
        "CA_TIMEOUT" { return "WordPress non ha risposto entro il tempo massimo. Controlla Internet e riprova." }
        "CA_NETWORK" { return (Protect-CalcioAffariSecretText $ErrorRecord.Exception.Message) }
        "CA_HTML_RESPONSE" { return "Il server ha restituito una pagina web invece dei dati. Controlla le protezioni SiteGround e riprova." }
        "CA_INVALID_JSON" { return "La risposta WordPress è danneggiata o incompleta. Aggiorna il plugin CalcioAffari News Engine." }
        "CA_INVALID_RESPONSE" { return "Il plugin WordPress non ha restituito i dati richiesti. Aggiorna CalcioAffari News Engine." }
        "CA_PLUGIN_ENDPOINT_MISSING" { return "CalcioAffari News Engine non è attivo in WordPress. Apri Plugin, attivalo e riprova." }
        default { return (Protect-CalcioAffariSecretText $ErrorRecord.Exception.Message) }
    }
}

function Enable-CalcioAffariDpiAwareness {
    try {
        if (-not ("CalcioAffari.NativeMethods" -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace CalcioAffari {
    public static class NativeMethods {
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    }
}
"@
        }
        [CalcioAffari.NativeMethods]::SetProcessDPIAware() | Out-Null
    }
    catch { }
}

function Get-CalcioAffariHiddenPowerShellLaunch {
    param(
        [Parameter(Mandatory = $true)][string]$InstallDir,
        [Parameter(Mandatory = $true)][string]$ScriptPath
    )

    $wscriptPath = Join-Path $env:SystemRoot "System32\wscript.exe"
    $launcherPath = Join-Path $InstallDir "hidden-launcher.vbs"
    $resolvedScriptPath = [IO.Path]::GetFullPath($ScriptPath)
    if (-not (Test-Path $wscriptPath)) { throw "Windows Script Host non è disponibile." }
    if (-not (Test-Path $launcherPath)) { throw "Launcher invisibile mancante. Reinstalla CalcioAffari Local Newsroom." }
    if (-not (Test-Path $resolvedScriptPath)) { throw "Script non trovato: $resolvedScriptPath" }

    $arguments = "//B //NoLogo `"$launcherPath`" `"$resolvedScriptPath`""
    return [pscustomobject]@{
        FilePath = $wscriptPath
        Arguments = $arguments
        Command = "`"$wscriptPath`" $arguments"
    }
}

function Start-CalcioAffariHiddenPowerShell {
    param(
        [Parameter(Mandatory = $true)][string]$InstallDir,
        [Parameter(Mandatory = $true)][string]$ScriptPath
    )

    $launch = Get-CalcioAffariHiddenPowerShellLaunch -InstallDir $InstallDir -ScriptPath $ScriptPath
    return Start-Process -FilePath $launch.FilePath -ArgumentList $launch.Arguments -PassThru
}

function Get-CalcioAffariScheduledTask {
    param([Parameter(Mandatory = $true)][string]$Name)

    try {
        $service = New-Object -ComObject "Schedule.Service"
        $service.Connect()
        return $service.GetFolder("\").GetTask($Name)
    }
    catch { return $null }
}

function Test-CalcioAffariScheduledTask {
    param([Parameter(Mandatory = $true)][string]$Name)
    return $null -ne (Get-CalcioAffariScheduledTask -Name $Name)
}

function Stop-CalcioAffariScheduledTask {
    param([Parameter(Mandatory = $true)][string]$Name)

    $task = Get-CalcioAffariScheduledTask -Name $Name
    if (-not $task) { return $false }
    try { $task.Stop(0); return $true }
    catch { return $false }
}

function Start-CalcioAffariScheduledTask {
    param([Parameter(Mandatory = $true)][string]$Name)

    $task = Get-CalcioAffariScheduledTask -Name $Name
    if (-not $task) { throw "Attività automatica '$Name' non trovata. Usa Ripara per ricrearla." }
    try { $task.Run($null) | Out-Null }
    catch { throw "Impossibile avviare l'attività automatica '$Name': $($_.Exception.Message)" }
}
