# qtquick3d-assimp Android 构建修复

> 记录 2026-09-09/10 基于 `build.txt` 12/17 失败日志的 4 步 Dockerfile.android 修复
> 涵盖 1 个 vendored 源码摆位 + 3 个 sed 补丁 + 1 个 ABI 跳过

---

## 1. 排查起点

用户提供 `build.txt` (Docker Desktop 构建日志), 关键错误位于第 12/17 步 (Dockerfile.android 的 qtquick3d 源码编译 RUN):

```
14.45 CMake Error at .../Qt6CoreMacros.cmake:2659 (add_library):
14.45   Target "AssimpImporterPlugin" links to target
14.45   "WrapQuick3DAssimp::WrapQuick3DAssimp" but the target was not found.
14.45 Call Stack (most recent call first):
14.45   .../Qt6CoreMacros.cmake:2451 (_qt_internal_add_library)
14.45   .../Qt6PluginHelpers.cmake:91 (qt6_add_plugin)
14.45   src/plugins/assetimporters/assimp/CMakeLists.txt:41 (qt_internal_add_plugin)
```

**初步判断**: `FindWrapQuick3DAssimp.cmake` 没成功创建 `WrapQuick3DAssimp::WrapQuick3DAssimp` IMPORTED target, 导致 `AssimpImporterPlugin` 链接阶段报 "target was not found"。

## 2. 根因分析 (四层)

### 2.1 第一层: aqt 装的 libassimp-dev 在 cross-compile 下不稳

Dockerfile 之前传 `-DQT_FEATURE_system_assimp=ON`, 让 Qt 通过 `find_package(assimp CONFIG QUIET)` 找 apt 装的 `libassimp-dev`:

- Debian/Ubuntu 的 `libassimp-dev` 5.3 包提供 `assimpConfig.cmake`, **理论上**会建 `assimp::assimp` IMPORTED target
- 实际在 `qt-cmake` 包装 + Android NDK 26 cross-compile 下, `assimp::assimp` target **没被成功创建** (POSIX `assimpConfig.cmake` 已知有 release-location 问题, 见 Qt 注释 [Debian bug #973361](https://bugs.debian.org/973361))
- `FindWrapQuick3DAssimp.cmake:11` 的 `if (assimp_FOUND AND TARGET assimp::assimp)` 失败, 也没进 `:47` 的 `assimp_LIBRARIES/INCLUDE_DIRS` fallback, target 始终未建

### 2.2 第二层: 3rdparty/assimp 源码是空的

`qtquick3d-6.7.2.zip` 自带的 `src/3rdparty/assimp/` 是**空目录** (仅 4 个 metadata 文件: `LICENSE` / `config.h` / `revision.h` / `qt_attribution.json`), 没有 `.cpp` 源文件。这意味着**切到 `system_assimp=OFF` 也编不了 vendored 路径**。

### 2.3 第三层: contrib/unzip/ioapi.c 用 glibc 64 位扩展

切到 `system_assimp=OFF` 后, Qt 源码自带的 `AssimpImporterPlugin/CMakeLists.txt:106` 起引用 `../../../3rdparty/assimp/src/code/...` 共 ~200 个源文件。其中 `contrib/unzip/ioapi.c` 用了 glibc 64 位文件 API:

```c
#define FOPEN_FUNC(filename, mode) fopen64(filename, mode)
#define FTELLO_FUNC(stream) ftello64(stream)
#define FSEEKO_FUNC(stream, offset, origin) fseeko64(stream, offset, origin)
```

**Android NDK 26 的 bionic libc 不提供 `fopen64` / `ftello64` / `fseeko64`** (POSIX 2008 扩展, glibc 和 macOS 有, Android 没跟)。Clang 17 编到 647/735 步时报 4 个 undeclared-function 错误。

### 2.4 第四层: aqt 装 android_armv7 产物不完整

`aqt install-qt linux android 6.7.2 android_armv7` 在容器内产物缺 `bin/qt-cmake` (POSIX 下 bash 报 "Permission denied" 而非 "No such file")。`/opt/Qt/6.7.2/android_armv7/` 目录结构残缺, 编译 RUN 一启动就崩。

## 3. 修复方案 (四步)

### 3.1 切到 vendored assimp (system_assimp=OFF)

不再依赖 apt 装的 `libassimp-dev`, 让 Qt 源码自带的 `AssimpImporterPlugin/CMakeLists.txt` 走 vendored 编译路径。

**前提**: 3rdparty/assimp 源码必须齐全。从 Qt 官方仓库找匹配版本——assimp 5.4.1 与 QtQuick3D 6.7.2 自带 `revision.h` 的 `VER_MINOR=4, VER_PATCH=1` 一致。

**操作**:
1. 用户预置 `qtquick3d-assimp-5.4.1.zip` 到项目根
2. Dockerfile 新增 `COPY qtquick3d-assimp-5.4.1.zip /tmp/qtquick3d-assimp-5.4.1.zip`
3. unzip 后把 `code/` `include/` `contrib/` mv 到 `${QT_SRC_DIR}/src/3rdparty/assimp/src/` (zip 顶层是 `qtquick3d-assimp-5.4.1/`, 不是 `src/` 摆好的形式)
4. **不覆盖** Qt 自带的 `config.h` / `revision.h` (这俩是 cmake configure 模板产物, 保留 Qt 自带的 5.4.1 成品)
5. 三个 ABI RUN (`android_arm64_v8a` / `android_x86_64` / `android_armv7`) 都把 `-DQT_FEATURE_system_assimp=ON` 改成 `OFF`, 去掉 `-DCMAKE_PREFIX_PATH=/usr` (不再需要让 cmake 找系统 assimp)

**源码覆盖度验证**: 解压 zip 后, QtQuick3D 引用的 250 个 3rdparty/assimp 文件中 248/250 命中 (缺的是 `config.h` 和 `revision.h`, 见上)。

### 3.2 ioapi.c 补丁: 切到 fopen (bionic 有)

`ioapi.c:18-26` 已有 `#if defined(__APPLE__) || defined(IOAPI_NO_64) || defined(__HAIKU__) || defined(MINIZIP_FOPEN_NO_64)` 分支, 选中时切到 `fopen/ftello/fseeko`。注入 `IOAPI_NO_64` 宏即可。

```bash
sed -i '1i#define IOAPI_NO_64 1' \
    ${QT_SRC_DIR}/src/3rdparty/assimp/src/contrib/unzip/ioapi.c
```

**但这又踩第三个坑**: bionic 也没有 `ftello` / `fseeko` (只有 `ftell` / `fseek`)。`IOAPI_NO_64` 切到非 64 位分支后, 第 21-22 行宏定义仍是 `ftello` / `fseeko`, Clang 17 又报 "undeclared function ftello"。

### 3.3 ioapi.c 第二补丁: ftello/fseeko → ftell/fseek

把 21-22 行的宏定义**再改一次**, 切到 bionic 提供的最古老 `ftell` / `fseek`:

```bash
sed -i 's|^#define FTELLO_FUNC(stream) ftello(stream)$|#define FTELLO_FUNC(stream) ftell(stream)|' \
    ${QT_SRC_DIR}/src/3rdparty/assimp/src/contrib/unzip/ioapi.c
sed -i 's|^#define FSEEKO_FUNC(stream, offset, origin) fseeko(stream, offset, origin)$|#define FSEEKO_FUNC(stream, offset, origin) fseek(stream, offset, origin)|' \
    ${QT_SRC_DIR}/src/3rdparty/assimp/src/contrib/unzip/ioapi.c
```

**正则关键**:
- 用 `^...$` 锚定整行, 只匹配宏定义那一行
- 用 `ftello(stream)$` (带 `(` 收尾) 匹配, 不会误伤 `#else` 支的 `ftello64(`
- 三条 ABI 共享 `${QT_SRC_DIR}` 同一份源码, arm64 块 sed 一次够

### 3.4 跳过 armv7 ABI

项目 CMakeLists.txt 只声明 `arm64-v8a` ABI, 不产 armv7 APK。`aqt install-qt android_armv7` 在容器内产物不完整, **保留** `qt-cmake: Permission denied` 错误。

**操作**:
- 第 94 行 aqt install armv7 → 注释掉
- 第 209-221 行 armv7 编译 RUN → 整体注释掉
- 保留注释解释原因 (项目仅在 arm64-v8a 上跑, 跳过不影响最终 APK 构建)

**未来若需要 armv7**: 单独排查 aqt 安装 (可能需换镜像源, 或手动下载 Qt online installer 离线包)。

## 4. 修复效果

| 阶段 | 失败步号 | 错误类型 |
|---|---|---|
| 修复前 | 12/17 (qtquick3d 第一次 RUN) | WrapQuick3DAssimp target 缺失 (system_assimp=ON 路径) |
| 修复 §3.1 后 | 647/735 (assimp 编译) | ioapi.c 4 个 fopen64/ftello64/fseeko64 错误 |
| 修复 §3.2 后 | 652/735 (assimp 编译) | ioapi.c 2 个 ftello/fseeko 错误 |
| 修复 §3.3 后 | 15/18 (armv7 编译) | qt-cmake: Permission denied (aqt 装 armv7 残缺) |
| 修复 §3.4 后 | 预期通过 | (Docker Desktop 验证) |

每步修复都把进度往下推, 最终 arm64 + x86_64 两个 ABI 完整 RUN 应可走通。

## 5. 改动清单 (Dockerfile.android)

| 位置 | 改动 |
|---|---|
| L94 | 注释 `aqt install-qt ... android_armv7` 整行 (4 行解释注释) |
| L155-156 | 新增 `COPY qtquick3d-assimp-5.4.1.zip /tmp/qtquick3d-assimp-5.4.1.zip` |
| L164-169 | arm64 块 unzip qtquick3d 之后, 新增 5 行: `mkdir -p .../3rdparty/assimp/src` + `unzip` 到 staging + `mv` 三个子目录 + `rm -rf staging` |
| L176 | `-DQT_FEATURE_system_assimp=ON -DCMAKE_PREFIX_PATH=/usr` → `-DQT_FEATURE_system_assimp=OFF` |
| L176-179 | 新增 3 个 sed 补丁: IOAPI_NO_64 注入 + ftello→ftell + fseeko→fseek |
| L202 | x86_64 块同步 `system_assimp=OFF` (replace_all 一次改两处) |
| L210-221 | armv7 编译 RUN 整块注释 (8 行) |

## 6. 验证 (待用户在 Docker Desktop 执行)

```bash
cd H:\AI_Claude\work_dir\app
docker build -f Dockerfile.android -t test_qtquick3d_assimp_fix . 2>&1 | tee build.txt
```

预期: 18 步全过, 镜像构建成功。

## 7. 经验总结

1. **cross-compile 下的 apt assimp 不可靠**。Debian/Ubuntu 的 `libassimp-dev` 在 Android NDK 工具链 + qt-cmake 包装下, `assimp::assimp` IMPORTED target 创建不稳。vendored 源码更可控
2. **assimp 5.x 跟 QtQuick3D 6.x 版本必须对齐**。assimp 5.3 vs 5.4 有 ABI 差异 (新增 API / 头文件), 跟 Qt 自带 `revision.h` 的 `VER_MINOR/VER_PATCH` 必须匹配
3. **bionic libc 不等于 glibc**。POSIX 2008 扩展 (`fopen64` / `ftello` / `fseeko`) 在 Android NDK 26 上**没有**, 移植老代码时一定要查 `<features.h>` / `<stdio.h>`。macOS 走 `__APPLE__` 分支 + `ftello` 没问题, Android 还得再退到 `ftell`
4. **sed 注入宏是最小侵入的修补方式**。比 `apt install patch` / 自定义 `Dockerfile` 镜像层更轻, 比 `git apply` 更可控 (apt 装 patch 在 Docker 里增加 100MB+ 镜像)
5. **aqt 装多个 Android ABI 时, 任何一步失败会破坏后续 RUN**。`Permission denied` 不是 "目录不存在" 而是 "文件 stat 失败", 排查时第一反应是 `ls -la` 容器内目录, 而不是 "换源重试"

## 8. 相关文件

- `Dockerfile.android` — 容器化环境定义 (本轮主要修改)
- `qtquick3d-6.7.2.zip` — QtQuick3D 6.7.2 源码 (本项目预置, 53MB)
- `qtquick3d-assimp-5.4.1.zip` — assimp 5.4.1 上游源码 (本项目预置, 53MB)
- `build.txt` — 构建日志 (本轮排查的源证据)
- `doc/07-部署与发布/Docker构建APK手册.md` — 用户视角构建手册 (Q14 同步新增)
- `doc/01-方案设计/04-三方依赖与版本清单.md` — assimp 5.4.1 + qtquick3d 源码 zip 同步登记
