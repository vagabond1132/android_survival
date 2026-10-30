# Docker 构建 APK 完全手册(从安装到装机)

> 适用版本: 荒野手册 v0.0.2 / Qt 6.7+ / Android 7.0+ (API 24+)
> 平台: Windows / macOS / Linux 通用

---

## 目录

1. [为什么用 Docker](#1-为什么用-docker)
2. [前置环境](#2-前置环境)
3. [Docker 安装](#3-docker-安装)
4. [验证 Docker](#4-验证-docker)
5. [拉取项目代码](#5-拉取项目代码)
6. [构建 Docker 镜像](#6-构建-docker-镜像)
7. [运行构建容器](#7-运行构建容器)
8. [编译项目](#8-编译项目)
9. [打包 APK](#9-打包-apk)
10. [APK 签名](#10-apk-签名)
11. [验证 APK](#11-验证-apk)
12. [设备安装](#12-设备安装)
13. [常见问题](#13-常见问题)

---

## 1. 为什么用 Docker

| 优势 | 说明 |
|---|---|
| **环境一致** | 同一镜像在任何机器(Ubuntu 22.04 + Qt 6.7.2 + Android NDK r26b)都一样 |
| **免装依赖** | 不用装 Java 17/Qt/SDK/NDK,镜像里都有 |
| **跨平台** | Windows / macOS / Linux 都能跑 |
| **可复现** | 删容器后能 100% 重建,无残留 |
| **隔离** | 不污染本机,装个 Docker Desktop 即可 |

**典型场景**: Windows 用户不想装 Linux 子系统 + 手动配 Qt + 装 NDK,直接 Docker 一键。

---

## 2. 前置环境

| 项目 | 最低 | 推荐 |
|---|---|---|
| CPU | 4 核 | 8 核+ |
| 内存 | 8 GB | 16 GB+ |
| 硬盘 | 30 GB(镜像+构建缓存) | 50 GB SSD |
| 网络 | 能访问 `download.qt.io` `dl.google.com` `hub.docker.com` | - |
| 系统 | Windows 10/11 / macOS 12+ / Ubuntu 20.04+ |  |

---

## 3. Docker 安装

### 3.1 Windows

**步骤 A: 启用 WSL 2**
```powershell
# PowerShell(管理员)
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
wsl --set-default-version 2
```
重启电脑。

**步骤 B: 安装 Docker Desktop**
1. 访问 https://www.docker.com/products/docker-desktop/
2. 下载 **Docker Desktop for Windows**(约 1 GB)
3. 双击 `Docker Desktop Installer.exe`
4. 安装选项勾选 **Use WSL 2 instead of Hyper-V**
5. 启动 Docker Desktop(右下角系统托盘出现鲸鱼图标 = 成功)

#### 3.1.1 特例：Win10 build 19044 装不了当前 Docker Desktop（2026-10-29）

本机实测 Windows 10 Pro 21H2 **build 10.0.19044**。Docker Desktop 4.49 起要求
**Win10 build 19045（22H2）**，19044 上装当前版本起不来；能装的只剩停更的旧版。

结论：**不用 Docker Desktop，直接在 WSL2 里装 Docker Engine（含 compose 插件）**。
构建链只需要 `docker compose build/run`，与 Desktop 无关。步骤：

```powershell
# 管理员 PowerShell（本机这两条已执行成功，/norestart = 等重启生效）
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
```

重启之后：
```bash
wsl --update
wsl --install -d Ubuntu            # 起一个发行版并设好用户
# 进入 Ubuntu 后按 Docker 官方 apt 源装 engine（jammy 用 docker-ce 源，
#   不要用 Ubuntu 自带的 docker.io 旧包 —— 它没有 compose v2 插件）：
#   https://docs.docker.com/engine/install/ubuntu/
#   包清单: docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
# 装完: sudo usermod -aG docker "$USER"（重开 shell 生效）, docker compose version 自检
```

之后照第 6 节在 WSL 里 `cd /mnt/d/build_docker/app && docker compose build android-builder`。
注意：WSL 里的 Docker 是**宿主机 WSL 内部**的 daemon，Windows 侧的 `build_apk.bat` 不走它。

#### 3.1.2 实测落地：WSL2 + Docker Engine 全流程（2026-10-30 已跑通）

上面那段是计划，这一节是**实际执行过的命令与量到的时间**，以后照这一节做。

**结果**：镜像与出包全部跑通，一次出包冷启动 ≈ 22 分钟；环境脚本全部入库在 `app/tools/`。

| 步骤 | 命令（Windows PowerShell / Git Bash） | 实测耗时 |
|---|---|---|
| WSL 内核 | `wsl --update` | 1 min（本机装出 WSL 3.0.1.0 / kernel 6.18.40.1） |
| 发行版 | `wsl --install -d Ubuntu-22.04 --no-launch` | ≈ 4 min 下载 |
| systemd | 写 `/etc/wsl.conf` 的 `[boot] systemd=true` → `wsl --shutdown` | — |
| Docker Engine | `bash /mnt/d/build_docker/app/tools/wsl_docker_setup.sh` | ≈ 3 min（Docker 29.9.2 + Compose v5.6.1 + containerd 2.4.2，storage=overlayfs） |
| 镜像 | `docker compose -f docker-compose.yml -f docker-compose.wsl.yml build android-builder` | **≈ 50 min（一次性）** |
| 出包 | `bash tools/wsl_build_apk.sh release arm64-v8a` | **冷 ≈ 22 min / 增量 ≈ 15–20 min** |

出包耗时拆解（0.0.3 那次）：STAGE 2 C++ 编译 12m14s → STAGE 3 androiddeployqt 14s +
gradle assembleRelease 9m09s → STAGE 4 校验与落盘 ≈ 1min。

三个必须知道的坑：

1. **`/project/build` 必须挂卷，不能在 9P 上。** `/mnt/d/...` 走 drvfs，Ninja 与 Gradle 的
   小文件 I/O 会慢到不可接受。`docker-compose.wsl.yml` 用命名卷 `android-build` 覆盖
   `build/`（合并后的 volumes 是 `ccache-cache` + `android-build` + `gradle-cache`）。
   副作用：`build/build_<type>_<abi>.log` 落在卷里，出包后必须复制回 `dist/` ——
   `wsl_build_apk.sh` 第 [3/3] 步已经在做（连同 `.log.gradle`）。
2. **Windows → WSL 不要用 `bash -c "…$()…"`。** Git Bash 会吃掉 `$var`、`$( )`、`{http_code}`，
   表现是探针输出空白、awk 语法错、`docker stop` 返回 15。所有多变量逻辑一律写成仓库里的
   脚本文件，再 `wsl.exe -d Ubuntu-22.04 -u root -- bash <脚本路径>`（前置 `export MSYS_NO_PATHCONV=1`）。
   要停构建用 `bash tools/wsl_stop_build.sh`，不要在命令行里嵌套。
3. **构建进行中绝不编辑 `build_apk.sh`。** bash 是按字节偏移回到同一个文件继续读的，
   中途改动会让它在错位处接着解析：0.0.2 那次就是「APK 已生成」之后报
   `line 1514: syntax error near unexpected token '2026-10-21'`（rc=2），STAGE 4 整段没跑。
   改脚本要等本轮出包结束，或先把容器停掉。

另：`wsl.exe` 的管理类输出（`--list`、`--status`）是 UTF-16LE，Linux 侧命令输出是 UTF-8，
不要对整条管道无脑 `iconv`，否则中文全成乱码。

### 3.2 macOS

```bash
# 方法 1: Homebrew(推荐)
brew install --cask docker
open /Applications/Docker.app

# 方法 2: 官网下载
# https://www.docker.com/products/docker-desktop/
# 拖入 Applications
```

### 3.3 Linux (Ubuntu/Debian)

```bash
# 卸载旧版
sudo apt-get remove docker docker-engine docker.io containerd runc

# 安装依赖
sudo apt-get update
sudo apt-get install ca-certificates curl gnupg lsb-release

# 添加 Docker 官方 GPG key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# 设置仓库
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 安装
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 添加当前用户到 docker 组(免 sudo)
sudo usermod -aG docker $USER
newgrp docker
```

---

## 4. 验证 Docker

```bash
docker --version
# 预期:Docker version 24.0.7, build ...

docker compose version
# 预期:Docker Compose version v2.x.x

docker run hello-world
# 预期:打印 "Hello from Docker!" 验证成功
```

**没成功?**
- Windows: 重启 Docker Desktop,确保 WSL 2 已启用
- Linux: 检查 `sudo systemctl status docker`
- macOS: Docker.app 需保持运行

---

## 5. 拉取项目代码

```bash
# 选择目录
mkdir -p ~/outdoor-survival && cd ~/outdoor-survival

# 假设代码在 H:\AI_Claude\work_dir\app
# 复制整个 app 目录到当前路径(根据你的实际情况)

# 验证项目结构
ls
# 应该看到:CMakeLists.txt, src/, qml/, assets/, android/, build_apk.sh, Dockerfile.android, docker-compose.yml
```

**关键文件清单**:
```
app/
├── CMakeLists.txt              # CMake 构建配置
├── Dockerfile.android          # Docker 镜像定义
├── docker-compose.yml          # Docker Compose 配置
├── build_apk.sh                # 一键打包脚本
├── src/                         # C++ 源码
├── qml/                         # QML 源码
├── assets/data/                 # 数据 JSON
├── android/                     # Android 资源
└── keystore/                    # 签名密钥(首次构建生成)
```

---

## 6. 构建 Docker 镜像

镜像包含:Ubuntu 22.04 + OpenJDK 17 + Android SDK/NDK 26 + Qt 6.7.2 + CMake + Ninja + ccache + 所有依赖。

```bash
cd app  # 进入项目根目录

# 首次构建(耗时 30-60 分钟,下载 Qt 6.7+ Android SDK)
docker compose build android-builder

# 看到以下输出表示成功:
# => [android-builder 9/9] CMD ["/bin/bash"]
# => => naming to docker.io/library/outdoor-survival-android-builder:latest
# Successfully tagged outdoor-survival-android-builder:latest
```

**镜像大小**: 约 8-10 GB(包含 Qt + Android SDK + NDK + 工具链 + ccache)。

**持久化缓存卷**(首次 `docker compose run` 后自动创建):
- `gradle-cache` → `/root/.gradle`:Gradle 依赖 + Daemon 状态
- `ccache-cache` → `/root/.ccache`:C++ 编译缓存(2GB 上限,启用压缩),跨容器复用

**后续增量构建**(秒级):
```bash
# 修改 Dockerfile 后
docker compose build --no-cache android-builder
```

**WSL 里要叠 override 文件**（否则 `build/` 落在 9P 上，见 §3.1.2 第 1 条）：
```bash
cd /mnt/d/build_docker/app
docker compose -f docker-compose.yml -f docker-compose.wsl.yml build android-builder
```

**`.dockerignore` 是构建时间的第一大头（2026-10-30 实测）。** `Dockerfile.android` 最后一层是
`COPY . /project/`，它会把整个 context 重传一遍并导出成一个新层。之前 `build/`、`dist/`、
`photo/`、`*.log` 全在 context 里，**1.3 GB**，光这一层的 export 就 ≈ 10 分钟 —— 而这层对
运行时毫无意义（`docker-compose.yml` 已经把宿主目录 `:/project` 挂上了，容器读的是挂载）。
现在 `.dockerignore` 加了 `build/ build-host/ android-build/ dist/ photo/ *.log keystore/`
（最后一项顺手把签名库挡在镜像外）。

> **不要把 `*.zip` 加进 `.dockerignore`。** `tools/qtquick3d-6.7.2.zip` 与
> `tools/qtquick3d-assimp-5.4.1.zip` 是镜像构建时 `COPY` 进去的源码包，挡掉它们等于挡掉
> qtquick3d 那一段，构建直接失败。

**收口脚本（Windows 侧一条命令做完上面全部）**：`bash tools/wsl_build_apk.sh [release] [arm64-v8a]`
—— [1/3] 镜像（已存在则跳过，`FORCE_IMAGE=1` 强制重建）→ [2/3] `compose run` 跑
`build_apk.sh`（`BUILD_JOBS` 默认 6，因为本机 WSL 只分到 7.6 GB 内存）→ [3/3] 把命名卷里的
`build_<type>_<abi>.log` 与 `.log.gradle` 复制回 `dist/` 并回显退出码。
配套的 `tools/wsl_stop_build.sh` 用来中止（杀 wrapper + 停运行中的容器）。

---

## 7. 运行构建容器

```bash
# 进入容器,启动交互式 shell
docker compose run --rm android-builder bash

# 验证容器内环境
java -version
# openjdk version "17.0.x"

cmake --version
# cmake version 3.22.1

ls $ANDROID_NDK_HOME
# source.properties  CMakeLists  meta  ...

ls $QT_PATH/bin
# qmake6  qmake6.7.2  qml  qmlformat  qmlscene  ...
```

**目录映射**:
- 主机 `./` → 容器 `/project`
- 主机 `./dist` → 容器 `/project/dist`(APK 输出)
- Gradle 缓存 → Docker volume `gradle-cache`(持久化)
- ccache 缓存 → Docker volume `ccache-cache`(持久化,C++ 增量编译加速)

---

## 8. 编译项目

`build_apk.sh` 已自动处理 CMake 配置 + 编译,通常无需手动执行下面的命令。如需手动调试:

在容器内:

```bash
cd /project

# 创建构建目录
mkdir -p build && cd build

# CMake 配置(Qt + Android NDK)
cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DCMAKE_PREFIX_PATH=$QT_PATH \
  -G Ninja

# 编译(使用全部 CPU 核, 可用 BUILD_JOBS=N 覆盖)
ninja -j$(nproc)
```

**关键特性**(`build_apk.sh` 已默认启用):
- **并行编译**: `-j$(nproc)`(可用 `BUILD_JOBS=4` 限制)
- **ccache 加速**: `CMAKE_CXX_COMPILER_LAUNCHER=ccache`,缓存跨容器复用
- **增量编译**: 保留 `CMakeCache.txt`,仅重编变更文件;`CLEAN=1` 强制全量重建

**单 ABI 时间**:
- 首次全量: 10-30 秒(并行 + ccache 预热后)
- 二次增量: 5-10 秒(仅重编变更的 cpp)

---

## 9. 打包 APK

用项目自带的 `build_apk.sh` 脚本,自动完成编译+打包+签名:

```bash
# 仍在容器内
cd /project

# 打包 release 版 arm64-v8a(默认,推荐)
bash build_apk.sh release arm64-v8a

# 同时打 3 个 ABI
bash build_apk.sh release all
```

**环境变量**(可选,覆盖默认行为):

| 变量 | 默认 | 作用 |
|---|---|---|
| `CLEAN=1` | 未设 | 强制清理 CMake 缓存,全量重建 |
| `BUILD_JOBS=N` | `$(nproc)` | 限制并行编译数(CPU 紧张时用) |
| `VERSION=x.y.z` | 未设 | 指定本次包版本号（`versionCode` 仍然 +1） |
| `VERSION_BUMP=0` | 未设 | 本次不动版本号 —— **测试包（模拟器/x86_64）必带**，否则白占一个发布号 |

```bash
# 强制全量重建(清理 CMake 缓存)
CLEAN=1 bash build_apk.sh release arm64-v8a

# 限制 4 核并行
BUILD_JOBS=4 bash build_apk.sh release arm64-v8a
```

**版本号：每次出包自动 +1（2026-10-30 起，脚本代劳，不再手工对齐）。**
用户口径是「每一次出包自动版本号 +1，例如 0.0.2 升级到 0.0.3」。落法是
`build_apk.sh` STAGE 1 里的一段（`assert_file "$KEYSTORE_PATH"` 之后）：

- **单一真源**仍是 `CMakeLists.txt` 的 `project(... VERSION x.y.z)` + `set(APP_VERSION_CODE N)`；
  脚本从这两处解析当前值，默认 patch +1、code +1。
- `apply_version()` 一次写齐**四处**：`CMakeLists.txt`（VERSION + APP_VERSION_CODE）、
  `android/AndroidManifest.xml`（`versionName`/`versionCode`）、`android/app/build.gradle`
  （`versionName`/`versionCode`）。写完后 6 条 `grep` 后置断言逐项核对，对不上就 `exit 1`。
- `sed` 的范围必须锁死在 `/^project(/,/^\)/`：`CMakeLists.txt:336` 还有一行
  `qt_add_qml_module(... VERSION 1.0)`，不限范围会被一起改掉（写这条断言时踩到的，
  已加**反向**断言：`VERSION 1.0` 必须还在）。裸 `)` 在 ERE 里是分组，要写 `/^\)/`。
- **失败自动回滚**：`trap restore_version_on_exit EXIT` + `APK_DONE` 标志。`set -e`、`die()`、
  裸 `exit` 三条路径都会把四处版本号恢复原值；只有 APK 已复制进 `dist/` 之后才允许留新版本，
  否则会出现「号涨了、包没出」这种更难受的状态。
- **产物再校验**：STAGE 4 用 `$ANDROID_SDK/build-tools/34.0.0/aapt dump badging` 把**成品 APK**
  的 `versionName`/`versionCode` 与本次目标值比对，不一致直接 `exit 1` 且**不落 `dist/`**。
  以前只能靠人肉对账（见下面 2026-10-26 那段），现在脚本自己拦。

三个开关：`VERSION=1.2.3` 指定号（code 仍 +1）；`VERSION_BUMP=0` 本轮完全不动号
（**模拟器/测试包必带**，测试包不该消耗发布号）；都不给就是默认 +1。

以下这一段保留原文，是这套自动化的由来，也是历史上真实出过的事故：

**输出位置**：`app/dist/`（不是仓库上级 `D:/build_docker/dist/`，那个目录不存在）。
文件名里的版本号由 `build_apk.sh` 末尾从 `CMakeLists.txt` 的 `project(... VERSION x.y.z)`
解析，不是环境变量 —— 2026-10-30 之前还要手工同步另外两份，现在四处由上面的
自动 +1 一次写齐。

> **2026-10-26 踩到的解析坑（已修）**：本项目 `project()` 是**多行**写法，`VERSION 0.0.2`
> 独占一行，而脚本原来用 `grep -m1 "^project(" CMakeLists.txt | grep -oE 'VERSION …'`
> —— 第一层只取到 `project(OutdoorSurvival` 那一行，第二层永远匹配不到，于是落到
> `[ -z "$APP_VERSION_STR" ] && APP_VERSION_STR="0.0.1"` 的兜底。结果：**包内**
> `aapt2 dump badging` 是 `versionCode='2' versionName='0.0.2'`（gradle 那份是对的），
> **包名**却一直写 `v0.0.1`，四阶段全绿、日志零 error，没有任何一行提示版本对不上。
> 现在改成 `awk '/^project\(/{f=1} f{print} f&&/\)/{f=0}'` 取整块再解析，**解析不到就
> `log_error` + `exit 1`**，不许用兜底版本号出包 —— 包名写错比出不了包更难查。
>
> 版本号在仓库里是**四份副本**：`CMakeLists.txt`（`project VERSION` + `APP_VERSION_CODE`）、
> `android/app/build.gradle`、`android/AndroidManifest.xml`、`tests/CMakeLists.txt`。
> 2026-10-30 起前三份由 `build_apk.sh` 的自动 +1 一次写齐并逐项 grep 核对，**第四份
> （`tests/CMakeLists.txt:7 project(OutdoorSurvivalTests VERSION …)`）不参与打包，
> 只在 unit-test profile 里用，仍会落后一位，不用管它**。发版后仍建议跑一遍对账：
>
> ```bash
> /opt/android-sdk/build-tools/34.0.0/aapt2 dump badging dist/<apk> | head -1
> # 期望 package: name='com.outdoor.survival' versionCode='3' versionName='0.0.3'
> # 且 versionName 与文件名里的 v<x.y.z> 一致 —— 不一致就是自动 +1 那条链断了
> # （STAGE 4 现在自己会比这一项，不一致直接 exit 1 且不落 dist/）
> ```
>
> 另外两处会被用户拿走的产物也带版本号：GPX 导出的 `creator` 属性（现取
> `"OutdoorSurvival " APP_VERSION`，以前写死 0.0.1），以及 `App::version()` /
> `QCoreApplication::setApplicationVersion()`（这两个走宏，自动跟着 `PROJECT_VERSION`）。

```
app/dist/
└── OutdoorSurvival-v0.0.2-release-arm64-v8a.apk     # 当前版本 0.0.2 / versionCode 2
```

**一次只能出一个 ABI**：`build_apk.sh` 的 ABI 参数只接 `arm64-v8a`（默认）/
`armeabi-v7a` / `x86_64` 之一，脚本头部注释里写的"all"**没有实现**，传未知值直接 case 报错。
更关键的是：镜像里 Qt 6.7.2 只装了 `android_arm64_v8a` 与 `android_x86_64` 两个 kit，
**没有 `android_armv7`**，所以 `armeabi-v7a` 已经在 `build_apk.sh:206-213` 被显式拦掉——
走到那个 case 分支就 `log_error "armeabi-v7a 不再支持: 构建镜像里没有 android_armv7 这个 Qt kit
(只出 arm64-v8a / x86_64)"` + `exit 1`，不会再把后面 CMake 的一串配置跑完才失败。
以前它指向 `$QT_BASE/android_armv7`，一路撞到 `Qt Android 包未找到` 才停，让人误判整个环境坏了。
旧版文档把三个 ABI 的产物并列列出，那个 `armeabi-v7a` 在现网是拿不到的。

> **2026-10-29 交付口径：只出 arm64-v8a。** 用户指定交付机型是 arm64，其他包不再出。
> `Dockerfile.android` 里 `android_x86_64` 的 kit 安装与 qtquick3d 的 x86_64 源码编译已
> **注释掉**（不是删除，附录里留了解释），镜像里实际只剩 `gcc_64` + `android_arm64_v8a`；
> 构建时间与镜像体积因此少一大块。随之而来的两个后果要记住：
> ① 用 x86_64 模拟器验证这条路**走不通**（模拟器跑不了 arm64 原生库），验证只剩真机；
> ② 要恢复 x86_64 包，先放开 Dockerfile 那两段并重建镜像，再把交付口径改回来。

**必须在 `app/` 目录下跑 `docker compose`**：`docker-compose.yml` 只在 `app/` 里，
从上级 `D:/build_docker/` 跑会瞬间 `no configuration file provided: not found`。
Git Bash 还会把 `/project/...` 这类容器内绝对路径改写成 `C:/Program Files/Git/project/...`
（容器里 CMake 直接报 source directory does not exist）—— 给 `compose run` 传容器内路径时
必须加 `MSYS_NO_PATHCONV=1`，或者干脆不传参数、靠脚本自己的默认值。
同理，`bash build_apk.sh` **不能在主机 shell 里直接跑**：它一上来就会报
`[ERROR] FATAL [STAGE 1]: Android NDK 不存在: /opt/android-sdk/ndk/...`，
那句报错的真实含义是"忘了在容器里跑"。

**退出码 0 不等于出包成功 —— 有两层会骗人。** 判定一轮构建只看三样，缺一不报喜：

1. 日志里没有 `error:` / `FATAL` 行，并且能 grep 到这三条收口行：
   `APK 签名验证通过` / `.so=` 数量 / `APK 自检全部通过`；
2. `app/dist/*.apk` 的**体积与 mtime 真的动了**（跟上一轮比）；
3. 上面两条都成立之后，退出码才有意义。

> 2026-10-23 实测踩过：一个后台构建任务上报 "completed (exit code 0)"，而它自己的日志末尾
> 写着 `[ERROR] FATAL [STAGE 2]: C++ 编译 (Ninja) 失败 (rc=2)`。反过来也踩过：收尾用
> `grep -c "FATAL\|error:"` 当最后一句，`grep -c` 在计数为 0 时**退出码是 1**，于是成功的那
> 趟被报成 "failed with exit code 1"。两个方向的 rc 都不能单独作判据，看日志尾部 + `ls -la app/dist/`。
> 最省事的写法：把出包命令和判据写在同一条后台命令里，例如
> `... bash build_apk.sh release arm64-v8a > /tmp/b.log 2>&1; tail -20 /tmp/b.log; ls -la dist/`。

**APK 大小**: 约 30-50 MB(Qt 运行时 + 应用代码 + 资源)。arm64 release 实测 ≈ 49.9 MB。
体积**不能**用来验证"某个 Qt 组件删掉了没有"：`build_apk.sh` 会把整个 Qt kit 的
`libQt6*.so` 无差别拷进 jniLibs，删掉 `find_package` 依赖只是让主二进制不再链它、运行时不再
dlopen 它。要看真凭据查 `build/release_arm64-v8a/CMakeFiles/OutdoorSurvival.dir/link.txt`。

---

## 10. APK 签名

`build_apk.sh` 已自动调用 `apksigner`,**默认使用 v1+v2+v3 三重签名**。

**首次运行需生成 keystore**(脚本会自动做):

```bash
# 在容器内
ls keystore/
# outdoor.keystore

# 签名信息
keytool -list -v -keystore keystore/outdoor.keystore -storepass outdoor123
# 别名: outdoor
# 有效期: 10000 天
```

**正式发布前请更换 keystore**:
```bash
# 生成新的 keystore
keytool -genkey -v \
  -keystore my-release-key.keystore \
  -alias outdoor \
  -keyalg RSA -keysize 2048 \
  -validity 10000

# 移动到项目
mv my-release-key.keystore app/keystore/outdoor.keystore
```

**⚠️ 务必备份好 keystore**,丢失后旧 APK 无法升级。

---

## 11. 验证 APK

```bash
# 验证签名
apksigner verify --verbose dist/OutdoorSurvival-v0.0.2-release-arm64-v8a.apk
# 预期: Verifies ... v1, v2, v3

# 查看 APK 信息
aapt2 dump badging dist/OutdoorSurvival-v0.0.2-release-arm64-v8a.apk
# 预期: package: name='com.outdoor.survival' versionCode=2 versionName='0.0.2'

# 看 APK 内容
unzip -l dist/OutdoorSurvival-v0.0.2-release-arm64-v8a.apk | head -20
```

---

## 12. 设备安装

### 12.1 启用 USB 调试

手机/平板 **设置 → 关于手机 → 连续点击 7 次"版本号"** → 开启"开发者模式"。

**设置 → 系统 → 开发者选项 → USB 调试** 打开。

### 12.2 连接与验证

```bash
# 连接 USB,验证设备
adb devices
# 预期: <serial>  device

# 卸载旧版(若有)
adb uninstall com.outdoor.survival

# 安装
adb install dist/OutdoorSurvival-v0.0.2-release-arm64-v8a.apk
# 预期: Success
```

### 12.3 启动与日志

```bash
# 启动应用(Qt 6 的 Activity 是 org.qtproject.qt.android.bindings.QtActivity)
adb shell am start -n com.outdoor.survival/org.qtproject.qt.android.bindings.QtActivity

# 实时日志
adb logcat -s OutdoorSurvival:V

# 完整抓取
adb logcat > adb_log.txt
```

> **注意**: 不要用 `com.outdoor.survival/.QtActivity` 启动 —— 清单中 Activity 名是全限定名 `org.qtproject.qt.android.bindings.QtActivity`,不是简写 `.QtActivity`(简写会被解析为 `com.outdoor.survival.QtActivity`,报 `Activity class does not exist`)。

### 12.4 卸载

```bash
adb uninstall com.outdoor.survival
```

---

## 13. 常见问题

### Q1. Docker 镜像构建失败(下载 Qt 超时)

**解决**:
- 重试 `docker compose build --no-cache android-builder`
- 检查网络能否访问 https://download.qt.io
- 必要时使用代理: `docker build --build-arg HTTP_PROXY=http://127.0.0.1:7890 .`

### Q2. Gradle 构建报 `OutOfMemoryError`

**解决**:
- `docker run` 时加 `-e GRADLE_OPTS="-Xmx4g"`
- 主机内存 < 16GB 时,关闭其他应用

### Q3. APK 安装时 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`

**解决**:
```bash
adb uninstall com.outdoor.survival
# 再重新 install
```

### Q4. APK 安装时 `INSTALL_PARSE_FAILED_NO_CERTIFICATES`

签名失败。重新生成 keystore,执行 `build_apk.sh release`。

### Q5. 应用启动后白屏 / 崩溃

```bash
# 查看崩溃日志
adb logcat *:E

# 常见原因:
# 1. 资源文件未打包 → 检查 qml.qrc 是否有 assets/data/
# 2. 数据格式错误 → 用 JSON 工具验证
# 3. Qt 库未链接 → 检查 CMakeLists.txt
```

### Q6. 高德/天地图底图加载失败

- 检查网络(应用首次启动需联网下载底图)
- 容器内生产 APK 时确认 Qt Network 模块已编译

### Q7. Docker 占用磁盘太多

```bash
# 清理未使用的镜像/容器
docker system prune -a

# 单独删除构建缓存
docker builder prune
```

### Q8. Windows 下文件路径问题

项目路径**不要**放在 `C:\Users\<用户>\` 下(权限+空格问题),建议 `D:\outdoor-survival\` 这种简单路径。

### Q9. 重新生成 keystore 签名后旧 APK 无法升级

**这是预期行为**。Android 安全机制:同包名+不同签名=无法覆盖安装。必须:
- 用 `adb uninstall` 卸载旧版
- 或用同包名同签名的 keystore

### Q10. 报错 `Could not find Qt6Config.cmake`

- 容器内 `echo $QT_PATH` 确认是 `/opt/Qt/6.7.2`
- 若不对,重新 `docker compose build --no-cache`

### Q11. APK 安装后包名是 `org.qtproject.example.OutdoorSurvival`(应为 `com.outdoor.survival`)

**根因**: `androiddeployqt` 生成的 `AndroidManifest.xml`(根目录)和 `app/build.gradle` 是 Qt 默认模板,没被项目里的覆盖。

**解决**:
- 确认 `build_apk.sh` 后处理步骤生效(日志应出现 `用项目 AndroidManifest 覆盖 .../android-build/AndroidManifest.xml` 和 `用项目 app/build.gradle 覆盖 .../app/build.gradle`)
- 确认 `build_apk.sh` 的 `DEPLOY_ARGS` **不带 `--gradle`**(否则 androiddeployqt 会在覆盖前调 gradle,用 Qt 模板构建)
- 卸载旧 APK 后重装:`adb uninstall org.qtproject.example.OutdoorSurvival`

### Q12. Gradle 报 `repository 'Google'/'maven' was added by build file/initialization script`

**根因**: Gradle 8.x 在 `settings.gradle` 设了 `FAIL_ON_PROJECT_REPOS`,禁止任何项目级仓库(含 init 脚本)。

**解决**:
- 仓库只能写在 `android/settings.gradle` 的 `pluginManagement.repositories` 和 `dependencyResolutionManagement.repositories`(已配阿里云镜像)
- 顶层 `android/build.gradle` **不能**写 `buildscript.repositories` 或 `allprojects.repositories`
- 容器内 `~/.gradle/init.d/aliyun-mirror.gradle` 只保留 `allprojects.buildscript.repositories`(buildscript 不受 `repositoriesMode` 限制)

### Q13. `adb shell am start` 报 `Activity class {com.outdoor.survival/com.outdoor.survival.QtActivity} does not exist`

**根因**: Activity 名写错。清单里 Activity 是全限定名 `org.qtproject.qt.android.bindings.QtActivity`,简写 `.QtActivity` 会被解析为 `com.outdoor.survival.QtActivity`(不存在)。

**解决**:
```bash
# 正确启动命令
adb shell am start -n com.outdoor.survival/org.qtproject.qt.android.bindings.QtActivity
```

### Q14. `docker build` 报 `WrapQuick3DAssimp::WrapQuick3DAssimp target was not found` 或 `ioapi.c: undeclarated function 'fopen64'`

**根因**: Dockerfile.android 第 12 步编译 qtquick3d 源码时, 启用 `-DQT_FEATURE_system_assimp=ON` 走 apt 装的 `libassimp-dev`, 在 cross-compile + qt-cmake 包装下 `assimp::assimp` IMPORTED target 创建不稳; 即使切到 `system_assimp=OFF`, assimp 5.4.1 的 `contrib/unzip/ioapi.c` 又用了 bionic libc 不提供的 `fopen64/ftello64/fseeko64`。

**完整排查与修复**: 见 [09-讨论记录/06-qtquick3d-assimp构建修复.md](../09-讨论记录/06-qtquick3d-assimp构建修复.md)

**快速验证** (2026-09-10 已修复版 Dockerfile):
```bash
# Dockerfile 改动点:
# 1. 预置 qtquick3d-assimp-5.4.1.zip (摆进 3rdparty/assimp/src/)
# 2. -DQT_FEATURE_system_assimp=OFF (走 vendored 路径)
# 3. sed 注入 IOAPI_NO_64 + 改 ftello→ftell / fseeko→fseek (bionic 兼容)
# 4. 注释 armv7 块 (项目只产 arm64-v8a)
docker build -f Dockerfile.android -t app-build . 2>&1 | tee build.txt
```

如果**不是上述 4 个根因**(比如修改了 Qt 版本、换 NDK 版本、换了 host 系统), 需要先查 `build.txt` 看具体错误步号和报错文件, 再回到讨论记录文档定位修复方案。

---

## 附录 A: 完整命令速查

```bash
# 完整流程(假设已经在 app/ 目录)
docker compose build android-builder
docker compose run --rm android-builder bash

# 在容器内:
cd /project
mkdir -p build && cd build
cmake .. -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake -DANDROID_ABI=arm64-v8a -DCMAKE_PREFIX_PATH=$QT_PATH -G Ninja
ninja -j$(nproc)
cd /project
bash build_apk.sh release all

# 退出容器
exit

# 主机查看
ls dist/

# 安装
adb install dist/OutdoorSurvival-v0.0.2-release-arm64-v8a.apk
```

**从主机一键构建**(无需进容器):
```bash
# 增量构建(默认)
docker compose run --rm android-builder bash -c "cd /project && bash build_apk.sh release arm64-v8a"

# 强制全量重建(清理 CMake 缓存)
docker compose run --rm android-builder bash -c "cd /project && CLEAN=1 bash build_apk.sh release arm64-v8a"

# 限制并行编译数(CPU 紧张时)
docker compose run --rm android-builder bash -c "cd /project && BUILD_JOBS=4 bash build_apk.sh release arm64-v8a"

# 启动应用(注意 Activity 是全限定名)
adb shell am start -n com.outdoor.survival/org.qtproject.qt.android.bindings.QtActivity
```

---

## 附录 B: 文件对应

| 用途 | 文件 |
|---|---|
| Docker 镜像定义 | [Dockerfile.android](../../Dockerfile.android) |
| Docker Compose | [docker-compose.yml](../../docker-compose.yml) |
| 构建脚本 | [build_apk.sh](../../build_apk.sh) |
| 旧版手册(供参考) | [APK构建与反馈指南.md](APK构建与反馈指南.md) |
| 工程规范 | [05-工程规范手册](../05-工程规范/工程规范手册.md) |

---

## 附录 C: 时间预估

| 阶段 | 首次 | 二次构建(增量) |
|---|---|---|
| 镜像下载 + 构建 | 30-60 分钟 | 缓存复用,5-10 分钟 |
| CMake 配置 | 1-2 分钟 | <2 秒(缓存命中) |
| C++ 编译(arm64) | 10-30 秒(并行 + ccache) | 5-10 秒(增量 + ccache) |
| Gradle 依赖 | 已缓存 | 已缓存 |
| APK 打包 + 签名 | 1-2 分钟 | 1-2 分钟 |
| **总计(首次)** | **45-90 分钟** | **2-5 分钟** |

> **加速关键**:
> - C++ 并行编译(`-j$(nproc)`)+ ccache(跨容器复用)
> - 增量编译(保留 `CMakeCache.txt`,只重编变更文件)
> - Gradle 缓存持久化(`gradle-cache` 卷)
> - 首次跑前必须 `docker compose build android-builder` 安装 ccache

---

## 附录 D: 推荐环境

| 组件 | 推荐 |
|---|---|
| 主机 | 16 GB 内存 + 256 GB SSD |
| OS | Windows 11 + WSL 2 / macOS 13+ / Ubuntu 22.04 |
| Docker | 24.0+ |
| 镜像 | outdoor-survival-android-builder:latest(8-10 GB) |
| 工具链 | Qt 6.7.2 / Android NDK r26b / OpenJDK 17 / CMake 3.22.1 / Ninja 1.11 / ccache 4.x |

---

**文档维护**: [doc/07-部署与发布/Docker构建APK手册.md](Docker构建APK手册.md)
**最后更新**: 2026-10-29(新增 §3.1.1 Win10 19044 装不了当前 Docker Desktop → WSL2 内装
Docker Engine 的具体路径; §9 补交付口径"只出 arm64-v8a"与 `Dockerfile.android` 注释 x86_64 kit 的后果。
上一轮 2026-09-10: Q14 新增 qtquick3d-assimp 编译失败条目, 详见
[09-讨论记录/06-qtquick3d-assimp构建修复.md](../09-讨论记录/06-qtquick3d-assimp构建修复.md))
