#!/usr/bin/env bash
# 荒野手册单元测试 (桌面 Qt6, 容器内执行)
#
#   docker compose run --rm unit-test                      # 全部
#   docker compose run --rm unit-test bash run_unit_tests.sh /project/build-host
#
# 说明:
#   - 用桌面 gcc_64 Qt 而不是 Android Qt: 单测无需设备, 跑得快, 且服务层是平台无关代码
#   - 桌面 Qt 必须含 qtpositioning (见 Dockerfile.hosttests), 否则 RouteService/
#     MapService/EmergencyService 直接 configure 失败
#   - AssetLoader 通过 OUTDOOR_ASSET_ROOT 环境变量定位 assets/data (由 tests/CMakeLists.txt
#     注入到 CTest), 测试进程没有 qrc
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# build-host 是 docker-compose.yml 里 unit-test service 的 Linux 命名卷,
# 增量编译可复用; 绝不能指到 Windows bind mount (链接出的 ELF 会变 0 字节)
BUILD_DIR="${1:-${PROJECT_DIR}/build-host}"
QT_PREFIX="${QT_PREFIX:-/opt/Qt/6.7.2/gcc_64}"

echo "=== CONFIGURE ==="
cmake -S "${PROJECT_DIR}/tests" -B "${BUILD_DIR}" \
      -DCMAKE_BUILD_TYPE=Debug \
      -DCMAKE_PREFIX_PATH="${QT_PREFIX}"

echo "=== BUILD ==="
cmake --build "${BUILD_DIR}" -j"$(nproc)"

echo "=== CTEST ==="
ctest --test-dir "${BUILD_DIR}" --output-on-failure
