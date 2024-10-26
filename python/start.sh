#!/bin/bash
QB_PORT="22147"    # qBittorrent Web UI 端口
ALIST_PORT=${ALIST_PORT:-5244}   # Alist 端口，如果不填写就启动内网穿透
ADMIN_PASSWORD=${ADMIN_PASSWORD:-qwe123456}  # Alist和qBittorrent密码，账号都是admin

# 统一输出格式的函数
log_info() {
    echo -e "\033[1;32m[信息]\033[0m $1"
}

log_error() {
    echo -e "\033[1;31m[错误]\033[0m $1"
}

ARCH=$(uname -m)
log_info "检测到处理器架构：$ARCH"

if [[ ! -f "./bin/busybox" ]]; then
    log_info "未找到 BusyBox，正在下载..."
    mkdir -p ./bin
    curl -L -sS -o ./bin/busybox https://busybox.net/downloads/binaries/1.21.1/busybox-x86_64
    chmod +x ./bin/busybox
    log_info "BusyBox 下载并安装完成"
else
    log_info "BusyBox 已存在，跳过下载"
fi

# 检查 qBittorrent 文件是否存在
if [[ ! -f "./qbittorrent-nox/qbittorrent-nox" ]]; then
    log_info "未找到 qBittorrent 文件，正在下载..."

    if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
        QB_URL="https://github.com/c0re100/qBittorrent-Enhanced-Edition/releases/download/release-4.6.7.10/qbittorrent-enhanced-nox_x86_64-linux-musl_static.zip"
    elif [[ "$ARCH" == "arm" || "$ARCH" == "armv7l" || "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
        QB_URL="https://github.com/c0re100/qBittorrent-Enhanced-Edition/releases/download/release-4.6.7.10/qbittorrent-enhanced-nox_aarch64-linux-musl_static.zip"
    else
        log_error "不支持的架构：$ARCH"
        exit 1
    fi

    curl -L -sS -o qbittorrent.zip "$QB_URL"
    mkdir -p ./qbittorrent-nox
    ./bin/busybox unzip qbittorrent.zip -d ./qbittorrent-nox
    rm -f qbittorrent.zip
    chmod +x ./qbittorrent-nox/qbittorrent-nox
    log_info "qBittorrent 下载并解压完成"
fi

# 启动 qBittorrent
log_info "启动 qBittorrent，端口：$QB_PORT"
./qbittorrent-nox/qbittorrent-nox --webui-port=$QB_PORT &
sleep 5

install_and_config_alist() {
    log_info "正在安装 Alist..."

    if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
        ALIST_URL="https://github.com/alist-org/alist/releases/download/v3.38.0/alist-linux-amd64.tar.gz"
    elif [[ "$ARCH" == "arm" || "$ARCH" == "armv7l" || "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
        ALIST_URL="https://github.com/alist-org/alist/releases/download/v3.38.0/alist-linux-arm64.tar.gz"
    else
        log_error "不支持的架构：$ARCH"
        exit 1
    fi

    INSTALL_DIR="$HOME/alist"
    mkdir -p "$INSTALL_DIR"

    if [[ ! -f "$INSTALL_DIR/alist" ]]; then
        log_info "未找到 Alist 文件，正在下载..."
        curl -L -sS -o alist.tar.gz "$ALIST_URL"
        tar -zxvf alist.tar.gz -C "$INSTALL_DIR"
        rm -f alist.tar.gz
        chmod +x "$INSTALL_DIR/alist"
        log_info "Alist 下载并解压完成"
    else
        log_info "Alist 已存在，跳过下载"
    fi

    CONFIG_FILE="$HOME/data/config.json"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_info "配置文件不存在，先启动 Alist 以生成配置文件..."
        nohup "$INSTALL_DIR/alist" server > "$INSTALL_DIR/alist_temp.log" 2>&1 &
        sleep 5
        if [[ -f "$CONFIG_FILE" ]]; then
            log_info "配置文件生成成功：$CONFIG_FILE"
        else
            log_error "启动后配置文件仍然不存在，退出。"
            exit 1
        fi
    else
        log_info "检测到已有配置文件，直接进行配置更新..."
    fi

    sed -i "s/\"http_port\":.*/\"http_port\": $ALIST_PORT,/" "$CONFIG_FILE"
    log_info "Alist 配置已更新，端口：$ALIST_PORT"

    log_info "启动 Alist 服务..."
    nohup "$INSTALL_DIR/alist" server > "$INSTALL_DIR/alist.log" 2>&1 &
    "$INSTALL_DIR/alist" admin set "$ADMIN_PASSWORD"
    log_info "Alist 已安装并运行，日志位于 $INSTALL_DIR/alist.log"
}

# Serveo 内网穿透
start_serveo_tunnel() {
    if [[ ! -f "./bin/dropbear" ]]; then
        log_info "未找到 dropbear，正在下载..."
        curl -L -sS -o ./bin/dropbear "https://github.com/zylf00/alist-qBittorrent/raw/refs/heads/main/test/dropbear"
        chmod +x ./bin/dropbear
        log_info "dropbear 下载并配置完成"
    fi

    PORT_FILE="serveo_port.txt"
    if [[ ! -f "$PORT_FILE" ]]; then
        ALIST_PUBLIC_PORT=$(shuf -i 1024-65535 -n 1)
        echo "$ALIST_PUBLIC_PORT" > "$PORT_FILE"
        log_info "生成并记录随机端口：$ALIST_PUBLIC_PORT"
    else
        ALIST_PUBLIC_PORT=$(cat "$PORT_FILE")
        log_info "使用记录的端口：$ALIST_PUBLIC_PORT"
    fi

    log_info "启动 Serveo 隧道用于 Alist 服务..."
    nohup ./bin/dropbear -y -T -R $ALIST_PUBLIC_PORT:localhost:$ALIST_PORT serveo.net > serveo_tunnel.log 2>&1 &
    log_info "Alist 服务现在可通过 serveo.net:${ALIST_PUBLIC_PORT} 访问"
}

# 启动 Alist 并根据端口情况决定是否启用 Serveo 隧道
install_and_config_alist
if [[ -z "$ALIST_PORT" || "$ALIST_PORT" == "5244" ]]; then
    start_serveo_tunnel
    disown
else
    log_info "ALIST_PORT 已配置为 $ALIST_PORT，不启用内网穿透"
fi

