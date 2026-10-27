@echo off
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Yama.ps1" -Islem Kur
if errorlevel 1 pause
