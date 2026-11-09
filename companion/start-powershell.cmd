@echo off
rem Double-click to start syncing using the PowerShell built into Windows (no install needed).
rem -ExecutionPolicy Bypass only applies to this one script; it does not change your system settings.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "powershell\WoWTodoSync.ps1" %*
pause
