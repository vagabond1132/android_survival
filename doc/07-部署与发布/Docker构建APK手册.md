# Docker 构建 APK 完全手册(从安装到装机)

> 适用版本: 荒野手册 v0.0.10（2026-11-05 出包 = 统一修改轮；v0.0.9 = 2026-11-04 / v0.0.7 = 2026-11-03）/ Qt 6.7.2 / Android 7.0+ (API 24+)
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
| 出包 | `bash tools/wsl_build_apk.sh release arm64-v8a` | **冷 ≈ 22 min / 同 ABI 增量 ≈ 11 min / 换 ABI 后首次 ≈ 15 min** |

> ⚠️ **"增量"有个前提：同一个 ABI 连续出**（2026-11-02 实测）。命名卷 `android-build` 里只有
> 一份 `CMakeCache.txt`，上一次出的是 x86_64、这次出 arm64 时 ABI 不符，STAGE 2 会从
> `The CXX compiler identification is Clang 17.0.2` 重新走一遍 configure，增量直接失效 ——
> 0.0.4 那次因此是 **15m2s** 而不是 11 min。在两个 ABI 之间来回试，成本按全冷估更实在。
> 详见 [09-讨论记录/12](../09-讨论记录/12-真机六项反馈与出包口径.md) §4.11。

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

4. **换 ABI 首次出包会死在 STAGE 3，根因是 `--no-build` 不建工程骨架**（2026-11-02 实测）。
   `androiddeployqt --no-build` 的 Qt 6.7 原文语义是 *"Do not build the package, it is useful
   to just install a package previously built"* —— 它只把 `.so` 装进
   `<output>/libs/<abi>/` 就返回，**不创建** `app/src/main/`、`res/values/libs.xml`。
   `build/release_arm64-v8a/android-build/` 里那份骨架是更早某次**完整模式**生成后留在命名卷
   `android-build` 里的，所以 arm64 一直"看起来没问题"；`release_x86_64/` 是新目录，STAGE 3
   后半段每个 `cp` 都撞 `No such file or directory`，退出码 1 且日志只剩一行 cp 报错。
   现在 `build_apk.sh` 的做法：缺 `res/values/libs.xml` 时先用 `--gradle` 完整模式引导一次，
   并把 `gradlew` 临时换成 `exit 1` 的桩 —— androiddeployqt 先写完工程文件、最后才调 gradle，
   桩让它 **≈20 秒**返回（不桩掉的话要付 5m38s 打一个我们并不用的 Qt 模板 debug 包），
   随后预填步骤会用真的 exec-本地-gradle 脚本覆盖这个桩。另外补了三处 `mkdir -p`／播种：
   `app/src/main/`、`app/src/main/java/`、以及把 Qt 写在**根** `res/` 的 `libs.xml` +
   `qtprovider_paths.xml` 播种到 `app/src/main/res/`（AGP 只读 app 模块那份，缺了它 QtLoader
   找不到 `qt_libs` 会启动即闪退）。实测 x86_64 增量出包 **6m37s**（STAGE 2 1m51s +
   STAGE 3 4m38s + STAGE 4 6s）。

5. **`qt_libs` 的「Core 排第一」不能写死 ABI**（2026-11-02 实测，x86_64 包装机即崩）。
   STAGE 3 会按「Qt6Core → 项目主 lib → 其他字母序」重排 `app/src/main/res/values/libs.xml`
   的 `qt_libs`。旧代码第二步判的是 `[ "$lib" = "libQt6Core_arm64-v8a" ]` —— 换 x86_64 时库名
   是 `libQt6Core_x86_64`，**匹配不上就静默不钉位**，Core 掉进字母序变成第 4 个。后果不是
   "顺序不好看"，是**启动必崩**：`Qt6ChartsQml/Charts/Concurrent` 先 `System.load`，链接器把
   Core 当 `DT_NEEDED` 依赖映射进来，而 ART 只对 `System.load` **显式点名**的那个库调
   `JNI_OnLoad` —— Core 那个负责设 `QJniEnvironment::s_javaVM` 的 `JNI_OnLoad` 就此被跳过，
   轮到 Multimedia 的 `JNI_OnLoad` 里 `new QJniEnvironment` 直接空指针：

   ```
   signal 11 (SIGSEGV), Cause: null pointer dereference
     #00 libQt6Core_x86_64.so  QJniEnvironment::getJniEnv()+38
     #02 libQt6Multimedia_x86_64.so  JNI_OnLoad+118
     ...  QtLoader.loadLibraryHelper → QtThread
   ```

   现在改成 `case "$lib" in libQt6Core_*)` 前缀匹配，并且**提到第 1 位**（必须抢在任何依赖
   Core 的库前面，项目主 lib 也要排在 Core 之后），匹配不到就 `die` 而不是静默降级。
   排查这条的入口：`aapt2 dump resources dist/<apk> | awk '/array\/qt_libs/{...}'` 能读到
   **编译进 APK 的真实顺序**，和容器里 `libs.xml` 的源码顺序对照 —— 两者不一致就是 AGP/aapt
   合并层在动它，别看源码猜。同文件另有一处 ABI 写死（NMEA plugin 的 SerialPort 检查）一并
   换成 `$TARGET_ABI`。

6. **ELF 架构校验用十进制比 `0x…` 字符串，会恒假**（2026-11-02 实测，`build_apk.sh` ≈1327 行）。
   `ABI_TRIPLE_MACHINE` 表里写的是 `0xB7` / `0x3e` 这种 16 进制串，而下面取 `e_machine`
   （偏移 18 的 little-endian uint16）用的是 `struct.unpack('<H')`，打出来是**十进制**
   （183 / 62）。`[ "$MACHINE" = "0xB7" ]` 于是永远为假 —— 三段后果：NDK 兜底 `cp` 是死代码、
   两处校验永远走 else、而且**"架构错, 手动覆盖"那条 log 每次出包都在误报**。
   误报比漏报更糟：看日志的人会长期以为包有问题。
   修法是先归一进制再比：`EXPECTED_MACHINE=$(( ${…##*:} ))`（bash 的 `$(( 0xB7 ))` = 183）。
   修完第一次看到真判绿：

   ```
   [查找] libc++_shared.so: …/x86_64-linux-android/libc++_shared.so (machine=62 ✅)
   ✅ AGP 已注入 libc++_shared.so (machine=0x3e), 跳过手动 cp
   ```

   口径：这类"校验"必须**能打出判据值**（`machine=62`），只打 ✅/❌ 的校验等于没校验。

7. **`build_apk.sh` 结尾打印的启动命令里的 activity 名是错的**（2026-11-02，**代码已修**）。
   它写 `org.qtproject.qt.android.QtActivityBase`，照敲报 `Error type 3`。这个包的入口是
   `com.outdoor.survival/.MainActivity`。查真实入口别猜，问包管理器：

   ```bash
   adb shell cmd package resolve-activity --brief com.outdoor.survival
   ```

   0.0.4 那轮只在文档里记了这条、没动代码，结果 0.0.5 的日志尾部**又原样打了一遍** ——
   "文档记了、代码没改"的坑会自己复发。现在 `build_apk.sh:1916` 改成从刚打好的 APK 读
   `aapt2 dump badging` 的 `launchable-activity`，读不到才退 `$APP_PACKAGE.MainActivity`。
   两个实现细节：容器里 `aapt2` **不在 PATH 上**（`command -v aapt2` 空），必须有
   `ls /opt/android-sdk/build-tools/*/aapt2` 这条 glob 兜底；Windows 侧则是
   `aapt2.exe`，脚本里不能写死可执行名。

   同一段还有个连带的恒假判断：`cmd package resolve-activity --brief` 回的是
   **`包名/.类名` 简写**（`com.outdoor.survival/.MainActivity`），跟 badging 的全限定名
   不是一个形状，直接 `[ "$ACTIVITY_INFO" = "$APP_PACKAGE/$APP_ACTIVITY" ]` 永远不相等，
   于是这段"等 activity 注册"的轮询每次都白等满 15 秒再报超时。修法是把简写先展开成
   全限定名再比。**判据**：轮询日志出现 `✅ activity 已注册 (waited 0~2s)` 才是真的通，
   出现"注册超时"而 `pm path` 又非空，先怀疑字符串形状而不是设备。

8. **`$?` 在 `Windows → wsl.exe → docker exec` 这一串里会被提前展开，读到的不是容器的码**
   （2026-11-03 #46 实测，并且**由这条误读倒推出过一个假结论**）。命令串里写
   `… ; echo rc=\$?`，转发到容器时已经变成 `echo rc=\0` —— 于是 `qml_load_check.sh` 明明
   `exit 1`（树里有加载期硬错、真机必白屏），却被读成"这脚本吞了退出码"，差一点把一道
   能抓白屏的门禁判成摆设。两种可用判法，二选一：
   - 不经过 `$?`：`bash tools/qml_load_check.sh > /tmp/x.log 2>&1 && echo GREEN || echo RED`；
   - **把读数写进仓库里的脚本、在容器内跑**（推荐，本轮用的就是这个）：脚本自己
     `bash tools/qml_load_check.sh; RC=$?; echo "load_check_rc=$RC"`，再顺带
     `grep -c` 日志里的 `加载失败` / `组件树加载通过` 做旁证 —— 退出码与关键行两个方向互相印证。
   同一条链上的坑还有两个已经记在册的：`… | tail` 把码盖成 `tail` 的（§18.2），
   `grep -c` 计数为 0 时自己返回 1（本节 §9 开头）。**统一口径：跨这条链只认「脚本自己打印的
   键值行」，不认命令行里内联的 `$?`。**

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

**APK 大小**: arm64 release 在 2026-11-03 之前实测 ≈ 49.9 MB，之后 **≈ 33.5 MB**
（0.0.6 = 35,148,762 B）—— 差的是 §9.1 那套剪枝砍掉的未使用 Qt 库。
体积**不能**单独用来验证"某个 Qt 组件删掉了没有"（见 §9.1 末尾）；要看真凭据查
`build/release_arm64-v8a/CMakeFiles/OutdoorSurvival.dir/link.txt`，以及包里的 `array/qt_libs`。

### 9.1 Qt 库收集：四阶段口径（2026-11-03 改，包体 −30%）

**改之前的行为**：`build_apk.sh` 对 Qt 库是**只加不删** —— androiddeployqt 的输出目录给什么就
拷什么，再按 `import` 补插件、按 DT_NEEDED 补库。**没有一步往外删**，所以两个后果：
① 整个 kit 的 `libQt6*.so`（Designer / Quick3D 全家 / 已删依赖的 Charts / Widgets …）原样进包，
0.0.2～0.0.5 一直是 50 MB；② **增量树只增不减** —— 就算把名单收紧了，上一版遗留的 .so 还躺在
`jniLibs/<abi>/` 里，第一次改完跑 x86_64 时日志"闭包补了 0 个"而 `jniLibs` 仍是 144 个就是这个现象。

**改之后**是一条 `KEEP_SO` 关联数组贯穿四个阶段（都在 STAGE 3，`build_apk.sh`）：

| 阶段 | 动作 | 失败即 die 的条件 |
|---|---|---|
| ① 权威集 | 拷 `androiddeployqt` 输出 `$BUILD_DIR/android-build/libs/<abi>` 下全部 .so，登记进 `KEEP_SO` | 该目录**一个 .so 都没有**（权威集空 = 后面无从判断，不能继续） |
| ② import 反查 | `grep -rhoE "^[[:space:]]*import +[A-Za-z][A-Za-z0-9.]*" qml` 去重，把模块路径逐段解析成 `$QT_QPA/qml/<…>` 目录，其中插件 .so 全部登记进 `KEEP_SO` | 某个 `import Qt…` 在 kit 里**找不到对应模块目录/插件** —— 装上去就是整页白屏 |
| ③ DT_NEEDED 闭包 | **只从 `KEEP_SO` 出发**做传递闭包（`readelf -d`），补 `libQt6*` / `libplugins_*` / `libqml_*` | — |
| ④ 剪枝 + 断言 | 删 `jniLibs/<abi>/` 下不在 `KEEP_SO`、且不在 `libc++_shared.so / libssl_3.so / libcrypto_3.so` 白名单里的 .so；然后断言三件必需库仍在 | 剪完缺 `libQt6Core_<abi>.so` / `libplugins_platforms_qtforandroid_<abi>.so` / 项目主 lib |

三条**必须记住**的口径：

1. **闭包的种子不能是整棵树**。原来是从 `jniLibs/` 里所有 .so 出发求闭包，等于把上一版残留也当
   种子，闭包会把它们需要的库再拉回来，剪枝就永远收敛不了。改成只从 `KEEP_SO` 出发之后，
   同一棵树第二轮报 `剪枝合计: 删 0 个` —— **幂等**，这是剪枝正确的判据。
2. **不信任 androiddeployqt 单一来源**。实测同一份源码、同一段调用，arm64 权威集 **79** 个、
   x86_64 **101** 个，差 22 个；arm64 缺的里面要命的是
   `libqml_QtQuick_Dialogs_qtquickdialogsplugin_<abi>.so` + 它的 `quickimpl` 插件 + QtQuick.Controls
   基座插件，而 `qml/pages/MapPage.qml:23`、`qml/pages/FieldGuideImagePickPage.qml:32` 都写着
   `import QtQuick.Dialogs`。**照① 直接出包 = 地图页整页白屏**，第一个 0.0.6 就是这么坏的。
   ② + ③ 把它补回来（arm64 补 3 个插件、闭包再补 `Qt6QuickDialogs2 / QuickImpl / Utils` 三库）。
   权威集为何随 ABI 变小**尚未查清**；口径是不靠解释、靠并集 + 两道 `die` 兜住 ——
   **宁可出包失败，不出白屏包**。
3. **`libc++_shared.so` / `libssl_3.so` / `libcrypto_3.so` 不参与 `KEEP_SO`**。它们是剪枝之后另外
   拷进来的（OpenSSL 是 Qt Android 的 TLS 运行期 dlopen 后端，`QT_FEATURE_openssl_linked=OFF`，
   DT_NEEDED 里看不见），也**不写进 `qt_libs`**；剪枝必须给它们开白名单，否则 TLS 直接失联。

**实测数字**（都取自当轮日志，别混轮次，见 §12.8 的日志口径）：

| | 权威集 | ②补 | ③补 | ④剪 | `jniLibs` | `qt_libs` | APK |
|---|---|---|---|---|---|---|---|
| x86_64 0.0.5 | 101 | — | 0 | 44 个 / 36 MB | 100 | 97 | 50,966,393 → **37,737,839** |
| arm64 0.0.6 首轮（坏包） | 79 | 无② | 0 | 56 个 / 43 MB | 78 | 75 | 34,527,945（缺 Dialogs，已废弃） |
| arm64 0.0.6 重建 | 79 | 3 | 3 | **0 个** | 84 | 81 | **35,148,762** |
| **arm64 0.0.7**（2026-11-03，含 #42/#45/#46）| 79 | 3 | 3 | **0 个** | 84 | 81 | **35,126,922**（−21.3 KB）|
| **arm64 0.0.9**（2026-11-04，含 #48/#49/#42 第二半；**0.0.8 那一号被并发构建吃掉，见 §12.11**）| 79 | 3 | 3 | **0 个** | 84 | 81 | **35,129,022**（+2.1 KB）|
| **arm64 0.0.10**（2026-11-05 = 统一修改轮，含 L15/L16/L12-src/#55/#43；本轮**只改文案与 QML，没加接口**）| 79 | 3 | 3 | **0 个** | 84 | 81 | **35,141,626**（+12,604 B）|

0.0.10 的库账与 0.0.9 **逐项相同**（79/3/3/0/84/81，`dist/wsl_release_arm64-v8a.log` 03:33:05~03:33:10 那七行），
所以库集合不是本轮体积变化的来源；+12,604 B 落在主 `.so`（本轮实测 **9,241,648 B**）里的 QML 编译字节码与
C++ 字符串表上 —— **这类"只改文案"的轮次，包体只会随文案长度小幅浮动，库数不动**。
`aapt2 dump badging` 独立复核：`versionCode='10' versionName='0.0.10'`、`native-code` 有且仅 `'arm64-v8a'`、
`lib/arm64-v8a/*.so` **84 个**、其他 ABI 0 个；`apksigner verify --print-certs` 证书 SHA-256 与 0.0.6/0.0.7/0.0.9
逐字相同 ⇒ **覆盖装勿卸载**（卸载会连紧急联系人名册与自建清单一起没）。

0.0.7 的库账与 0.0.6 重建轮**逐项相同**（79/3/3/0/84/81，日志同 §9.1 那七行），差的 21.3 KB 是
#41 从六个数据 JSON 里删掉的 `reviewer` 占位符 + 页头去重，**不是**库集合变化 ——
所以这一轮**不必重跑 `reg_sweep` 的库完整性判据**，但页级白屏那一条仍要上真机（见下）。
`aapt2 dump badging` 独立复核：`versionCode='7' versionName='0.0.7'`、
`sdkVersion 24 / targetSdkVersion 34`、**`native-code: 'arm64-v8a'`（有且仅此一项）**；
zip 991 个条目、`lib/arm64-v8a/*.so` 84 个、其他 ABI 目录 0 个；
`apksigner verify --print-certs` 通过，且**证书 SHA-256 与 0.0.6 逐字相同**
（`ae1ceedb…b38c3e`）—— 这条是"能覆盖安装、不会 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`"的真凭据。
⚠️ 主机侧跑 `apksigner.bat` 要给嵌套的 JDK 路径：`JAVA_HOME=D:/build_docker/jdk17/jdk-17.0.20.1+1`
（`D:/build_docker/jdk17` 那层只是解压目录，直接给会报 "JAVA_HOME is set to an invalid directory"）。
⚠️ `array/qt_libs` 用 **aapt2** 只能确认资源存在（`resource 0x7f030002 array/qt_libs`），
`--values` 是 **aapt1** 的口径、build-tools 34 里没 `aapt`；要数条目和顺序就读当轮日志
`qt_libs 包含 81 个 .so (顺序: Qt6Core → 项目主 lib → 其他)` 那一行。
⚠️ **别在 WSL 里对 `/mnt/d` 跑 `find /`**（本轮想找 aapt2 时顺手写了一句，两分钟不返回被迫中止）；
Windows 侧已知路径 `D:/build_docker/android_sdk/build-tools/34.0.0/` 直接调 `.exe`/`.bat` 就行，
9P 上的递归 `find` 是这条路最慢的一种走法。

0.0.6 包里 84 个 .so = 未压缩 75.3 MB / 压缩后 28.3 MB；最大单库是
`libplugins_multimedia_ffmpegmediaplugin_arm64-v8a.so` **15.72 MB**（`QtMultimedia` 摄像头链路真需要，
**不是**裁剪候选），项目主 so 8.81 MB 排第二。

**怎么验剪枝没剪坏**（体积不算证据）：
- 包侧：`aapt dump --values resources dist/<apk>` 里数 `array/qt_libs` 的 `Count=`，
  确认首项 `arm64-v8a;Qt6Core_arm64-v8a`、次项项目主 lib，并 grep 关键插件在不在
  （`plugins_platforms_qtforandroid`、每个 `qml_Qt*_plugin`）；
- 运行侧：`tools/reg_sweep.sh` 跑满（5 根格 5 种画面、WARN/CRIT/FATAL=0、日志增量 >1 KB），
  再**逐个 `import` 的页面走一遍** —— 缺 QML 插件是**页级白屏**，不是启动崩溃，
  只跑根格可能看不到（本轮 ② 之所以重要，就是因为坏包的根格照样能刷出来）。
  **注意模拟器判不了全部**，arm64 真机仍需装机复核。
- ⚠️ `aapt dump --values` 对 array 会打 `<bag>`，**必须连 `Count=` 和 `#N (Key=…)` 一起看**；
  只 `grep -oE "arm64-v8a;…\.so"` 会抓到 0 条（本轮就这么误判过一次"qt_libs 是空的"）。

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
# 启动应用（2026-11-02 校准：以 APK 自己的 badging 为准）
/opt/android-sdk/build-tools/*/aapt2 dump badging app.apk | grep launchable-activity
#   → launchable-activity: name='com.outdoor.survival.MainActivity'
adb shell am start -W -n com.outdoor.survival/.MainActivity

# 实时日志
adb logcat -s OutdoorSurvival:V OutdoorDiag:E

# 完整抓取
adb logcat > adb_log.txt

# App 自己的落盘日志（Logger 链路，见 09-讨论记录/12 §4.13）
adb shell 'ls -t /data/data/com.outdoor.survival/files/logs/app_*.log'
```

> **注意**: 启动入口是清单里注册的 `com.outdoor.survival.MainActivity`（Qt 6 的基类
> `org.qtproject.qt.android.bindings.QtActivity` 是它的父类，不是 launcher entry）。本节
> 原先写的 `.QtActivity` / `QtActivityBase` 两种都点不起来（报 `Activity class does not exist`），
> 真机与模拟器实测均如此 —— `build_apk.sh` 出包尾部那条提示也已改成从 badging 现读，见
> 09-讨论记录/12 §4.15 末段。

### 12.4 卸载

```bash
adb uninstall com.outdoor.survival
```

### 12.5 模拟器全功能走查：`tools/reg_sweep.sh`

改完 UI 想"所有功能都过一遍"，靠人眼逐屏看不可复现，所以有一条脚本化的走查：
Windows 侧 Git Bash + adb 打 x86_64 模拟器，产物落 `tmp_reg/<tag>/`。

```bash
# 用法：bash tools/reg_sweep.sh <tag> ["x y" | "x y 名字" ...]
MSYS_NO_PATHCONV=1 PATH="/d/build_docker/android_sdk/platform-tools:$PATH" \
  bash /d/build_docker/app/tools/reg_sweep.sh 005_paths \
       "540 2210 goto_map" "675 2000 m_track"
```

三条可机读判据（**不是**"截图好看"）：

| 判据 | 期望 | 拦的是什么 |
|---|---|---|
| 走查期间落盘日志里 `WARN/CRIT/FATAL` 的**增量** | 0 | 静默降级（Logger 链路见 12 §4.13） |
| 每一步点击都要**换帧**；5 个根格截出 5 种画面 | 未换帧 0 / 5 种 | "没切页"与"没重绘"必须分开判（12 §4.18） |
| 每张截图体积下限 `MIN_PNG`（默认 40000 B） | 0 张低于 | 黑屏 PNG 压出来 ~22 KB，真渲染 100 KB+ |

两条铁律：

1. **绝不点拨号 / SOS 长按 / 短信发送**。SOS 格只"进页面看一眼"就退回营地格（脚本里是
   `band_sos` 之后紧跟一颗 `band_back`）。这一条只能由用户自己在真机上按。
2. **跑走查时容器里不能有编译**。本机 8 逻辑核，容器一编译模拟器就饿死：实测
   `EGL_emulation app_time_stats: avg=2338ms` + 整屏黑 + 截图 22 KB 全同，看起来像
   "App 白屏 bug"，其实是抢不到 CPU。

退出码：`0` 有效 / `2` 画面没切页 / `3` 疑似黑屏 / `4` 日志增量 < 1 KB（App 没在跑）。
判据的成因与两轮改法记在 09-讨论记录/12 §4.17、§4.18。

### 12.6 定点击坐标：用 `uiautomator dump`，不要扫像素

§12.5 的脚本要的是"给一串坐标点下去"，而**坐标从哪来**这一轮才定下来。扫像素
（PowerShell + System.Drawing 数某行的暗像素）在这台 AVD 上是废的：swiftshader 的撕裂楔形会把
整块区域画花，扫出来的是**伪影的斜边**——想定位一颗按钮，扫到的是一条每行左端点线性右移的边
（y=1628 起 x=692、y=1744 到 x=998），据此定坐标连偏三次（12 §4.19）。

```bash
MSYS_NO_PATHCONV=1 ADB=/d/build_docker/android_sdk/platform-tools/adb.exe
$ADB shell uiautomator dump /sdcard/w.xml >/dev/null
$ADB shell cat /sdcard/w.xml | tr '<' '\n' | grep -a VirtualChild \
  | sed 's/.*content-desc="\([^"]*\)".*bounds="\(\[[0-9,]*\]\[[0-9,]*\)\)".*/\1 \2/'
#   返回 [44,1899][285,1986]
#   写进名册 [688,1627][1006,1747]
```

Qt 6 的 Quick Controls 会把 accessible 名字透出到 Android 无障碍树，`content-desc` 就是 QML 里
的 `text`，`bounds` 是**设备像素**、与 `screencap` 同尺度，取矩形中心即可，第一枪就中。

三个边界必须知道：

1. **`TextField` 不进这棵树**（只有带名字的控件进），所以填输入框仍要估坐标；字段之间跳用
   `adb shell input keyevent 61`（Tab），比每格重新估一次稳。
2. **弹框开着时 dump 到的是 IME 压矮之后**的坐标。这反而是个免费判据：
   `windowSoftInputMode="adjustResize"` 生效与否直接读得出来（同一颗按钮
   y 1627..1747 → 1244..1364），比看截图准。
3. `input text` 打不了中文，中文排版（如⑤联系人名片的换行与截断）在模拟器上判不了，仍等真机。
4. **裸 `Text` 也不进这棵树** —— 只有可访问的控件（按钮、带 `content-desc` 的项）在里面。
   实测「我」页滚到底，整棵树只剩 `[菜单]`、`[荒野手册]` 两枚（都在 header），页里的段头、
   行标签、版本号一个都没有。所以**"文字压到吸底条上"这类版式 bug 不能用 dump 判**，
   只能截图目视；dump 的用途限定在"给可点的东西定坐标"。
   （SOS 页能测到「去添加」[184,1888][436,2008] 是因为它是 `Button`，不是 `Text`。）
5. ⚠️ **第 4 条在真机上会更糟：连"可点的东西"也可能整片消失**。2026-11-03 首次上
   HONOR PGT-AN00，地图页 dump 出来**只有 13 个节点**，底部五格导航条和工作台四格
   **一个都没有** —— 因为它们的 `Accessible` 根本没挂上（logcat 里 4 条
   `Accessible must be attached to an Item`，见 12 §4.24 L7）。
   所以 **dump 不是通用手段，它只在"无障碍确实挂上了"的构建上有效**。真机定坐标的
   正确顺序是：**① 先从 QML 算公式**（`dp × 倍率`，倍率 = `Override density / 160`，
   本机 448/160 = **2.8**），**② 再用截图像素验证公式**，不要反过来。
   像素验证用 `tools/png_probe.js`（纯 Node + zlib 解 PNG，按通道右移量化后取颜色游程，
   抗锯齿噪声压掉、纯色 UI 区浮出来）：

   ```bash
   cd /d/build_docker/app
   node tools/png_probe.js qcol tmp_reg/device006/p2_pre.png 100 3 8   # 竖切 x=100: 找上下分界
   node tools/png_probe.js qrow tmp_reg/device006/p2_pre.png 2245 3 10 # 横切 y=2245: 找左右分界
   ```
   量化后 `#1e1f1e` 这类三位一字符的是**浅色**（`0x1e<<3 ≈ 0xf0`），`#4813` 这种
   某通道占两位十六进制的要按位拆（R=4→0x20、G=8→0x40、B=0x13→0x9b = 状态栏蓝）。
   实测结果：地图工作台 sheet 顶边 **y≈2061**、四格等宽四列（`1224/4=306`）中心
   **x=153/459/765/1071**；导航带 **2424..2555**（132 px）对公式的 134 px 差 2 px
   （`lineHair` 取整），**公式可信**。
   > 上面说的"扫像素在 AVD 上是废的"仍然成立，但那是 **swiftshader 撕裂楔形**造成的；
   > 真机 + 量化游程不是同一件事，**真机上扫像素是可行的**，别把两条混成一条。

顺带一条：`console.log` 在 release 包里**只进 logcat**（`adb logcat -d | grep -a "\[map\]"`），
不进 `/data/data/com.outdoor.survival/files/logs/app_*.log`；后者要 root 读，
release 包不可 debug 所以 `run-as` 会报 `package not debuggable`。


### 12.7 判"改法进没进包"：拆包数串，别看 `build/` 的时间戳

出包后想确认某一行 QML 改动真的落进了 APK，**两条路都是错的**（2026-11-02 复核 0.0.5 时都撞过，
详见 12 §4.21）：

1. **看 `build/release_<abi>/` 里产物的 mtime** —— 那棵树是 Windows 侧的历史残留，本次构建的真实
   产物不在那儿。实测：`MePage_qml.cpp` 显示 10-29，而源码是当天 13:07 改的；包内主 .so
   9,233,472 B，树里 `stripped_native_libs/` 那份 9,132,040 B —— 根本不是同一份。据此会误判成
   "增量没生效"。
   **2026-11-04 查到成因**：`docker-compose.wsl.yml:26` 用**命名卷 `android-build` 挂在 `/project/build`**，
   所以主机 `app/build/` 对 WSL 构建而言是**空壳**（实测
   `find app/build/release_arm64-v8a -newermt "当天 11:00" -type f | wc -l` = **0**，
   而 `docker run --rm -v app_android-build:/v --entrypoint ls osw_ut:snap -la /v` 里
   `release_arm64-v8a` 的 mtime 就是当轮构建时刻）。**要看构建真相得进卷，不能看主机 `build/`**。
2. **对主 .so 直接 `grep` 明文** —— Qt 6 的 rcc 是**压缩**嵌进 `.so` 的，源码文本（含中文）
   明文扫不到，`夜晚配色`、`离线数据已入库` 都返回 0；只有进了编译字节码**名字池**的标识符
   （`bottomClearance`、`显示`）才明文命中。据此会误判成"包里没 QML"。

**可用的做法**（脚本 `tools/apk_rcc_probe.py`）：从 APK 取出 `lib/arm64-v8a/libOutdoorSurvival*.so`，
扫 zlib（`78 01/9C/DA`）与 zstd（`28 B5 2F FD`）魔数，逐块试解，在解压流里数 needle。
本次 310 个候选块、36 块解出。**关键：要同时数"旧写法"**，只数新串不闭合 —— 缓存万一没重生成，
旧串会照样在包里。合格的输出长这样：

```
新写法 parent && parent.height > 0      明文 0 + 解压 3 = 3     ← 三页各一处
旧写法 Math.max(parent…800, 800)        明文 0 + 解压 0 = 0     ← 必须为 0
新注释「不兜 800 的下限」                明文 0 + 解压 1 = 1
```

**数旧串时有两条限定（2026-11-04 撞到的，别把它们当成"包里还有旧代码"）**：

1. **注释里抄了旧写法会误报。** 本轮 `FilterRow.qml:79` 为讲清 bug 把原来的
   `Array.isArray(comboModel)` 原样抄进注释 ⇒ 反查报"旧串 = 1"。
   **2026-11-04 起这条已由脚本自己处理**：`count_outside_comments()` 每次命中回溯到本行行首，
   行首到命中点之间有 `//` 就不计数 —— **明文区和解压流两边都去注释**。
   去注释后仍非 0，才是"包里真的还留着旧写法"。
2. **新旧两个 needle 必须互不包含。** 同一行族里 `border.color: …weatherSource === index` **含有**
   子串 `color: …weatherSource === index` ⇒ 拿 `color: …旧串` 做对照永远非 0。
   对照要挑只出现一次的那一行（本轮用 `font.bold: …`）。
3. 也别顺手去 `grep` 卷里的 `.rcc/qmlcache/*_qml.cpp` —— 编译产物同样**不含 QML 标识符明文**
   （2026-11-04 实测 `grep -c headCol|pageHeadH|implicitHeight` 在 `PageHeadBand_qml.cpp` = 0，
   而同一轮解压 `.so` 却在压缩流里数到了那句新写法）。**阴性一律不作数，只有"解压流命中"是证据。**

#### 12.7.1 脚本已门禁化，但它的"期望 0"分支自己假绿过一次（2026-11-04）

`apk_rcc_probe.py` 现在收 `--must-hit '标签=文本'` / `--must-be-zero '标签=文本'`，
逐条判定、**任一判错 exit 1**，没带任何 `--must-hit` 对照时 **exit 2**（解压一条都没解出来时，
所有"期望 0"会集体假绿，判据不成立）。本轮七条 needle 的实跑（`tmp_reg/probe_009.sh`，321 候选块 / 33 解出）：

```
OK  新L14      去注释(明文+解压) 1   OK  旧L14  0   OK  新L6-1  1   OK  旧L6-1  0
OK  新L11④     去注释(明文+解压) 1   OK  旧L11④ 0   OK  对照clip 35   === PASS（判错 0 条）===
```

**但它第一版是错的**：`期望 0` 只数"解压流去注释"，把明文那一份整个忽略掉（当时的理由是
"二进制里没法安全去注释"）。反证 `--must-be-zero Z=pageHeadH` 报了 **OK**，而 `pageHeadH`
在源树里真实存在（明文裸计数 4）—— **一道会假绿的门禁比没有门禁更坏**。修完后三条反证都过
（`tmp_reg/probe_controls.sh`）：

| 反证 | 期望 | 实跑 |
|---|---|---|
| ① `--must-be-zero Z=pageHeadH`（明文区真实存在） | FAIL + rc=1 | `FAIL … 去注释 2 = 2 期望 0（含注释的裸计数是 4）` ⇒ **rc=1** ✅ |
| ② `--must-hit 不存在=zzzNoSuchNeedlezzz` | FAIL + rc=1 | `FAIL 不存在 … 0 = 0 期望 >0` ⇒ **rc=1** ✅ |
| ③ 只带 `--must-be-zero`，不带对照 | rc=2 | `!! 本次没带任何 --must-hit 对照串…` ⇒ **rc=2** ✅ |

口径记下来：**把一次性取证脚本升级成门禁时，必须当场跑"它应该会 FAIL"的那几条**，
"正例 PASS"只证明脚本会打印绿，不证明它会变红。

另外 `build_apk.sh` 自己有一道守卫会在 `.qml` 比 qmlcache 新时清缓存触发 `qmlcachegen` 重生成，
日志里能看到 `检测到 .qml 比 qmlcache 新…` 和逐页的 `Generating .rcc/qmlcache/…`；
**但它是自述，只能当旁证，判据仍以拆包数串为准。**

### 12.8 读构建日志：每个 ABI 只信它自己那一轮刚写出来的

`build_apk.sh` 的日志按 ABI 分开写（`wsl_release_<abi>.log`），但**上一轮的日志不会被清掉**，
`tail` / `grep` 很容易读到**混着旧内容**的一段。2026-11-03 就这么误判过一次：从日志里"看到"
剪枝把项目主 lib、`qtforandroid` 平台插件、QtLocation 都删了，据此差点判"剪枝写错了、整轮回滚"。
实际那段属于 **11-02 的 arm64 那轮（旧代码）**，当轮 arm64 日志里那三个文件一条都没被删。

三条规矩：

1. 读日志先看**时间戳 + ABI 标识**（`jniLibs/arm64-v8a/` vs `jniLibs/x86_64/`），对不上就当没看见；
   更稳的办法是 `grep -nE "权威集|import 反查|闭包补|剪枝合计|认定需要|jniLibs/.*共|qt_libs 包含|保命断言"`
   一次把当轮这几行全捞出来，它们**必须自洽**。0.0.6 重建轮自洽的部分（拆包实测可复算）：
   `jniLibs` 84 = 包内 **81 个进 `qt_libs`**（`libQt6*` 31 + `libplugins_*` 29 + `libqml_*` 20 + 项目主
   lib 1）+ **3 个不进 `qt_libs`** 的 `libc++_shared.so` / `libssl_3.so` / `libcrypto_3.so`。
   **不对账的部分也记下来**：日志的 `KEEP_SO` 计数是 85，比包内 Qt 侧的 82（81 + 后来被删的 NMEA
   插件）多 **3 个**，本轮没逐项对上是谁 —— 不影响包的正确性（断言与走查都过），但说明
   **`KEEP_SO` 的计数不能直接当"包内 Qt 库数"引用**，要报数就报拆包数出来的那三个前缀。留作待查。
2. **构建进行中不要编辑 `build_apk.sh`**。bash 是边读边执行，脚本中途被改会让解释器从错位处续读，
   症状是一堆莫名其妙的语法/行为异常，比 bug 本身难查。本轮加"保命断言"就是加完立刻回滚、
   等构建结束再重新加上。
3. **断言/校验的文件名不要凭猜**。本轮在断言清单里写了 `libqml_Material_*`、
   `libplugins_imageformats_svg`，都是猜的名字，真实名是
   `libqml_QtQuick_Controls_Material_qtquickcontrols2materialstyleplugin_*`、
   `libplugins_imageformats_qsvg_*` —— 猜错会报一堆假"缺失"，把注意力带偏。
   先 `ls $QT_QPA/qml/…` 或从当轮 `jniLibs` 列一遍，再写判据。


### 12.9 真机（非模拟器）装机与取证：荣耀这一台撞到的三条

2026-11-03 第一次把 0.0.6 装到真机（HONOR PGT-AN00 / Android 16 / SDK 36 / arm64-v8a），
三条与模拟器不同的口径，都是当场撞出来的：

1. **`adb install` 流式安装会静默失败**。症状是 `Performing Streamed Install` 之后
   **错误体为空**，看不出原因，荣耀（含 HONOR/华为系）通病。加 **`--no-streaming`** 一次成功。
   升级装（`-r`）在签名一致时可用；本轮按用户决定走的是 **`adb uninstall` 后全新装**，
   代价是**真机数据全清**（标注/轨迹/紧急联系人），不可回退，必须先问用户。
2. **release 包在真机上读不到 App 私有文件**，模拟器那套判据直接作废：
   ```
   adb shell ls /data/data/com.outdoor.survival/files/logs/  → Permission denied
   adb shell run-as com.outdoor.survival id                  → run-as: package not debuggable
   ```
   所以真机回归的证据只有两样：**截图** + **按 pid 过滤的 logcat**
   （`adb shell pidof -s com.outdoor.survival` → `adb logcat -d --pid=<pid>`）。
   `tools/reg_sweep.sh` 里"日志字节增量 > 1 KB"那条判据在真机**不成立**，别照搬。
   要拿真机文件日志只有两条路：出 debug 包（占一个版本号、改的是打包口径不是代码），
   或在 App 里做日志导出到 `/sdcard` 的入口（是功能改动，得单独排）。
3. **装机前先核 ABI 与倍率，别假设**。`ro.product.cpu.abi` 决定包能不能装（本项目只出
   arm64-v8a），`wm density` 的 **Override** 值（不是 Physical）决定 dp→px 倍率：
   本机 Physical 528 / **Override 448** → 倍率 `448/160 = 2.8`。
   内容区底边要从 `uiautomator dump` 的根节点读（本机 **2556**，`2556..2688` 是系统栏），
   再减 `navBandH × 倍率` 才是导航带中心，**按模拟器的比例推 y 会点到系统栏、把 App 甩回桌面**。

走查驱动器：`tools/reg_sweep_device.sh`（冷启动 + 点五格 + 轮询换帧 + 抓 logcat）、
`tools/reg_tap_device.sh`（按步骤表点**实测坐标**跑二级页面）、`tools/png_probe.js`（从截图像素
反推元素边界，用法见 §12.6 第 5 条）。三者都在 gitignore 的 `tmp_reg/` 里，是本轮的工具沉淀。

### 12.10 真机二级页面走查：坐标换算与日志计数的两条硬口径（2026-11-03，pass 2）

pass 2 跑了 13 轮 / 55 步（地图工作台四格与图层/定位/搜索、资源页类目 chip 与省份·月份选择器、
物种详情、急救步骤页、紧急联系人与添加表单、我页七个二级入口、抽屉、搜索对话框），
步骤表在 gitignore 的 `tmp_reg/steps_*.txt`，每行 `name|x|y`。两条当场定下来的口径：

1. **二级页坐标用「显示图 × 1.36」换算，再用 `png_probe.js` 复核，不要拍脑袋**。
   截图是 `1224×2688` 原生分辨率，但读图时看到的是约 `900` 宽的缩放图，
   倍率 `1224/900 = 1.36`。换算完必须拿列扫描验一次：
   ```bash
   node tools/png_probe.js qcol tmp_reg/device006/r2_res.png 700 3 6
   ```
   本轮在 x=700 扫到 `754..847` / `877..970` 两段纯色区，正是省份、月份两个下拉的内区，
   中心 800/923 对换算值 805/922 差 ≤5 px —— 换算可用。55 步**只点空 1 次**，
   而那 1 次恰恰是**页面自己的锅**（二级页返回键位置漂移，见下）。
   **注意换算只对"同一张截图"成立**：筛选态一变，控件就整体下移（动物界子类目三行时
   省份行从 805 掉到 885），所以**每轮步数要少、跑完看图再定下一步**，别一次写完 20 步再跑。
2. **logcat 的 WARN 计数不能跨轮比较，"这轮 0 条"不等于"缺陷已消失"**。
   pass 1 报过 4 条 `Accessible must be attached to an Item`，pass 2 十三轮**全 0**，
   其中两轮明确打开过 Material `Dialog`（添加联系人、搜索），按 pass 1 的归因本该复报。
   真相是**那 4 条只在冷启动后首次实例化时报**，而 pass 2 全程没重启进程
   （`adb shell pidof -s com.outdoor.survival` 一直是 2045）。所以：
   **要判"某条运行时警告还在不在"，必须先 force-stop 冷启动**（`tools/reg_sweep_device.sh` 就是这么做的），
   在同一个热进程里跑第二轮拿到的 0 是**假绿**。

顺带一条取证副产物：`tools/reg_tap_device.sh` 的 `换帧=1` 只证明"画面变了"，
**不证明"点的东西对了"** —— 状态栏时钟每秒都在变。所以步表跑完必须逐张看图，
本轮就是这么发现「月份筛了 7 月但下拉仍显示全部」这种控件级 bug 的（详见 09-讨论记录/12 §4.25 F1）。

---

### 12.11 一次只跑一个构建：涨号在 STAGE 1、交付包的名字在 STAGE 4 现读（2026-11-04 实测）

`build_apk.sh` 把版本号在 **STAGE 1 就 +1 写进 4 处文件**（`CMakeLists.txt` / `AndroidManifest.xml` /
gradle 两处），而 **STAGE 4 复制 APK 到 `dist/` 时再现读一次** `CMakeLists.txt` 来拼文件名。
于是**并发跑两轮构建会把这两件事搅在一起**，2026-11-04 实测到完整现场：

```
A 轮 02:58:47  0.0.7 → 0.0.8        B 轮 03:12:35  0.0.8 → 0.0.9（改写同一批文件）
A 轮 03:15:48  ✅ APK 版本回验通过: versionName=0.0.8 versionCode=8   ← 从包里读的真值
A 轮 03:15:52    路径: /project/dist/OutdoorSurvival-v0.0.9-…apk      ← 复制时现读 CMakeLists
```

**A 造出来的 versionCode=8 那个包，被按 0.0.9 的名字放进了 `dist/`。** 只看"路径:"那行会拿到一个
"名字说 9、里面是 8"的交付包；只看日志尾部的成功行还会反过来误判（本轮另一条教训：
后台命令写成 `… > log 2>&1; echo "rc=$?"` 会让 **echo 盖掉真实退出码**，一次成功的构建被我记成了失败的）。

三条规矩：

1. **出包期间不并发构建**（同一份 `/project`、同一个 `android-build` 卷、同一批版本号文件）；
   也别并发跑全树 qmllint / load check 抢内存（WSL 只有主机一半内存，实测 `free -m` 总量 7796 MB，
   而 `BUILD_JOBS=6` + gradle `-Xmx2048m` 本来就有余量爆掉的风险）。
2. **拿包里的真值定版本号**：装机前用 Windows 侧 build-tools 34 跑
   `aapt2 dump badging <apk> | grep ^package`，读 `versionCode=` / `versionName=` 与 `native-code:`，
   **不要引用构建日志里"路径:"那一行**（那只是复制时的文件名）。
   本轮据此确认 `dist/…v0.0.9….apk`（35,129,022 B）是 `versionCode='9' versionName='0.0.9'`、
   `native-code: 'arm64-v8a'` 有且仅一个，`unzip -l` 991 条目 / `lib/arm64-v8a/` 84 个 `.so` / 其他 ABI 0 个。
3. **号被吃掉就跳格，不回退**。0.0.8 那一号被 A 消耗了却从未以正确的名字存在过，
   跳一格比"盘上冒出对不上的号"好对账；但文档与 commit 必须写实际那个号。
   真要拿指定位号出包：`VERSION=0.0.8 bash tools/wsl_build_apk.sh`（或 `VERSION_BUMP=0` 不涨号），脚本头写着这两个开关。

`apksigner verify --print-certs` 记得**逐版对证书 SHA-256**：0.0.6 / 0.0.7 / 0.0.9 三版都是
`ae1ceedb615a9bbe5072d390b61dd1e8b105b8d45d0cec212ade3b4563b38c3e` ⇒ 同证书可 `adb install -r` **覆盖装**，
**千万别卸载**（卸载会连真机上的紧急联系人名册与自建清单一起没）。
跑 `apksigner` 要 `JAVA_HOME` 指到真正的 JDK 根（本机是 `D:\build_docker\jdk17\jdk-17.0.20.1+1`，
指到上一层会报 "JAVA_HOME is set to an invalid directory"）。
**0.0.10（2026-11-05 统一修改轮）复核补进同一条**：`apksigner verify --print-certs` 仍是
`ae1ceedb615a9bbe5072d390b61dd1e8b105b8d45d0cec212ade3b4563b38c3e`，**Verified using v2 scheme: true、v1/v3/v3.1/v4 全 false**
（本机签名方案从 0.0.6 起就只有 v2，别按"v1+v2+v3"那句旧文档去判失败）。
容器内路径 `/opt/android-sdk/build-tools/34.0.0/apksigner`，`which apksigner` 在 PATH 里取不到，要写全路径。

### 12.12 判「C++ 改的文案进没进包」：rcc 探针盖不到，要按字节数主 `.so`（2026-11-05 出 0.0.10 时定下）

§12.7 那个 `tools/apk_rcc_probe.py` 解的是 **rcc 资源段**，里面只有 **QML / 数据文件**。
本轮 L12 的另一半改在 `src/`（`fail(ServiceErrorCode::X, QStringLiteral("…"))`、`Err<T>(…)`、
`requireNonEmpty(value, "字段名", ctx)`），**这些字符串不经过 rcc** —— 它们被编译进主 `.so` 的只读数据段，
`QStringLiteral` 出的是 **UTF-16**，所以：

- 用 rcc 探针判 src 侧改动 = **判不到**（解压流里根本没有它们）；
- 直接对 `.so` 做**明文 UTF-8 `grep`** = **也判不到**（中文短语句在包里是 UTF-16LE 字节，ASCII grep 返回 0 会误判成"没进包"）。

**可用做法**（本轮一次性跑通，**尚未固化成常驻脚本**）：解 APK 取 `lib/arm64-v8a/libOutdoorSurvival_arm64-v8a.so`
（本轮 9,241,648 B），对每条 needle 同时数 `s.encode('utf-8')` 与 `s.encode('utf-16-le')` 两种编码的出现次数。
本轮实测：must-hit `本机数据库没打开` 1 / `这个 GPX 文件打不开` 2（`warningTriggered` 与 `fail` 各一处，同一字面量两处引用）/
`这条装备的编号` 1；must-be-zero `DB 未打开`、`List not found`、`equipmentId 不能为空`、`knot_progress 写入失败`、
`listMap.id 为空`、`routeId 不能为空` **全 0** ⇒ PASS。

三条口径：
1. **"包侧已复核"这句话必须说清算了哪一半**。只跑 rcc 探针 = 只盖住 QML 那一半，src 文案改动一律还要这一步。
2. **计数要能解释**。`这个 GPX 文件打不开` 出 2 不是错，是源码里两处引用（`warningTriggered` + `fail`）；
   反过来若一条 must-hit 出 0，先怀疑编码（UTF-16）再怀疑构建，别急着说"构建没生效"。
3. **编码按字面量类型分两路，判据必须双编码一起数**（本轮在同一份 `.so` 上逐条量出来的对照）：
   `knot_progress`（`QLatin1String` / 纯 ASCII）utf-8 **8** / utf-16 **0**；
   `本机数据库没打开`（`QStringLiteral`）utf-8 **0** / utf-16 **1**。
   只按一种编码数，命中数会静默偏低甚至归零。
4. **must-be-zero 只能挑「用户可见通道」里的串**。本轮 `not found` 在包里 utf-16 仍出 **2** ——
   那是 `ImageColorExtractor.cpp:41/166` 的 `result["detail"] = QStringLiteral("file not found: ") + localPath`，
   而 `detail` 按 2026-10-23 #115 的既定口径**只进 `console.warn`**，屏上那句是 `info.error`（中文，
   `FieldGuideImagePickPage.qml:141`）。同理 `AssetLoader::loadJson(..., &err)` 的英文 `err` 全部只进 `Logger`。
   所以"包里还有英文串"本身不是缺陷，**判据要钉的是它落在哪个字段**。

**下一轮待办**：把这段并进 `tools/apk_rcc_probe.py`（加 `--so-utf16-hit` / `--so-utf16-zero` 两个开关），
让它和 rcc 那半共用同一个 exit code 口径 —— 现在这一步是人判，不属于 27 道门禁。

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

**先分清"整 app 白屏"和"某一个页白屏"** —— 两者根因不同（2026-11-03 实测）：

| 现象 | 根因 | 查法 |
|---|---|---|
| 装完启动即崩 / splash 一闪就没 | `qt_libs` 里 Qt6Core 没排第 1（见 Q16）；或平台插件 `libplugins_platforms_qtforandroid_*` 缺 | 拆包看 `array/qt_libs` 首项；`build_apk.sh:1391-1396` 的保命断言本就该拦住 |
| **根格能刷出来，只有某个页白屏** | 那个页 `import` 的 QML 模块**插件没进包** | 包内 `libqml_<模块名>_*` 在不在；`logcat` 里会有 `module "QtQuick.Dialogs" plugin not found` 一类 |

第二行这档**只在点进那一页时才暴露**，所以模拟器跑根格走查（§12.5）判不出问题。0.0.6 第一个包就是
这个：arm64 的 androiddeployqt 权威集比 x86_64 少 22 个库，其中含 `QtQuick.Dialogs` 的两个插件，
而 `MapPage.qml:23`、`FieldGuideImagePickPage.qml:32` 都 import 它 → 地图页整页白屏。
现在的口径是 **§9.1** 的四阶段收集 + 两道 `die`（import 有、kit 里没插件就禁止出包）。

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

**根因**: Activity 名写错。简写 `.QtActivity` 会被解析为 `com.outdoor.survival.QtActivity`(不存在)。

**解决**（2026-11-02 校准，别再抄 `QtActivityBase` / `bindings.QtActivity`）:
```bash
# 以 APK 自己的 badging 为准
/opt/android-sdk/build-tools/*/aapt2 dump badging app.apk | grep launchable-activity
#   → launchable-activity: name='com.outdoor.survival.MainActivity'
adb shell am start -W -n com.outdoor.survival/.MainActivity
```
`org.qtproject.qt.android.bindings.QtActivity` 只是本项目 `MainActivity` 的**父类**，清单里注册的
entry 是 `com.outdoor.survival.MainActivity`；本节旧版本给的两种全名都点不起来（真机 + 模拟器
各取证一次）。`build_apk.sh` 出包尾部的启动提示也已改成现读 badging，见 09-讨论记录/12 §4.15 末段。

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

### Q15. 换一个 ABI 首次出包, STAGE 3 报 `cp: cannot create regular file '.../android-build/app/src/main/AndroidManifest.xml': No such file or directory`

**根因**: `androiddeployqt --no-build` 只**安装依赖**、不**创建工程骨架**(见 §3.1.2 坑 4)。
老 ABI 的 `android-build/` 目录里有历史完整模式生成的骨架, 所以同一套脚本在它身上跑得通;
新 ABI 的 `release_<abi>/android-build/` 是空的, STAGE 3 后半段所有往 `app/...` 落文件的
`cp` 全部失败。日志特征: androiddeployqt 那句 `Android package built successfully in 14 ms`
照样打印(它只是算了个包名路径), 但 `find ... -name AndroidManifest.xml` 一行产物都没有。

**自查命令**(容器内, 一眼看出骨架有没有):

```bash
docker compose -f docker-compose.yml -f docker-compose.wsl.yml run --rm android-builder \
  bash -c 'O=/project/build/release_x86_64/android-build;
           ls $O; echo "libs/*.so=$(find $O/libs -name "*.so" | wc -l)";
           ls $O/res/values/libs.xml $O/app/src/main 2>&1'
```

`libs/*.so` 只有个位数(缺 Qt6* 全家桶) + 没有 `res/values/libs.xml` = 就是这个坑。

**已修**: `build_apk.sh` 的 STAGE 3 加了"引导部署"分支(缺 `libs.xml` 时用 `--gradle` 完整模式
+ `gradlew` 桩, ≈20 秒)和三处目录兜底(`mkdir -p app/src/main`、`app/src/main/java`、把根
`res/` 播种进 `app/src/main/res/`)。修完 x86_64 实测 6m37s 出包, STAGE 4 版本回验通过。

### Q16. 装包成功、`am start` 后 splash 一闪就没, logcat 里 `SIGSEGV` 落在 `QJniEnvironment::getJniEnv()`

**根因**: `qt_libs` 数组里 **Qt6Core 没排在最前**, 见 §3.1.2 坑 5。崩溃栈固定长这样:

```
#00 libQt6Core_<abi>.so  QJniEnvironment::getJniEnv()+38   (Cause: null pointer dereference)
#01 libQt6Core_<abi>.so  QJniEnvironment::QJniEnvironment()+26
#02 libQt6Multimedia_<abi>.so  JNI_OnLoad+118
...  QtLoader.loadLibraryHelper → QtLoader.loadLibraries → QtThread
```

**自查命令**(Windows 侧, 直接读**编译进 APK 的**顺序, 别看容器里的源码 `libs.xml`):

```bash
D:/build_docker/android_sdk/build-tools/34.0.0/aapt2.exe dump resources dist/<apk>.apk \
  | awk '/^ *resource 0x[0-9a-f]+ array\/qt_libs$/{f=1;next} f&&/^ *resource 0x/{exit} f{print}' \
  | grep -oE "Qt6[A-Za-z0-9_-]*" | head -6
```

第 1 个不是 `Qt6Core_<abi>` = 就是这个坑。注意**同一个数组在源码 `libs.xml` 里可能有几十上百条、
顺序也不同**: androiddeployqt 写的 `res/values/libs.xml`(根) 与 AGP 真正打进包的
`app/src/main/res/values/libs.xml` 是两份文件, 只有后者生效。

**已修**(2026-11-02): `build_apk.sh` 的重排步骤改成 `libQt6Core_*` 前缀匹配并置于第 1 位,
匹配不到直接 `die`。

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
**最后更新**: 2026-11-05（第十一轮 = **统一修改轮** #53~#60 + **0.0.10 出包**：`apksigner verify --print-certs`
补进 §12.11 末尾 —— 0.0.10 仍是 `ae1ceedb…38c3e` 同一把证书、**只有 v2 scheme**（v1/v3/v3.1/v4 全 false），
容器内要写全路径 `/opt/android-sdk/build-tools/34.0.0/apksigner`；新增 **§12.12「判 C++ 改的文案进没进包」**
—— `apk_rcc_probe.py` 解的是 rcc 资源段，**只盖 QML**，`src/` 里 `fail()`/`Err<T>()` 的中文串编译进主 `.so`
且 `QStringLiteral` 出的是 **UTF-16LE**（本轮同一份 `.so` 上量出 `knot_progress` utf-8 8 / utf-16 0，
`本机数据库没打开` utf-8 0 / utf-16 1），所以判 src 侧必须**双编码数主 `.so` 字节**；这条口径 0.0.10 包侧已实跑
（3 条 must-hit 全在、6 条旧串全 0），**但仍未固化成常驻脚本**。包侧 rcc 反查本轮实测：329 个压缩块 / 解出 33 块，
10 条 needle 的命中数与源码 `grep` **逐条相等**（含对照串 `clip: true` = 35，防"一块都没解出来"集体假绿）。
耗时口径改在 08-全代码索引 §18.3：0.0.10 实测 **15m45s**（STAGE 1 1s / 2 10m1s / 3 5m37s / 4 6s），
比 0.0.7 那次"跨多目录 ≈20 min"低 ⇒ **真正的变量是动没动 `.h`，不是动了几个目录**。）

**上一轮**: 2026-11-04（第九轮 #48/#49/#42 第二半 + **0.0.9 出包**：新增 **§12.11「一次只跑一个构建」**
—— 实测并发两轮构建会让 A 造出的 `versionCode=8` 包被按 `v0.0.9` 的名字放进 `dist/`（涨号在 STAGE 1 改文件、
复制名在 STAGE 4 现读 `CMakeLists.txt`），规矩是**装机前用 `aapt2 dump badging` 读包里的真值，不引用日志"路径:"那行**，
外加 `后台命令结尾 `; echo rc=$?` 会盖掉真实退出码`、同证书 0.0.6/0.0.7/0.0.9 SHA-256 逐字相同 = 覆盖装勿卸载；
§12.7 补三处：**主机 `app/build/` 是空壳的成因 = `docker-compose.wsl.yml:26` 用命名卷 `android-build` 挂 `/project/build`**、
数旧串的两条限定（注释里抄了旧写法会误报 / 新旧 needle 必须互不包含）、
`grep` 卷里 `qmlcache/*_qml.cpp` 同样不含 QML 标识符明文（阴性一律不作数，只有解压流命中是证据）。
本轮按 §12.7 的正解重做包侧反查：321 个压缩块 / 解出 33 个，三条改动的新写法各命中 1、旧写法各 0。
新增 **§12.7.1** —— `apk_rcc_probe.py` 门禁化（`--must-hit` / `--must-be-zero` / 判错 exit 1 / 无对照 exit 2），
**但它第一版的"期望 0"分支只数解压流、漏掉明文区，被 `--must-be-zero Z=pageHeadH` 反证当场抓出假绿**；
修法是明文区与解压流**两边都按行去 `//` 注释再计数**，并记下口径：一次性取证脚本升级成门禁时，
必须当场跑"它应该会 FAIL"的反证，正例 PASS 只证明脚本会打印绿，不证明它会变红。
上一轮 2026-11-03（第七轮 #45/#46 + **0.0.7 出包**：§9.1 加 `arm64 0.0.7` 一行与包体独立复核口径
（`versionCode=7` / `native-code` 仅 arm64-v8a / 84 个 .so / 证书 SHA-256 与 0.0.6 逐字相同 = 能覆盖安装），
并记两条主机侧坑：`apksigner.bat` 要嵌套 JDK 路径、`--values` 是 aapt1 的口径而 build-tools 34 只有 aapt2、
别在 WSL 里对 `/mnt/d` 跑 `find /`；§3.1.2 加第 8 条 —— **`$?` 在 Windows→wsl→docker exec 串里被提前展开**，
由它误读过 `qml_load_check` 的退出码。上一轮 2026-10-29（新增 §3.1.1 Win10 19044 装不了当前 Docker Desktop → WSL2 内装
Docker Engine 的具体路径; §9 补交付口径"只出 arm64-v8a"与 `Dockerfile.android` 注释 x86_64 kit 的后果。
上一轮 2026-09-10: Q14 新增 qtquick3d-assimp 编译失败条目, 详见
[09-讨论记录/06-qtquick3d-assimp构建修复.md](../09-讨论记录/06-qtquick3d-assimp构建修复.md)）
