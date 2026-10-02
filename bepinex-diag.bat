@echo off
REM ==========================================================================
REM  BepInEx IL2CPP diagnostics - launcher
REM  Runs bepinex-diag.ps1 from this folder. No arguments needed.
REM  Put this .bat and bepinex-diag.ps1 in the SAME folder, then double-click.
REM ==========================================================================
setlocal
chcp 65001 >nul
title BepInEx diagnostics

set "SCRIPT=%~dp0bepinex-diag.ps1"

if not exist "%SCRIPT%" (
    echo [ERROR] bepinex-diag.ps1 not found next to this .bat file.
    echo         Put both files in the same folder and try again.
    goto :end
)

echo Working folder: %CD%
echo Script        : %SCRIPT%
echo.

where pwsh >nul 2>nul
if %ERRORLEVEL%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
    goto :end
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"

:end
echo.
echo ---------------------------------------------------------------
echo Copy the text above and paste it where you asked for help.
echo ---------------------------------------------------------------
pause
endlocal
