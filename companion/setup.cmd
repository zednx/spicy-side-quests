@echo off
rem Node.js edition: (re)configure the markdown file, WoW folder and account, then start syncing.
cd /d "%~dp0"
node src\index.ts --setup %*
pause
