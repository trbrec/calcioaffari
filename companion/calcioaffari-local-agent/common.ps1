$ErrorActionPreference = "Stop"

function Get-CalcioAffariAgentPath {
    param([Parameter(Mandatory = $true)][string]$InstallDir)

    $versioned = @(Get-ChildItem -LiteralPath $InstallDir -Filter 'agent-*.ps1' -File -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.BaseName -match '^agent-(\d+(?:\.\d+){1,3})$') {
            [pscustomobject]@{ File = $_; Version = [version]$Matches[1] }
        }
    } | Sort-Object Version -Descending)
    if ($versioned.Count -gt 0) { return $versioned[0].File.FullName }
    return [IO.Path]::GetFullPath((Join-Path $InstallDir 'agent.ps1'))
}

function Get-CalcioAffariResourceProfile {
    param([AllowNull()][string]$Name)

    $normalized = if ([string]::IsNullOrWhiteSpace($Name)) { "Bilanciato" } else { $Name.Trim() }
    switch -Regex ($normalized) {
        '^(?i:eco)$' {
            return [pscustomobject]@{
                Name = "Eco"; PollSeconds = 300; IdleMaxSeconds = 900
                ActiveDelaySeconds = 15; KeepAlive = "30s"; NumThread = 3
                ProcessPriority = "BelowNormal"; MaxBurstJobs = 1; CooldownSeconds = 300
                DeferOnExternalGpuLoad = $true; GpuBusyThreshold = 10
                ResourceCheckSeconds = 2; MaxInferenceCalls = 4; MaxRevisions = 1
            }
        }
        '^(?i:performance|prestazioni)$' {
            return [pscustomobject]@{
                Name = "Prestazioni"; PollSeconds = 15; IdleMaxSeconds = 60
                ActiveDelaySeconds = 2; KeepAlive = "2m"; NumThread = 6
                ProcessPriority = "Normal"; MaxBurstJobs = 5; CooldownSeconds = 30
                DeferOnExternalGpuLoad = $false; GpuBusyThreshold = 0
                ResourceCheckSeconds = 2; MaxInferenceCalls = 4; MaxRevisions = 1
            }
        }
        '^(?i:balanced|bilanciato)$' {
            return [pscustomobject]@{
                Name = "Bilanciato"; PollSeconds = 60; IdleMaxSeconds = 300
                ActiveDelaySeconds = 5; KeepAlive = "30s"; NumThread = 4
                ProcessPriority = "BelowNormal"; MaxBurstJobs = 2; CooldownSeconds = 120
                DeferOnExternalGpuLoad = $true; GpuBusyThreshold = 15
                ResourceCheckSeconds = 2; MaxInferenceCalls = 4; MaxRevisions = 1
            }
        }
        default { throw "Profilo risorse non valido: $Name" }
    }
}

function Get-CalcioAffariConfiguredProfile {
    param($Config)
    $name = if ($Config -and $Config.PSObject.Properties["resource_profile"]) { [string]$Config.resource_profile } else { "Bilanciato" }
    return Get-CalcioAffariResourceProfile $name
}

function Set-CalcioAffariProcessProfile {
    param($Profile)
    try {
        $priority = [Enum]::Parse([Diagnostics.ProcessPriorityClass], [string]$Profile.ProcessPriority, $true)
        [Diagnostics.Process]::GetCurrentProcess().PriorityClass = $priority
    }
    catch { }
}

function Get-CalcioAffariExternalGpuLoad {
    param([int]$Threshold = 20)
    if ($Threshold -le 0) { return $null }

    try {
        $usageByPid = @{}
        $samples = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop)
        foreach ($sample in $samples) {
            $name = [string]$sample.Name
            if ($name -notmatch '(?i)^pid_(?<pid>\d+).*engtype_(?:3D|Compute|Graphics)') { continue }
            $processId = [int]$Matches.pid
            if ($processId -le 4 -or $processId -eq $PID) { continue }
            $value = [double]$sample.UtilizationPercentage
            if (-not $usageByPid.ContainsKey($processId)) { $usageByPid[$processId] = 0.0 }
            $usageByPid[$processId] += $value
        }

        foreach ($entry in @($usageByPid.GetEnumerator() | Sort-Object Value -Descending)) {
            if ([double]$entry.Value -lt $Threshold) { continue }
            $process = Get-Process -Id ([int]$entry.Key) -ErrorAction SilentlyContinue
            if (-not $process -or $process.ProcessName -in @(
                'dwm', 'csrss', 'explorer', 'ollama', 'ollama app',
                'ollama_llama_server', 'llama-server'
            )) { continue }
            return [pscustomobject]@{
                ProcessId = [int]$entry.Key
                ProcessName = [string]$process.ProcessName
                Utilization = [Math]::Round([double]$entry.Value, 1)
            }
        }
    }
    catch { }
    return $null
}

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

function ConvertTo-CalcioAffariFormBody {
    param([Parameter(Mandatory = $true)][hashtable]$Form)

    $parts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($key in @($Form.Keys | Sort-Object)) {
        $value = $Form[$key]
        if ($null -eq $value) { $value = '' }
        elseif ($value -isnot [string]) { $value = $value | ConvertTo-Json -Depth 100 -Compress }
        $parts.Add(('{0}={1}' -f
            [Net.WebUtility]::UrlEncode([string]$key),
            [Net.WebUtility]::UrlEncode([string]$value)))
    }
    return $parts -join '&'
}

function Get-CalcioAffariServerErrorCode {
    param($ErrorRecord)
    if ($ErrorRecord -and $ErrorRecord.Exception -and $ErrorRecord.Exception.Data.Contains("ServerCode")) {
        return [string]$ErrorRecord.Exception.Data["ServerCode"]
    }
    return ""
}

function ConvertTo-CalcioAffariCurlConfigValue {
    param([AllowEmptyString()][string]$Value)
    if ($Value -match "[`r`n]") { throw "Valore HTTP non valido." }
    return $Value.Replace('\', '\\').Replace('"', '\"')
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

    $curl = Get-Command 'curl.exe' -ErrorAction SilentlyContinue
    if (-not $curl) {
        throw (New-CalcioAffariException "CA_NETWORK" "cURL non è disponibile. Aggiorna Windows o reinstalla CalcioAffari Local Newsroom." 0)
    }
    $bodyForm = @{} + $Form
    $bodyForm.agent_token = $Token
    $body = ConvertTo-CalcioAffariFormBody -Form $bodyForm
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('silent')
    $lines.Add('show-error')
    $lines.Add('request = "POST"')
    $lines.Add(('url = "{0}"' -f (ConvertTo-CalcioAffariCurlConfigValue $Uri)))
    $lines.Add(('user-agent = "{0}"' -f (ConvertTo-CalcioAffariCurlConfigValue $UserAgent)))
    $lines.Add(('header = "X-CalcioAffari-Token: {0}"' -f (ConvertTo-CalcioAffariCurlConfigValue $Token)))
    $lines.Add('header = "Content-Type: application/x-www-form-urlencoded; charset=utf-8"')
    $lines.Add(('max-time = "{0}"' -f [Math]::Max(1, $TimeoutSeconds)))
    $lines.Add('compressed')
    # The whole form is percent-encoded before it enters cURL's config parser.
    # This avoids raw JSON quotes/backslashes while keeping both header and body
    # secrets out of process arguments and temporary files.
    $lines.Add(('data = "{0}"' -f $body))
    $lines.Add('write-out = "\nCA_CURL_META:%{http_code}:%{content_type}"')

    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $curl.Source
    $start.Arguments = '--config -'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    # Windows PowerShell 5.1 uses the .NET Framework ProcessStartInfo shape,
    # where the three encoding properties are not available. Its redirected
    # streams already use the process console encoding set by the app. PowerShell
    # 7/.NET receives explicit BOM-less UTF-8.
    if ($start.PSObject.Properties['StandardInputEncoding']) { $start.StandardInputEncoding = New-Object Text.UTF8Encoding($false) }
    if ($start.PSObject.Properties['StandardOutputEncoding']) { $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false) }
    if ($start.PSObject.Properties['StandardErrorEncoding']) { $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false) }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw "Impossibile avviare cURL." }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write(($lines -join "`n") + "`n")
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(([Math]::Max(1, $TimeoutSeconds) + 5) * 1000)) {
            try { $process.Kill() } catch { }
            throw (New-CalcioAffariException "CA_TIMEOUT" "Il collegamento a WordPress ha superato il tempo massimo." 0)
        }
        $output = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            if ($process.ExitCode -eq 28) {
                throw (New-CalcioAffariException "CA_TIMEOUT" "Il collegamento a WordPress ha superato il tempo massimo." 0)
            }
            throw (New-CalcioAffariException "CA_NETWORK" ("WordPress non è raggiungibile: cURL {0}. {1}" -f $process.ExitCode, $stderr.Trim()) 0)
        }
        if ($output -notmatch '(?s)^(.*)\r?\nCA_CURL_META:(\d{3}):(.*)$') {
            throw (New-CalcioAffariException "CA_INVALID_RESPONSE" "cURL non ha restituito i metadati HTTP attesi." 0)
        }
        return ConvertFrom-CalcioAffariResponse -StatusCode ([int]$Matches[2]) -ContentType ([string]$Matches[3]).Trim() -Body ([string]$Matches[1]) -ExpectedProperties $ExpectedProperties
    }
    finally {
        $process.Dispose()
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

function Set-CalcioAffariScheduledTaskEnabled {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Enabled
    )

    $task = Get-CalcioAffariScheduledTask -Name $Name
    if (-not $task) { return $false }
    try { $task.Enabled = $Enabled; return $true }
    catch { return $false }
}

function Stop-CalcioAffariRuntimeProcesses {
    param([Parameter(Mandatory = $true)][string]$InstallDir)

    $root = [IO.Path]::GetFullPath($InstallDir)
    foreach ($process in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        if ($_.Name -notin @("powershell.exe", "pwsh.exe")) { return $false }
        $commandLine = [string]$_.CommandLine
        return $commandLine -like ("*" + $root + "*") -and $commandLine -match '(?i)(agent(?:-[0-9.]+)?|heartbeat)\.ps1'
    })) {
        Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction SilentlyContinue
    }
}

function Stop-CalcioAffariModel {
    param([AllowNull()][string]$Model)
    if ([string]::IsNullOrWhiteSpace($Model)) { return }

    $ollama = Get-Command "ollama" -ErrorAction SilentlyContinue
    if (-not $ollama) {
        foreach ($candidate in @(
            (Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"),
            (Join-Path $env:LOCALAPPDATA "Ollama\ollama.exe"),
            (Join-Path $env:ProgramFiles "Ollama\ollama.exe")
        )) {
            if (Test-Path $candidate) { $ollama = [pscustomobject]@{ Source = $candidate }; break }
        }
    }
    if (-not $ollama) { return }
    try {
        $process = Start-Process -FilePath $ollama.Source -ArgumentList @("stop", $Model) -WindowStyle Hidden -Wait -PassThru
        $process.Dispose()
    }
    catch { }
}

function Get-CalcioAffariDependencyState {
    param([Parameter(Mandatory = $true)][string]$InstallDir)

    $path = Join-Path $InstallDir "dependencies.json"
    if (Test-Path -LiteralPath $path) {
        try { return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { }
    }
    return [pscustomobject]@{
        ollama_installed_by_calcioaffari = $false
        model_installed_by_calcioaffari = $false
        model = "qwen3:14b"
    }
}

function Set-CalcioAffariDependencyOwnership {
    param(
        [Parameter(Mandatory = $true)][string]$InstallDir,
        [Nullable[bool]]$OllamaInstalledByCalcioAffari,
        [Nullable[bool]]$ModelInstalledByCalcioAffari,
        [AllowNull()][string]$Model
    )

    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    $state = Get-CalcioAffariDependencyState -InstallDir $InstallDir
    if ($null -ne $OllamaInstalledByCalcioAffari) {
        $state.ollama_installed_by_calcioaffari = [bool]$OllamaInstalledByCalcioAffari
    }
    if ($null -ne $ModelInstalledByCalcioAffari) {
        $state.model_installed_by_calcioaffari = [bool]$ModelInstalledByCalcioAffari
    }
    if (-not [string]::IsNullOrWhiteSpace($Model)) { $state.model = $Model }
    $path = Join-Path $InstallDir "dependencies.json"
    $temporary = "$path.tmp"
    [IO.File]::WriteAllText($temporary, ($state | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $path -Force
}

function Stop-CalcioAffariOwnedOllamaProcesses {
    param([Parameter(Mandatory = $true)][string]$InstallDir)

    $state = Get-CalcioAffariDependencyState -InstallDir $InstallDir
    if (-not [bool]$state.ollama_installed_by_calcioaffari) { return }
    foreach ($process in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $name = [string]$_.Name
        $path = [string]$_.ExecutablePath
        $name -match '^(?i:ollama(?: app)?|ollama_llama_server|llama-server)\.exe$' -and
            $path -match '(?i)\\Ollama\\'
    })) {
        Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction SilentlyContinue
    }
}

function Disable-CalcioAffariOwnedOllamaAutostart {
    param([Parameter(Mandatory = $true)][string]$InstallDir)

    $state = Get-CalcioAffariDependencyState -InstallDir $InstallDir
    if (-not [bool]$state.ollama_installed_by_calcioaffari) { return }

    $startup = [Environment]::GetFolderPath('Startup')
    foreach ($name in @('Ollama.lnk', 'Ollama App.lnk')) {
        $path = Join-Path $startup $name
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    }
    $runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if (Test-Path $runPath) {
        $values = Get-ItemProperty -Path $runPath -ErrorAction SilentlyContinue
        foreach ($name in @('Ollama', 'Ollama App')) {
            $property = $values.PSObject.Properties[$name]
            if ($property -and [string]$property.Value -match '(?i)\\Ollama\\') {
                Remove-ItemProperty -Path $runPath -Name $name -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Suspend-CalcioAffariAutomation {
    param(
        [Parameter(Mandatory = $true)][string]$InstallDir,
        [Parameter(Mandatory = $true)][string]$TaskName,
        [Parameter(Mandatory = $true)][string]$WatchdogTaskName,
        [AllowNull()][string]$Model
    )

    $pausePath = Join-Path $InstallDir "agent-paused.txt"
    [IO.File]::WriteAllText($pausePath, (Get-Date).ToString("o"), (New-Object Text.UTF8Encoding($false)))
    Stop-CalcioAffariScheduledTask -Name $TaskName | Out-Null
    Stop-CalcioAffariScheduledTask -Name $WatchdogTaskName | Out-Null
    Set-CalcioAffariScheduledTaskEnabled -Name $TaskName -Enabled $false | Out-Null
    Set-CalcioAffariScheduledTaskEnabled -Name $WatchdogTaskName -Enabled $false | Out-Null
    Stop-CalcioAffariRuntimeProcesses -InstallDir $InstallDir
    Stop-CalcioAffariModel -Model $Model
}

function Resume-CalcioAffariAutomation {
    param(
        [Parameter(Mandatory = $true)][string]$InstallDir,
        [Parameter(Mandatory = $true)][string]$TaskName,
        [Parameter(Mandatory = $true)][string]$WatchdogTaskName
    )

    Remove-Item (Join-Path $InstallDir "agent-paused.txt") -Force -ErrorAction SilentlyContinue
    Set-CalcioAffariScheduledTaskEnabled -Name $TaskName -Enabled $true | Out-Null
    Set-CalcioAffariScheduledTaskEnabled -Name $WatchdogTaskName -Enabled $true | Out-Null
    Start-CalcioAffariScheduledTask -Name $TaskName
}
