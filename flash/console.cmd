@echo off
REM Open the DC35 CNet badge's serial console. Double-click it, or run it from
REM cmd.exe or PowerShell with arguments:
REM   flash\console.cmd -Port COM5 -Echo -Command "HELP"
REM Bypass applies to this one run only; it changes no system setting.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0console.ps1" %*
set "rc=%errorlevel%"
REM Keep the window open after an error when started by double-click.
if not "%rc%"=="0" (
  setlocal enabledelayedexpansion
  echo !cmdcmdline! | "%SystemRoot%\System32\find.exe" /i "%~nx0" >nul && pause
)
exit /b %rc%
