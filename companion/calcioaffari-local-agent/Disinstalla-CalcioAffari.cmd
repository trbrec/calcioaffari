@echo off
set "CA_UNINSTALL=%LOCALAPPDATA%\CalcioAffari\uninstall.ps1"
set "CA_HIDDEN=%LOCALAPPDATA%\CalcioAffari\hidden-launcher.vbs"
if not exist "%CA_UNINSTALL%" (
  set "CA_UNINSTALL=%~dp0uninstall.ps1"
  set "CA_HIDDEN=%~dp0hidden-launcher.vbs"
)
start "" wscript.exe //B //NoLogo "%CA_HIDDEN%" "%CA_UNINSTALL%"
