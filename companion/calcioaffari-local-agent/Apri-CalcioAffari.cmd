@echo off
set "CA_APP=%LOCALAPPDATA%\CalcioAffari\launcher.ps1"
set "CA_HIDDEN=%LOCALAPPDATA%\CalcioAffari\hidden-launcher.vbs"
if not exist "%CA_APP%" (
  echo CalcioAffari Local Newsroom non e ancora installato.
  echo Avvia prima Installa-CalcioAffari.cmd.
  pause
  exit /b 1
)
if not exist "%CA_HIDDEN%" (
  echo Launcher invisibile mancante. Reinstalla CalcioAffari Local Newsroom.
  pause
  exit /b 1
)
start "" wscript.exe //B //NoLogo "%CA_HIDDEN%" "%CA_APP%"
