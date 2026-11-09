@echo off
rem Double-click to (re)configure the markdown file, WoW folder and account, then start syncing.
rem Uses the PowerShell built into Windows; nothing to install.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "powershell\SpicySideQuests.ps1" -Setup %*
pause
