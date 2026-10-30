#!/usr/bin/env bash
# WSL2 里装 Docker Engine (构建 Android APK 用) —— 见 doc/07-部署与发布/Docker构建APK手册.md §3.1.1
#
# 为什么不用 Docker Desktop: 本机是 Windows 10 21H2 (10.0.19044), Docker Desktop 4.49+
#   要求 19045+, 且不装 WSL 版也没法跑 Linux 容器. 所以走 "WSL2 里的原生 docker-ce",
#   Windows 侧通过 `wsl.exe -d Ubuntu-22.04 -- docker ...` 调它.
#
# 用法 (在 Git Bash / PowerShell 里):
#   MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu-22.04 -u root -- bash -c \
#     "bash /mnt/d/build_docker/app/tools/wsl_docker_setup.sh"
#
# 口径:
#   - 装 docker-ce (Docker 官方 apt 仓库的阿里云镜像), **不装** Ubuntu 自带的 docker.io:
#     docker.io 不带 compose v2 插件, 而本项目全部命令写的都是 `docker compose` (无横线).
#   - 幂等: 已经装过的包 apt 会自己跳过; 源已经换过不会再换一遍.
set -euo pipefail

MIRROR=${APT_MIRROR:-mirrors.tuna.tsinghua.edu.cn}
DOCKER_APT=${DOCKER_APT_MIRROR:-mirrors.aliyun.com/docker-ce}

echo "[1/5] apt 源换到 $MIRROR"
if [ -f /etc/apt/sources.list ] && grep -q 'archive.ubuntu.com\|security.ubuntu.com' /etc/apt/sources.list; then
    [ -f /etc/apt/sources.list.bak ] || cp /etc/apt/sources.list /etc/apt/sources.list.bak
    sed -i "s|http://archive.ubuntu.com/ubuntu|http://$MIRROR/ubuntu|g; \
            s|http://security.ubuntu.com/ubuntu|http://$MIRROR/ubuntu|g" /etc/apt/sources.list
fi
# Ubuntu 24.04+ 的 deb822 格式 (jammy 用不上, 但脚本要能在新发行版上重跑)
if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
    sed -i "s|http://archive.ubuntu.com/ubuntu|http://$MIRROR/ubuntu|g; \
            s|http://security.ubuntu.com/ubuntu|http://$MIRROR/ubuntu|g" /etc/apt/sources.list.d/ubuntu.sources
fi
apt-get update

echo "[2/5] 前置包"
apt-get install -y --no-install-recommends ca-certificates curl gnupg

echo "[3/5] Docker 官方 apt 仓库 (镜像: $DOCKER_APT)"
install -m 0755 -d /etc/apt/keyrings
if [ ! -s /etc/apt/keyrings/docker.asc ]; then
    curl -fsSL --max-time 120 "https://$DOCKER_APT/linux/ubuntu/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
fi
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
ARCH=$(dpkg --print-architecture)
cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.asc] https://$DOCKER_APT/linux/ubuntu $CODENAME stable
EOF
apt-get update

echo "[4/5] 安装 docker-ce + compose/buildx 插件"
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[5/5] 开机自启 (需要 systemd)"
if [ -d /run/systemd/system ]; then
    systemctl enable docker
    systemctl start docker || true
else
    # 本次还没有 systemd (/etc/wsl.conf 里 boot.systemd=true 要 wsl --shutdown 重启才生效),
    # 先手工把守护进程拉起来, 让脚本一次跑完就能验证.
    service docker start || (dockerd >/var/log/dockerd.out 2>&1 &)
    sleep 3
    echo "  ⚠️  本次是无 systemd 启动的 dockerd; 要让 WSL 一起来就用 docker,"
    echo "     请在 /etc/wsl.conf 加 [boot] systemd=true 后执行 wsl --shutdown 再进来."
fi

docker --version
docker compose version
docker info --format 'Server API {{.ServerVersion}} / storage={{.Driver}}' || true
echo "✅ Docker Engine 就绪"
