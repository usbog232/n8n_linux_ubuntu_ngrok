#!/bin/bash

set -euo pipefail

echo "====== 🚀 一键部署 Cloudflare Tunnel + n8n 开始 ======"

read -p "🌐 请输入你的完整域名（如 n8n.example.com）: " DOMAIN
read -p "📧 请输入你的 Cloudflare 账户邮箱（用于提示）: " EMAIL
read -p "👤 请输入 n8n 登录用户名: " N8N_USER
read -p "🔒 请输入 n8n 登录密码: " N8N_PASS

# 安装 Docker（如未安装）
if ! command -v docker &> /dev/null; then
    echo "🔧 安装 Docker 中..."
    curl -fsSL https://get.docker.com | bash
fi

# 安装 docker-compose plugin（适配新版）
if ! docker compose version &> /dev/null; then
    echo "🔧 安装 docker compose plugin 中..."
    apt-get update
    apt-get install -y docker-compose-plugin
fi

# 安装 cloudflared（如未安装）
if ! command -v cloudflared &> /dev/null; then
    echo "🔧 安装 cloudflared 中..."
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o cloudflared.deb
    sudo dpkg -i cloudflared.deb
fi

# 登录 Cloudflare 账号（弹出浏览器）
echo "🌐 请用浏览器打开授权链接进行 Cloudflare 登录..."
cloudflared tunnel login

# 创建 tunnel
TUNNEL_NAME="n8n-tunnel"
TUNNEL_ID=$(cloudflared tunnel create $TUNNEL_NAME | grep 'Created tunnel' | awk '{print $4}')
CREDENTIAL_FILE="/root/.cloudflared/${TUNNEL_ID}.json"

# 写入 cloudflared 配置
mkdir -p ~/.cloudflared
cat <<EOF > ~/.cloudflared/config.yml
tunnel: $TUNNEL_ID
credentials-file: $CREDENTIAL_FILE

ingress:
  - hostname: $DOMAIN
    service: http://localhost:5678
  - service: http_status:404
EOF

# 安装 tunnel systemd 服务
cloudflared service install

# 创建 n8n 工作目录
mkdir -p /root/n8n/n8n_data
cd /root/n8n

# 生成 docker-compose.yml
cat <<EOF > docker-compose.yml
version: "3"

services:
  n8n:
    image: n8nio/n8n
    restart: always
    ports:
      - "5678:5678"
    environment:
      - N8N_PORT=5678
      - N8N_HOST=0.0.0.0
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=$N8N_USER
      - N8N_BASIC_AUTH_PASSWORD=$N8N_PASS
      - WEBHOOK_URL=https://$DOMAIN
      - VUE_APP_URL_BASE_API=https://$DOMAIN
      - NODE_ENV=production
      - TZ=Asia/Shanghai
    volumes:
      - ./n8n_data:/home/node/.n8n
EOF

# 启动 n8n 服务
docker compose up -d

# 提示 DNS 设置
echo ""
echo "✅ 请前往 Cloudflare 网站设置以下 DNS:"
echo ""
echo "类型：CNAME"
echo "名称：$(echo $DOMAIN | cut -d. -f1)"
echo "内容：$TUNNEL_ID.cfargotunnel.com"
echo "状态：🔶 代理（Proxy）开启"
echo ""
echo "📦 n8n 服务已部署成功，公网访问地址为： https://$DOMAIN"
