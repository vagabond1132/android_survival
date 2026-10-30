#!/usr/bin/env bash
# Windows 侧装 Android 模拟器的前置件 (JDK 17 + cmdline-tools) —— 2026-10-30
#
# 为什么装在 Windows 而不是 WSL: WSL2 里 /proc/cpuinfo 没有 vmx (嵌套虚拟化没开),
#   模拟器进去就是纯软件渲染, 慢到不能用来复核 UI; Windows 侧可以用 WHPX
#   (VirtualMachinePlatform 功能已经为 WSL2 打开了)。
# 为什么还要 JDK: sdkmanager / avdmanager 是 Java 程序, 本机此前没有 java。
# 下载源: JDK 走清华 Adoptium 镜像, cmdline-tools 走 dl.google.com (实测可达)。
#
# 可重复执行: 已下载/已解压的步骤会跳过。
set -uo pipefail

ROOT=/d/build_docker
TOOLS=$ROOT/android_tools
SDK=$ROOT/android_sdk
JDK_DIR=$ROOT/jdk17
JDK_ZIP=$TOOLS/OpenJDK17U-jdk_x64_windows_hotspot_17.0.20.1_1.zip
JDK_URL=https://mirrors.tuna.tsinghua.edu.cn/Adoptium/17/jdk/x64/windows/OpenJDK17U-jdk_x64_windows_hotspot_17.0.20.1_1.zip
CT_ZIP=$TOOLS/commandlinetools-win-11076708_latest.zip
CT_URL=https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip

mkdir -p "$TOOLS" "$SDK"

unzip_to() {
    local zip=$1 dst=$2
    if command -v unzip >/dev/null 2>&1; then
        unzip -q -o "$zip" -d "$dst"
    else
        # Git Bash 没带 unzip 时退回 PowerShell
        powershell.exe -NoProfile -Command "Expand-Archive -LiteralPath '$(cygpath -w "$zip")' -DestinationPath '$(cygpath -w "$dst")' -Force"
    fi
}

echo "[1/4] JDK 17"
if [ -x "$(find "$JDK_DIR" -maxdepth 3 -name java.exe -print -quit 2>/dev/null)" ]; then
    echo "  已存在: $JDK_DIR"
else
    [ -f "$JDK_ZIP" ] || curl -fL --connect-timeout 15 --max-time 900 -o "$JDK_ZIP" "$JDK_URL" || exit 1
    mkdir -p "$JDK_DIR"
    unzip_to "$JDK_ZIP" "$JDK_DIR" || exit 1
fi
JAVA_EXE=$(find "$JDK_DIR" -maxdepth 3 -name java.exe -print -quit)
JDK_HOME=$(dirname "$(dirname "$JAVA_EXE")")
echo "  java: $JAVA_EXE"
"$JAVA_EXE" -version 2>&1 | head -1

echo "[2/4] cmdline-tools"
if [ -f "$SDK/cmdline-tools/latest/bin/sdkmanager.bat" ]; then
    echo "  已存在: $SDK/cmdline-tools/latest"
else
    [ -f "$CT_ZIP" ] || curl -fL --connect-timeout 15 --max-time 900 -o "$CT_ZIP" "$CT_URL" || exit 1
    mkdir -p "$SDK/cmdline-tools"
    unzip_to "$CT_ZIP" "$SDK/cmdline-tools" || exit 1
    # zip 顶层是 cmdline-tools/, 必须摆成 cmdline-tools/latest/ 否则 sdkmanager 找不到仓库
    if [ -d "$SDK/cmdline-tools/cmdline-tools" ]; then
        mv "$SDK/cmdline-tools/cmdline-tools" "$SDK/cmdline-tools/latest"
    fi
fi
ls "$SDK/cmdline-tools/latest/bin/" | head -5

echo "[3/4] 写环境变量脚本 (给后续 sdkmanager / emulator 用)"
JDK_WIN=$(cygpath -w "$JDK_HOME")
SDK_WIN=$(cygpath -w "$SDK")
printf '﻿' > "$ROOT/env_android.ps1"
cat >> "$ROOT/env_android.ps1" <<EOF
# 一次性设置本次会话的 Android 工具链环境变量 (PowerShell: . .\\env_android.ps1)
\$env:JAVA_HOME = '$JDK_WIN'
\$env:ANDROID_HOME = '$SDK_WIN'
\$env:ANDROID_SDK_ROOT = \$env:ANDROID_HOME
\$env:Path = "\$env:JAVA_HOME\\bin;\$env:ANDROID_HOME\\platform-tools;\$env:ANDROID_HOME\\emulator;\$env:Path"
Write-Host "JAVA_HOME=\$env:JAVA_HOME"
Write-Host "ANDROID_HOME=\$env:ANDROID_HOME"
EOF
echo "  写了 $ROOT/env_android.ps1"

echo "[4/4] sdkmanager 自检"
# .bat 必须由 cmd.exe 执行, 且 `/c` 会被 Git Bash 当成路径改写成 C:/Program Files/Git/c,
# 所以整条命令前面要加 MSYS_NO_PATHCONV=1
MSYS_NO_PATHCONV=1 cmd.exe /c "$(cygpath -w "$SDK/cmdline-tools/latest/bin/sdkmanager.bat") --version" 2>&1 | tail -3
echo '下一步 (约 1.5-1.6GB 下载):'
echo '  powershell -ExecutionPolicy Bypass -File D:\build_docker\app\tools\win_sdk_pkgs.ps1'
