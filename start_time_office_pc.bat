@echo off
title FieldStaff Time Office - Windows Desktop App
echo ===================================================================
echo   FieldStaff AI Biometric Attendance System - Time Office PC App
echo ===================================================================
echo.

cd /d "%~dp0time_office_desktop"

if exist "node_modules\electron\dist\electron.exe" (
    echo [*] Launching Time Office Desktop Application...
    start "" "node_modules\electron\dist\electron.exe" .
    echo [*] Time Office Desktop App is now running!
    timeout /t 2 >nul
    exit /b 0
)

echo [*] Starting Time Office in development mode...
npm run dev:pc
pause
