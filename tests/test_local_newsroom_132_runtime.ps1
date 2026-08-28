$ErrorActionPreference = "Stop"

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$agentPath = Join-Path $repoRoot "companion\calcioaffari-local-agent\agent.ps1"
$stubPath = Join-Path $PSScriptRoot "ollama_stub.py"
$testRoot = Join-Path $env:RUNNER_TEMP "CalcioAffari-132-runtime"
$configPath = Join-Path $testRoot "agent.json"
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

$stub = Start-Process -FilePath "python" -ArgumentList @($stubPath) -PassThru -WindowStyle Hidden
try {
    $ready = $false
    foreach ($attempt in 1..20) {
        try {
            Invoke-RestMethod -Uri "http://127.0.0.1:18999/api/tags" -TimeoutSec 1 | Out-Null
            $ready = $true
            break
        }
        catch { Start-Sleep -Milliseconds 250 }
    }
    if (-not $ready) { throw "Ollama stub did not start." }

    $env:CALCIOAFFARI_AGENT_TEST_MODE = "1"
    . $agentPath -ConfigPath $configPath
    Remove-Item Env:CALCIOAFFARI_AGENT_TEST_MODE -ErrorAction SilentlyContinue

    $script:ModelStopCalled = $false
    function Get-CalcioAffariExternalGpuLoad {
        return [pscustomobject]@{ ProcessName = "QualificationGame"; ProcessId = 4242; Utilization = 81.5 }
    }
    function Stop-CalcioAffariModel {
        param([string]$Model)
        $script:ModelStopCalled = ($Model -eq "qwen3:14b")
    }

    $config = [pscustomobject]@{
        ollama_url = "http://127.0.0.1:18999"
        model = "qwen3:14b"
        resource_profile = "Eco"
    }
    $job = [pscustomobject]@{
        id = 132
        generation = [pscustomobject]@{ num_ctx = 2048; num_predict = 128; temperature = 0.1 }
        schema = [pscustomobject]@{ type = "object" }
        system_prompt = "Return JSON."
    }

    $started = Get-Date
    $caught = $null
    try {
        Invoke-OllamaStructuredRequest -Config $config -Job $job -Prompt "qualification" | Out-Null
    }
    catch { $caught = $_ }
    $elapsed = ((Get-Date) - $started).TotalSeconds

    if (-not $caught) { throw "Active inference was not preempted." }
    if ((Get-CalcioAffariErrorCode $caught) -ne "CA_RESOURCE_PREEMPTED") {
        throw "Unexpected preemption error: $($caught.Exception.Message)"
    }
    if (-not $script:ModelStopCalled) { throw "Model unload was not requested after preemption." }
    if ($script:ModelTouched) { throw "Model remained marked as resident after preemption." }
    if ($elapsed -gt 8) { throw "Preemption took too long: $elapsed seconds." }
}
finally {
    Remove-Item Env:CALCIOAFFARI_AGENT_TEST_MODE -ErrorAction SilentlyContinue
    if ($stub -and -not $stub.HasExited) { Stop-Process -Id $stub.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
