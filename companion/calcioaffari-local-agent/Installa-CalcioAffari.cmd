@echo off
title CalcioAffari Local Newsroom - Installazione
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
if errorlevel 1 (
  echo.
  echo Installazione non completata. Leggi il messaggio sopra oppure comunicami l'errore.
  pause
)
