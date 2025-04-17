#!/bin/bash

set -euo pipefail

# === 获取用户输入 ===
echo "====== 🚀 n8n + ngrok 自动部署开始 ======"
read -p "🔑 请输入你的 ngrok Authtoken: " NGROK_TOKEN
read -p "👤 设置 n8n 登录用户名: " N8N_USER
read -p "🔒 设置 n8n 登录密码: " N8N_PASS

N8N_PORT="5678"

# === 基础设置 ===
echo "[1/8] 📦 安装依赖..."
apt update && apt install -y docker.io docker-compose jq curl unzip

# === 安装 ngrok ===
echo "[2/8] 🌐 安装 ngrok..."
wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz
rm -f ngrok && tar -xzf ngrok-v3-stable-linux-amd64.tgz
mv ngrok /usr/local/bin/ && chmod +x /usr/local/bin/ngrok
ngrok config add-authtoken "$NGROK_TOKEN"

# === 创建 n8n 目录 ===
echo "[3/8] 📁 创建 n8n 配置目录..."
mkdir -p /root/n8n && cd /root/n8n

cat <<EOF > .env
DOMAIN_NAME=n8n.tunnel.local
N8N_BASIC_AUTH_USER=$N8N_USER
N8N_BASIC_AUTH_PASSWORD=$N8N_PASS
EOF

cat <<EOF > docker-compose.yml
version: '3.7'
services:
  n8n:
    image: n8nio/n8n
    restart: always
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=\${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=\${N8N_BASIC_AUTH_PASSWORD}
      - N8N_HOST=\${DOMAIN_NAME}
      - N8N_PORT=$N8N_PORT
      - WEBHOOK_TUNNEL_URL=
      - WEBHOOK_URL=
      - VUE_APP_URL_BASE_API=
      - N8N_PROTOCOL=https
      - TZ=Asia/Shanghai
    ports:
      - "$N8N_PORT:$N8N_PORT"
    volumes:
      - n8n_data:/home/node/.n8n
volumes:
  n8n_data:
EOF

docker-compose pull

# === 配置 ngrok 隧道 ===
echo "[4/8] 📄 配置 ngrok 隧道..."
mkdir -p ~/.ngrok2
cat <<EOF > ~/.ngrok2/ngrok-local.yml
version: 2
authtoken: $NGROK_TOKEN
tunnels:
  n8n:
    proto: http
    addr: $N8N_PORT
EOF

# === systemd 托管 ngrok ===
echo "[5/8] ⚙️ 配置 systemd 管理 ngrok..."
cat <<EOF > /etc/systemd/system/ngrok.service
[Unit]
Description=Ngrok Tunnel Service for n8n
After=network.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/ngrok start --all --config /root/.ngrok2/ngrok-local.yml
Restart=always
RestartSec=5
KillMode=process
Environment=HOME=/root
WorkingDirectory=/root

[Install]
WantedBy=multi-user.target
EOF

# === webhook 更新脚本 ===
echo "[6/8] 🧠 创建 webhook 自动更新脚本..."
cat <<'EOF' > /root/n8n/update_webhook_from_ngrok.sh
#!/bin/bash
set -euo pipefail
COMPOSE_FILE="/root/n8n/docker-compose.yml"
NGROK_API="http://127.0.0.1:4040/api/tunnels"

for i in {1..5}; do
  N8N_URL=$(curl -s $NGROK_API | jq -r '.tunnels[] | select(.config.addr | test("5678")) | .public_url')
  [[ -n "$N8N_URL" ]] && break
  sleep 2
done

[[ -z "$N8N_URL" ]] && echo "❌ 无法获取 n8n 地址" && exit 1

sed -i "s|WEBHOOK_TUNNEL_URL=.*|WEBHOOK_TUNNEL_URL=$N8N_URL|" "$COMPOSE_FILE"
sed -i "s|WEBHOOK_URL=.*|WEBHOOK_URL=$N8N_URL|" "$COMPOSE_FILE"
sed -i "s|VUE_APP_URL_BASE_API=.*|VUE_APP_URL_BASE_API=$N8N_URL|" "$COMPOSE_FILE"

cd /root/n8n
docker-compose up -d --force-recreate
EOF
chmod +x /root/n8n/update_webhook_from_ngrok.sh

# === webhook systemd 服务 ===
echo "[7/8] ⚙️ 配置 systemd 管理 webhook 更新..."
cat <<EOF > /etc/systemd/system/update-ngrok-n8n.service
[Unit]
Description=Update n8n Webhook URL from ngrok
After=ngrok.service
Requires=ngrok.service

[Service]
Type=oneshot
ExecStart=/bin/bash /root/n8n/update_webhook_from_ngrok.sh

[Install]
WantedBy=multi-user.target
EOF

# === 启动服务 ===
echo "[8/8] 🚀 启动 ngrok 和 webhook 替换服务..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable ngrok.service update-ngrok-n8n.service
systemctl start ngrok.service
sleep 5
systemctl start update-ngrok-n8n.service

# === 完成提示 ===
echo -e "\n✅ 部署完成！n8n 公网地址将在几秒后出现在以下命令："
echo "curl http://127.0.0.1:4040/api/tunnels | jq"
echo "或登录 dashboard 查看： https://dashboard.ngrok.com"
