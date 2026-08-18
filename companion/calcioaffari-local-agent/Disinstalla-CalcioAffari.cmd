@echo off
set "CA_UNINSTALL=%LOCALAPPDATA%\CalcioAffari\uninstall.ps1"
if not exist "%CA_UNINSTALL%" set "CA_UNINSTALL=%~dp0uninstall.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CA_UNINSTALL%"
pause
