@echo off
REM Flash the DC35 CNet badge firmware in the folder above over USB.
REM Double-click it, or run it from cmd.exe or PowerShell with arguments:
REM   flash\flash.cmd -Port COM5 -Full -Erase -Baud 115200 -VerifyOnly -DryRun
REM Bypass applies to this one run only; it changes no system setting.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0flash.ps1" %*
set "rc=%errorlevel%"
if not "%rc%"=="0" (
  echo.
  echo [flash] Stopped - nothing was written to the badge.
  echo [flash] Valid arguments:
  echo [flash]   -Port COM5       which badge ^(found automatically if only one^)
  echo [flash]   -Baud 115200     slower, for a flaky cable
  echo [flash]   -Full            also write the bootloader and partition table
  echo [flash]   -Erase           wipe the badge completely first
  echo [flash]   -VerifyOnly      check the files and stop
  echo [flash]   -DryRun          print the esptool command, write nothing
)
REM Keep the window open when started by double-click.
setlocal enabledelayedexpansion
echo !cmdcmdline! | "%SystemRoot%\System32\find.exe" /i "%~nx0" >nul && pause
exit /b %rc%
