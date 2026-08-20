@echo off
set "CA_APP=%LOCALAPPDATA%\CalcioAffari\launcher.ps1"
if not exist "%CA_APP%" (
  echo CalcioAffari Local Newsroom non e ancora installato.
  echo Avvia prima Installa-CalcioAffari.cmd.
  pause
  exit /b 1
)
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%CA_APP%"
