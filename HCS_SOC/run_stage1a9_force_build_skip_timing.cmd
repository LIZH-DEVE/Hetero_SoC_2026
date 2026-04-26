@echo off
setlocal

if "%~1"=="" (
  echo usage: %~nx0 LOG_DIR
  exit /b 2
)

set "LOG_DIR=%~1"
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "REPO_DIR=%%~fI"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
echo started > "%LOG_DIR%\status.txt"

set "SHADOW_SKIP_TIMING_REPORTS=1"
cd /d "%REPO_DIR%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%build_ax7020_udp_gateway_shadow_mirror_boot.ps1" -ForceExport
set "RC=%ERRORLEVEL%"
echo exit=%RC% > "%LOG_DIR%\status.txt"
exit /b %RC%
