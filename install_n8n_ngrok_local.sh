#!/bin/bash
set -euo pipefail

echo "====== 🚀 n8n + ngrok 本地部署 HTTPS 自动化脚本 ======"

# 用户交互输入
read -p "🔑 请输入你的 ngrok Token: " NGROK_TOKEN
read -p "🌐 n8n 监听端口（默认 5678）: " N8N_PORT
N8N_PORT=${N8N_PORT:-5678}
read -p "🧠 Ollama 监听端口（默认 11434）: " OLLAMA_PORT
OLLAMA_PORT=${OLLAMA_PORT:-11434}
read -p "👤 设置 n8n 登录用户名: " N8N_USER
read -p "🔒 设置 n8n 登录密码: " N8N_PASS

# 安装依赖
echo "📦 安装 Docker、Docker Compose 和 jq..."
apt update && apt install -y curl jq docker.io docker-compose
systemctl enable docker && systemctl start docker

# 创建目录
mkdir -p /root/n8n && cd /root/n8n

# 写入 docker-compose.yml
cat <<EOF > docker-compose.yml
version: "3"

services:
  n8n:
    image: n8nio/n8n
    restart: always
    ports:
      - "$N8N_PORT:$N8N_PORT"
    environment:
      - N8N_PORT=$N8N_PORT
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=$N8N_USER
      - N8N_BASIC_AUTH_PASSWORD=$N8N_PASS
      - WEBHOOK_TUNNEL_URL=https://placeholder.com
      - WEBHOOK_URL=https://placeholder.com
      - VUE_APP_URL_BASE_API=https://placeholder.com
      - NODE_ENV=production
      - TZ=Asia/Shanghai
    volumes:
      - ./n8n_data:/home/node/.n8n
EOF

# 写入 ngrok 配置
mkdir -p ~/.ngrok2
cat <<EOF > ~/.ngrok2/ngrok-local.yml
authtoken: $NGROK_TOKEN

tunnels:
  n8n:
    proto: http
    addr: $N8N_PORT
  ollama:
    proto: http
    addr: $OLLAMA_PORT
EOF

# 写入更新脚本
cat <<EOF > /root/n8n/update_ngrok_all.sh
#!/bin/bash
set -euo pipefail

COMPOSE_FILE="/root/n8n/docker-compose.yml"
NGROK_CONFIG="\$HOME/.ngrok2/ngrok-local.yml"
NGROK_API="http://127.0.0.1:4040/api/tunnels"

# 等待 Ollama 启动监听
for i in {1..10}; do
  if curl -s http://localhost:$OLLAMA_PORT > /dev/null; then
    echo "✅ Ollama 已监听端口 $OLLAMA_PORT"
    break
  fi
  echo "⏳ 等待 Ollama 启动（第 \$i 秒）..."
  sleep 1
done

# 启动 ngrok（拆开）
pkill -f "ngrok start" || true
nohup ngrok start n8n --config "\$NGROK_CONFIG" --log=stdout --log-format=logfmt > /dev/null 2>&1 &
sleep 2
nohup ngrok start ollama --config "\$NGROK_CONFIG" --log=stdout --log-format=logfmt > /dev/null 2>&1 &
sleep 3

# 获取 n8n 公网地址
for i in {1..5}; do
  N8N_URL=\$(curl -s \$NGROK_API | jq -r '.tunnels[] | select(.config.addr | test("$N8N_PORT")) | .public_url')
  [[ -n "\$N8N_URL" ]] && break
  sleep 2
done
[[ -z "\$N8N_URL" ]] && echo "❌ 无法获取 n8n 地址" && exit 1
echo "✅ n8n 公网地址: \$N8N_URL"

# 替换 docker-compose 环境变量
sed -i "s|WEBHOOK_TUNNEL_URL=.*|WEBHOOK_TUNNEL_URL=\$N8N_URL|" "\$COMPOSE_FILE"
sed -i "s|WEBHOOK_URL=.*|WEBHOOK_URL=\$N8N_URL|" "\$COMPOSE_FILE"
sed -i "s|VUE_APP_URL_BASE_API=.*|VUE_APP_URL_BASE_API=\$N8N_URL|" "\$COMPOSE_FILE"

cd /root/n8n
docker compose up -d --force-recreate

# 获取 Ollama 公网地址
for i in {1..5}; do
  OLLAMA_URL=\$(curl -s \$NGROK_API | jq -r '.tunnels[] | select(.config.addr | test("$OLLAMA_PORT")) | .public_url')
  [[ -n "\$OLLAMA_URL" ]] && break
  sleep 2
done
[[ -z "\$OLLAMA_URL" ]] && echo "❌ 无法获取 Ollama 地址" && exit 1
echo "✅ Ollama 公网地址: \$OLLAMA_URL"
echo "\$OLLAMA_URL" > /root/n8n/ollama_ngrok_url.txt
EOF

chmod +x /root/n8n/update_ngrok_all.sh

# systemd 开机自启服务
cat <<EOF > /etc/systemd/system/update-ngrok-all.service
[Unit]
Description=n8n + Ollama ngrok auto starter
After=network.target docker.service

[Service]
Type=oneshot
ExecStart=/root/n8n/update_ngrok_all.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable update-ngrok-all.service
systemctl start update-ngrok-all.service

echo ""
echo "✅ 安装完成！"
echo "🌐 n8n 公网地址将在 update_ngrok_all.sh 执行后自动替换"
echo "📁 Ollama 公网地址文件：/root/n8n/ollama_ngrok_url.txt"
echo ""
