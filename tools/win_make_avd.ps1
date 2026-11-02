# 建 AVD 并启动模拟器 (WHPX) —— 2026-10-30
#
# 前置: 先跑 tools/win_emulator_prereq.sh + tools/win_sdk_pkgs.ps1.
# 用法:
#   powershell -ExecutionPolicy Bypass -File D:\build_docker\app\tools\win_make_avd.ps1 -NoStart  # 只建 AVD
#   powershell -ExecutionPolicy Bypass -File D:\build_docker\app\tools\win_make_avd.ps1           # 建(若缺) + 启动
#   (AVD 已存在时再跑一次就是直接启动, -Start 只是给人读意图用的别名)
#
# AVD 目录放 D 盘 (--path), 默认会在 C:\Users\<u>\.android\avd 把系统盘塞满.
# 加速: 本机是 i5-1035G1 (8 逻辑核) + 15.7 GB 内存, 所以 -gpu host + -cores 4 + -memory 2048,
#   再多就要和 WSL 构建容器抢内存了 (见 [2/2] 处的说明).
param(
    [switch]$NoStart,
    [ValidateSet('host','swiftshader_indirect','client','angle_indirect')]
    [string]$Gpu = 'host',
    [switch]$WipeData
)
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

if ($NoStart) {
    Write-Host "[2/2] -NoStart: 只建 AVD, 不起模拟器"
    Write-Host "启动: 再跑一次本脚本, 不带 -NoStart"
    exit 0
}

Write-Host "[2/2] 启动模拟器 (WHPX; -gpu $Gpu; 窗口出现即成功, Ctrl+C 不停后台)"
# 本机 15.7 GB 物理内存, WSL2 已占走约 7.6 GB —— 模拟器给 2048 MB 就够跑 Qt 空壳,
# 再大会把主机压进 swap, 判 UI 流畅度 (④"分析图卡顿") 时读数也不可信.
# 跑模拟器复核前建议先 `wsl --shutdown` 把内存还回来.
# -gpu host 在 i5-1035G1 (Intel UHD) + WHPX 上实测会让 guest 卡到 adbd 不响应
# (2026-11-02: 装了 50 MB 的包后 adb shell echo ok 直接超时), 遇到这种情况改用
# -Gpu swiftshader_indirect —— 慢但稳, 判功能不判流畅度时用.
$emuArgs = @(
    '-avd', $AVD, '-gpu', $Gpu, '-cores', '4', '-memory', '2048',
    '-no-boot-anim', '-accel', 'on', '-no-audio', '-no-snapshot'
)
if ($WipeData) { $emuArgs += '-wipe-data' }
# stderr 落盘: 模拟器一旦挂死, 光看 adb devices 分不清是 guest 卡了还是 adbd 挂了
$emuLog = 'D:\build_docker\_scratch_debug\emulator_console.log'
Start-Process -FilePath "$env:ANDROID_HOME\emulator\emulator.exe" -ArgumentList $emuArgs `
    -WindowStyle Normal -RedirectStandardError $emuLog

Write-Host "等启动完成后: D:\build_docker\android_sdk\platform-tools\adb.exe devices"
Write-Host "模拟器控制台输出: $emuLog"
