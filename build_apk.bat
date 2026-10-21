@echo off
REM 荒野手册 Android APK 打包脚本 (Windows)
REM 使用 Gradle 构建（正确处理 Qt manifest merging）
REM 用法: build_apk.bat [debug^|release] [abi]

setlocal enabledelayedexpansion

REM ============================================================================
REM 配置
REM ============================================================================
set PROJECT_ROOT=%~dp0
set APP_DIR=%PROJECT_ROOT%
set ANDROID_NDK=%ANDROID_NDK_HOME%
set ANDROID_SDK=%ANDROID_HOME%
set ANDROID_PLATFORM=android-34
set BUILD_TYPE=%1
if "%BUILD_TYPE%"=="" set BUILD_TYPE=release
set TARGET_ABI=%2
if "%TARGET_ABI%"=="" set TARGET_ABI=arm64-v8a
set QT_PATH=%QT_PATH%
if "%QT_PATH%"=="" set QT_PATH=C:\Qt\6.7.2
set KEYSTORE_PATH=%KEYSTORE_PATH%
if "%KEYSTORE_PATH%"=="" set KEYSTORE_PATH=%APP_DIR%keystore\outdoor.keystore

REM ============================================================================
REM 检查
REM ============================================================================
if not exist "%ANDROID_NDK%" (
    echo [ERROR] Android NDK not found: %ANDROID_NDK%
    echo Set ANDROID_NDK_HOME environment variable
    exit /b 1
)

if not exist "%QT_PATH%" (
    echo [ERROR] Qt not found: %QT_PATH%
    echo Set QT_PATH environment variable
    exit /b 1
)

set QT_QPA=
if "%TARGET_ABI%"=="arm64-v8a" set QT_QPA=%QT_PATH%\android_arm64_v8a
if "%TARGET_ABI%"=="x86_64" set QT_QPA=%QT_PATH%\android_x86_64
rem 2026-10-21: armeabi-v7a 去掉 —— 构建镜像没装 android_armv7 这个 Qt kit, 只出
rem   arm64-v8a / x86_64. 与 build_apk.sh 同一处判断保持一致, 别让人以为还能打 v7a.
if "%TARGET_ABI%"=="armeabi-v7a" (
    echo [ERROR] armeabi-v7a not supported: no android_armv7 Qt kit in the build image
    exit /b 1
)

if not exist "%QT_QPA%" (
    echo [ERROR] Qt Android package not found: %QT_QPA%
    exit /b 1
)

echo [INFO] Environment OK
echo   Qt: %QT_PATH%
echo   NDK: %ANDROID_NDK%
echo   SDK: %ANDROID_SDK%
echo   ABI: %TARGET_ABI%
echo   Build: %BUILD_TYPE%

REM ============================================================================
REM 创建 keystore
REM ============================================================================
if not exist "%KEYSTORE_PATH%" (
    echo [INFO] Creating keystore: %KEYSTORE_PATH%
    if not exist "%APP_DIR%keystore" mkdir "%APP_DIR%keystore"
    keytool -genkey -v -keystore "%KEYSTORE_PATH%" ^
        -alias outdoor ^
        -keyalg RSA -keysize 2048 -validity 25000 ^
        -storepass outdoor123 -keypass outdoor123 ^
        -dname "CN=OutdoorSurvival, OU=Outdoor, O=Outdoor, L=Beijing, ST=Beijing, C=CN"
)

REM ============================================================================
REM CMake 配置
REM ============================================================================
echo [INFO] Running CMake and building...
set BUILD_DIR=%APP_DIR%build\%BUILD_TYPE%_%TARGET_ABI%
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

set ANDROID_NDK_ROOT=%ANDROID_NDK%
set ANDROID_SDK_ROOT=%ANDROID_SDK%

cd /d "%BUILD_DIR%"

cmake "%APP_DIR%" ^
    -G "Ninja" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_TOOLCHAIN_FILE=%ANDROID_NDK%\build\cmake\android.toolchain.cmake ^
    -DANDROID_ABI=%TARGET_ABI% ^
    -DANDROID_PLATFORM=android-34 ^
    -DCMAKE_PREFIX_PATH=%QT_QPA%

if errorlevel 1 (
    echo [ERROR] CMake configuration failed
    exit /b 1
)

echo [INFO] Building C++...
cmake --build . -j 4

if errorlevel 1 (
    echo [ERROR] Build failed
    exit /b 1
)

REM ============================================================================
REM androiddeployqt 生成所有资源并创建 Gradle 项目
REM ============================================================================
echo [INFO] Deploying Qt libraries...
"%QT_PATH%\bin\androiddeployqt.exe" ^
    --input "%BUILD_DIR%\android-%TARGET_ABI%-deployment.json" ^
    --output "%BUILD_DIR%\android-build" ^
    --android-platform %ANDROID_PLATFORM% ^
    --gradle ^
    --no-translations ^
    --%BUILD_TYPE%

if errorlevel 1 (
    echo [ERROR] androiddeployqt failed
    exit /b 1
)

REM ============================================================================
REM 使用 Gradle 构建 APK（让 Qt manifest merging 正确工作）
REM ============================================================================
echo [INFO] Building APK with Gradle...

cd /d "%BUILD_DIR%\android-build"

call gradle.bat assemble%BUILD_TYPE% ^
    -PABI_FILTERS=%TARGET_ABI% ^
    --no-daemon ^
    -p "%BUILD_DIR%\android-build"

if errorlevel 1 (
    echo [ERROR] Gradle build failed
    exit /b 1
)

REM ============================================================================
REM 输出 APK
REM ============================================================================
for /r "%BUILD_DIR%\android-build\build\outputs\apk" %%f in (*.apk) do (
    set APK_PATH=%%f
    goto :found_apk
)

:found_apk
if defined APK_PATH (
    echo ==========================================
    echo  [OK] APK Build Complete
    echo   Path: !APK_PATH!
    echo ==========================================

    if not exist "%APP_DIR%dist" mkdir "%APP_DIR%dist"
    copy /Y "!APK_PATH!" "%APP_DIR%dist\" > /dev/null
    echo APK copied to: %APP_DIR%dist) else (
    echo [ERROR] APK not found in build outputs
    exit /b 1
)