# Windows 侧 Android SDK 包安装 (模拟器验证用) —— 2026-10-30
#
# 为什么装在 Windows 而不是 WSL: WSL2 里 /proc/cpuinfo 没有 vmx (嵌套虚拟化没开),
#   /dev/kvm 也不存在, 模拟器只能靠 Windows 侧的 WHPX 跑.
# 前置: 先跑 bash tools/win_emulator_prereq.sh (JDK 17 + cmdline-tools).
# 用法: powershell -ExecutionPolicy Bypass -File D:\build_docker\app\tools\win_sdk_pkgs.ps1
# 下载量约 1.5-1.6 GB, 全部落在 D:\build_docker\android_sdk (不污染 C 盘).

$ErrorActionPreference = 'Stop'
. D:\build_docker\env_android.ps1

$SDK  = $env:ANDROID_HOME
$MGR  = "$SDK\cmdline-tools\latest\bin\sdkmanager.bat"

Write-Host "[1/4] sdkmanager 自检"
& $MGR --version | Select-Object -Last 2

Write-Host "[2/4] 接受许可 (一次性)"
# 注意: `'y' * 30` 在 PowerShell 里是**一个** 30 个 y 的字符串, 会被 sdkmanager 当一行读,
# 于是许可照样不接受 (2026-10-30 实测: 输出 "Skipping ... license is not accepted").
# 要的是 40 个独立的 y 行 —— 用管道逐个发.
1..40 | ForEach-Object { 'y' } | & $MGR --licenses --sdk_root=$SDK | Out-Null
Write-Host "  许可已接受"

Write-Host "[3/4] 装包"
# build-tools 不是可选的: mobile-use 的环境检查器把 aapt.exe 列为 required,
# 缺它就没法把 AVD 认成可用 target (2026-10-30 check-mobile-environment.mjs 实测).
$pkgs = @(
    'platform-tools',
    'emulator',
    'platforms;android-34',
    'build-tools;34.0.0',
    'system-images;android-34;google_apis;x86_64'
)
foreach ($p in $pkgs) {
    Write-Host "  -> $p"
    & $MGR --install $p --sdk_root=$SDK
    if ($LASTEXITCODE -ne 0) { throw "安装失败: $p" }
}

Write-Host "[4/4] 已装清单"
& $MGR --list --sdk_root=$SDK | Select-String -Pattern 'Installed', '^\s+\[', 'platform', 'emulator', 'system-images' | Select-Object -First 30

Write-Host ""
Write-Host "下一步: powershell -ExecutionPolicy Bypass -File D:\build_docker\app\tools\win_make_avd.ps1"
