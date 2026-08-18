[CmdletBinding()]
param([switch]$Confirm)

$ErrorActionPreference = "SilentlyContinue"
$InstallDir = Join-Path $env:LOCALAPPDATA "CalcioAffari"
$TaskName = "CalcioAffari Local Agent"
$WatchdogTaskName = "CalcioAffari Local Agent Watchdog"

if (-not $Confirm) {
    Write-Host "Questa operazione rimuove CalcioAffari Local Newsroom, configurazione, log e credenziale cifrata." -ForegroundColor Yellow
    Write-Host "Ollama e il modello locale non verranno rimossi e potranno essere riutilizzati."
    $answer = Read-Host "Scrivi DISINSTALLA per confermare"
    if ($answer -cne "DISINSTALLA") {
        Write-Host "Operazione annullata."
        exit 0
    }
}

& schtasks.exe /End /TN $TaskName 2>$null | Out-Null
& schtasks.exe /End /TN $WatchdogTaskName 2>$null | Out-Null
& schtasks.exe /Delete /TN $TaskName /F 2>$null | Out-Null
& schtasks.exe /Delete /TN $WatchdogTaskName /F 2>$null | Out-Null

$startMenu = Join-Path ([Environment]::GetFolderPath("Programs")) "CalcioAffari"
$desktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "CalcioAffari Local Newsroom.lnk"
Remove-Item $desktopShortcut -Force -ErrorAction SilentlyContinue
Remove-Item $startMenu -Recurse -Force -ErrorAction SilentlyContinue

if (Test-Path $InstallDir) {
    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "CalcioAffari Local Newsroom è stato rimosso." -ForegroundColor Green
Write-Host "Ollama e Qwen3 sono stati conservati per evitare di riscaricare circa 9,3 GB."

