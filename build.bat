@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build\Build-Exe.ps1"
echo.
pause
