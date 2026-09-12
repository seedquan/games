@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-Windows-Acceptance.ps1"
set "ABYSS_ACCEPT_EXIT=%ERRORLEVEL%"
pause
exit /b %ABYSS_ACCEPT_EXIT%
