# 建 AVD 并启动模拟器 (WHPX) —— 2026-10-30
#
# 前置: 先跑 tools/win_emulator_prereq.sh + tools/win_sdk_pkgs.ps1.
# 用法:
#   powershell -ExecutionPolicy Bypass -File D:\build_docker\app\tools\win_make_avd.ps1        # 建 + 启动
#   powershell -ExecutionPolicy Bypass -File D:\build_docker\app\tools\win_make_avd.ps1 -Start # 只启动
#
# AVD 目录放 D 盘 (--path), 默认会在 C:\Users\<u>\.android\avd 把系统盘塞满.
# 加速: 本机是 i5-1035G1 (8 逻辑核), 所以 -gpu host + -cores 4 + -memory 3072,
#   再多就要和 WSL 构建容器抢内存了.
param([switch]$Start)
$ErrorActionPreference = 'Stop'
. D:\build_docker\env_android.ps1

$AVD  = 'osw_api34'
$IMG  = 'system-images;android-34;google_apis;x86_64'
$HOME_AVD = 'D:\build_docker\android_avd'
$AVDM = "$env:ANDROID_HOME\cmdline-tools\latest\bin\avdmanager.bat"

New-Item -ItemType Directory -Force -Path $HOME_AVD | Out-Null
$env:ANDROID_AVD_HOME = $HOME_AVD

$exists = & $AVDM list avd | Select-String -Pattern "Name: $AVD"
if (-not $exists) {
    Write-Host "[1/2] 创建 AVD: $AVD ($IMG / pixel_5)"
    # 尾答 "no" = 不创建自定义配置 (.ini 追问), avdmanager 在非交互下会卡在这一问
    'no' | & $AVDM create avd --name $AVD --package $IMG --device pixel_5 --force
    if ($LASTEXITCODE -ne 0) { throw "avdmanager create avd 失败 (rc=$LASTEXITCODE)" }
} else {
    Write-Host "[1/2] AVD 已存在: $AVD"
}

Write-Host "[2/2] 启动模拟器 (WHPX; 窗口出现即成功, Ctrl+C 不停后台)"
Start-Process -FilePath "$env:ANDROID_HOME\emulator\emulator.exe" -ArgumentList @(
    '-avd', $AVD, '-gpu', 'host', '-cores', '4', '-memory', '3072',
    '-no-snapshot-save', '-no-boot-anim', '-accel', 'on'
) -WindowStyle Normal

Write-Host "等启动完成后: D:\build_docker\android_sdk\platform-tools\adb.exe devices"
