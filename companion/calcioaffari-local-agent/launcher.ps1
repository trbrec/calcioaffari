[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$InstallDir = Join-Path $env:LOCALAPPDATA "CalcioAffari"
$configured = (Test-Path (Join-Path $InstallDir "agent.json")) -and (Test-Path (Join-Path $InstallDir "agent-token.txt"))
$target = Join-Path $InstallDir $(if ($configured) { "dashboard.ps1" } else { "setup-gui.ps1" })
if (-not (Test-Path $target)) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("Installazione incompleta. Riesegui il setup di CalcioAffari Local Newsroom.", "CalcioAffari", "OK", "Error") | Out-Null
    exit 1
}
Start-Process -FilePath (Join-Path $PSHOME "powershell.exe") -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$target`""
