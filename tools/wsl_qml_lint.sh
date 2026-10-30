#!/usr/bin/env bash
# 在容器里跑 QML 门禁 (qmllint), 日志落回 Windows 侧可读的 dist/.
# 用法: bash tools/wsl_qml_lint.sh [.qml 路径...]   # 不给参数 = 全量 qml/
#
# 为什么要包一层: Windows → wsl.exe → docker compose run 这条链上, 任何 "$( )" 都会被
# Git Bash 吃掉 (见 doc/07 §3.1.2 第 2 条), 所以参数只能在 WSL 侧展开.
set -uo pipefail
cd /mnt/d/build_docker/app

LOG=dist/qml_lint_$(date +%Y%m%d_%H%M%S).log
ARGS=""
for a in "$@"; do ARGS="$ARGS $a"; done

docker compose -f docker-compose.yml -f docker-compose.wsl.yml run --rm android-builder \
    bash -c "bash tools/qml_lint.sh$ARGS > /project/$LOG 2>&1; echo rc=\$?; grep -c '^Warning' /project/$LOG; grep '^Error' /project/$LOG | head -20"

echo "日志: app/$LOG"
