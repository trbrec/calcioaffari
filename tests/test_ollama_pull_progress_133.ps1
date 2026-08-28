$ErrorActionPreference = "Stop"

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$installPath = Join-Path $repoRoot "companion\calcioaffari-local-agent\install.ps1"
$testRoot = Join-Path $env:RUNNER_TEMP "CalcioAffari-133-progress"
$progressPath = Join-Path $testRoot "ollama-progress.out"
$statusPath = Join-Path $testRoot "status.json"
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

$writer = $null
$streamWriter = $null
try {
    $env:CALCIOAFFARI_INSTALL_TEST_MODE = "1"
    . $installPath -StatusPath $statusPath
    Remove-Item Env:CALCIOAFFARI_INSTALL_TEST_MODE -ErrorAction SilentlyContinue

    $writer = [IO.File]::Open($progressPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    $streamWriter = [IO.StreamWriter]::new($writer, [Text.Encoding]::UTF8, 4096, $true)
    $streamWriter.Write("pulling manifest`r`ndownloading layer 37%`r`n")
    $streamWriter.Flush()
    $writer.Flush()

    $readAllTextFailed = $false
    try { [IO.File]::ReadAllText($progressPath) | Out-Null }
    catch [IO.IOException] { $readAllTextFailed = $true }
    if (-not $readAllTextFailed) {
        throw "The qualification did not reproduce the ReadAllText sharing violation."
    }

    $snapshot = Read-CalcioAffariSharedText $progressPath
    if ($snapshot -notmatch "37%") {
        throw "The shared reader did not recover progress while the writer remained open."
    }

    $streamWriter.Write("downloading layer 82%`r`n")
    $streamWriter.Flush()
    $writer.Flush()
    $snapshot = Read-CalcioAffariSharedText $progressPath
    if ($snapshot -notmatch "82%") {
        throw "The shared reader did not observe subsequent progress."
    }
}
finally {
    Remove-Item Env:CALCIOAFFARI_INSTALL_TEST_MODE -ErrorAction SilentlyContinue
    if ($streamWriter) { $streamWriter.Dispose() }
    if ($writer) { $writer.Dispose() }
    Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
