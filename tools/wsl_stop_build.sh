#!/usr/bin/env bash
# 停掉 WSL 侧在跑的出包过程 (包装脚本 + compose 起的容器)
pkill -f wsl_build_apk.sh 2>/dev/null && echo "killed wrapper" || echo "wrapper 不在跑"
IDS=$(docker ps -q)
if [ -n "$IDS" ]; then
    echo "停止容器: $IDS"
    docker stop $IDS >/dev/null 2>&1
else
    echo "没有运行中的容器"
fi
sleep 2
docker ps --format '{{.Names}} {{.Status}}'
echo "--- 剩余 ---"
