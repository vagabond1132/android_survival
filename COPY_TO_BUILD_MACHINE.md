# COPY_TO_BUILD_MACHINE.md

荒野手册（OutdoorSurvival）Android APK 构建同步清单

> 目的：开发机（Windows）→ 编译机（Linux）需要同步的内容清单，以及构建/验收流程。
> 解决背景：当前 `OutdoorSurvival-v0.0.1-release-arm64-v8a.apk` 内**缺少全部业务 Java 类**
> （`OutdoorSurvivalApp`、`EmergencyService`、`QtActivity` 均为 0 处）且**无 `lib/` 目录**
> （Qt native `.so` 缺失），导致设备启动即 `ClassNotFoundException`。
> 根因：`build_apk.sh` 中"复制 Java 源到 gradle 工程"的步骤（570-597 行）未生效。

---

## 一、必须拷贝的项目源码（开发机 → 编译机，增量同步）

以下内容位于 `H:\AI_Claude\work_dir\app\`，需完整同步到编译机对应目录：

```
app/
├── CMakeLists.txt          # 主构建配置（Qt 模块 / 包名 / QML / 资源 / 版本）
├── android/                # 整个目录（AndroidManifest / build.gradle / settings.gradle /
│                           #   gradle.properties / app/build.gradle / app/CMakeLists.txt /
│                           #   app/proguard-rules.pro / res/ / src/*.java）
├── qml/                    # 全部 .qml（Main.qml + pages/ + components/）
├── src/                    # C++ 全部源码（main.cpp + core/ + firstaid/ + species/ +
│                           #   survival/ + knots/ + routes/ + emergency/ + equipment/ +
│                           #   map/ + travel/ + platform/）
├── assets/data/            # 12 个数据 JSON（firstaid_entries、field_guide_*、
│                           #   danger_species、survival_items、knots、routes、
│                           #   checklists、travel、equipment_base、equipment_rules）
├── third_party/            # OpenSSL 3.x 预编译库（★必备，缺失则 Qt HTTPS 全灭、
│                           #   地图白底）。CMakeLists.txt 的 if(ANDROID) 块通过
│                           #   QT_ANDROID_EXTRA_LIBS 登记部署：
│                           #   third_party/android_openssl/ssl_3/<abi>/
│                           #     {libcrypto_3.so, libssl_3.so}  共 8 个 .so / 18MB
│                           #   注意后缀 _3 是 Qt 6 Android 官方约定，不可改名
├── build_apk.sh            # 构建脚本（核心，含 Java 复制逻辑）
├── keystore/               # 签名证书（不存在则脚本自动生成默认 outdoor.keystore）
└── COPY_TO_BUILD_MACHINE.md
```

> 注意：不要拷贝本机生成的 `.apk` / `build/` / `OutdoorSurvival-v0.0.1-release-arm64-v8a/` 解压目录。
> 这些都是产物，编译机会重新生成。

---

## 二、编译机环境依赖（确认版本即可，不需要从开发机拷贝）

| 依赖 | 路径 / 版本要求 | 说明 |
|---|---|---|
| Qt 6.7.2 | `/opt/Qt/6.7.2/` | 需含 `gcc_64`（host）与 `android_arm64_v8a` 两套 |
| Android SDK | `/opt/android-sdk` | 含 `build-tools/34.0.0`（apksigner 路径被硬编码） |
| Android NDK | `/opt/android-sdk/ndk/26.1.10909125` | `build_apk.sh` 默认值 |
| JDK | 17 | AGP 8.4.0 编译要求 |
| Gradle | `gradle-8.6-bin.zip` | 放到项目根目录，脚本自动解压；建议放 `app/gradle-8.6-bin.zip` |

> 路径均为 `build_apk.sh` 中的硬编码默认值。若编译机环境不同，需先改脚本顶部变量
> （`ANDROID_SDK`、`ANDROID_NDK`、`QT_BASE`）或用环境变量覆盖。

---

## 三、构建命令

```bash
# 在编译机的项目根目录执行（app/ 下）
CLEAN=1 bash build_apk.sh release arm64-v8a
```

- `CLEAN=1`：强制清理 CMake 缓存，确保全量重新配置（避免缓存了旧的 Java 源缺失状态）。
- 产物输出到 `dist/OutdoorSurvival-v0.0.1-release-arm64-v8a.apk`。

---

## 四、构建后验收（验证是否真正修复）

### 1. 确认 Java 源已进入 gradle 工程

```bash
ls build/release_arm64-v8a/android-build/app/src/main/java/com/outdoor/survival/
# 必须看到 OutdoorSurvivalApp.java 和 EmergencyService.java
```

### 2. 确认 APK 内含业务类与 native 库

```bash
unzip -l dist/OutdoorSurvival-v0.0.1-release-arm64-v8a.apk | grep -E "lib/|classes"
# 预期输出：
#   lib/arm64-v8a/libOutdoorSurvival.so    （native 库存在）
#   classes.dex                             （DEX 存在）

# 再确认 DEX 里有业务类（关键验收项）
unzip -p dist/OutdoorSurvival-v0.0.1-release-arm64-v8a.apk classes.dex | grep -c "OutdoorSurvivalApp"
# 预期输出 > 0
```

### 2b. 确认 OpenSSL 3.x 已进 APK（地图 / HTTPS 修复验收）

```bash
# (1) CMake configure 阶段应打印注入日志
#     [OpenSSL3] arm64-v8a: 注入 /.../third_party/android_openssl/ssl_3/arm64-v8a
#     若打印 WARNING "[OpenSSL3] 未找到 ..." → third_party/ 没同步到编译机

# (2) deployment-settings.json 应出现 "extraLibs" 键
grep -A3 '"extraLibs"' build/release_arm64-v8a/android-OutdoorSurvival-deployment-settings.json

# (3) APK 内 lib/arm64-v8a/ 必须有两个 OpenSSL 库（关键验收项）
unzip -l dist/OutdoorSurvival-v0.0.1-release-arm64-v8a.apk | grep -E "libcrypto_3|libssl_3"
# 预期输出：
#   lib/arm64-v8a/libcrypto_3.so
#   lib/arm64-v8a/libssl_3.so
```

### 3. 真机验证

安装 APK 后检查 logcat：

```bash
adb install -r dist/OutdoorSurvival-v0.0.1-release-arm64-v8a.apk
adb logcat -s AndroidRuntime:E OutdoorSurvival:I | head
```

- 不应再出现 `ClassNotFoundException: com.outdoor.survival.OutdoorSurvivalApp`。
- 应看到 `OutdoorSurvival: App started: com.outdoor.survival`（`OutdoorSurvivalApp.onCreate` 打点）。

---

## 五、常见故障排查

| 现象 | 可能原因 | 处理 |
|---|---|---|
| APK 仍无 `OutdoorSurvivalApp` | Java 复制步骤失败 / gradle 未读源码 | 检查 `build_apk.sh` 570-597 行的 `cp -r` 是否报错；确认 `android/src/com/outdoor/survival/` 目录存在且有 `.java` 文件 |
| APK 有类但无 `lib/` 目录 | CMake 编译或 native 打包失败 | 查看构建日志中 `cmake --build` 阶段是否成功；确认 `android/app/CMakeLists.txt` 的 `add_subdirectory` 能找到根 `CMakeLists.txt` |
| APK 无 `libcrypto_3.so`/`libssl_3.so` | `third_party/` 未同步到编译机 / 未 `CLEAN=1` 重 configure | 确认编译机存在 `third_party/android_openssl/ssl_3/arm64-v8a/`；确认 configure 日志无 `[OpenSSL3] 未找到` WARNING；确认 deployment-settings.json 有 `extraLibs` |
| gradle 报下载依赖超时 | 编译机无外网 / 镜像失效 | 检查 `android/settings.gradle` 的仓库镜像配置；确认 `gradle-8.6-bin.zip` 在项目根目录 |
| `apksigner` 验证失败 | SDK build-tools 版本不对 | 确认 `/opt/android-sdk/build-tools/34.0.0/apksigner` 存在 |
| 启动仍崩但类已存在 | 签名 / manifest 未合并 | 先装 `-debug` 版对比（`bash build_apk.sh debug arm64-v8a`），确认是否为签名问题 |
