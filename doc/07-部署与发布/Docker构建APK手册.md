# Docker 构建 APK 完全手册(从安装到装机)

> 适用版本: 荒野手册 v0.0.1 / Qt 6.7+ / Android 7.0+ (API 24+)
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

```bash
# 强制全量重建(清理 CMake 缓存)
CLEAN=1 bash build_apk.sh release arm64-v8a

# 限制 4 核并行
BUILD_JOBS=4 bash build_apk.sh release arm64-v8a
```

**输出位置**(在主机上):
```
dist/
├── OutdoorSurvival-v0.0.1-release-arm64-v8a.apk
├── OutdoorSurvival-v0.0.1-release-armeabi-v7a.apk
└── OutdoorSurvival-v0.0.1-release-x86_64.apk
```

**APK 大小**: 约 30-50 MB(Qt 运行时 + 应用代码 + 资源)

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
apksigner verify --verbose dist/OutdoorSurvival-v0.0.1-release-arm64-v8a.apk
# 预期: Verifies ... v1, v2, v3

# 查看 APK 信息
aapt2 dump badging dist/OutdoorSurvival-v0.0.1-release-arm64-v8a.apk
# 预期: package: name='com.outdoor.survival' versionCode=1 versionName='0.0.1'

# 看 APK 内容
unzip -l dist/OutdoorSurvival-v0.0.1-release-arm64-v8a.apk | head -20
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
adb install dist/OutdoorSurvival-v0.0.1-release-arm64-v8a.apk
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
adb install dist/OutdoorSurvival-v0.0.1-release-arm64-v8a.apk
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
**最后更新**: 2026-09-10(Q14 新增 qtquick3d-assimp 编译失败条目, 详见 [09-讨论记录/06-qtquick3d-assimp构建修复.md](../09-讨论记录/06-qtquick3d-assimp构建修复.md))
