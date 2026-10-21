#!/bin/bash
# 荒野手册 Android APK 完整打包脚本
# 用法：bash build_apk.sh [debug|release] [abi]
#   abi 可选：arm64-v8a (默认), x86_64
#     armeabi-v7a 已从可交付目标里去掉: 构建容器里只装了 android_arm64_v8a /
#     android_x86_64 两个 Qt kit, 没有 android_armv7 (2026-10-21 核对, 见
#     doc/08-索引与概念/全代码索引.md §18.3). 传 v7a 会在下面 Qt 包检查处直接报错停下.
#
# 日志输出:
#   全部 stdout/stderr 同时写入 $APP_DIR/build/build_<type>_<abi>.log
#   这样在 docker 容器里跑完后, 退出容器也能看到完整 build 报告

set -e

# ============================================================================
# 配置
# ============================================================================
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROJECT_ROOT"
ANDROID_DIR="$APP_DIR/android"
ANDROID_NDK=${ANDROID_NDK_HOME:-/opt/android-sdk/ndk/26.1.10909125}
ANDROID_SDK=${ANDROID_HOME:-/opt/android-sdk}
ANDROID_PLATFORM="android-34" # 强制指定平台标识，防止被外部错误环境变量覆盖
BUILD_TYPE="${1:-release}"
TARGET_ABI="${2:-arm64-v8a}"
QT_BASE=${QT_BASE:-/opt/Qt/6.7.2}

# 颜色 (提前定义, 让日志 tee 也能用)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 关键: 把每条 log_* 输出也追加到 LOG_FILE (不依赖 exec > >(tee), 避免
# docker 容器退出时 detached tee 没收尾导致 dex 校验段日志丢失)
# 改用更稳的双写: 主 fd 走 console (docker compose run 的 stdout),
# 同时每行 echo 末尾追加到 LOG_FILE.
# 2026-09-10: 加 [HH:MM:SS] 时间戳, 排查超时/卡死时能看出哪步耗时长
_ts() { date +%H:%M:%S; }
_orig_log_info() { echo -e "${GREEN}[INFO]${NC} [$(date +%H:%M:%S)] $1"; }
_orig_log_warn() { echo -e "${YELLOW}[WARN]${NC} [$(date +%H:%M:%S)] $1"; }
_orig_log_error() { echo -e "${RED}[ERROR]${NC} [$(date +%H:%M:%S)] $1"; }
log_info()  { _orig_log_info "$1";  echo -e "${GREEN}[INFO]${NC} [$(date +%H:%M:%S)] $1" >> "$LOG_FILE"; }
log_warn()  { _orig_log_warn "$1";  echo -e "${YELLOW}[WARN]${NC} [$(date +%H:%M:%S)] $1" >> "$LOG_FILE"; }
log_error() { _orig_log_error "$1"; echo -e "${RED}[ERROR]${NC} [$(date +%H:%M:%S)] $1" >> "$LOG_FILE"; }

# ============================================================================
# 长期可维护性标准: 阶段标签 + die 函数 + 统一错误处理
# ============================================================================
# 设计目的:
#   1) 每个阶段有清晰的 begin/end 标签, 日志可定位
#   2) die() 替代裸 exit 1, 强制打印错误位置
#   3) assert_file() / assert_cmd() 显式契约, 阶段间必跑
#   4) critical_step() 替代 set -e 静默抓错
# ============================================================================

# 当前阶段标签 (1-4: prepare/build-app/deploy/verify)
STAGE=0
# 阶段开始 epoch 秒 (整型, 由 stage_begin 写入, stage_end 读出走时差)
STAGE_START_EPOCH=0
# 整个脚本开始 epoch (用于输出总耗时)
SCRIPT_START_EPOCH=$(date +%s)
stage_begin() {
    STAGE=$1
    local name="$2"
    STAGE_START_EPOCH=$(date +%s)
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    log_info "[STAGE $STAGE/$TOTAL_STAGES] ▶ BEGIN: $name"
    echo "════════════════════════════════════════════════════════════════"
}
# 格式化秒数为 "Xm Ys" 或 "Ys"
_format_duration() {
    local secs=$1
    if [ "$secs" -ge 60 ]; then
        local m=$((secs / 60))
        local s=$((secs % 60))
        echo "${m}m${s}s"
    else
        echo "${secs}s"
    fi
}
stage_end() {
    local end_epoch
    end_epoch=$(date +%s)
    local dur=$((end_epoch - STAGE_START_EPOCH))
    local total_dur=$((end_epoch - SCRIPT_START_EPOCH))
    log_info "[STAGE $STAGE/$TOTAL_STAGES] ■ END OK (本阶段: $(_format_duration $dur), 累计: $(_format_duration $total_dur))"
}
TOTAL_STAGES=4

# die: 带堆栈位置的致命退出
die() {
    local msg="$1"
    local code=${2:-1}
    log_error "FATAL [STAGE $STAGE]: $msg"
    log_error "退出码: $code"
    log_error "调用位置: ${BASH_SOURCE[1]}:${BASH_LINENO[0]}"
    exit "$code"
}

# assert_file: 断言文件存在, 不存在则 die
assert_file() {
    local f="$1"
    local desc="${2:-文件}"
    [ -f "$f" ] || die "$desc 不存在: $f"
}

# assert_dir: 断言目录存在, 不存在则 die
assert_dir() {
    local d="$1"
    local desc="${2:-目录}"
    [ -d "$d" ] || die "$desc 不存在: $d"
}

# assert_cmd: 断言命令可执行, 不存在则 die
assert_cmd() {
    local cmd="$1"
    local desc="${2:-命令}"
    command -v "$cmd" >/dev/null 2>&1 || die "$desc 不可执行: $cmd (PATH=$PATH)"
}

# critical_step: 包装命令, 失败时 die 并显示命令
critical_step() {
    local desc="$1"
    shift
    log_info "执行: $desc"
    log_info "命令: $*"
    # 2026-10-19: 原来写 `if ! "$@"; then local rc=$?` —— `!` 已把状态位取反,
    #   $? 恒为 0, die 只报 "失败 (rc=0)", 脚本以 0 退出. 结果一次 C++ 编译失败
    #   (ImageFetcherService.cpp 编译错误) 被 docker compose run 当成成功返回,
    #   白跑一轮. 改成 || 捕获真实 rc 并原样传给 die.
    local rc=0
    "$@" || rc=$?
    if [ "$rc" -ne 0 ]; then
        die "$desc 失败 (rc=$rc)" "$rc"
    fi
}

# 关键: 全部 stdout + stderr 同时写入 build/build_<type>_<abi>.log
# 用普通 tee (不是 exec > >(tee)) + 末尾 restore, 避免 docker 容器退出时
# detached tee 子进程未收尾导致 dex 校验段日志丢失
mkdir -p "$APP_DIR/build"
LOG_FILE="$APP_DIR/build/build_${BUILD_TYPE}_${TARGET_ABI}.log"
: > "$LOG_FILE"
log_info "📄 完整日志同时写入: $LOG_FILE"
log_info "🛠  构建标准: 4 阶段 (prepare/build-app/deploy/verify), 关键阶段带 die() 断言"
QT_HOST_PATH=${QT_HOST_PATH:-$QT_BASE/gcc_64}
KEYSTORE_PATH="${KEYSTORE_PATH:-$APP_DIR/keystore/outdoor.keystore}"
KEYSTORE_PASSWORD="${KEYSTORE_PASSWORD:-outdoor123}"
KEY_ALIAS="${KEY_ALIAS:-outdoor}"
KEY_PASSWORD="${KEY_PASSWORD:-outdoor123}"
# 关键: APP_NAME 必须从 CMakeLists.txt:40 解析, 不能依赖环境变量!
# 原因:
#   - CMakeLists.txt:40 set(APP_NAME "OutdoorSurvival") 硬编码
#   - 但容器里经常 export APP_NAME=荒野手册 (中文显示名, 用作其他用途)
#   - 如果 build_apk.sh 用 $APP_NAME 拼 .so 路径, 会拼成 lib荒野手册_arm64-v8a.so
#   - 实际 CMake 生成的 .so 是 libOutdoorSurvival_arm64-v8a.so → 找不到
# 解决: 直接 grep CMakeLists.txt 拿真值, 忽略环境变量 (unset 避免污染).
unset APP_NAME
APP_NAME_SAFE=""
if [ -f "$APP_DIR/CMakeLists.txt" ]; then
    # 用 awk 提取 set(APP_NAME "...") 第一个字符串参数, 兼容括号内空格
    APP_NAME_SAFE=$(awk '/^[[:space:]]*set\(APP_NAME[[:space:]]+"/ {
        gsub(/^[[:space:]]*set\(APP_NAME[[:space:]]+"/, "")
        gsub(/".*$/, "")
        print
        exit
    }' "$APP_DIR/CMakeLists.txt" 2>/dev/null)
fi
case "${APP_NAME_SAFE:-}" in
    "") APP_NAME_SAFE="OutdoorSurvival" ;;
esac
log_info "  APP_NAME_SAFE: $APP_NAME_SAFE (从 CMakeLists.txt 解析, 忽略环境变量)"

# ============================================================================
# STAGE 1/4: PREPARE - 检查环境, 准备路径
# ============================================================================
stage_begin 1 "PREPARE - 检查环境, 准备路径"
log_info "检查环境..."

# 关键阶段间断言: 关键路径必须在脚本早期就存在
assert_dir "$ANDROID_NDK" "Android NDK"
assert_dir "$QT_BASE" "Qt 安装根"
assert_cmd keytool "keytool (Java 工具链)"

if [ ! -d "$ANDROID_NDK" ]; then
    log_error "Android NDK 未找到: $ANDROID_NDK"
    exit 1
fi

if [ ! -d "$QT_BASE" ]; then
    log_error "Qt 未找到: $QT_BASE"
    exit 1
fi

# 检查 Qt Android 包
case "$TARGET_ABI" in
    arm64-v8a)
        QT_QPA="$QT_BASE/android_arm64_v8a"
        ;;
    armeabi-v7a)
        # 2026-10-21: 这里以前指向 $QT_BASE/android_armv7, 而构建镜像里根本没装那个 kit
        # (/opt/Qt/6.7.2 只有 gcc_64 / android_arm64_v8a / android_x86_64), 于是会一路走到
        # 下面的 [ ! -d "$QT_QPA" ] 才失败, 报一句"Qt 包没找到"让人以为环境坏了.
        # 真机是 arm64、模拟器是 x86_64, v7a 不在交付范围 → 在这一步就说清楚原因停下.
        log_error "armeabi-v7a 不再支持: 构建镜像里没有 android_armv7 这个 Qt kit (只出 arm64-v8a / x86_64)"
        exit 1
        ;;
    x86_64)
        QT_QPA="$QT_BASE/android_x86_64"
        ;;
    *)
        log_error "不支持的 ABI: $TARGET_ABI"
        exit 1
        ;;
esac

if [ ! -d "$QT_QPA" ]; then
    log_error "Qt Android 包未找到: $QT_QPA"
    exit 1
fi

log_info "环境检查通过"

# ============================================================================
# 准备
# ============================================================================
mkdir -p "$APP_DIR/keystore"
mkdir -p "$APP_DIR/build"

# 创建 keystore（如果不存在）
if [ ! -f "$KEYSTORE_PATH" ]; then
    log_info "创建签名 keystore: $KEYSTORE_PATH"
    keytool -genkey -v -keystore "$KEYSTORE_PATH" \
        -alias "$KEY_ALIAS" \
        -keyalg RSA -keysize 2048 -validity 25000 \
        -storepass "$KEYSTORE_PASSWORD" \
        -keypass "$KEY_PASSWORD" \
        -dname "CN=OutdoorSurvival, OU=Outdoor, O=Outdoor, L=Beijing, ST=Beijing, C=CN" \
        2>&1 | tail -5
fi
assert_file "$KEYSTORE_PATH" "签名 keystore"

stage_end

# ============================================================================
# 构建
# ============================================================================
BUILD_DIR="$APP_DIR/build/${BUILD_TYPE}_${TARGET_ABI}"

# 增量编译: 默认保留 CMake 缓存, 只在以下情况清理:
#   1. 显式 CLEAN=1 (强制全量重建)
#   2. CMakeCache.txt 不存在 (首次构建)
#   3. CMakeLists.txt 比 CMakeCache.txt 新 (配置变更, 缓存失效)
# 否则保留缓存, Ninja 会只重编变更的 cpp, 大幅缩短二次构建时间.
NEED_CLEAN=0
if [ "${CLEAN:-0}" = "1" ]; then
    NEED_CLEAN=1
    log_info "CLEAN=1, 强制清理 CMake 缓存"
elif [ ! -f "$BUILD_DIR/CMakeCache.txt" ]; then
    NEED_CLEAN=1
    log_info "首次构建, 无 CMakeCache.txt"
elif [ "$APP_DIR/CMakeLists.txt" -nt "$BUILD_DIR/CMakeCache.txt" ]; then
    NEED_CLEAN=1
    log_info "CMakeLists.txt 已更新, 清理 CMake 缓存以重新配置"
fi

# 2026-09-15: 增量构建下, .qml 改动不会触发 qmlcachegen 重生成
# (Ninja 只看 CMakeLists.txt + 源 cpp 依赖, 不感知 qml 文件)
# 解决: 检测 .qml 文件比 .rcc/qmlcache 新, 就清 qmlcache 让 qmlcachegen 重新跑
if [ -d "$BUILD_DIR/.rcc/qmlcache" ]; then
    NEWEST_QML=$(find "$APP_DIR/qml" -name "*.qml" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1)
    OLDEST_QMLCACHE=$(find "$BUILD_DIR/.rcc/qmlcache" -name "*_qml.cpp" -type f -printf '%T@\n' 2>/dev/null | sort -n | head -1)
    if [ -n "$NEWEST_QML" ] && [ -n "$OLDEST_QMLCACHE" ]; then
        # 浮点比较: 最老的 qmlcache 比最新的 qml 还老, 说明缓存过期
        if awk -v qml="$NEWEST_QML" -v cache="$OLDEST_QMLCACHE" 'BEGIN{exit !(qml>cache)}' ; then
            NEED_CLEAN=1
            log_info "检测到 .qml 比 qmlcache 新, 清理 qmlcache 触发 qmlcachegen 重生成"
        fi
    fi
fi

if [ "$NEED_CLEAN" = "1" ]; then
    rm -rf "$BUILD_DIR/CMakeCache.txt" "$BUILD_DIR/CMakeFiles"
fi
mkdir -p "$BUILD_DIR"

log_info "=========================================="
log_info "构建配置:"
log_info "  构建类型: $BUILD_TYPE"
log_info "  目标 ABI: $TARGET_ABI"
log_info "  Qt 路径: $QT_BASE"
log_info "  NDK 路径: $ANDROID_NDK"
log_info "  SDK 路径: $ANDROID_SDK"
log_info "  构建目录: $BUILD_DIR"
log_info "=========================================="

# 导出并强制修正环境变量（关键修复点）
export ANDROID_NDK_ROOT="$ANDROID_NDK"
export ANDROID_SDK_ROOT="$ANDROID_SDK"
export ANDROID_PLATFORM="android-34" # 强制重置，防止外部污染
export QT_HOST_PATH="$QT_HOST_PATH"

# 确保 JAVA_HOME 存在
if [ -z "$JAVA_HOME" ]; then
    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
fi

# 使用 Qt 提供的 qt-cmake 包装脚本
QT_CMAKE="$QT_QPA/bin/qt-cmake"

if [ ! -f "$QT_CMAKE" ]; then
    log_error "qt-cmake 未找到: $QT_CMAKE"
    exit 1
fi

# ============================================================================
# STAGE 2/4: BUILD-APP - CMake 配置 + C++ 编译
# ============================================================================
stage_begin 2 "BUILD-APP - CMake 配置 + C++ 编译 (Ninja)"
log_info "配置 CMake (使用 qt-cmake)..."
critical_step "CMake configure" "$QT_CMAKE" \
    -DANDROID_SDK_ROOT="$ANDROID_SDK" \
    -DANDROID_NDK_ROOT="$ANDROID_NDK" \
    -DQT_HOST_PATH="$QT_HOST_PATH" \
    -DCMAKE_BUILD_TYPE=$([ "$BUILD_TYPE" = "debug" ] && echo "Debug" || echo "Release") \
    -S "$APP_DIR" \
    -B "$BUILD_DIR"

# 阶段间断言: CMakeCache.txt 必须生成
assert_file "$BUILD_DIR/CMakeCache.txt" "CMake configure 产物"

# 关键阶段间断言: deployment-settings.json 必须生成 (qtAndroidSourceDir 注入后才能用)
# 兼容 Qt 6.7 两种命名
# 关键: 用 APP_NAME_SAFE 兜底, 避免 APP_NAME 未定义或为空时路径错位
DEPLOY_JSON_AFTER_CMAKE=""
for cand in \
    "$BUILD_DIR/android-${APP_NAME_SAFE}-deployment-settings.json" \
    "$BUILD_DIR/lib${APP_NAME_SAFE}_${TARGET_ABI}-deployment.json"; do
    [ -f "$cand" ] && DEPLOY_JSON_AFTER_CMAKE="$cand" && break
done
if [ -n "$DEPLOY_JSON_AFTER_CMAKE" ]; then
    log_info "  ✅ deployment-settings.json 已生成: $DEPLOY_JSON_AFTER_CMAKE"
    # 验证 qtAndroidSourceDir 注入 (用 python3 准确查 JSON key, 兼容引号格式)
    if command -v python3 >/dev/null 2>&1; then
        QT_SRC_DIR=$(python3 -c "
import json
with open('$DEPLOY_JSON_AFTER_CMAKE') as f:
    d = json.load(f)
print(d.get('qtAndroidSourceDir', ''))
" 2>/dev/null)
        if [ -n "$QT_SRC_DIR" ]; then
            log_info "  ✅ qtAndroidSourceDir 已注入 (CMake 阶段): $QT_SRC_DIR"
        else
            log_warn "  ⚠️  qtAndroidSourceDir 未注入, build_apk.sh 会兜底"
        fi
    else
        log_warn "  ⚠️  python3 不可用, 无法验证 qtAndroidSourceDir"
    fi
fi

# ============================================================================
# 离线 Gradle 预填 (必须在 cmake --build 之前!)
# 关键: Qt 6 的 _make_apk 目标在 cmake --build 阶段自动调 androiddeployqt,
#       它会调 gradle-wrapper.jar, wrapper 找不到发行包就会下载.
#       所以必须先解压到 ~/.gradle/wrapper/dists/... 命中 wrapper 缓存.
# 关键 2: 我们会让脚本不调 Qt 的 _make_apk 目标, 而是手动跑 androiddeployqt
# ============================================================================
log_info "预填 Gradle 发行包..."

# 用 bash 内置函数计算 base36 hash (md5 + BigInteger toString(36))
# 等价于: BigInteger(md5_hex_as_int).toString(36)
to_base36() {
    local hex="$1"
    local n=0
    local i v c
    for ((i=0; i<${#hex}; i++)); do
        c=${hex:$i:1}
        case "$c" in
            0) v=0;; 1) v=1;; 2) v=2;; 3) v=3;; 4) v=4;;
            5) v=5;; 6) v=6;; 7) v=7;; 8) v=8;; 9) v=9;;
            a) v=10;; b) v=11;; c) v=12;; d) v=13;; e) v=14;; f) v=15;;
        esac
        n=$((n*16 + v))
    done
    if [ $n -eq 0 ]; then
        echo "0"
        return
    fi
    local result=""
    local alpha="0123456789abcdefghijklmnopqrstuvwxyz"
    while [ $n -gt 0 ]; do
        local rem=$((n % 36))
        local ch=${alpha:$rem:1}
        result="$ch$result"
        n=$((n / 36))
    done
    echo "$result"
}

GRADLE_LOCAL_ZIP=""
GRADLE_VER=""
GRADLE_BIN=""
GRADLE_USER_HOME="${GRADLE_USER_HOME:-$HOME/.gradle}"
export GRADLE_USER_HOME

# ----------------------------------------------------------------------------
# 清理 ~/.gradle/gradle.properties 里 AGP 8.1+ 已移除的选项
# 原因: 之前构建可能在 ~/.gradle/gradle.properties (gradle-cache volume 持久化)
#       残留 android.bundle.enableUncompressedNativeLibs 选项, AGP 8.4 会报:
#       "The option 'android.bundle.enableUncompressedNativeLibs' is deprecated.
#        It was removed in version 8.1 of the Android Gradle plugin."
#       直接删除该文件 (项目里没有 gradle.properties, 不影响功能)
# ----------------------------------------------------------------------------
USER_GRADLE_PROPS="$GRADLE_USER_HOME/gradle.properties"
if [ -f "$USER_GRADLE_PROPS" ]; then
    if grep -q "android.bundle.enableUncompressedNativeLibs" "$USER_GRADLE_PROPS" 2>/dev/null; then
        log_warn "发现 $USER_GRADLE_PROPS 含已废弃选项, 删除该文件"
        rm -f "$USER_GRADLE_PROPS"
    fi
fi

# ----------------------------------------------------------------------------
# 注入阿里云 Maven 镜像 (init.gradle)
# 原因: androiddeployqt 内部 gradle 需要拉 AGP/google/central 依赖, 容器内断外网
# 通过 $GRADLE_USER_HOME/init.d/ 注入镜像, 对所有项目生效, 不必改 androiddeployqt
# 生成的 build.gradle/settings.gradle
# ----------------------------------------------------------------------------
mkdir -p "$GRADLE_USER_HOME/init.d"
cat > "$GRADLE_USER_HOME/init.d/aliyun-mirror.gradle" << 'EOF'
// 阿里云 Maven 镜像 (init 脚本兜底)
// 注意: 项目仓库 (普通 dependencies) 已经在 settings.gradle 的
//       dependencyResolutionManagement.repositories 里声明了阿里云镜像,
//       此处不再通过 allprojects { repositories { ... } } 注入, 因为会被
//       FAIL_ON_PROJECT_REPOS / PREFER_SETTINGS 模式拦截:
//         "repository 'maven' was added by initialization script"
// 此处只保留 buildscript 仓库 (AGP classpath 等) 的镜像兜底, buildscript
// 不受 repositoriesMode 限制, 可以安全添加.
allprojects {
    buildscript {
        repositories {
            // 多个国内镜像 + 官方源做 fallback, 避免单源限流/断网导致全部失败
            maven { url 'https://maven.aliyun.com/repository/gradle-plugin' }
            maven { url 'https://maven.aliyun.com/repository/google' }
            maven { url 'https://maven.aliyun.com/repository/central' }
            maven { url 'https://maven.aliyun.com/repository/public' }
            maven { url 'https://mirrors.cloud.tencent.com/nexus/repository/maven-public/' }
            maven { url 'https://repo.huaweicloud.com/repository/maven/' }
            google()
            mavenCentral()
            gradlePluginPortal()
        }
    }
}
EOF
log_info "已注入阿里云 Maven 镜像: $GRADLE_USER_HOME/init.d/aliyun-mirror.gradle"

# 查找本地 Gradle zip: 优先选版本最高的 (AGP 8.4 要求 Gradle 8.6+)
# glob 按字典序返回, 会优先选到 8.3 而非 8.6, 所以要按版本号排序选最高
BEST_GRADLE_VER=""
BEST_GRADLE_ZIP=""
for candidate in "$APP_DIR"/gradle-*.zip "$APP_DIR"/gradle.zip; do
    [ -f "$candidate" ] || continue
    # 从文件名提取版本号 (支持 gradle-8.6-bin.zip / gradle-8.6-rc-4-bin.zip / gradle-9.7.1-bin.zip)
    bn=$(basename "$candidate")
    ver=$(echo "$bn" | sed -E 's/^gradle-?([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/')
    [ -z "$ver" ] && ver="0"
    # 版本比较: 用 sort -V 降序, 取第一个
    if [ -z "$BEST_GRADLE_VER" ] || \
       [ "$(printf "%s\n%s\n" "$ver" "$BEST_GRADLE_VER" | sort -V | head -1)" != "$ver" ]; then
        BEST_GRADLE_VER="$ver"
        BEST_GRADLE_ZIP="$candidate"
    fi
done
GRADLE_LOCAL_ZIP="$BEST_GRADLE_ZIP"

# 找不到本地 Gradle zip 时, 从国内镜像自动下载 (腾讯云/阿里云)
# 下载稳定版 gradle-8.6-bin.zip (满足 AGP 8.4+ 的最低要求)
# 优先腾讯云, 失败再阿里云, 都失败才退出
if [ -z "$GRADLE_LOCAL_ZIP" ]; then
    REQUIRED_GRADLE_VERSION="8.6"
    TARGET_ZIP="$APP_DIR/gradle-${REQUIRED_GRADLE_VERSION}-bin.zip"
    MIRRORS=(
        "https://mirrors.cloud.tencent.com/gradle/gradle-${REQUIRED_GRADLE_VERSION}-bin.zip"
        "https://mirrors.aliyun.com/macports/distfiles/gradle/gradle-${REQUIRED_GRADLE_VERSION}-bin.zip"
        "https://services.gradle.org/distributions/gradle-${REQUIRED_GRADLE_VERSION}-bin.zip"
    )
    log_warn "未找到本地 Gradle zip, 尝试从国内镜像下载 gradle-${REQUIRED_GRADLE_VERSION}-bin.zip"
    for url in "${MIRRORS[@]}"; do
        log_info "尝试下载: $url"
        if curl -fSL --connect-timeout 10 --max-time 300 -o "$TARGET_ZIP" "$url"; then
            if [ -s "$TARGET_ZIP" ]; then
                GRADLE_LOCAL_ZIP="$TARGET_ZIP"
                log_info "✅ 下载成功: $GRADLE_LOCAL_ZIP ($(du -h "$GRADLE_LOCAL_ZIP" | cut -f1))"
                break
            fi
        fi
        log_warn "下载失败: $url"
        rm -f "$TARGET_ZIP" 2>/dev/null
    done
fi

# 下载仍然失败, 退出
if [ -z "$GRADLE_LOCAL_ZIP" ]; then
    log_error "未找到本地 Gradle 发行包, 国内镜像下载也失败"
    log_error "请手工下载 gradle-8.6-bin.zip 放到 $APP_DIR/ 下后重试"
    log_error "推荐镜像:"
    log_error "  腾讯云: https://mirrors.cloud.tencent.com/gradle/gradle-8.6-bin.zip"
    log_error "  阿里云: https://mirrors.aliyun.com/macports/distfiles/gradle/gradle-8.6-bin.zip"
    exit 1
fi

log_info "检测到本地 Gradle 发行包: $GRADLE_LOCAL_ZIP"

# 从 zip 文件名识别版本号
zip_basename=$(basename "$GRADLE_LOCAL_ZIP" .zip)
    GRADLE_VER=$(echo "$zip_basename" | sed -E 's/^gradle-?([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/')
    if [ -z "$GRADLE_VER" ] || [ "$GRADLE_VER" = "$zip_basename" ]; then
        GRADLE_VER=$(unzip -l "$GRADLE_LOCAL_ZIP" 2>/dev/null \
            | awk '{print $4}' | grep -oE '^gradle-[0-9]+\.[0-9]+(\.[0-9]+)?' \
            | head -1 | sed 's/^gradle-//')
    fi
    if [ -z "$GRADLE_VER" ]; then
        log_error "无法从 $GRADLE_LOCAL_ZIP 识别 Gradle 版本"
        exit 1
    fi
    log_info "Gradle 版本: $GRADLE_VER"

    TOP_DIR=$(unzip -l "$GRADLE_LOCAL_ZIP" 2>/dev/null \
        | awk '{print $4}' | grep -oE '^gradle-[0-9]+\.[0-9]+(\.[0-9]+)?/' \
        | head -1 | sed 's:/$::')
    [ -z "$TOP_DIR" ] && TOP_DIR="gradle-$GRADLE_VER"
    log_info "zip 顶层目录: $TOP_DIR"

    # === 预填一个明确的位置 ===
    # === 解压 gradle 到容器本地文件系统, 不用 named volume ===
    # 原因: Docker 可能把 /root/.gradle (gradle-cache volume) 标记为 noexec,
    #       导致 gradle 二进制虽 -rwxr-xr-x 但无法执行
    # 用 zip 路径的 md5 前 8 位作为子目录名(避免冲突)
    GRADLE_HASH=$(echo -n "$GRADLE_LOCAL_ZIP" | md5sum | cut -c1-8)
    GRADLE_INSTALL_DIR="/opt/gradle-install/$GRADLE_HASH"
    GRADLE_BIN="$GRADLE_INSTALL_DIR/$TOP_DIR/bin/gradle"
    GRADLE_OK_MARKER="/opt/gradle-install/$GRADLE_HASH/.installed"

    mkdir -p "$GRADLE_INSTALL_DIR"
    if [ ! -x "$GRADLE_BIN" ]; then
        log_info "[hash=$GRADLE_HASH] 解压 Gradle 到: $GRADLE_INSTALL_DIR (本地文件系统)"
        rm -rf "$GRADLE_INSTALL_DIR" 2>/dev/null || true
        mkdir -p "$GRADLE_INSTALL_DIR"
        TMP_DIR=$(mktemp -d)
        log_info "  临时目录: $TMP_DIR"
        if ! unzip -q "$GRADLE_LOCAL_ZIP" -d "$TMP_DIR"; then
            log_error "解压失败"
            rm -rf "$TMP_DIR"
            exit 1
        fi
        log_info "  zip 顶层: $(ls "$TMP_DIR" | head -3)"
        # zip 通常含 gradle-<ver>/ 顶层目录; 但若没有, 也可能直接展开
        if [ -d "$TMP_DIR/$TOP_DIR" ]; then
            log_info "  复制 $TMP_DIR/$TOP_DIR/* 到 $GRADLE_INSTALL_DIR/"
            cp -r "$TMP_DIR/$TOP_DIR"/. "$GRADLE_INSTALL_DIR/" || { log_error "cp 失败"; exit 1; }
        else
            log_info "  复制 $TMP_DIR/* 到 $GRADLE_INSTALL_DIR/ (无顶层目录)"
            cp -r "$TMP_DIR"/. "$GRADLE_INSTALL_DIR/" || { log_error "cp 失败"; exit 1; }
        fi
        log_info "  解压后目录: $(ls "$GRADLE_INSTALL_DIR" | head -5)"

        # 关键修复: 不再按 $TOP_DIR 拼接, 动态探测真实的 bin/gradle 位置
        # 原因: 上面 cp 已把内容展平到 $GRADLE_INSTALL_DIR 根, 不论 zip 是否含顶层目录
        FOUND_GRADLE_BIN=$(find "$GRADLE_INSTALL_DIR" -name "gradle" -type f -path "*/bin/gradle" 2>/dev/null | head -1)
        if [ -z "$FOUND_GRADLE_BIN" ]; then
            log_error "未在 $GRADLE_INSTALL_DIR 中找到 gradle 二进制"
            ls -laR "$GRADLE_INSTALL_DIR" 2>/dev/null | head -30
            rm -rf "$TMP_DIR"
            exit 1
        fi
        GRADLE_BIN="$FOUND_GRADLE_BIN"
        log_info "  bin 目录: $(ls "$(dirname "$GRADLE_BIN")" 2>/dev/null | head -5)"
        log_info "  gradle 路径: $GRADLE_BIN"

        rm -rf "$TMP_DIR"
        chmod +x "$GRADLE_BIN" || { log_error "chmod 失败: $GRADLE_BIN"; exit 1; }
        touch "$GRADLE_OK_MARKER"
    else
        log_info "Gradle 已就绪: $GRADLE_BIN"
    fi

    # 显式重新验证 gradle 可执行
    if [ -x "$GRADLE_BIN" ]; then
        log_info "✅ Gradle 就绪: $GRADLE_BIN"
    else
        log_error "Gradle 二进制不可执行: $GRADLE_BIN"
        ls -la "$GRADLE_INSTALL_DIR/$TOP_DIR/bin/" 2>&1 | head -5
        log_info "尝试直接执行: $GRADLE_BIN --version"
        "$GRADLE_BIN" --version 2>&1 | head -3
        exit 1
    fi

# 持久化 gradle 路径
if [ -n "$GRADLE_LOCAL_ZIP" ] && [ -x "$GRADLE_BIN" ]; then
    echo "$GRADLE_BIN" > "$APP_DIR/.gradle_bin_path"
else
    log_warn "GRADLE_BIN 未就绪"
fi

# 编译(排除 _make_apk 目标, 我们手动调用)
log_info "开始编译 (排除 Qt 的 _make_apk 自动目标)..."
critical_step "C++ 编译 (Ninja)" cmake --build "$BUILD_DIR" --config $([ "$BUILD_TYPE" = "debug" ] && echo "Debug" || echo "Release") \
    -j"${BUILD_JOBS:-$(nproc)}" --target OutdoorSurvival

# 阶段间断言: 编译产物 .so 必须存在
PROJECT_SO="$BUILD_DIR/lib${APP_NAME_SAFE}_${TARGET_ABI}.so"
[ -f "$PROJECT_SO" ] || [ -f "$BUILD_DIR/lib${APP_NAME_SAFE}.so" ] || {
    log_info "  BUILD_DIR 顶层 .so 列表:"
    ls -la "$BUILD_DIR"/*.so 2>/dev/null || echo "  (无)"
    die "编译产物 .so 不存在: $PROJECT_SO"
}
log_info "  ✅ 编译产物 .so 已生成"

# 关键: 必须 install 才能让 androiddeployqt 找到 application binary
# ----------------------------------------------------------------------------
# androiddeployqt 期望 binary 在:
#   <build>/android-build/libs/<abi>/lib<target>_<abi>.so
# 来源是 cmake --install 把 lib<target>.so 装到 CMAKE_INSTALL_PREFIX (= android-build) + lib/
# 不调 install, androiddeployqt 必报 'Cannot find application binary'
#
# 注意: install() 段还会调 qt_generate_deploy_qml_app_script, 把 qml/assets 复制
#       到 lib/. 这是 androiddeployqt 后续找 qml 资源的来源. 跳过 install 会导致
#       QML 加载失败.
# ----------------------------------------------------------------------------
log_info "执行 install (生成 androiddeployqt 所需的 libs/<abi>/lib<target>_<abi>.so)"

# 关键: 显式指定 --prefix android-build/, 避免 NDK toolchain 默认值不一致
# (有些 NDK 工具链 CMAKE_INSTALL_PREFIX=/usr/local, 会让 install 装到错的目录)
INSTALL_PREFIX="$BUILD_DIR/android-build"
critical_step "cmake install (prefix=$INSTALL_PREFIX)" \
    cmake --install "$BUILD_DIR" --config $([ "$BUILD_TYPE" = "debug" ] && echo "Debug" || echo "Release") \
    --prefix "$INSTALL_PREFIX"

# 阶段间断言: install 后的 binary 必须存在
# 路径: <BUILD_DIR>/android-build/lib/lib<target>_<abi>.so (CMake install 默认)
# 注意: 错误信息说 "build dir .../android-build//libs/<abi>/..." 是 androiddeployqt 期望路径.
#       但实际 install 把 binary 装到 lib/ (单层). 需要在断言前补一次 cp 到 libs/<abi>/.
# ----------------------------------------------------------------------------
# 阶段间断言: install 后的 binary 必须存在
# 关键: CMakeLists.txt 在 Android 工具链下设 CMAKE_INSTALL_LIBDIR=libs/<abi>
#       所以 install 实际路径 = <BUILD_DIR>/android-build/libs/<abi>/lib<target>_<abi>.so
#       这正好匹配 androiddeployqt 期望路径, 不需要 cp 同步
# ----------------------------------------------------------------------------
ANDROID_BUILD_LIBS_DIR="$BUILD_DIR/android-build/libs/$TARGET_ABI"
INSTALL_REAL="$ANDROID_BUILD_LIBS_DIR/lib${APP_NAME_SAFE}_${TARGET_ABI}.so"
[ -f "$INSTALL_REAL" ] || {
    log_info "  期望路径: $ANDROID_BUILD_LIBS_DIR/"
    log_info "  实际内容:"
    ls -la "$ANDROID_BUILD_LIBS_DIR/" 2>/dev/null || echo "  (目录不存在)"
    # 兜底: 看 lib/ (兼容老 Qt 6 默认)
    ANDROID_BUILD_LIB_DIR="$BUILD_DIR/android-build/lib"
    if [ -f "$ANDROID_BUILD_LIB_DIR/lib${APP_NAME_SAFE}_${TARGET_ABI}.so" ]; then
        log_info "  ⚠️  发现老路径 .so, 同步到 libs/<abi>/"
        mkdir -p "$ANDROID_BUILD_LIBS_DIR"
        cp -f "$ANDROID_BUILD_LIB_DIR/lib${APP_NAME_SAFE}_${TARGET_ABI}.so" "$INSTALL_REAL"
    else
        die "install 后未找到 application binary: $INSTALL_REAL"
    fi
}
log_info "  ✅ install 产物 .so: $INSTALL_REAL"

stage_end

# ============================================================================
# STAGE 3/4: DEPLOY - androiddeployqt (--no-build) + 手动 gradle assembleRelease
# ============================================================================
stage_begin 3 "DEPLOY - androiddeployqt (--no-build) + 手动 gradle assembleRelease"

# ----------------------------------------------------------------------------
# 调用 androiddeployqt (--no-build), 走混合流程 (稳定方案, B):
#   1) 注入 qtAndroidSourceDir 到 deployment.json (指向项目 android/)
#   2) androiddeployqt 生成项目骨架 (含 res/values/libs.xml, QtLoader 必需)
#   3) 我们 sed 修 Qt 模板 build.gradle (移除 AGP 8.1+ 废弃选项)
#   4) 覆盖项目 build.gradle / app/build.gradle / AndroidManifest 等
#   5) 手动 gradle assembleRelease (走项目 build.gradle + signingConfig)
# 为什么不用 --gradle --release: 它内部调 gradle, 没机会修模板 build.gradle
# ----------------------------------------------------------------------------
# === 优先用上面预填阶段持久化的正确 gradle 路径 ===
# (原代码按 $GRADLE_VER 拼路径, 与实际解压结果不一致, 故改读 .gradle_bin_path)
if [ -s "$APP_DIR/.gradle_bin_path" ]; then
    LOCAL_GRADLE_BIN=$(cat "$APP_DIR/.gradle_bin_path")
    log_info "本地 gradle 路径 (来自 .gradle_bin_path): $LOCAL_GRADLE_BIN"
else
    LOCAL_GRADLE_BIN="/opt/gradle-install/${GRADLE_HASH:-00000000}/gradle-${GRADLE_VER:-8.3}/bin/gradle"
    log_info "本地 gradle 路径 (回退拼装): $LOCAL_GRADLE_BIN"
fi

# 显式 fallback: 如果路径不对, 优先用 PATH 中的 gradle (Dockerfile 已预装)
if [ ! -x "$LOCAL_GRADLE_BIN" ] && command -v gradle >/dev/null 2>&1; then
    LOCAL_GRADLE_BIN=$(command -v gradle)
    log_info "回退到 PATH gradle: $LOCAL_GRADLE_BIN"
fi
# 最后再搜索 /opt/gradle-install
if [ ! -x "$LOCAL_GRADLE_BIN" ]; then
    FOUND_GRADLE=$(find /opt/gradle-install -name "gradle" -type f 2>/dev/null | grep -E "/bin/gradle$" | head -1)
    if [ -n "$FOUND_GRADLE" ] && [ -x "$FOUND_GRADLE" ]; then
        LOCAL_GRADLE_BIN="$FOUND_GRADLE"
        log_info "找到可执行 gradle: $LOCAL_GRADLE_BIN"
    fi
fi

if [ -x "$LOCAL_GRADLE_BIN" ]; then
    DEPLOY_TOOL="$QT_HOST_PATH/bin/androiddeployqt"
    if [ ! -f "$DEPLOY_TOOL" ]; then
        log_error "androiddeployqt 未找到: $DEPLOY_TOOL"
        exit 1
    fi

    log_info "运行 androiddeployqt (--gradle --release, 走完整流程)..."

    # Qt 6.7 qt_add_executable + qt_add_qml_module 生成的 deployment 文件名
    # 实际: android-<target>-deployment-settings.json
    # 也有变体: lib<target>_<abi>-deployment.json / android-<abi>-deployment.json
    # 关键: 用 APP_NAME_SAFE 兜底 (避免 APP_NAME 环境变量污染, 与 line 148 保持一致)
    DEPLOY_JSON=""
    for candidate in \
        "$BUILD_DIR/android-${APP_NAME_SAFE}-deployment-settings.json" \
        "$BUILD_DIR/android-${TARGET_ABI}-deployment.json" \
        "$BUILD_DIR/lib${APP_NAME_SAFE}_${TARGET_ABI}-deployment.json" \
        "$BUILD_DIR/${APP_NAME_SAFE}-${TARGET_ABI}-deployment.json"; do
        if [ -f "$candidate" ]; then
            DEPLOY_JSON="$candidate"
            break
        fi
    done
    if [ -z "$DEPLOY_JSON" ]; then
        DEPLOY_JSON=$(find "$BUILD_DIR" -maxdepth 2 -name "*deployment*.json" 2>/dev/null | head -1)
    fi
    if [ -z "$DEPLOY_JSON" ] || [ ! -f "$DEPLOY_JSON" ]; then
        log_error "未找到 deployment json (期望路径: $BUILD_DIR/lib*_${TARGET_ABI}-deployment.json)"
        log_info "实际构建目录内容:"
        ls -la "$BUILD_DIR" 2>/dev/null | head -20
        exit 1
    fi
    log_info "使用 deployment json: $DEPLOY_JSON"

    # ----------------------------------------------------------------------------
    # 关键: 注入 qtAndroidSourceDir 到 deployment-settings.json (兜底逻辑)
    # 原因: androiddeployqt --gradle 模式下, 用此字段定位项目 Android 源码目录
    #       (含 build.gradle / AndroidManifest.xml / java / res), 没它会用 Qt 模板
    #       默认 (applicationId = org.qtproject.example.outdoorsurvival), 与我们的
    #       AndroidManifest (com.outdoor.survival) 不匹配 → 闪退.
    # 主注入在 CMakeLists.txt (configure 阶段已自动注入), 此处仅作兜底.
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json, sys
p = '$DEPLOY_JSON'
with open(p) as f:
    d = json.load(f)
if 'qtAndroidSourceDir' not in d or d['qtAndroidSourceDir'] != '$APP_DIR/android':
    d['qtAndroidSourceDir'] = '$APP_DIR/android'
    with open(p, 'w') as f:
        json.dump(d, f, indent=3)
    print('  ✅ 兜底注入 qtAndroidSourceDir:', d['qtAndroidSourceDir'])
else:
    print('  ✅ qtAndroidSourceDir 已在 CMake 阶段注入, 跳过')
" || {
            log_error "注入 qtAndroidSourceDir 失败 (python3 处理 deployment json 报错)"
            log_info "原始 deployment.json 内容 (前 30 行):"
            head -30 "$DEPLOY_JSON"
            exit 1
        }
    else
        log_warn "python3 不可用, 跳过兜底注入. 依赖 CMakeLists.txt 的注入已生效"
    fi

    # ----------------------------------------------------------------------------
    # 关键修复: 用 --no-build 模式, 我们手动跑 gradle
    # 原因: --gradle --release 模式下 androiddeployqt 内部调 gradle, 没机会修
    #       Qt 模板生成的 build.gradle (含 AGP 8.1+ 废弃选项)
    # 解决: --no-build 模式 + 后续手动 sed 修 build.gradle + 手动 gradle assembleRelease
    # ----------------------------------------------------------------------------
    DEPLOY_ARGS=(
        --input "$DEPLOY_JSON"
        --output "$BUILD_DIR/android-build"
        --android-platform $ANDROID_PLATFORM
        --jdk "$JAVA_HOME"
        --no-translations
        --no-build
    )

    # ----------------------------------------------------------------------------
    # 关键: 在 androiddeployqt 运行之前预填 gradle wrapper, 让它走本地 gradle
    # 否则 androiddeployqt 内部会通过 wrapper 下载 gradle-8.3-bin.zip (断网失败)
    # 策略: 先建出 $BUILD_DIR/android-build/gradle/wrapper/ 骨架 + gradlew
    #       androiddeployqt 看到这些文件已存在不会重写, 后续会走本地 gradle
    # ----------------------------------------------------------------------------
    PREP_OUT="$BUILD_DIR/android-build"
    PREP_WRAPPER_DIR="$PREP_OUT/gradle/wrapper"
    mkdir -p "$PREP_WRAPPER_DIR"

    if [ -n "$GRADLE_LOCAL_ZIP" ] && [ -x "$LOCAL_GRADLE_BIN" ]; then
        FILE_URL="file://$GRADLE_LOCAL_ZIP"
        log_info "预填 gradle-wrapper.properties: $FILE_URL"
        cat > "$PREP_WRAPPER_DIR/gradle-wrapper.properties" << EOF
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=$FILE_URL
networkTimeout=10000
validateDistributionUrl=false
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

        # gradlew 改写为直接 exec 本地 gradle, 完全跳过 wrapper 下载流程
        cat > "$PREP_OUT/gradlew" << EOF
#!/usr/bin/env bash
exec "$LOCAL_GRADLE_BIN" "\$@"
EOF
        chmod +x "$PREP_OUT/gradlew"
        log_info "✅ 已预填 gradle wrapper (绕过下载)"

        # 关键: 注入 keystore 路径 + 密码到 gradle.properties, 避免 androiddeployqt
        # 调 gradle 时找不到签名配置.
        # 关键 2: 必须**追加**到 gradle.properties, 不能写入 .append 后缀文件 —
        #        androiddeployqt 在 --gradle 模式下会**自己生成**一份
        #        gradle.properties, 如果已存在会**覆盖**而非合并, .append 不被读.
        # 策略: 我们先建一份空 gradle.properties, 让 androiddeployqt 看到"已存在"
        #       时**跳过生成** (它默认行为是"if exists: skip" 而非 "overwrite"),
        #       然后我们写完后, androiddeployqt 不会覆盖, 我们的内容保留.
        #       兜底: 写完后, 重新 cat 确保所有 keystore 变量都在.
        log_info "预填 gradle.properties (项目版本 + 注入 keystore 配置)"
        GRADLE_PROPS="$PREP_OUT/gradle.properties"
        # 关键: 复制项目 android/gradle.properties, 保留 android.useAndroidX 等关键配置
        # 之前用 'cat >' 完全覆盖, 丢失 useAndroidX → gradle 报 "AndroidX dependencies detected
        # but the android.useAndroidX property is not enabled" → build 失败
        if [ -f "$APP_DIR/android/gradle.properties" ]; then
            cp -f "$APP_DIR/android/gradle.properties" "$GRADLE_PROPS"
            log_info "  ✅ 复制项目 gradle.properties (含 useAndroidX=true 等)"
        else
            [ -f "$GRADLE_PROPS" ] && rm -f "$GRADLE_PROPS"
        fi
        # 追加 build_apk.sh 注入的配置 (keystore + 性能优化)
        cat >> "$GRADLE_PROPS" << EOF

# === 由 build_apk.sh 注入 (供 androiddeployqt + 手动 gradle 使用) ===
# Android 签名配置 (让 AGP 找到 keystore, 自动签名 release 包)
android.injected.signing.store.file=${KEYSTORE_PATH}
android.injected.signing.store.password=${KEYSTORE_PASSWORD}
android.injected.signing.key.alias=${KEY_ALIAS}
android.injected.signing.key.password=${KEY_PASSWORD}
# 性能优化 (避免 OOM)
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
org.gradle.parallel=true
org.gradle.caching=true
EOF
        log_info "  ✅ gradle.properties 已写入 (项目版本 + 注入配置)"
        log_info "  KEYSTORE_PATH: $KEYSTORE_PATH"
        log_info "  KEY_ALIAS: $KEY_ALIAS"
    fi

    # 关键: 把 gradle 二进制路径放进 PATH, androiddeployqt 内部调 gradle 时
    # 会优先用 PATH 里的 (我们的本地 gradle), 而不是用 wrapper 下载.
    # 同时设 GRADLE_USER_HOME, 走我们预设的 .gradle/init.d (阿里云镜像)
    if [ -x "$LOCAL_GRADLE_BIN" ]; then
        GRADLE_BIN_DIR="$(dirname "$LOCAL_GRADLE_BIN")"
        export PATH="$GRADLE_BIN_DIR:$PATH"
        export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$HOME/.gradle}"
        log_info "PATH 已加 gradle 目录: $GRADLE_BIN_DIR"
        log_info "GRADLE_USER_HOME: $GRADLE_USER_HOME"
    fi

    # 关键: stderr 也合并到 stdout, 避免 androiddeployqt 失败时诊断信息丢失
    # (build_apk.sh 用 set -e, 若 DEPLOY_TOOL 写 stderr 失败, 我们看不到原因)
    "$DEPLOY_TOOL" "${DEPLOY_ARGS[@]}" 2>&1 || {
        log_error "androiddeployqt 失败！"
        log_info "检查可能的根因:"
        log_info "  - $DEPLOY_JSON 路径正确吗?"
        log_info "  - $BUILD_DIR/android-build/ 是否可写?"
        log_info "  - 容器内 /opt/Qt/6.7.2/gcc_64/bin/androiddeployqt 是否能单独跑?"
        exit 1
    }

    log_info "✅ androiddeployqt 完成 (--no-build, 生成项目骨架)"

    # ============================================================================
    # 关键修复: 清理 Qt 模板生成 build.gradle 的 AGP 8.1+ 废弃选项
    # ----------------------------------------------------------------------------
    # 错误: 'android.bundle.enableUncompressedNativeLibs is deprecated' (AGP 8.1 移除)
    # 原因: Qt 6.7 androiddeployqt 生成的 build.gradle 第 1 行默认有这选项
    # 修法: 手动 sed 移除 (幂等: 不存在也不报错)
    # ----------------------------------------------------------------------------
    log_info "清理 build.gradle 中 AGP 8.1+ 废弃选项 (android.bundle.enableUncompressedNativeLibs)"
    for gradle_file in "$BUILD_DIR/android-build/app/build.gradle" \
                      "$BUILD_DIR/android-build/build.gradle"; do
        if [ -f "$gradle_file" ]; then
            # 移除含 android.bundle.enableUncompressedNativeLibs 的整行
            sed -i.bak '/android\.bundle\.enableUncompressedNativeLibs/d' "$gradle_file"
            rm -f "$gradle_file.bak"
            log_info "  ✅ 已清理: $gradle_file"
        fi
    done

    # 阶段间断言: APK 必须生成 (--no-build 不会生成, 这里直接断言会失败)
    # 改为: 验证 androiddeployqt 产物 + gradle 任务可执行
    log_info "  androiddeployqt 产物:"
    find "$BUILD_DIR/android-build" -maxdepth 3 -name "AndroidManifest.xml" 2>/dev/null | head -3
    log_info "  ✅ androiddeployqt 项目骨架已生成"

    # ----------------------------------------------------------------------------
    # 关键: 用项目 android/ 覆盖 androiddeployqt 生成的 build.gradle
    # 原因: Qt 6.7 模板的 build.gradle 缺 signingConfig, 强制覆盖用项目版本
    # ----------------------------------------------------------------------------
    for GFILE in build.gradle settings.gradle; do
        if [ -f "$APP_DIR/android/$GFILE" ]; then
            cp -f "$APP_DIR/android/$GFILE" "$BUILD_DIR/android-build/$GFILE"
            log_info "  ✅ 覆盖 $GFILE (项目版本)"
        fi
    done
    if [ -f "$APP_DIR/android/app/build.gradle" ]; then
        # 2026-09-10: androiddeployqt --no-build 模式**不**创建 app/ 目录,
        # 手动建好避免 cp 报 "No such file or directory"
        mkdir -p "$BUILD_DIR/android-build/app"
        cp -f "$APP_DIR/android/app/build.gradle" "$BUILD_DIR/android-build/app/build.gradle"
        log_info "  ✅ 覆盖 app/build.gradle (项目版本, 含完整 signingConfig)"
    fi
    if [ -f "$APP_DIR/android/app/CMakeLists.txt" ]; then
        cp -f "$APP_DIR/android/app/CMakeLists.txt" "$BUILD_DIR/android-build/app/CMakeLists.txt"
        log_info "  ✅ 覆盖 app/CMakeLists.txt (项目版本)"
    fi
    if [ -f "$APP_DIR/android/app/proguard-rules.pro" ]; then
        cp -f "$APP_DIR/android/app/proguard-rules.pro" "$BUILD_DIR/android-build/app/proguard-rules.pro"
        log_info "  ✅ 覆盖 app/proguard-rules.pro (项目版本)"
    fi
    if [ -f "$APP_DIR/android/AndroidManifest.xml" ]; then
        cp -f "$APP_DIR/android/AndroidManifest.xml" "$BUILD_DIR/android-build/AndroidManifest.xml"
        cp -f "$APP_DIR/android/AndroidManifest.xml" "$BUILD_DIR/android-build/app/src/main/AndroidManifest.xml"
        log_info "  ✅ 覆盖 AndroidManifest.xml (项目版本, 决定 applicationId)"
    fi

    # 关键: 复制项目 java 源 (不删 androiddeployqt 模板的 org/qtproject)
    SRC_JAVA_DIR="$APP_DIR/android/src"
    GEN_JAVA_DIR="$BUILD_DIR/android-build/app/src/main/java"
    if [ -d "$SRC_JAVA_DIR" ] && [ -n "$(ls -A "$SRC_JAVA_DIR" 2>/dev/null)" ]; then
        cp -r "$SRC_JAVA_DIR/." "$GEN_JAVA_DIR/" 2>/dev/null
        log_info "  ✅ 复制项目 java 源: $(find "$GEN_JAVA_DIR" -name "*.java" 2>/dev/null | wc -l) 个 .java"
    fi

    # 关键修复: 复制 Qt 6.7 Android jar 到 app/libs/
    # --------------------------------------------------------------------
    # 背景: app/build.gradle 用 implementation files('libs/Qt6AndroidMultimedia.jar')
    #       等声明了 6 个 Qt 6.7 java 桥接 jar. 但 files() 只对已存在文件生效.
    #       之前 build_apk.sh 没把 androiddeployqt 生成的 jar 复制到 app/libs/,
    #       AGP 静默跳过, dex 缺 org.qtproject.qt.android.multimedia.QtAudioDeviceManager
    #       等类, 启动期 libQt6Multimedia 的 JNI_OnLoad 调 loadClass 失败 → JNI_ERR → 闪退.
    # 源: androiddeployqt 已把 jar 落到 $BUILD_DIR/android-build/libs/
    # 目标: $BUILD_DIR/android-build/app/libs/ (AGP files('libs/...') 默认查找路径)
    # 注意: Qt 6.5+ 把 Qt5AndroidPositioning 改名 QtAndroidPositioning.jar (去掉了 5),
    #       只有这个 jar 不带 6, 必须显式枚举, 不能通配 Qt6Android*.jar.
    # --------------------------------------------------------------------
    QT_JARS_DIR="$BUILD_DIR/android-build/libs"
    APP_LIBS_DIR="$BUILD_DIR/android-build/app/libs"
    if [ -d "$QT_JARS_DIR" ]; then
        mkdir -p "$APP_LIBS_DIR"
        QT_JARS_COPIED=0
        QT_JARS_MISSING=""
        for j in Qt6Android.jar Qt6AndroidMultimedia.jar Qt6AndroidNetwork.jar \
                 Qt6AndroidNetworkInformationBackend.jar Qt6AndroidQuick.jar \
                 QtAndroidPositioning.jar; do
            if [ -f "$QT_JARS_DIR/$j" ]; then
                cp -f "$QT_JARS_DIR/$j" "$APP_LIBS_DIR/"
                QT_JARS_COPIED=$((QT_JARS_COPIED + 1))
            else
                QT_JARS_MISSING="$QT_JARS_MISSING $j"
            fi
        done
        if [ -n "$QT_JARS_MISSING" ]; then
            log_warn "  ⚠️  以下 Qt jar 缺失:$QT_JARS_MISSING (启动时相关模块 JNI_OnLoad 会失败)"
        fi
        log_info "  ✅ 复制 Qt jar 到 app/libs/: $QT_JARS_COPIED / 6"
    else
        log_warn "  ⚠️  $QT_JARS_DIR 不存在, 跳过 Qt jar 复制 (后续会因 dex 缺类崩溃)"
    fi

    # 关键: 复制 res (不删 androiddeployqt 生成的 values/libs.xml, 含 qt_libs)
    # ----------------------------------------------------------------------------
    # 之前 bug: 用 `if [ -f "$item/libs.xml" ]` 检查项目 res/values/libs.xml (不存在),
    #          走 else 分支 cp -r 整个 values/ → 覆盖 Qt 模板生成的 libs.xml
    #          → 启动期 QtLoader 找不到 qt_libs → Resources$NotFoundException 闪退
    # 修法: 先看 DST (androiddeployqt 已生成的) 有没有 libs.xml, 有则保留
    # ----------------------------------------------------------------------------
    SRC_RES_DIR="$APP_DIR/android/res"
    DST_RES_DIR="$BUILD_DIR/android-build/app/src/main/res"
    if [ -d "$SRC_RES_DIR" ] && [ -n "$(ls -A "$SRC_RES_DIR" 2>/dev/null)" ]; then
        mkdir -p "$DST_RES_DIR"
        for item in "$SRC_RES_DIR"/*; do
            bn=$(basename "$item")
            DST_ITEM="$DST_RES_DIR/$bn"
            if [ "$bn" = "values" ] && [ -f "$DST_ITEM/libs.xml" ]; then
                # 关键: DST 已有 androiddeployqt 生成的 libs.xml, 保留它
                # 项目 values/ 下其他文件 (strings.xml 等) 合并进去
                log_info "  [保留] DST values/libs.xml (Qt 模板, 含 qt_libs)"
                mkdir -p "$DST_ITEM"
                for vfile in "$item"/*; do
                    vbn=$(basename "$vfile")
                    if [ "$vbn" != "libs.xml" ]; then
                        cp -f "$vfile" "$DST_ITEM/" 2>/dev/null
                    else
                        log_info "  [跳过] $vbn (由 Qt 模板生成, 保留)"
                    fi
                done
            else
                cp -r "$item" "$DST_RES_DIR/" 2>/dev/null
            fi
        done
        log_info "  ✅ 复制项目 res (保留 Qt 模板的 values/libs.xml)"
    fi

    # 关键: 复制 .so 到 jniLibs/<abi>/ (AGP 8 jniLibs.srcDirs 需要这里)
    case "$TARGET_ABI" in
        arm64-v8a)   ANDROID_LIB_DIR="arm64-v8a"   ;;
        armeabi-v7a) ANDROID_LIB_DIR="armeabi-v7a" ;;
        x86_64)      ANDROID_LIB_DIR="x86_64"      ;;
        *) die "不支持的 ABI: $TARGET_ABI" ;;
    esac
    AAR_LIBS_DIR="$BUILD_DIR/android-build/app/src/main/jniLibs/$ANDROID_LIB_DIR"
    mkdir -p "$AAR_LIBS_DIR"
    # 复制项目 .so (CMake install 已经在 android-build/libs/<abi>/)
    if [ -f "$BUILD_DIR/android-build/libs/$ANDROID_LIB_DIR/lib${APP_NAME_SAFE}_${TARGET_ABI}.so" ]; then
        cp -f "$BUILD_DIR/android-build/libs/$ANDROID_LIB_DIR/lib${APP_NAME_SAFE}_${TARGET_ABI}.so" "$AAR_LIBS_DIR/"
        log_info "  ✅ 复制项目 .so 到 jniLibs"
    fi
    # 复制 Qt 自带 .so (从 androiddeployqt 输出 + QT_QPA)
    # ----------------------------------------------------------------------------
    # 历史:
    #   - 之前只 find $QT_QPA/lib 复制 libQt6*.so + libplugins_*.so
    #   - 但 androiddeployqt 还生成了 libqml_*.so (QML 插件), libplugins_position_*,
    #     libplugins_qmltoolging_* 等 40+ .so 都在 $AAR_LIBS_SRC (即
    #     android-build/libs/arm64-v8a/) 里, 但不在 $QT_QPA/lib 顶层
    #   - 这些 .so 在 qt_libs 列表之外, 是 QML 引擎按需 dlopen 的, 缺失时 QML
    #     加载任意 module 都找不到插件 → loadQtLibraries 失败 → 错误对话框
    #     找不到 qt_error_loading_qt_libs 资源 → 二次崩溃 (run.txt 现象)
    # 当前策略: 先 QT_QPA 补集 (split 模块如 Qt6Charts), 再 androiddeployqt 输出
    #           覆盖 (androiddeployqt 是权威来源, 与项目具体 Qt 版本精确匹配)
    AAR_LIBS_SRC="$BUILD_DIR/android-build/libs/$ANDROID_LIB_DIR"
    QT_SO_COUNT=0
    # 1) 先从 QT_QPA 补集 (androiddeployqt 没枚举的 Qt split 模块: libQt6Charts 等)
    # 关键: 必须递归搜, 不限 maxdepth 1.
    #   - 顶层 lib/ 含 libQt6Core / libQt6Gui / libQt6Qml / libQt6Quick 等核心 .so
    #   - 子目录 qml/QtQuick3D/ 含 libQt6Quick3D_arm64-v8a.so, 它被
    #     libQt6Quick3DSpatialAudio (顶层) 链式依赖. 如果不递归, qt_libs 里有
    #     Quick3DSpatialAudio 但没 Quick3D → 启动期 dlopen Quick3DSpatialAudio
    #     找不到 Quick3D → UnsatisfiedLinkError → 闪退 (run.txt 09-09 08:25:50.945
    #     实际崩溃, 依赖链 libQt6Quick3DSpatialAudio_arm64-v8a.so needs libQt6Quick3D_arm64-v8a.so)
    # 排除子目录:
    #   - CMakefiles/ 含静态 lib 或 build 中间产物, 不是 .so 运行时依赖
    #   - libexec/ pkgconfig/ .cmake 等都是元数据, 不是 .so
    if [ -d "$QT_QPA/lib" ]; then
        # 先找顶层 (主 lib)
        QTPA_TOP_COUNT=$(find "$QT_QPA/lib" -maxdepth 1 -name "libQt6*.so" 2>/dev/null | wc -l)
        if [ "$QTPA_TOP_COUNT" -gt 0 ]; then
            find "$QT_QPA/lib" -maxdepth 1 -name "libQt6*.so" -exec cp -f {} "$AAR_LIBS_DIR/" \; 2>/dev/null
        fi
        # 再递归找子目录 (QML 插件模块, 如 QtQuick3D)
        QTPA_REC_COUNT=$(find "$QT_QPA/lib" -mindepth 2 -name "libQt6*.so" \
            -not -path "*/CMakefiles/*" \
            -not -path "*/pkgconfig/*" \
            -not -path "*/cmake/*" \
            2>/dev/null | wc -l)
        if [ "$QTPA_REC_COUNT" -gt 0 ]; then
            find "$QT_QPA/lib" -mindepth 2 -name "libQt6*.so" \
                -not -path "*/CMakefiles/*" \
                -not -path "*/pkgconfig/*" \
                -not -path "*/cmake/*" \
                -exec cp -f {} "$AAR_LIBS_DIR/" \; 2>/dev/null
        fi
        QTPA_SO_COUNT=$((QTPA_TOP_COUNT + QTPA_REC_COUNT))
        log_info "  ✅ 补集 QT_QPA/libQt6*.so: 顶层 $QTPA_TOP_COUNT + 子目录 $QTPA_REC_COUNT (如 libQt6Quick3D)"
        QT_SO_COUNT=$QTPA_SO_COUNT
    fi
    # 关键补集: 搜 $QT_QPA/qml/ 下的 libQt6*.so
    # 背景: Qt 6 Android 把一些 QML 模块 split 装到 $QT_QPA/qml/<ModuleName>/,
    #       不在 $QT_QPA/lib/ 下. 例如 qtquick3d 的 libQt6Quick3D_arm64-v8a.so
    #       可能落在 $QT_QPA/qml/QtQuick3D/. 必须在这里补集, 否则 SpatialAudio
    #       链式依赖 Quick3D 还是找不到 → UnsatisfiedLinkError 闪退.
    if [ -d "$QT_QPA/qml" ]; then
        QML_REC_COUNT=$(find "$QT_QPA/qml" -name "libQt6*.so" 2>/dev/null | wc -l)
        if [ "$QML_REC_COUNT" -gt 0 ]; then
            find "$QT_QPA/qml" -name "libQt6*.so" -exec cp -f {} "$AAR_LIBS_DIR/" \; 2>/dev/null
            log_info "  ✅ 补集 QT_QPA/qml/libQt6*.so: $QML_REC_COUNT 个 (如 libQt6Quick3D)"
            QT_SO_COUNT=$((QT_SO_COUNT + QML_REC_COUNT))
        fi
    fi
    # 2) 再用 androiddeployqt 输出覆盖 (含 libqml_*, libplugins_position_* 等)
    #    androiddeployqt 是权威来源, 与项目 Qt 版本精确匹配, 同名 .so 覆盖 QT_QPA 的
    if [ -d "$AAR_LIBS_SRC" ]; then
        DEPLOYQT_SO_COUNT=$(find "$AAR_LIBS_SRC" -maxdepth 1 -name "*.so" 2>/dev/null | wc -l)
        if [ "$DEPLOYQT_SO_COUNT" -gt 0 ]; then
            find "$AAR_LIBS_SRC" -maxdepth 1 -name "*.so" -exec cp -f {} "$AAR_LIBS_DIR/" \; 2>/dev/null
            QT_SO_COUNT=$((QT_SO_COUNT + DEPLOYQT_SO_COUNT))
            log_info "  ✅ 复制 androiddeployqt 输出 .so: $DEPLOYQT_SO_COUNT 个 (含 libqml_*/libplugins_qmltooling_*)"
        fi
    fi
    log_info "  📊 jniLibs 复制阶段累计: $QT_SO_COUNT 个 .so"

    # 关键补集: Qt Android OpenSSL 3.x 运行库 (libcrypto_3.so + libssl_3.so)
    # ----------------------------------------------------------------------------
    # 背景: Qt 自身不链接 OpenSSL (QT_FEATURE_openssl_linked=OFF), TLS 后端
    #   libplugins_tls_qopensslbackend_<abi>.so 在运行期用 QLibrary(dlopen) 按
    #   名字找 3.x OpenSSL (libssl_3.so / libcrypto_3.so). APK lib/<abi>/ 若缺它们
    #   → dlopen 失败 → QSslSocket 起不来 → 所有 HTTPS 全灭.
    #   现象: 地图瓦片源(https) 拉不到 → 地图白底; ImageFetcherService 也全挂.
    # 文件名: 必须保持 ..._3.so 后缀 (_3 == ANDROID_OPENSSL_SUFFIX), **不可改名**.
    # 来源: third_party/android_openssl/ssl_3/<abi>/ (与 CMakeLists.txt 的
    #   QT_ANDROID_EXTRA_LIBS 同源; 这里幂等再补一次, 保证即使 androiddeployqt
    #   extraLibs 链路失效也能进 APK).
    # 放置: 仅进 jniLibs → APK lib/<abi>/, **不**进 values/libs.xml 的 qt_libs
    #   (TLS 后端运行期 dlopen 即可, 启动期不强制 load, 降低启动失败面; 见下方收集器排除).
    # 2026-10-09: 修地图白底 — 之前 build_apk.sh 完全不处理 OpenSSL, 全 https 瓦片拉不到.
    OSSL_SRC_DIR="$APP_DIR/third_party/android_openssl/ssl_3/$ANDROID_LIB_DIR"
    OSSL_COPIED=0
    for ossl in libcrypto_3.so libssl_3.so; do
        if [ -f "$OSSL_SRC_DIR/$ossl" ]; then
            cp -f "$OSSL_SRC_DIR/$ossl" "$AAR_LIBS_DIR/" && OSSL_COPIED=$((OSSL_COPIED + 1))
        fi
    done
    if [ "$OSSL_COPIED" -eq 2 ]; then
        log_info "  ✅ 复制 OpenSSL 3.x 运行库: libcrypto_3.so + libssl_3.so ($ANDROID_LIB_DIR)"
    else
        log_error "  ❌ OpenSSL 3.x 运行库缺失 (仅复制 $OSSL_COPIED/2 个), 源目录: $OSSL_SRC_DIR"
        log_error "     缺它 → QSslSocket 起不来 → 所有 HTTPS(含地图瓦片) 拉不到 → 地图白底."
        log_error "     请确认 third_party/android_openssl/ssl_3/$ANDROID_LIB_DIR/ 下有 libcrypto_3.so + libssl_3.so"
        exit 1
    fi

    # 2026-09-10: 清理缺依赖的 Qt plugin
    # 问题: NMEA GPS plugin (libplugins_position_qtposition_nmea_*.so) 编译时链 libQt6SerialPort
    #       但 aqt 装 qtlocation 时**不**自动装 qtserialport 模块 → 启动期 dlopen 报
    #       "libQt6SerialPort_arm64-v8a.so not found" → FATAL EXCEPTION (run.txt L1469)
    # 项目不用 NMEA 串口 GPS (用 Android QGeoPositionInfoSource), 主动删 NMEA plugin.
    NMEA_PLUGIN="$AAR_LIBS_DIR/libplugins_position_qtposition_nmea_arm64-v8a.so"
    if [ -f "$NMEA_PLUGIN" ] && [ ! -f "$AAR_LIBS_DIR/libQt6SerialPort_arm64-v8a.so" ]; then
        rm -f "$NMEA_PLUGIN"
        log_warn "  🗑  删 NMEA plugin (缺 libQt6SerialPort, 项目用 Android Location API): $(basename $NMEA_PLUGIN)"
    fi
    # 复制 libc++_shared.so (NDK runtime, 关键!)
    # ----------------------------------------------------------------------------
    # 历史:
    #   - 之前 find $ANDROID_NDK 找第一个 libc++_shared.so, 选到 32-bit ARM 版本
    #   - 复制后 APK 装到 arm64-v8a 设备, 架构不匹配 → native crash
    # 当前策略 (与 build.gradle 协调):
    #   - build.gradle 不再显式 jniLibs.srcDirs 限定
    #   - AGP 8.4 mergeReleaseNativeLibs 会**自动**从 NDK sysroot 注入 libc++_shared.so
    #   - build_apk.sh 仅做兜底: 检测 AGP 是否已注入, 没注入才手动补
    # ----------------------------------------------------------------------------
    LIBCXX_SHARED=""

    # 2026-09-11 (#68 D1): NDK_TRIPLE / EXPECTED_MACHINE 之前 2 个 case 块 + python
    # 校验共 30 行, 实际只在 AGP 自动注入失败时跑. 合并到一个 case 块, 用
    # declare -A 关联 ABI→(triple,machine) 减少 50% 代码.
    declare -A ABI_TRIPLE_MACHINE=(
        ["arm64-v8a"]="aarch64-linux-android:0xB7"
        ["armeabi-v7a"]="arm-linux-androideabi:0x28"
        ["x86_64"]="x86_64-linux-android:0x3E"
        ["x86"]="i686-linux-android:0x03"
    )
    if [ "${ABI_TRIPLE_MACHINE[$ANDROID_LIB_DIR]}" ]; then
        NDK_TRIPLE="${ABI_TRIPLE_MACHINE[$ANDROID_LIB_DIR]%%:*}"
        EXPECTED_MACHINE="${ABI_TRIPLE_MACHINE[$ANDROID_LIB_DIR]##*:}"
        CANDIDATE="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/$NDK_TRIPLE/libc++_shared.so"
        if [ -f "$CANDIDATE" ]; then
            MACHINE=$(python3 -c "
import struct
with open('$CANDIDATE', 'rb') as f:
    f.seek(18)
    print(struct.unpack('<H', f.read(2))[0])
" 2>/dev/null)
            if [ -n "$MACHINE" ] && [ "$MACHINE" = "$EXPECTED_MACHINE" ]; then
                LIBCXX_SHARED="$CANDIDATE"
                log_info "  [查找] libc++_shared.so: $CANDIDATE (machine=$MACHINE ✅)"
            else
                log_warn "  [查找] libc++_shared.so: $CANDIDATE (machine=$MACHINE, 期望 $EXPECTED_MACHINE, 跳过)"
            fi
        fi
    fi

    # 关键: 检查 AGP 是否已注入
    if [ -f "$AAR_LIBS_DIR/libc++_shared.so" ]; then
        EXISTING_MACHINE=$(python3 -c "
import struct
with open('$AAR_LIBS_DIR/libc++_shared.so', 'rb') as f:
    f.seek(18)
    print(struct.unpack('<H', f.read(2))[0])
" 2>/dev/null)
        if [ -n "$EXISTING_MACHINE" ] && [ "$EXISTING_MACHINE" = "$EXPECTED_MACHINE" ]; then
            log_info "  ✅ AGP 已注入 libc++_shared.so (machine=0x$(printf '%x' $EXISTING_MACHINE)), 跳过手动 cp"
            LIBCXX_SHARED=""  # 清空, 跳过复制
        else
            log_warn "  ⚠️  AGP 注入的 libc++_shared.so 架构错 (machine=0x$(printf '%x' $EXISTING_MACHINE)), 手动覆盖"
        fi
    fi

    if [ -n "$LIBCXX_SHARED" ] && [ -f "$LIBCXX_SHARED" ]; then
        cp -f "$LIBCXX_SHARED" "$AAR_LIBS_DIR/" && \
            log_info "  ✅ 复制 NDK runtime: libc++_shared.so (正确架构)" || \
            log_warn "  ⚠️  cp libc++_shared.so 失败"
    else
        log_info "  ℹ️  libc++_shared.so 由 AGP 自动注入 (NDK sysroot)"
    fi
    FINAL_SO_COUNT=$(find "$AAR_LIBS_DIR" -maxdepth 1 -name "*.so" 2>/dev/null | wc -l)
    log_info "  📊 jniLibs/$ANDROID_LIB_DIR/ 共 $FINAL_SO_COUNT 个 .so"

    # ============================================================================
    # 关键修复: 自动生成 values/libs.xml (Qt 必需资源)
    # ----------------------------------------------------------------------------
    # 背景: QtLoader.useLocalQtLibs() 调 Resources.getIdentifier("qt_libs", "string", pkg)
    #       找不到 → Resources$NotFoundException → 启动闪退
    # 修法: 从 $AAR_LIBS_DIR 实际 .so 列表生成 values/libs.xml
    # 长期可维护: 加新 .so 不需改 strings.xml, 自动同步
    # ----------------------------------------------------------------------------
    # 关键: 顺序很关键! QtLoader 按 qt_libs 顺序 System.loadLibrary 每个 .so
    # 如果 libQt6Core 不在第一个, 依赖 libQt6Core 的 lib (e.g. libQt6Charts) 会
    # 在 JNI_OnLoad 时调 QJniEnvironment::getJniEnv() 拿空指针 → SIGSEGV.
    #
    # 策略:
    #   1. 第一项必须是 libOutdoorSurvival_<abi>.so (项目主 lib, 它的 JNI_OnLoad
    #      调 QtLoader 初始化 JNIEnv, 后续 .so 才能拿到 JNIEnv)
    #   2. 接着是 libQt6Core (Qt 基础, 其他 Qt lib 依赖)
    #   3. 然后其他 Qt 库 (按依赖顺序: Gui → Qml → Quick → 业务模块)
    #   4. 排除 libc++_shared.so (NDK runtime, AGP 自动注入)
    #
    # 长期可维护: 加新 Qt 模块自动包含, 顺序由 build_apk.sh 硬编码
    # ----------------------------------------------------------------------------
    log_info "  生成 values/libs.xml (Qt 必需资源, 按依赖顺序)"
    VALUES_DIR="$BUILD_DIR/android-build/app/src/main/res/values"
    mkdir -p "$VALUES_DIR"

    # 收集所有 .so (排除 libc++_shared.so, AGP 自动注入)
    # 2026-10-09: 也排除 OpenSSL 3.x (libcrypto_3/libssl_3) —— 它是 TLS 后端
    #   运行期 dlopen 的库, 不是 QtLoader 启动期要 System.loadLibrary 的 Qt 库.
    #   放进 qt_libs 会让启动期多 load 两个库, 徒增失败面; 仅留在 jniLibs→APK 即可.
    declare -A ALL_LIBS
    for so in "$AAR_LIBS_DIR"/*.so; do
        [ -f "$so" ] || continue
        bn=$(basename "$so" .so)
        [ "$bn" = "libc++_shared" ] && continue
        case "$bn" in
            libcrypto_3|libssl_3) continue ;;
        esac
        ALL_LIBS["$bn"]=1
    done

    # 关键: 按 Qt 依赖顺序排序
    # 第一优先级: libOutdoorSurvival (项目主 lib, 必须最先 load)
    # 第二优先级: libQt6Core (Qt 基础)
    # 第三优先级: 其他 Qt 库 (按字母序, 但 libQt6Core 已经在前面)
    ORDERED_LIST=""
    # 1) 项目主 lib
    for lib in "${!ALL_LIBS[@]}"; do
        if [[ "$lib" == OutdoorSurvival* ]]; then
            ORDERED_LIST="${ORDERED_LIST}${lib};"
            unset ALL_LIBS["$lib"]
        fi
    done
    # 2) libQt6Core
    for lib in "${!ALL_LIBS[@]}"; do
        if [ "$lib" = "libQt6Core_arm64-v8a" ]; then
            ORDERED_LIST="${ORDERED_LIST}${lib};"
            unset ALL_LIBS["$lib"]
            break
        fi
    done
    # 3) 其他 Qt 库按字母序
    for lib in $(echo "${!ALL_LIBS[@]}" | tr ' ' '\n' | sort); do
        ORDERED_LIST="${ORDERED_LIST}${lib};"
    done
    QT_LIBS_LIST="${ORDERED_LIST%;}"
    log_info "  qt_libs 包含 $(echo "$QT_LIBS_LIST" | tr ';' '\n' | wc -l) 个 .so (顺序: 项目主 lib → Qt6Core → 其他)"

    # 关键: 覆盖生成 values/libs.xml (Androiddeployqt --no-build 模式不生成此文件)
    # ----------------------------------------------------------------------------
    # 关键 1: bundle_local_qt_libs / use_local_qt_libs 必须是 INTEGER 字符串 ("1"/"0"),
    #         不是 "true"/"false"!
    #         QtLoader.useLocalQtLibs:368 调 Integer.parseInt(getString(id))
    #         Integer.parseInt("true") 抛 NumberFormatException → 启动闪退
    # 关键 2: qt_libs 必须是 <string-array>, 不是 <string>!
    #         QtLoader.getQtLibrariesList:362 调
    #         getStringArray(getIdentifier("qt_libs", "array", pkg))
    #         如果资源是 <string>, getIdentifier 返回的 ID 是 R.string.qt_libs (id≠0),
    #         但 getStringArray 内部检查 type 发现不是 string-array 抛
    #         Resources$NotFoundException: String array resource ID #0x0
    #         (run.txt 18:17:29.044 实际崩溃, line 23 38-40)
    # 关键 3: 每个 <item> 格式必须是 "arm64-v8a;<basename 不带 lib 前缀>"
    #         e.g. "arm64-v8a;Qt6Core_arm64-v8a" (不是 libQt6Core_arm64-v8a)
    #         preferredAbiLibs 按 ';' split, 取第二部分作为 libname, 然后 getLibrariesFullPaths
    #         会自动加 'lib' 前缀和 '.so' 后缀 (字节码 QtLoader.java:493-505)
    # ----------------------------------------------------------------------------
    # 把分号分隔列表转成 <string-array>, 每个 <item> 格式 "arm64-v8a;<basename 不带 lib>"
    # 关键 4: libname 部分必须去掉 "lib" 前缀! QtLoader.getLibrariesFullPaths 字节码
    #   line 41-91: endsWith('.so') 时跳过, 否则无脑加 ".so" + "lib" 前缀.
    #   如果 qt_libs 写 'arm64-v8a;libQt6Core_arm64-v8a', QtLoader 会拼成
    #   'liblibQt6Core_arm64-v8a.so' (双 lib) → loadLibraryHelper 报
    #   "Can't find 'liblibQt6Core_arm64-v8a.so'" (run.txt 19:25:49.993 实际崩溃)
    #   正确格式: 'arm64-v8a;Qt6Core_arm64-v8a', QtLoader 拼成 'libQt6Core_arm64-v8a.so' ✓
    ARRAY_ITEMS=""
    IFS=';' read -ra LIBS_ARR <<< "$QT_LIBS_LIST"
    for lib in "${LIBS_ARR[@]}"; do
        [ -z "$lib" ] && continue
        # 去掉 'lib' 前缀 (QtLoader 内部会再加)
        [[ "$lib" == lib* ]] && lib="${lib#lib}"
        ARRAY_ITEMS="${ARRAY_ITEMS}    <item>${ANDROID_LIB_DIR};${lib}</item>"$'\n'
    done
    cat > "$VALUES_DIR/libs.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- 由 build_apk.sh 自动生成 (从 jniLibs/<abi>/*.so 扫描) -->
    <!-- QtLoader.getQtLibrariesList 调 getStringArray, 必须是 string-array -->
    <string-array name="qt_libs" translatable="false">
${ARRAY_ITEMS}    </string-array>
    <!-- QtLoader.getBundledLibs:409 调 getStringArray("bundled_libs", "array", pkg).
         必须存在 (即使是空), 否则 getIdentifier 返回 0 → getStringArray(0) 抛
         Resources$NotFoundException: String array resource ID #0x0 (run.txt 14:14:12.340 实际崩溃).
         2026-09-10: 之前 build_apk.sh 覆盖生成 libs.xml 时漏了 bundled_libs 资源,
         getBundledLibs 永远返回 null, loadQtLibraries 第一行 ifnonnull 直接 return true 跳过去 →
         loadLibraryHelper 一行未到 → Qt 库未 load → outdoor 启动期 dlopen 全部失败.
         加空 array 修复. -->
    <string-array name="bundled_libs" translatable="false"></string-array>
    <!-- QtLoader.getLocalLibrariesList:387 调 getStringArray("load_local_libs", "array", pkg).
         如果资源完全不存在, getIdentifier 返回 0, getStringArray(0) 抛
         Resources$NotFoundException: String array resource ID #0x0 (run.txt 18:39:15.837).
         反编译 QtLoader 字节码确认 preferredAbiLibs 输入为空时返回空 ArrayList,
         loadLibraries(空 list) 第一行 ifnonnull 走 iconst_0/ireturn 返回 true (no-op).
         所以空的 string-array 完全合法, 主流程不受影响.
         未来若需细分 plugins (libplugins_*.so) 到 load_local_libs, 改这里即可. -->
    <string-array name="load_local_libs" translatable="false"></string-array>
    <!-- bundle_local_qt_libs=1: 把 Qt 库打包进 APK (从 jniLibs/ 加载, 不走 Ministro) -->
    <string name="bundle_local_qt_libs" translatable="false">1</string>
    <!-- use_local_qt_libs=1: QtLoader.useLocalQtLibs() 必须返回 true 才会继续 loadQtLibraries.
         反编译 Qt6Android.jar QtLoader.useLocalQtLibs:367 确认: parseInt(getString(id)) == 1 才返回 true.
         use=0 会让 QtLoader 第一行就 finish() (loadQtLibraries 字节码 line 4-19).
         旧注释 "bundle=1 时 use 必须=0" 是 Qt 5 时代逻辑, Qt 6.7.2 两个都必须是 1. -->
    <string name="use_local_qt_libs" translatable="false">1</string>
    <!-- QT_ANDROID_FONTS=0: 走 Android 默认字体 (避免 Qt 字体加载问题) -->
    <string name="QT_ANDROID_FONTS" translatable="false">0</string>
</resources>
EOF
    log_info "  ✅ values/libs.xml 已生成 (含 $FINAL_SO_COUNT 个 .so, qt_libs+load_local_libs 都是 string-array, bundle=1/use=1)"

    # 关键: 也要注入到项目 strings.xml (让 AAPT2 在打包时合并)
    # 因为 AAPT2 优先用项目 res, 我们直接在 jniLibs 同时复制项目 strings.xml 含相同 key
    # 但这会冲突, 所以我们只保留 libs.xml 即可 (AGP 看到 libs.xml 就在 values/)
    # 我们的项目 res/values/strings.xml 仍有 static_init_classes, 单独合并入 arsc

    # 关键: keystore 注入 (确保 AGP 找得到签名)
    # 上面 line 780 已经在 androiddeployqt 之前注入过, 这里兜底 (--no-build 模式
    # 不会被 androiddeployqt 覆盖, 但保险起见再查一次)
    GRADLE_PROPS_DEPLOY="$BUILD_DIR/android-build/gradle.properties"
    if [ -f "$GRADLE_PROPS_DEPLOY" ] && \
       ! grep -q "android.injected.signing.store.file" "$GRADLE_PROPS_DEPLOY" 2>/dev/null; then
        log_info "  注入 keystore 配置到 gradle.properties (兜底)"
        cat >> "$GRADLE_PROPS_DEPLOY" << EOF

# === build_apk.sh 注入 (签名配置兜底) ===
android.injected.signing.store.file=${KEYSTORE_PATH}
android.injected.signing.store.password=${KEYSTORE_PASSWORD}
android.injected.signing.key.alias=${KEY_ALIAS}
android.injected.signing.key.password=${KEY_PASSWORD}
EOF
    fi

    # ----------------------------------------------------------------------------
    # 关键: 手动跑 gradle assembleRelease
    # 原因: --no-build 模式 androiddeployqt 不调 gradle, 我们手动跑 (已修 build.gradle)
    # 关键: 必须用 PIPESTATUS 捕获 gradle 真实返回码, 不能用 '$?' (会被 tail 吞掉)
    # 关键: 必须保留完整 stderr, 不能用 | tail -100 截断
    # ----------------------------------------------------------------------------
    log_info "手动运行 gradle assembleRelease..."
    cd "$BUILD_DIR/android-build"
    GRADLE_TASK="assembleRelease"
    # 关键: 用 set -o pipefail 让管道任何一环失败整体失败
    set -o pipefail
    # 关键: 完整重定向到 LOG_FILE 而不是 tail, 调试时再 cat

    # ----------------------------------------------------------------------------
    # 优化 1: --offline 开关 (OFFLINE=1 启用, 默认 0 联网)
    # ----------------------------------------------------------------------------
    # 节省: 5-15s (避免 metadata 校验/版本检查/远程 build cache 的网络往返)
    # 风险: 冷启动 (gradle-cache volume 首次) 会立即失败, 此时需回退联网
    # 检测方式: 检查 modules-2 缓存目录是否非空 (Gradle 下载依赖后必留)
    # ----------------------------------------------------------------------------
    GRADLE_OFFLINE_FLAG=""
    if [ "${OFFLINE:-0}" = "1" ]; then
        if [ -d "/root/.gradle/caches/modules-2" ] && \
           [ -n "$(ls -A /root/.gradle/caches/modules-2/files-2.1/ 2>/dev/null)" ]; then
            GRADLE_OFFLINE_FLAG="--offline"
            log_info "  启用 --offline (gradle 缓存已就绪: $(du -sh /root/.gradle/caches/modules-2 2>/dev/null | cut -f1))"
        else
            log_warn "  OFFLINE=1 但 gradle 缓存为空, 降级为联网模式 (首次构建需联网预热)"
        fi
    fi

    # ----------------------------------------------------------------------------
    # 优化 2: APK inputs hash 缓存 (FORCE_GRADLE=1 强制跑, 默认 0 自动跳过)
    # ----------------------------------------------------------------------------
    # 节省: 20-40s (跳过整个 gradle assembleRelease)
    # 原理: 算所有影响 APK 的 inputs 的 sha256 摘要, 与上次一致且 APK 已存在
    #       → 直接复用现有 APK, 不调 gradle
    # 风险: 漏算某个 inputs → 旧 APK 装上. 缓解: 全面扫描 + FORCE_GRADLE=1 强制开关
    # 注意: --rerun-tasks 仍会强制重跑所有 task, 跳过 gradle 才是真正节省
    # ----------------------------------------------------------------------------
    APK_STAMP="$BUILD_DIR/.apk.inputs.sha256"
    APK_OUTPUT_REL="app/build/outputs/apk/release/app-release.apk"
    APK_OUTPUT="$BUILD_DIR/android-build/$APK_OUTPUT_REL"
    SHOULD_RUN_GRADLE=1
    GRADLE_SKIP_REASON=""

    if [ "${FORCE_GRADLE:-0}" != "1" ] && [ -f "$APK_OUTPUT" ] && [ -f "$APK_STAMP" ]; then
        log_info "计算 APK inputs 指纹..."
        # 用 () 子 shell + {} 列表精确分组, 避免 -o 优先级陷阱
        NEW_HASH=$( (
            # 项目 java 源
            find "$BUILD_DIR/android-build/app/src/main/java" -type f 2>/dev/null
            # native 库
            find "$BUILD_DIR/android-build/app/src/main/jniLibs" -type f 2>/dev/null
            # res 资源
            find "$BUILD_DIR/android-build/app/src/main/res" -type f 2>/dev/null
            # gradle 配置 (精确文件名, 避免 find -o 优先级陷阱)
            for f in "$BUILD_DIR/android-build/build.gradle" \
                     "$BUILD_DIR/android-build/settings.gradle" \
                     "$BUILD_DIR/android-build/gradle.properties" \
                     "$BUILD_DIR/android-build/app/build.gradle"; do
                [ -f "$f" ] && echo "$f"
            done
            # AndroidManifest
            [ -f "$BUILD_DIR/android-build/app/src/main/AndroidManifest.xml" ] && \
                echo "$BUILD_DIR/android-build/app/src/main/AndroidManifest.xml"
            # keystore (签名变化)
            [ -f "$KEYSTORE_PATH" ] && echo "$KEYSTORE_PATH"
            # C++ 主 lib
            [ -f "$BUILD_DIR/lib${APP_NAME_SAFE}_${TARGET_ABI}.so" ] && \
                echo "$BUILD_DIR/lib${APP_NAME_SAFE}_${TARGET_ABI}.so"
        ) | sort -u | xargs -r sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1)

        OLD_HASH=$(cat "$APK_STAMP" 2>/dev/null)
        if [ -n "$NEW_HASH" ] && [ "$NEW_HASH" = "$OLD_HASH" ]; then
            SHOULD_RUN_GRADLE=0
            GRADLE_SKIP_REASON="APK inputs 未变且 APK 已存在 (sha256=${NEW_HASH:0:12}...)"
            log_info "  ⏭  $GRADLE_SKIP_REASON"
        else
            log_info "  inputs 已变 (old=${OLD_HASH:0:12}... new=${NEW_HASH:0:12}...) → 重跑 gradle"
        fi
    elif [ "${FORCE_GRADLE:-0}" = "1" ]; then
        log_info "  FORCE_GRADLE=1, 强制跑 gradle"
    elif [ ! -f "$APK_OUTPUT" ]; then
        log_info "  APK 不存在, 首次构建必须跑 gradle"
    elif [ ! -f "$APK_STAMP" ]; then
        log_info "  无 stamp 文件, 必须跑 gradle 一次建立基线"
    fi

    if [ "$SHOULD_RUN_GRADLE" = "1" ]; then
        "$LOCAL_GRADLE_BIN" --no-daemon --rerun-tasks $GRADLE_OFFLINE_FLAG "$GRADLE_TASK" \
            -Pandroid.injected.signing.store.file="$KEYSTORE_PATH" \
            -Pandroid.injected.signing.store.password="$KEYSTORE_PASSWORD" \
            -Pandroid.injected.signing.key.alias="$KEY_ALIAS" \
            -Pandroid.injected.signing.key.password="$KEY_PASSWORD" > "$LOG_FILE.gradle" 2>&1
        GRADLE_RC=$?
        # 关闭 pipefail, 避免影响后续
        set +o pipefail
        cd "$APP_DIR"
        if [ $GRADLE_RC -ne 0 ]; then
            log_error "gradle $GRADLE_TASK 失败 (rc=$GRADLE_RC)"
            log_info "完整日志已写入: $LOG_FILE.gradle"
            log_info "最后 50 行 (供快速诊断):"
            tail -50 "$LOG_FILE.gradle" | while IFS= read -r line; do
                log_info "  | $line"
            done
            die "gradle $GRADLE_TASK 失败 (rc=$GRADLE_RC)"
        fi
        log_info "✅ gradle $GRADLE_TASK 完成"

        # gradle 跑成功后才更新 stamp (避免 gradle 失败但 stamp 已更新, 下次跳过)
        if [ -n "$NEW_HASH" ]; then
            echo "$NEW_HASH" > "$APK_STAMP"
            log_info "  📝 stamp 已更新: $APK_STAMP"
        fi
    else
        # 跳过 gradle, 恢复 pipefail 状态 (后续可能用)
        set +o pipefail
        cd "$APP_DIR" 2>/dev/null || true
        log_info "  ✅ gradle 跳过, 复用 APK: $APK_OUTPUT"
    fi

    # 阶段间断言: APK 必须生成
    APK_AFTER_DEPLOY=$(find "$BUILD_DIR/android-build" -name "app-*.apk" \
        ! -name "*-unsigned.apk" ! -name "*-unaligned.apk" 2>/dev/null | head -1)
    [ -n "$APK_AFTER_DEPLOY" ] || die "gradle assembleRelease 后未找到 APK: $BUILD_DIR/android-build/**/app-*.apk"
    log_info "  ✅ APK 已生成: $APK_AFTER_DEPLOY"
else
    die "本地 gradle 不可执行: $LOCAL_GRADLE_BIN"
fi

stage_end

# ============================================================================
# STAGE 4/4: VERIFY - APK 自检 + 复制到 dist
# ============================================================================
stage_begin 4 "VERIFY - APK 自检 + 复制到 dist"
# ----------------------------------------------------------------------------
# 关键修复: Java 类进 dex 断言
# 原因: 之前 build 报告"Java 复制完成, 共 2 个 .java", 但最终 APK 的 4 个 dex
#       中根本找不到 com.outdoor.survival.OutdoorSurvivalApp 字符串, 启动时
#       ClassNotFoundException 立即崩. 这里在 gradle 跑完后, 立即解 APK 检查 dex,
#       任一关键类不在 dex 中则 exit 1, 避免坏 APK 复制到 dist.
# ----------------------------------------------------------------------------
log_info "校验 dex 中关键 Java 类..."
# 关键: 先 find APK, 再 stat (旧代码先 stat 后 find, 用了未赋值变量导致 stat 失败)
APK_TMP_FOR_CHECK="$BUILD_DIR/android-build/app/build/outputs/apk/$BUILD_TYPE"
APK_CHECK_FILE=$(find "$APK_TMP_FOR_CHECK" -name "*.apk" ! -name "*-unsigned.apk" ! -name "*-unaligned.apk" 2>/dev/null | head -1)
if [ -z "$APK_CHECK_FILE" ] || [ ! -f "$APK_CHECK_FILE" ]; then
    log_error "APK 自检失败: 找不到 $APK_TMP_FOR_CHECK 下的 APK"
    find "$BUILD_DIR/android-build" -name "*.apk" 2>/dev/null | head -10
    exit 1
fi
APK_SIZE_BYTES=$(stat -c%s "$APK_CHECK_FILE" 2>/dev/null || stat -f%z "$APK_CHECK_FILE" 2>/dev/null)
log_info "  [诊断] APK 文件: $(basename "$APK_CHECK_FILE") ($APK_SIZE_BYTES bytes)"
log_info "  [诊断] APK 内 dex 列表:"
unzip -l "$APK_CHECK_FILE" 2>/dev/null | awk '/classes[0-9]*\.dex/ {print "    | "$4" ("$1" bytes)"}'
log_info "  [诊断] APK 内 AndroidManifest 引用的 .OutdoorSurvivalApp / .EmergencyService:"
unzip -p "$APK_CHECK_FILE" AndroidManifest.xml 2>/dev/null | strings | grep -E "OutdoorSurvivalApp|EmergencyService" | head -5 | while IFS= read -r line; do
    log_info "    | $line"
done

# 遍历所有 dex, 检查 OutdoorSurvivalApp 和 EmergencyService 都在
DEX_DIR_TMP=$(mktemp -d)
unzip -q -o "$APK_CHECK_FILE" "classes*.dex" -d "$DEX_DIR_TMP" 2>/dev/null
# === 诊断: 每个 dex 的 com/outdoor/survival 字符串 ===
log_info "  [诊断] 每个 dex 中 com.outdoor.survival 包字符串数:"
for DEX_FILE in "$DEX_DIR_TMP"/classes*.dex; do
    [ -f "$DEX_FILE" ] || continue
    COUNT=$(strings "$DEX_FILE" 2>/dev/null | grep -c "com/outdoor/survival" || true)
    log_info "    | $(basename "$DEX_FILE") (size=$(stat -c%s "$DEX_FILE" 2>/dev/null)) → $COUNT 处 com/outdoor/survival"
done
MISSING_CLASSES=()
for REQUIRED_CLASS in "OutdoorSurvivalApp" "EmergencyService"; do
    FOUND=0
    for DEX_FILE in "$DEX_DIR_TMP"/classes*.dex; do
        [ -f "$DEX_FILE" ] || continue
        # 在 dex 中查找类名 (dex 字符串格式是 "Lcom/outdoor/survival/OutdoorSurvivalApp;")
        if strings "$DEX_FILE" 2>/dev/null | grep -q "Lcom/outdoor/survival/${REQUIRED_CLASS};"; then
            FOUND=1
            log_info "  ✅ $REQUIRED_CLASS 存在于 $(basename "$DEX_FILE")"
            break
        fi
    done
    if [ "$FOUND" -eq 0 ]; then
        MISSING_CLASSES+=("$REQUIRED_CLASS")
        log_error "  ❌ $REQUIRED_CLASS 在所有 dex 中均未找到"
    fi
done
rm -rf "$DEX_DIR_TMP"
if [ ${#MISSING_CLASSES[@]} -gt 0 ]; then
    log_error "关键 Java 类缺失: ${MISSING_CLASSES[*]}"
    log_error "APK 启动会立即 ClassNotFoundException 崩溃, 拒绝复制到 dist"
    log_info "诊断信息:"
    log_info "  - android/src/ 下的 Java 源文件:"
    find "$APP_DIR/android/src" -name "*.java" 2>/dev/null
    log_info "  - app/src/main/java/ 复制结果:"
    find "$BUILD_DIR/android-build/app/src/main/java" -name "*.java" 2>/dev/null
    log_info "  - app/build.gradle sourceSets 段:"
    grep -A 8 "sourceSets" "$BUILD_DIR/android-build/app/build.gradle" 2>/dev/null
    exit 1
fi
log_info "✅ 关键 Java 类自检通过"

log_info "提取 APK..."
# 关键: 优先选 signed 的, 排除 -unsigned.apk 和 -unaligned.apk
# (Android 会在同目录同时输出 app-release.apk 和 app-release-unsigned.apk,
#  按字典序 unsigned 比 .apk 字符更早, head -1 会错选)
# 注意: AGP 8 的 APK 输出路径是 <project>/<module>/build/outputs/apk/<variant>/<app>-<variant>.apk
# 我们这里 module = "app" (settings.gradle:32 include ':app'), 所以路径是
#   $BUILD_DIR/android-build/app/build/outputs/apk/release/app-release.apk
# 不是 $BUILD_DIR/android-build/build/outputs/apk/app-release.apk (少两层).
APK_SEARCH_PATHS=(
    "$BUILD_DIR/android-build/app/build/outputs/apk/$BUILD_TYPE"
    "$BUILD_DIR/android-build/build/outputs/apk/$BUILD_TYPE"
    "$BUILD_DIR/android-build/app/build/outputs/apk"
    "$BUILD_DIR/android-build/build/outputs/apk"
)
APK_PATH=""
for SEARCH_DIR in "${APK_SEARCH_PATHS[@]}"; do
    if [ -d "$SEARCH_DIR" ]; then
        APK_PATH=$(find "$SEARCH_DIR" \
            -name "*.apk" \
            ! -name "*-unsigned.apk" ! -name "*-unaligned.apk" \
            | head -n 1)
        if [ -n "$APK_PATH" ]; then
            break
        fi
    fi
done
if [ -z "$APK_PATH" ]; then
    log_error "未找到已签名的 APK 文件！"
    log_info "已搜索:"
    printf "  - %s\n" "${APK_SEARCH_PATHS[@]}"
    log_info "outputs 目录实际内容:"
    find "$BUILD_DIR/android-build" -name "*.apk" 2>/dev/null | head -20
    exit 1
fi

# 二次验证: 用 apksigner 确认 APK 真的签名了
APKSIGNER="$ANDROID_SDK/build-tools/34.0.0/apksigner"
if [ -x "$APKSIGNER" ]; then
    log_info "用 apksigner 验证签名..."
    if "$APKSIGNER" verify --print-certs "$APK_PATH" >/dev/null 2>&1; then
        log_info "✅ APK 签名验证通过"
    else
        log_error "APK 签名验证失败! 不会复制到 dist"
        "$APKSIGNER" verify --print-certs "$APK_PATH" 2>&1 | head -10
        exit 1
    fi
else
    log_warn "apksigner 未找到 ($APKSIGNER), 跳过签名验证"
fi

# ----------------------------------------------------------------------------
# 关键修复: APK 最终自检关卡
# 原因: 之前 APK 装上后立刻崩, 原因之一就是 APK 内 0 个 .so. 这里在签名验证
#       通过后、复制到 dist 前, 用 unzip -l 二次确认 .so 数量 > 0, 防止任何
#       异常路径让坏 APK 流到下游.
# ----------------------------------------------------------------------------
log_info "APK 最终自检 (lib/ 与 dex 关键类)..."
SO_COUNT_IN_APK=$(unzip -l "$APK_PATH" 2>/dev/null | awk '/\.so$/ {n++} END {print n+0}')
log_info "  APK 内 .so 数量: $SO_COUNT_IN_APK"
if [ "$SO_COUNT_IN_APK" -lt 5 ]; then
    log_error "APK 内 .so 数量过少 ($SO_COUNT_IN_APK), 启动必然 UnsatisfiedLinkError"
    log_info "APK 内 .so 列表:"
    unzip -l "$APK_PATH" 2>/dev/null | awk '/\.so$/ {print "  " $4}' | head -20
    exit 1
fi

# 关键断言: 确认 OpenSSL 3.x 运行库真的进了 APK lib/<abi>/
# 缺它 → TLS 后端 dlopen 失败 → 所有 HTTPS(含地图瓦片) 拉不到 → 地图白底.
# (2026-10-09: 之前 build_apk.sh 完全不校验, 坏 APK 会静默流入 dist)
APK_SO_LIST=$(unzip -l "$APK_PATH" 2>/dev/null | awk '/\.so$/ {print $4}')
for OSSL_LIB in libcrypto_3.so libssl_3.so; do
    if echo "$APK_SO_LIST" | grep -q "lib/$ANDROID_LIB_DIR/$OSSL_LIB"; then
        log_info "  ✅ APK 含 $OSSL_LIB (lib/$ANDROID_LIB_DIR/)"
    else
        log_error "APK 缺 $OSSL_LIB (lib/$ANDROID_LIB_DIR/)!"
        log_error "  Qt TLS 后端运行期 dlopen 找不到 OpenSSL → QSslSocket 不可用 →"
        log_error "  所有 HTTPS(含地图瓦片) 拉不到 → 地图白底. 拒绝复制到 dist."
        log_info "APK 内 .so 列表:"
        echo "$APK_SO_LIST" | sed 's/^/  /' | head -30
        exit 1
    fi
done

# 二次确认 OutdoorSurvivalApp 仍在 dex 中 (防御性, 之前已查过一次)
DEX_DIR_FINAL=$(mktemp -d)
unzip -q -o "$APK_PATH" "classes*.dex" -d "$DEX_DIR_FINAL" 2>/dev/null
FINAL_FOUND=0
for DEX_FILE in "$DEX_DIR_FINAL"/classes*.dex; do
    [ -f "$DEX_FILE" ] || continue
    if strings "$DEX_FILE" 2>/dev/null | grep -q "Lcom/outdoor/survival/OutdoorSurvivalApp;"; then
        FINAL_FOUND=1
        break
    fi
done
rm -rf "$DEX_DIR_FINAL"
if [ "$FINAL_FOUND" -eq 0 ]; then
    log_error "APK 自检失败: dex 中仍找不到 OutdoorSurvivalApp"
    exit 1
fi
log_info "✅ APK 自检全部通过 (.so=$SO_COUNT_IN_APK, OutdoorSurvivalApp 存在)"

# 提取 VERSION (从 project(... VERSION x.y.z ...) 行)
APP_VERSION_STR=$(grep -m1 "^project(" "$APP_DIR/CMakeLists.txt" | grep -oE 'VERSION[[:space:]]+[0-9]+\.[0-9]+(\.[0-9]+)?' | awk '{print $2}')
[ -z "$APP_VERSION_STR" ] && APP_VERSION_STR="0.0.1"
# 关键: 用 APP_NAME_SAFE 而不是硬编码 "OutdoorSurvival", 与 CMakeLists.txt:40 保持一致
APK_BASE_NAME="${APP_NAME_SAFE}-v${APP_VERSION_STR}-${BUILD_TYPE}-${TARGET_ABI}.apk"
mkdir -p "$APP_DIR/dist"
cp "$APK_PATH" "$APP_DIR/dist/$APK_BASE_NAME"

log_info "=========================================="
log_info "✅ APK 打包完成"
log_info "  路径: $APP_DIR/dist/$APK_BASE_NAME"
log_info "=========================================="
# ---------------------------------------------------------------------------
# 启动闪退诊断 (自动执行, 替代原"只 log_info 不做事"的占位段)
#   背景: 2026-09-20 run.txt 复现 -92 START_CLASS_NOT_FOUND, 根因是
#         adb shell am start 在 system_server 注册 app type (type=65535)
#         完成前下达, PackageManager 还没把 ActivityRecord 准备好.
#         解决: 安装后 sleep 5 等 PACKAGE_ADDED + type 注册, 再用 -W 同步启动.
# ---------------------------------------------------------------------------
APP_PACKAGE=$(grep -m1 'applicationId' "$APP_DIR/android/app/build.gradle" 2>/dev/null \
              | grep -oE '"[^"]+"' | head -1 | tr -d '"')
[ -z "$APP_PACKAGE" ] && APP_PACKAGE="com.outdoor.survival"
APP_ACTIVITY="org.qtproject.qt.android.QtActivityBase"

if command -v adb >/dev/null 2>&1 && adb get-state >/dev/null 2>&1; then
    log_info "💡 检测到 adb 设备, 自动执行启动诊断 → $APP_DIR/run.txt"
    log_info "  目标: $APP_PACKAGE/$APP_ACTIVITY"

    # [1/4] 安装 (用刚打包好的 APK)
    log_info "  [1/4] adb install -r ..."
    adb install -r "$APK_PATH" 2>&1 | tail -3 || log_warn "  install 返回非 0, 继续尝试启动"

    # [2/4] 轮询等 PackageManager 注册 (避免鸿蒙 ~2 秒 system_server 注册延迟导致 -92)
    #   鸿蒙特性: AppMarket installSuccess 回调早于 system_server 注册 app type 2 秒.
    #   固定 sleep 5 偶尔不够, 改成轮询 cmd package resolve-activity, 最多等 15 秒.
    log_info "  [2/4] 轮询等待 activity 注册 (鸿蒙 system_server 延迟 ~2s) ..."
    WAIT_SEC=0
    WAIT_MAX=15
    while [ "$WAIT_SEC" -lt "$WAIT_MAX" ]; do
        ACTIVITY_INFO=$(adb shell cmd package resolve-activity --brief "$APP_PACKAGE" 2>/dev/null | tr -d '\r' | tail -1)
        if [ "$ACTIVITY_INFO" = "$APP_PACKAGE/$APP_ACTIVITY" ]; then
            log_info "  ✅ activity 已注册 (waited ${WAIT_SEC}s): $ACTIVITY_INFO"
            break
        fi
        sleep 1
        WAIT_SEC=$((WAIT_SEC + 1))
    done
    if [ "$WAIT_SEC" -ge "$WAIT_MAX" ]; then
        log_warn "  ⚠️  activity 注册超时 (${WAIT_MAX}s), 尝试启动可能 -92"
    fi

    # 验证包已就绪
    PKG_PATH=$(adb shell pm path "$APP_PACKAGE" 2>/dev/null | tr -d '\r' | head -1)
    if [ -z "$PKG_PATH" ]; then
        log_warn "  ⚠️  pm path 返回空, 包未注册, 跳过启动"
    else
        log_info "  ✅ pm path: $PKG_PATH"

        # [3/4] 清 logcat + 同步阻塞启动 (-W 等结果, 不再发完不等)
        log_info "  [3/4] adb shell am start -W $APP_PACKAGE/$APP_ACTIVITY"
        adb logcat -c
        adb shell am start -W -n "$APP_PACKAGE/$APP_ACTIVITY" 2>&1 | head -10

        # [4/4] 等 10 秒让 QtLoader / Displayed 事件触发, 抓全量 logcat
        log_info "  [4/4] 等 10 秒后抓 logcat → $APP_DIR/run.txt"
        sleep 10
        adb logcat -d -v threadtime > "$APP_DIR/run.txt" 2>&1

        RUN_LINES=$(wc -l < "$APP_DIR/run.txt" 2>/dev/null || echo 0)
        log_info "  📄 run.txt: $RUN_LINES 行"

        # 自动检查 app 是否真的启动
        if grep -qE "ActivityTaskManager:.*Displayed.*$APP_PACKAGE" "$APP_DIR/run.txt" 2>/dev/null; then
            log_info "  ✅ 检测到 Displayed 事件, app 启动成功"
        elif grep -qE "ActivityTaskManager.*START.*$APP_PACKAGE" "$APP_DIR/run.txt" 2>/dev/null; then
            log_warn "  ⚠️  发现 START 事件, 启动可能失败 (见 run.txt)"
        else
            log_warn "  ⚠️  未发现 $APP_PACKAGE 启动日志, 需人工分析 run.txt"
        fi
    fi
else
    log_info "💡 启动诊断 (手动模式, 未检测到 adb 设备):"
    log_info "     # 1. 等 PACKAGE_ADDED 完成 (安装后至少 sleep 5)"
    log_info "     sleep 5"
    log_info "     # 2. 同步阻塞启动 (-W 等结果, 避免 -92 时序问题)"
    log_info "     adb shell am start -W -n $APP_PACKAGE/$APP_ACTIVITY"
    log_info "     # 3. 等 10 秒让 QtLoader / Displayed 事件触发"
    log_info "     sleep 10"
    log_info "     # 4. 抓全量 logcat (用 -b main 不是 -b crash)"
    log_info "     adb logcat -d -v threadtime > $APP_DIR/run.txt"
fi
stage_end
# 总耗时 (脚本启动 → 全部 4 阶段完成)
_TOTAL_END=$(date +%s)
_TOTAL_DUR=$((_TOTAL_END - SCRIPT_START_EPOCH))
log_info "⏱  脚本总耗时: $(_format_duration $_TOTAL_DUR) (从 $0 启动起算)"
log_info "🎉 全部 4 阶段完成"