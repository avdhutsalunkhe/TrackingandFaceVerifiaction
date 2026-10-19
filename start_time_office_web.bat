@echo off
title FieldStaff Time Office - Web Application Console
echo ===================================================================
echo   FieldStaff AI Biometric Attendance System - Time Office Web App
echo ===================================================================
echo.
echo [*] Starting Time Office Web Application on port 5175...
echo [*] Local URL: http://localhost:5175 (Browser opening automatically)
echo [*] LAN Network: Accessible from any browser on your network at port 5175
echo.

cd /d "%~dp0time_office_desktop"

npm run dev:web

pause
