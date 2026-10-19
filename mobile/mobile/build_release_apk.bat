@echo off
setlocal
echo =================================================================
echo   FieldStaff AI Mobile App — Release Build ^& Size Optimizer
echo =================================================================

REM 1. Configure Java Home from Android Studio
if exist "C:\Program Files\Android\Android Studio\jbr\bin\java.exe" (
    set "JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
    set "PATH=C:\Program Files\Android\Android Studio\jbr\bin;%PATH%"
    echo [INFO] Detected Java from Android Studio: %JAVA_HOME%
)

REM 2. Fetch Dependencies
echo [INFO] Resolving Flutter dependencies...
call flutter pub get

REM 3. Compile Optimized Split-ABI Release APKs
echo [INFO] Compiling Release APKs with R8 minification, code shrinking, and symbol stripping...
call flutter build apk --release --split-per-abi --obfuscate --split-debug-info=./build/app/outputs/symbols

REM 4. Copy to release_apks Directories
if not exist "..\release_apks" mkdir "..\release_apks"
if not exist "..\..\release_apks" mkdir "..\..\release_apks"
copy /Y "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" "..\release_apks\fieldstaff-attendance-arm64-v8a-release.apk" >nul
copy /Y "build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk" "..\release_apks\fieldstaff-attendance-armeabi-v7a-release.apk" >nul
copy /Y "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" "..\..\release_apks\fieldstaff-attendance-arm64-v8a-release.apk" >nul
copy /Y "build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk" "..\..\release_apks\fieldstaff-attendance-armeabi-v7a-release.apk" >nul

echo.
echo =================================================================
echo   Build Successful! Optimized APKs:
echo =================================================================
echo   1. ARM64 (Modern Android devices): 
echo      ..\release_apks\fieldstaff-attendance-arm64-v8a-release.apk (~18.3 MB)
echo.
echo   2. ARMv7 (Legacy 32-bit Android devices):
echo      ..\release_apks\fieldstaff-attendance-armeabi-v7a-release.apk (~15.7 MB)
echo =================================================================
echo.
pause
