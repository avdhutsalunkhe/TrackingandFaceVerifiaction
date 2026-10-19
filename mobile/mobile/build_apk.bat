@echo off
setlocal
set "JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
set "PATH=C:\Program Files\Android\Android Studio\jbr\bin;%PATH%"

echo ========================================================
echo   FieldStaff Attendance - Release APK Build Pipeline
echo ========================================================
echo JAVA_HOME: %JAVA_HOME%

cd /d "%~dp0"
echo Working Directory: %CD%

echo [*] Starting Flutter build apk --release...
call flutter build apk --release
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Build failed with exit code %ERRORLEVEL%
    exit /b %ERRORLEVEL%
)

echo [*] Build completed successfully. Copying APK to release folders...
if not exist "..\..\release_apks" mkdir "..\..\release_apks"
copy /y "build\app\outputs\flutter-apk\app-release.apk" "..\..\release_apks\fieldstaff-attendance-universal-release.apk"

if not exist "..\..\backend\release_apks" mkdir "..\..\backend\release_apks"
copy /y "build\app\outputs\flutter-apk\app-release.apk" "..\..\backend\release_apks\fieldstaff-attendance-universal-release.apk"

echo ========================================================
echo   [SUCCESS] Release APK built and deployed!
echo   Location: release_apks\fieldstaff-attendance-universal-release.apk
echo ========================================================
exit /b 0
