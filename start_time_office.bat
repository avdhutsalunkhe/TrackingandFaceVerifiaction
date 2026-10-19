@echo off
title FieldStaff Time Office Console Launcher
cls
echo ===================================================================
echo   FieldStaff AI Biometric Attendance System - Time Office Console
echo ===================================================================
echo.
echo   [1] Run as Website (Browser - Port 5175)
echo   [2] Run as Windows Desktop Application (PC Electron App)
echo   [3] Build Production Windows Installer (.exe)
echo   [4] Build Production Website Bundle
echo   [5] Exit
echo.
echo ===================================================================
set /p choice="Enter choice [1-5] (Default is 1): "

if "%choice%"=="" set choice=1
if "%choice%"=="1" goto RUN_WEB
if "%choice%"=="2" goto RUN_PC
if "%choice%"=="3" goto BUILD_PC
if "%choice%"=="4" goto BUILD_WEB
if "%choice%"=="5" exit /b 0

echo Invalid selection. Starting Web Console...
goto RUN_WEB

:RUN_WEB
cls
call "%~dp0start_time_office_web.bat"
goto END

:RUN_PC
cls
call "%~dp0start_time_office_pc.bat"
goto END

:BUILD_PC
cls
echo [*] Building Production Windows Desktop Application (.exe)...
cd /d "%~dp0time_office_desktop"
npm run build:win
pause
goto END

:BUILD_WEB
cls
echo [*] Building Production Website Bundle...
cd /d "%~dp0time_office_desktop"
npm run build:web
pause
goto END

:END
