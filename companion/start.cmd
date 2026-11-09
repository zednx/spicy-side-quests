@echo off
rem Double-click to start syncing. Needs Node.js 22.18 or newer: https://nodejs.org
cd /d "%~dp0"
node src\index.ts %*
pause
