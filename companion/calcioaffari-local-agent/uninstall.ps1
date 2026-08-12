$ErrorActionPreference = "SilentlyContinue"
& schtasks.exe /End /TN "CalcioAffari Local Agent" | Out-Null
& schtasks.exe /Delete /TN "CalcioAffari Local Agent" /F | Out-Null
$installDir = Join-Path $env:LOCALAPPDATA "CalcioAffari"
Write-Host "Attività pianificata rimossa. Per eliminare anche configurazione, log e credenziale cifrata, rimuovi manualmente: $installDir"

