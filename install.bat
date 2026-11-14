@echo off
setlocal EnableExtensions
title DeepSeek Harness: dsh-arabic + Vazirmatn

rem Runs install.ps1 from this folder when it is there, otherwise downloads it.
rem -ExecutionPolicy Bypass applies to this process only: no machine policy is
rem changed and .ps1 files are never associated with anything.

set "RAW=https://raw.githubusercontent.com/devopshelper/dsh-arabic-vazirmatn/main/install.ps1"
set "HERE=%~dp0install.ps1"
set "CACHE=%TEMP%\dsh-arabic-vazirmatn\install.ps1"
set "RC=0"

where powershell.exe >nul 2>nul
if errorlevel 1 (
    echo.
    echo ERROR: Windows PowerShell was not found on this system.
    set "RC=1"
    goto :done
)

if exist "%HERE%" (
    set "PS1=%HERE%"
) else (
    echo Downloading the installer...
    if not exist "%TEMP%\dsh-arabic-vazirmatn" mkdir "%TEMP%\dsh-arabic-vazirmatn" >nul 2>nul
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; try { Invoke-WebRequest -Uri '%RAW%' -OutFile '%CACHE%' -UseBasicParsing } catch { exit 1 }"
    if errorlevel 1 (
        echo ERROR: could not download install.ps1 from %RAW%
        set "RC=1"
        goto :done
    )
    set "PS1=%CACHE%"
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"

:done
echo.
if not "%RC%"=="0" echo The installer exited with code %RC%.
if defined DSH_NO_PAUSE exit /b %RC%
rem Keep the window open only for the double-click case (no arguments).
if not "%~1"=="" exit /b %RC%
echo %cmdcmdline% | find /i "%~nx0" >nul
if not errorlevel 1 pause
exit /b %RC%
