#!/usr/bin/env bash
# 在 WSL2 + Docker Engine 里出 arm64-v8a 包 (2026-10-30)
#
# 为什么要这个包装脚本, 而不是照手册直接敲 docker compose:
#   1) 本机没有 Docker Desktop (Win10 19044 装不了 4.49+, 见手册 §3.1.1), docker 命令
#      只存在于 WSL 的 Ubuntu-22.04 里, Windows 侧必须经 wsl.exe 进去调;
#   2) 必须叠 docker-compose.wsl.yml —— 主 compose 把整个 /project 绑在 /mnt/d 的 9P
#      共享盘上, CMake/Ninja 那棵 1.3G 的构建树写在 9P 上会慢到不能用;
#   3) build_apk.sh 的日志写在 $APP_DIR/build/ = 卷里, Windows 看不到, 所以跑完把
#      两份日志拷到 dist/ (那是 Windows 的 app\dist\), 失败时不用进容器查。
#
# 用法 (Git Bash / PowerShell, 从 Windows 侧):
#   MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu-22.04 -u root -- \
#     bash -c "bash /mnt/d/build_docker/app/tools/wsl_build_apk.sh"
#   全量重建加 CLEAN=1:
#   ... -- bash -c "CLEAN=1 bash /mnt/d/build_docker/app/tools/wsl_build_apk.sh"
#   出模拟器包 (不涨版本号, 镜像要先 FORCE_IMAGE=1 重建过):
#   ... -- bash -c "ABI=x86_64 VERSION_BUMP=0 bash /mnt/d/build_docker/app/tools/wsl_build_apk.sh"
#
# 前置: tools/wsl_docker_setup.sh 已跑过 (docker-ce + compose 插件)。
set -euo pipefail

APP_DIR=${APP_DIR:-/mnt/d/build_docker/app}
# 位置参数与环境变量都认: `wsl_build_apk.sh release x86_64` == `TYPE=release ABI=x86_64 ...`
TYPE=${1:-${TYPE:-release}}
ABI=${2:-${ABI:-arm64-v8a}}
# 镜像构建 + C++ 编译都在容器里; 容器继承 compose 的 cpu 限制 (本机 nproc=8)
# BUILD_JOBS 透传给 build_apk.sh; WSL 默认只给主机内存的一半 (本机 7.6G),
# 并行开满 8 路 + gradle -Xmx2048m 有余量爆掉的风险, 所以默认收到 6。
BUILD_JOBS=${BUILD_JOBS:-6}

cd "$APP_DIR"
COMPOSE=(docker compose -f docker-compose.yml -f docker-compose.wsl.yml)

echo "[1/3] 镜像 outdoor-survival-android-builder"
# 镜像只在没有的时候构建 (首次要下 Qt + 源码编 qtquick3d, 实测 ~50 分钟)。
# 之后改的通常是 /project 挂载里的源码, 与镜像无关 —— 再跑一遍 compose build
# 只是把整个上下文重传 + 重导出 COPY 层 (实测白花 10 分钟)。
# 动了 Dockerfile.android / .dockerignore 时用 FORCE_IMAGE=1 强制重建。
if docker image inspect outdoor-survival-android-builder:latest >/dev/null 2>&1 \
   && [ "${FORCE_IMAGE:-0}" != "1" ]; then
    echo "  已有镜像, 跳过构建 (要重建用 FORCE_IMAGE=1)"
else
    "${COMPOSE[@]}" build android-builder
fi

echo "[2/3] 容器内打包 $TYPE / $ABI (BUILD_JOBS=$BUILD_JOBS, CLEAN=${CLEAN:-0})"
set +e
# VERSION_BUMP / VERSION 必须在这里透传进容器: 模拟器/x86_64 这种测试包不能占发布号,
# 所以出 x86_64 包时要带 VERSION_BUMP=0 (build_apk.sh 的默认行为是每次出包 +1)。
"${COMPOSE[@]}" run --rm android-builder bash -c \
    "CLEAN=${CLEAN:-0} BUILD_JOBS=$BUILD_JOBS VERSION_BUMP=${VERSION_BUMP:-1} ${VERSION:+VERSION=$VERSION} bash build_apk.sh $TYPE $ABI"
RC=$?
set -e

echo "[3/3] 拷构建日志到 dist/ (Windows 侧可读)"
# 日志在命名卷 android-build (/project/build) 里, Windows 看不见; gradle 那份是
# build_apk.sh 写的 $LOG_FILE.gradle。两份都拷进 dist/ (Windows 的 app\dist\),
# 失败时不用进容器查。
"${COMPOSE[@]}" run --rm android-builder bash -c \
    "mkdir -p /project/dist && cp -f /project/build/build_${TYPE}_${ABI}.log /project/dist/wsl_${TYPE}_${ABI}.log 2>/dev/null; \
     cp -f /project/build/build_${TYPE}_${ABI}.log.gradle /project/dist/wsl_${TYPE}_${ABI}.gradle.log 2>/dev/null; \
     ls -la /project/dist/ | tail -5" || true

echo "退出码: $RC"
ls -la "$APP_DIR/dist/" | tail -5
exit "$RC"
