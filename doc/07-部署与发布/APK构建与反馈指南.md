

# Android APK 构建完整流程 + 问题反馈指南

> 本文档涵盖：另一台电脑 Docker 安装、Android 项目构建全流程、问题反馈机制、logcat 使用、Bug 报告模板。

---

## 目录

### 第一部分：另一台电脑 Docker 安装
1. [硬件要求](#一硬件要求)
2. [BIOS 虚拟化启用](#二bios-虚拟化启用)
3. [Docker Desktop 安装](#三docker-desktop-安装)
4. [WSL 2 配置](#四wsl-2-配置)
5. [项目传输](#五项目传输)
6. [构建 APK](#六构建-apk)

### 第二部分：构建全流程
7. [完整构建步骤](#七完整构建步骤)
8. [构建过程详解](#八构建过程详解)
9. [构建日志解读](#九构建日志解读)

### 第三部分：问题反馈
10. [问题分类](#十问题分类)
11. [logcat 详细使用](#十一logcat-详细使用)
12. [问题反馈渠道](#十二问题反馈渠道)
13. [Bug 报告模板](#十三bug-报告模板)
14. [常见问题速查](#十四常见问题速查)

---

# 第一部分：另一台电脑 Docker 安装

## 一、硬件要求

### 最低配置
- **CPU**：4 核以上，支持 VT-x（Intel）或 AMD-V
- **内存**：8GB（推荐 16GB）
- **磁盘**：30GB 可用空间（推荐 50GB+）
- **系统**：Windows 10 64-bit (版本 2004+) 或 Windows 11

### 推荐配置
- **CPU**：8 核
- **内存**：16GB
- **磁盘**：SSD 100GB+
- **系统**：Windows 11 64-bit

## 二、BIOS 虚拟化启用

Docker Desktop 依赖 Hyper-V 或 WSL 2，需要 CPU 虚拟化支持。

### Intel CPU（VT-x）
1. 重启电脑，按 **Del** / **F2** / **F10** 进入 BIOS
2. 找到 **Advanced** → **CPU Configuration** 或 **Security**
3. 启用：
   - Intel Virtualization Technology (VT-x)
   - Intel VT-d（如果有）
4. 保存退出（通常 F10）

### AMD CPU（AMD-V）
1. 重启进入 BIOS
2. 找到 **Advanced** → **CPU Configuration**
3. 启用 **SVM Mode**（Secure Virtual Machine）
4. 保存退出

### 验证
打开任务管理器 → 性能 → CPU，底部显示"虚拟化：已启用"。

## 三、Docker Desktop 安装

### 3.1 下载

**官方下载（推荐）**：
```
https://desktop.docker.com/win/main/amd64/Docker Desktop Installer.exe
```

**国内镜像**（下载更快）：
- 阿里云镜像：https://mirrors.aliyun.com/docker-toolbox/
- 网易镜像：https://hub-mirror.c.163.com/docker-toolbox/

### 3.2 安装

1. 双击运行 `Docker Desktop Installer.exe`
2. 配置选项：
   - ✅ **Use WSL 2 instead of Hyper-V**（推荐）
   - ✅ **Add shortcut to desktop**
3. 点击 **Ok** 开始安装
4. 等待 5-10 分钟
5. 安装完成，**重启 Windows**

### 3.3 首次启动

1. 从开始菜单启动 **Docker Desktop**
2. 接受服务协议
3. 跳过登录（点击 **Skip**）
4. 等待右下角图标变绿（约 30-60 秒）

### 3.4 验证

打开 PowerShell 或 Git Bash：

```bash
docker --version
# 输出: Docker version 24.0.x, build xxxxx

docker compose version
# 输出: Docker Compose version v2.x.x

docker info | head -10
# 应显示 Server 信息
```

### 3.5 配置镜像加速（重要，可选）

为加速下载，国内用户配置镜像：

创建 `%UserProfile%\.docker\daemon.json`：

```json
{
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com",
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com"
  ],
  "features": {
    "buildkit": true
  }
}
```

重启 Docker Desktop。

## 四、WSL 2 配置

### 4.1 启用 WSL 功能

PowerShell（管理员）：

```powershell
# 启用 WSL
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart

# 启用虚拟机平台
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
```

**重启 Windows**。

### 4.2 设置 WSL 2 为默认

```powershell
wsl --set-default-version 2
```

### 4.3 安装 Ubuntu

```powershell
# 列出可用发行版
wsl --list --online

# 安装 Ubuntu 22.04
wsl --install -d Ubuntu-22.04

# 设置默认用户（按提示输入）
```

### 4.4 验证 WSL

```powershell
wsl --list --verbose
# 输出 NAME STATE VERSION
# Ubuntu-22.04 Running 2
```

### 4.5 配置 WSL 内存（推荐）

创建 `%UserProfile%\.wslconfig`：

```ini
[wsl2]
memory=8GB
processors=4
swap=2GB
localhostForwarding=true
```

重启 WSL：`wsl --shutdown`

## 五、项目传输

### 方案 A：通过 Git（推荐）

#### 在当前电脑：
```bash
cd H:\AI_Claude\work_dir
git init
git add .
git commit -m "Initial commit: 荒野手册 v1.0"
# 推送到 GitHub / Gitee / GitLab
git remote add origin https://github.com/yourname/outdoor-survival.git
git push -u origin main
```

#### 在另一台电脑：
```bash
git clone https://github.com/yourname/outdoor-survival.git
cd outdoor-survival
```

### 方案 B：直接拷贝

#### 当前电脑打包：
```bash
# 打包源码（不含 build/）
cd H:\AI_Claude\work_dir
tar -czf outdoor-survival.tar.gz \
    --exclude='*/build/*' \
    --exclude='*/dist/*' \
    --exclude='*.log' \
    .

# 或使用 zip（Windows 原生）
# 在文件资源管理器中右键 -> 发送到 -> 压缩(zipped)文件夹
```

#### 传输方式：
- U 盘
- 网盘（百度网盘 / 阿里云盘）
- 局域网共享
- 邮件附件（小项目可）

#### 另一台电脑解压：
```bash
# Linux
tar -xzf outdoor-survival.tar.gz

# Windows
# 右键 -> 解压到当前文件夹
```

### 方案 C：使用 Git LFS（大文件）

如果有大型模型文件，使用 Git LFS：
```bash
git lfs install
git lfs track "*.param"
git lfs track "*.bin"
```

## 六、构建 APK

在另一台电脑，进入项目目录：

```bash
cd outdoor-survival
cd app
```

### 6.1 第一次构建（30-60 分钟）

```bash
# 构建 Docker 镜像
docker compose build android-builder
```

**会下载**：
- Ubuntu 22.04（~70MB）
- Qt 6.7.2 for Android（~1GB）
- Android SDK + NDK（~2GB）
- ccache（~1MB,C++ 增量编译加速）
- ~~NCNN（~500MB）~~(2026-08-27 V2 移除,改为图鉴检索)

**镜像大小**：约 8-10GB

**预计时间**：
- 网络 100Mbps：30-45 分钟
- 网络 50Mbps：60-90 分钟
- 网络 10Mbps：3-4 小时

### 6.2 构建 APK

```bash
# arm64-v8a（推荐）— 增量编译,默认并行
docker compose run --rm android-builder \
    bash -c "cd /project && bash build_apk.sh release arm64-v8a"

# 强制全量重建(清理 CMake 缓存)
docker compose run --rm android-builder \
    bash -c "cd /project && CLEAN=1 bash build_apk.sh release arm64-v8a"

# 限制并行编译数(CPU 紧张时)
docker compose run --rm android-builder \
    bash -c "cd /project && BUILD_JOBS=4 bash build_apk.sh release arm64-v8a"
```

**构建时间**：
- 第一次：15-20 分钟
- 增量构建（仅改几个 cpp）：5-10 秒(C++ 增量编译 + ccache 命中)
- 强制全量(CLEAN=1)：1-2 分钟

### 6.3 查看输出

```bash
# 在 Windows 上
explorer dist\

# 或 PowerShell
Get-ChildItem dist\

# 应看到：
# OutdoorSurvival-v1.0.0-release-arm64-v8a.apk
```

### 6.4 验证 APK

```bash
# 检查 APK 信息
$ANDROID_HOME/build-tools/34.0.0/aapt dump badging dist/OutdoorSurvival-v1.0.0-release-arm64-v8a.apk

# 检查签名
$ANDROID_HOME/build-tools/34.0.0/apksigner verify --print-certs dist/OutdoorSurvival-v1.0.0-release-arm64-v8a.apk
```

---

# 第二部分：构建全流程

## 七、完整构建步骤

### 7.1 流程图

```
源码 → CMake 配置 → 编译 → 部署 Qt → 链接 APK → 对齐 → 签名 → 验证
 ↓        ↓           ↓         ↓          ↓        ↓        ↓        ↓
 src/   build_apk   NDK      QML 部署   aapt2   zipalign  apksigner  检查
        .sh 启动   编译      库复制     链接
```

### 7.2 详细步骤

#### Step 1: 项目准备
```bash
# 进入项目目录
cd /path/to/app

# 检查项目结构
ls -la
# 应看到: src/ qml/ assets/ android/ CMakeLists.txt
```

#### Step 2: 启动 Docker 构建环境
```bash
# Docker Compose 启动（首次会构建镜像）
docker compose build android-builder

# 输出示例：
# [+] Building 245.3s (45/45) FINISHED
# => [android-builder internal]  . 30.2s => => ...
# => => naming to docker.io/library/app-android-builder:latest
```

#### Step 3: 进入容器
```bash
# 方式 1: 直接运行构建命令
docker compose run --rm android-builder \
    bash -c "cd /project && bash build_apk.sh release arm64-v8a"

# 方式 2: 进入容器交互式调试
docker compose run --rm android-builder bash
# 现在你在容器内
cd /project
bash build_apk.sh release arm64-v8a
```

#### Step 4: CMake 配置
```bash
# 在 build_apk.sh 中会自动执行：
mkdir -p build/release_arm64-v8a
cd build/release_arm64-v8a

cmake /project \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE=/opt/android-sdk/ndk/26.1.10909125/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-34 \
    -DCMAKE_PREFIX_PATH=/opt/Qt/6.7.2/android_arm64_v8a
```

#### Step 5: 编译
```bash
# 自动执行(首次 10-30 秒, 增量 5-10 秒)
# -j$(nproc) 并行编译, ccache 加速, 增量编译保留 CMakeCache.txt
# 可用 BUILD_JOBS=N 覆盖并行数, CLEAN=1 强制全量重建
cmake --build . -j$(nproc)
```

#### Step 6: 部署 Qt 库
```bash
# 自动执行（约 2-3 分钟）
# 注意: 不带 --gradle, 让 androiddeployqt 只生成项目结构, 不调 gradle
# (否则会在我们 cp 覆盖 build.gradle 前调 gradle, 用 Qt 模板触发 FAIL_ON_PROJECT_REPOS)
/opt/Qt/6.7.2/bin/androiddeployqt \
    --input build/release_arm64-v8a/android-arm64-v8a-deployment.json \
    --output build/release_arm64-v8a/android-build \
    --android-platform android-34 \
    --no-translations \
    --release
# 之后 build_apk.sh 会:
# 1. cp 项目 build.gradle / settings.gradle / app/build.gradle 覆盖 Qt 模板
# 2. cp 项目 AndroidManifest.xml 覆盖(根目录 + app/src/main/ 两份)
# 3. 手动调 gradle assembleRelease
```

#### Step 7: 链接 APK
```bash
# 自动执行
$ANDROID_HOME/build-tools/34.0.0/aapt2 link \
    -o OutdoorSurvival-v1.0.0-release-arm64-v8a.apk \
    -I $ANDROID_HOME/platforms/android-34/android.jar \
    --manifest /project/android/AndroidManifest.xml \
    -R build/release_arm64-v8a/android-build/res \
    -A /project/android/assets \
    --auto-add-overlay
```

#### Step 8: 对齐
```bash
$ANDROID_HOME/build-tools/34.0.0/zipalign -p -f 4 \
    OutdoorSurvival-v1.0.0-release-arm64-v8a.apk \
    OutdoorSurvival-v1.0.0-release-arm64-v8a.aligned
mv OutdoorSurvival-v1.0.0-release-arm64-v8a.aligned \
   OutdoorSurvival-v1.0.0-release-arm64-v8a.apk
```

#### Step 9: 签名
```bash
$ANDROID_HOME/build-tools/34.0.0/apksigner sign \
    --ks /project/keystore/outdoor.keystore \
    --ks-pass pass:outdoor123 \
    --ks-key-alias outdoor \
    --key-pass pass:outdoor123 \
    --v1-signing-enabled true \
    --v2-signing-enabled true \
    --v3-signing-enabled true \
    OutdoorSurvival-v1.0.0-release-arm64-v8a.apk
```

#### Step 10: 验证 + 复制
```bash
# 验证签名
$ANDROID_HOME/build-tools/34.0.0/apksigner verify \
    --print-certs \
    OutdoorSurvival-v1.0.0-release-arm64-v8a.apk

# 复制到 dist
cp OutdoorSurvival-v1.0.0-release-arm64-v8a.apk /project/dist/
```

## 八、构建过程详解

### 8.1 NDK 编译阶段

C++ 源文件（41 个）→ ARM64 汇编 → .o 对象文件 → 链接为 .so

**关键文件**：
- `OutdoorSurvival.so` - 主可执行
- `libQt6Core.so` 等 - Qt 运行时

**耗时**：~10-15 分钟
**输出**：~30-50MB（libOutdoorSurvival.so + Qt libs）

### 8.2 Qt 部署阶段

Qt QML 文件 → 编译为 qmlc → 打包到 assets/

**关键目录**：
- `qml/QtQuick/` - Qt Quick 模块
- `qml/QtQuick/Controls/` - 控件
- `assets/qml/OutdoorSurvival/` - 应用 QML

**耗时**：~2-3 分钟

### 8.3 APK 打包阶段

合并：
- AndroidManifest.xml
- classes.dex
- lib/（所有 .so）
- assets/（QML + JSON）
- resources.arsc

**耗时**：~30 秒

### 8.4 签名阶段

- v1 签名（JAR 签名）
- v2 签名（APK 签名方案 v2）
- v3 签名（APK 签名方案 v3）

**耗时**：~5 秒

## 九、构建日志解读

### 9.1 正常日志

```
==========================================
Building 荒野手册 v1.0.0
Package: com.outdoor.survival
Version code: 100
Min SDK: 24, Target SDK: 34
NCNN: ON
==========================================

[INFO] Configuring CMake...
-- The C compiler identification is Clang 17.0.6
-- The CXX compiler identification is Clang 17.0.6
-- Detecting CXX compile features
-- Detecting CXX ABI info
-- Configuring done
-- Generating done
-- Build files have been written to: ...

[INFO] Building...
[  1%] Building CXX object src/CMakeFiles/OutdoorSurvival.dir/main.cpp.o
[  2%] Building CXX object src/CMakeFiles/OutdoorSurvival.dir/core/App.cpp.o
...
[ 50%] Building CXX object src/CMakeFiles/OutdoorSurvival.dir/...
...
[100%] Built target OutdoorSurvival
```

### 9.2 错误日志示例

#### NDK 未找到
```
[ERROR] Android NDK not found: /opt/android-sdk/ndk/26.1.10909125
[INFO] Set ANDROID_NDK_HOME environment variable
```

#### Qt 未找到
```
[ERROR] Qt not found: /opt/Qt/6.7.2
[INFO] Set QT_PATH environment variable
```

#### 编译错误
```
error: use of undeclared identifier 'xxx'
note: did you mean 'yyy'?
1 error generated.
make[2]: *** [src/CMakeFiles/OutdoorSurvival.dir/xxx.cpp.o] Error 1
```

#### 链接错误
```
undefined reference to `xxx::yyy()'
collect2: error: ld returned 1 exit status
make: *** [OutdoorSurvival] Error 1
```

---

# 第三部分：问题反馈

## 十、问题分类

### 10.1 按严重性

| 级别 | 描述 | 响应时间 |
|---|---|---|
| **P0 致命** | App 崩溃、SOS 失效、数据丢失 | 立即 |
| **P1 严重** | 核心功能失效、安全问题 | 24h |
| **P2 一般** | 非核心功能失效、UI 错误 | 3d |
| **P3 轻微** | 文案错误、优化建议 | 7d |

### 10.2 按模块

| 模块 | 关注点 |
|---|---|
| 急救 | 决策正确性、内容准确性 |
| SOS | 拨号、短信、GPS |
| 识别 | 准确率、速度、离线 |
| 路线 | 数据正确、推荐合理 |
| 应急 | 重量计算、清单管理 |
| UI | 流畅度、可读性 |
| 性能 | 启动、内存、电量 |
| 兼容 | 设备、版本 |
| 安全 | 加密、权限、隐私 |

## 十一、logcat 详细使用

### 11.1 启动 logcat

#### 实时查看
```bash
# 查看所有日志
adb logcat

# 仅看 App 日志
adb logcat | grep -i "outdoor\|survival"

# 详细查看
adb logcat -s OutdoorSurvival:V AndroidRuntime:E Qt:V

# 保存到文件
adb logcat > logcat.txt
```

#### 按场景过滤

```bash
# SOS 触发流程
adb logcat -s EmergencyService:V OutdoorSurvival:V

# 识别流程
adb logcat -s RecognitionEngine:V CloudRecognition:V

# 急救决策
adb logcat -s FirstAidService:V DecisionEngine:V
```

#### 按时间过滤

```bash
# 最近 1 小时
adb logcat -t '01-01 00:00:00.000'

# 实时 + 时间戳
adb logcat -v time
```

### 11.2 关键日志标识

我们 App 的日志标签：

| 标签 | 含义 |
|---|---|
| `OutdoorSurvival` | 主类 |
| `FirstAidService` | 急救服务 |
| `EmergencyService` | SOS 服务 |
| `RecognitionEngine` | 识别 |
| `CloudRecognition` | 云端识别 |
| `RecognitionStorage` | 存储 |
| `RouteService` | 路线 |
| `ChecklistService` | 应急 |
| `SpeciesService` | 物种 |
| `SurvivalService` | 生存 |
| `KnotService` | 绳结 |
| `AndroidPlatform` | Android 平台 |
| `Logger` | 日志系统 |

### 11.3 抓取崩溃日志

```bash
# 1. 启动 logcat
adb logcat -c  # 清空
adb logcat > crash.log &

# 2. 复现崩溃

# 3. Ctrl+C 停止

# 4. 查找 FATAL
grep -A 30 "FATAL" crash.log
```

### 11.4 ANR（应用无响应）

```bash
# 查看 ANR
adb shell ls /data/anr/

# 拉取
adb pull /data/anr/ ./anr_logs/

# 查看 traces.txt
cat traces.txt
```

## 十二、问题反馈渠道

### 12.1 反馈方式

#### 渠道 A：直接反馈（推荐）
- 当面描述问题
- 截图 + 文字
- 录屏

#### 渠道 B：文件反馈
- 问题日志
- APK 复现

#### 渠道 C：实时通讯
- 微信 / QQ 群
- 飞书 / 钉钉

#### 渠道 D：Bug 跟踪系统
- GitHub Issues
- 内部 Bug 系统

### 12.2 反馈时提供

**必备信息**：
1. **问题描述**：清楚说明发生了什么
2. **复现步骤**：怎么触发
3. **预期结果**：应该是什么样
4. **实际结果**：实际是什么样
5. **设备信息**：型号、Android 版本
6. **App 版本**：版本号、versionCode
7. **截图 / 录屏**：直观证据
8. **logcat 日志**：技术细节

## 十三、Bug 报告模板

### 13.1 简版模板（用户用）

```markdown
# Bug #XXX

## 概要
[一句话描述]

## 复现步骤
1. 打开 App
2. 进入 [页面]
3. 点击 [按钮]
4. 看到 [现象]

## 预期结果
应该显示 [预期]

## 实际结果
实际显示 [实际]

## 截图
[粘贴截图]

## 设备
- 设备: 华为 Mate 60
- 系统: HarmonyOS 4.0
- App 版本: 1.0.0
```

### 13.2 详版模板（开发用）

```markdown
# Bug #XXX: [标题]

## 概要
[详细描述]

## 复现步骤
1. 打开 App
2. ...
3. ...

## 预期结果
[具体]

## 实际结果
[具体]

## 严重性
- [ ] P0 致命
- [ ] P1 严重
- [ ] P2 一般
- [ ] P3 轻微

## 优先级
- [ ] P0 立即
- [ ] P1 下一版
- [ ] P2 后续

## 环境
- 设备: [品牌型号]
- Android: [版本]
- 屏幕: [分辨率]
- 存储: [可用空间]
- 网络: [WiFi/4G/5G/无]

## App 信息
- 版本: 1.0.0
- versionCode: 100
- 首次安装: [是/否]
- 数据迁移: [是/否]

## 复现概率
- [ ] 必现
- [ ] 偶现（约 X 次/10 次）
- [ ] 仅在特定条件

## logcat 日志
```
[粘贴相关日志]
```

## 截图 / 录屏
[附件]

## 分析
[开发者的分析]

## 修复
[代码改动]

## 验证
[测试方法]
```

### 13.3 反馈话术

#### 普通用户
> "急救决策里点 '蛇咬' 后白屏了，重启也没用。iPhone 14，鸿蒙 4.0，App 1.0.0。"

#### 高级用户
> "复现路径：急救 -> 蛇咬 -> 启动决策 -> 选项 B，100% 白屏。logcat 看到 FirstAidService 段错误。环境：Mate 60 Pro, HarmonyOS 4.0.0.138, v1.0.0 (100)。"

#### 开发者
> "TC-FA-007 在真机崩溃（Pixel 7, Android 14），堆栈显示在 getDecisionNode 中的空指针。怀疑是 JSON 解析时 options 字段为 null。修复：在 FirstAidService::getDecisionNode 增加空值检查。"

## 十四、常见问题速查

### Q1: Docker Desktop 启动失败

**症状**：Docker Desktop 图标红色，提示错误

**解决**：
```bash
# 1. 检查虚拟化
# 任务管理器 -> 性能 -> CPU -> 虚拟化: 已启用

# 2. 启用 Hyper-V
# 控制面板 -> 程序 -> 启用或关闭 Windows 功能
# 勾选: Hyper-V, 容器, 适用于 Linux 的 Windows 子系统

# 3. 重启

# 4. 重置 Docker
# Docker Desktop -> Troubleshoot -> Reset to factory defaults
```

### Q2: docker build 极慢

**症状**：下载镜像缓慢

**解决**：
- 配置镜像加速（见 3.5）
- 使用更快的网络
- 避开高峰时段

### Q3: 磁盘空间不足

**症状**：`no space left on device`

**解决**：
```bash
# 清理 Docker 缓存
docker system prune -a
docker image prune -a
docker volume prune

# 清理 build 目录
rm -rf app/build/
```

### Q4: 编译错误 NDK

**症状**：`/opt/android-sdk/ndk/... not found`

**解决**：
```bash
# 在 Docker 容器内检查
docker compose run --rm android-builder bash
ls /opt/android-sdk/ndk/

# 应该看到: 26.1.10909125
```

### Q5: Qt 找不到

**症状**：`Qt not found: /opt/Qt/6.7.2`

**解决**：
```bash
# 在容器内检查
ls /opt/Qt/6.7.2/android_arm64_v8a/lib/cmake/Qt6/

# 如不存在，Dockerfile 需修复
# 检查网络，Qt 安装可能超时
```

### Q6: APK 签名失败

**症状**：`Failed to sign`

**解决**：
```bash
# 检查 keystore
ls -la keystore/outdoor.keystore

# 重新生成
keytool -genkey -v -keystore keystore/outdoor.keystore \
    -alias outdoor -keyalg RSA -keysize 2048 -validity 25000 \
    -storepass outdoor123 -keypass outdoor123 \
    -dname "CN=OutdoorSurvival, O=Outdoor, C=CN"
```

### Q7: 找不到 aapt2

**症状**：`aapt2: command not found`

**解决**：
```bash
# 路径不对
# 默认: $ANDROID_HOME/build-tools/34.0.0/aapt2
# 在容器内
which aapt2
find /opt/android-sdk -name "aapt2"
```

### Q8: 编译成功但 APK 启动崩溃

**症状**：APK 安装后点击立即闪退

**解决**：
```bash
# 1. 查看 logcat
adb logcat -s AndroidRuntime:E Qt:E

# 2. 常见原因：
# - NDK 版本不匹配
# - 缺少资源文件
# - QML 错误
```

### Q9: 启动后白屏

**症状**：App 启动后长时间白屏

**解决**：
```bash
# 查看 QML 错误
adb logcat -s Qt:V QML:V

# 常见原因：
# - QML 文件未打包
# - 模块导入错误
# - 资源路径错误
```

### Q10: SOS 拨打不成功

**症状**：点击 120 没有反应

**解决**：
```bash
# 1. 检查权限
adb shell dumpsys package com.outdoor.survival | grep permission

# 2. 检查 ACTION_DIAL 兼容性
adb logcat | grep -i "dial\|phone"

# 3. Android 10+ 使用 ACTION_DIAL（不会自动拨打）
# 4. Android < 10 可用 ACTION_CALL
```

## 附录 A：完整构建命令速查

```bash
# === 另一台电脑完整流程 ===

# 1. 验证 Docker
docker --version

# 2. 进入项目
cd outdoor-survival/app

# 3. 构建 Docker 镜像（首次 30-60 分钟）
docker compose build android-builder

# 4. 构建 APK（首次 15-20 分钟, 增量 2-5 分钟）
docker compose run --rm android-builder \
    bash -c "cd /project && bash build_apk.sh release arm64-v8a"

# 4a. 强制全量重建(清理 CMake 缓存)
docker compose run --rm android-builder \
    bash -c "cd /project && CLEAN=1 bash build_apk.sh release arm64-v8a"

# 4b. 限制并行编译数(CPU 紧张时)
docker compose run --rm android-builder \
    bash -c "cd /project && BUILD_JOBS=4 bash build_apk.sh release arm64-v8a"

# 5. 查看输出
ls -lh dist/

# 6. 验证 APK（版本号取 CMakeLists.txt 的 project(... VERSION 0.0.2)）
$ANDROID_HOME/build-tools/34.0.0/aapt dump badging dist/OutdoorSurvival-v0.0.2-release-arm64-v8a.apk
# 预期: package: name='com.outdoor.survival' versionCode=2 versionName='0.0.2'
# 注意 versionCode 由 android/app/build.gradle 决定：build_apk.sh 会用仓库里的这份
# 覆盖 android-build/app/build.gradle，CMakeLists.txt:59 的 APP_VERSION_CODE 只喂模板。
# 三处（CMakeLists VERSION / build.gradle / AndroidManifest）不同步时，文件名和包内版本会分叉。

# 7. 启动应用(Activity 是全限定名, 不要用 .QtActivity 简写)
adb shell am start -n com.outdoor.survival/org.qtproject.qt.android.bindings.QtActivity

# 8. 复制到桌面（Windows）
cp dist/OutdoorSurvival-v0.0.2-release-arm64-v8a.apk /mnt/c/Users/Public/Desktop/
```

## 附录 B：反馈工作流

```
发现问题
  ↓
拍照 / 录屏
  ↓
抓 logcat
  ↓
填写 Bug 报告
  ↓
通过反馈渠道提交
  ↓
开发分析
  ↓
修复代码
  ↓
回归测试
  ↓
新版本发布
  ↓
验证问题解决
```

---

## 文档维护

- **创建日期**：2026-08-24
- **版本**：v1.0
- **配套**：15 份项目级文档
- **状态**：完整
