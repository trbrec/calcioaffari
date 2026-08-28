@echo off
cd /d "%~dp0"
start "" wscript.exe //B //NoLogo "%~dp0hidden-launcher.vbs" "%~dp0setup-gui.ps1"
