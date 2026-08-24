[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$OutputPath)

$ErrorActionPreference = "Stop"
$InstallDir = Join-Path $env:LOCALAPPDATA "CalcioAffari"
$ConfigPath = Join-Path $InstallDir "agent.json"
$SecretPath = Join-Path $InstallDir "agent-token.txt"
$ConnectionPausePath = Join-Path $InstallDir "connection-paused.txt"
$UserPausePath = Join-Path $InstallDir "agent-paused.txt"
$TaskName = "CalcioAffari Local Agent"
$AgentVersion = "1.2.4"
. (Join-Path $PSScriptRoot "common.ps1")

function Save-Result([hashtable]$Result) {
    $Result["updated_at"] = (Get-Date).ToString("o")
    $temporary = "$OutputPath.tmp"
    [IO.File]::WriteAllText($temporary, ($Result | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
    Move-Item $temporary $OutputPath -Force
}

$result = @{
    success = $false; configured = $false; task_state = "Assente"; ollama_online = $false; model_ready = $false
    site_online = $false; site_state = "Non verificato"; details = @(); health = $null; resource_profile = $null
}
try {
    if (-not (Test-Path $ConfigPath) -or -not (Test-Path $SecretPath)) { throw "Configurazione non trovata." }
    $result.configured = $true
    $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $profile = Get-CalcioAffariConfiguredProfile $config
    $result.resource_profile = @{
        name = $profile.Name; poll_seconds = $profile.PollSeconds; active_delay_seconds = $profile.ActiveDelaySeconds
        keep_alive = $profile.KeepAlive; num_thread = $profile.NumThread; process_priority = $profile.ProcessPriority
    }
    $result.task_state = if (Test-Path $UserPausePath) { "In pausa" } elseif (Test-CalcioAffariScheduledTask -Name $TaskName) { "Attivo" } else { "Assente" }

    try {
        $tags = Invoke-RestMethod -Uri ($config.ollama_url.TrimEnd('/') + "/api/tags") -Method Get -TimeoutSec 4
        $result.ollama_online = $true
        $models = @($tags.models | ForEach-Object { [string]$_.name })
        $result.model_ready = $models -contains ([string]$config.model) -or $models -contains (([string]$config.model) + ":latest")
    }
    catch { $result.details += "Ollama non raggiungibile." }

    if (Test-Path $ConnectionPausePath) {
        $result.site_state = "Collegamento sospeso"
        $result.details += [IO.File]::ReadAllText($ConnectionPausePath).Trim()
    }
    else {
        $encrypted = [IO.File]::ReadAllText($SecretPath).Trim()
        $secure = ConvertTo-SecureString -String $encrypted
        $credential = [System.Management.Automation.PSCredential]::new("calcioaffari", $secure)
        $token = $credential.GetNetworkCredential().Password
        try {
            $uri = $config.site_url.TrimEnd('/') + "/wp-admin/admin-ajax.php?action=ca_news_health"
            $health = Invoke-CalcioAffariJsonRequest -Uri $uri -UserAgent "CalcioAffari-Diagnostics/$AgentVersion" -Token $token -TimeoutSeconds 8 -ExpectedProperties @("version", "publication_mode", "sources_enabled", "jobs")
            $result.site_online = $true
            $result.site_state = "WordPress collegato"
            $result.health = $health
        }
        catch {
            $result.site_state = Get-CalcioAffariFriendlyError $_
            $result.details += $result.site_state
        }
    }
    $result.success = $true
}
catch { $result.details += (Protect-CalcioAffariSecretText $_.Exception.Message) }
finally { Save-Result $result }
