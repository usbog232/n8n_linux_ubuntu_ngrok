#!/bin/bash
set -euo pipefail

COMPOSE_FILE="/root/n8n/docker-compose.yml"
NGROK_CONFIG="$HOME/.ngrok2/ngrok-ollama.yml"
NGROK_API="http://127.0.0.1:4040/api/tunnels"

# =============================
# 等待 Ollama 监听 11434
# =============================
for i in {1..10}; do
  if curl -s http://localhost:11434 > /dev/null; then
    echo "✅ Ollama 已监听端口 11434"
    break
  fi
  echo "⏳ 等待 Ollama 启动（第 $i 秒）..."
  sleep 1
done

# =============================
# 启动 ngrok 多隧道（n8n + ollama）
# =============================
echo "🚦 启动 ngrok 多隧道..."
pkill -f "ngrok start" || true
nohup ngrok start --all --config "$NGROK_CONFIG" --log=stdout --log-format=logfmt > /dev/null 2>&1 &
sleep 3

# =============================
# 获取 n8n 的公网地址
# =============================
N8N_URL=""
for i in {1..5}; do
  N8N_URL=$(curl -s "$NGROK_API" | jq -r '.tunnels[] | select(.config.addr | test("5678")) | .public_url')
  if [[ -n "$N8N_URL" ]]; then break; fi
  echo "⏳ 正在等待 n8n ngrok 地址生成..."
  sleep 2
done

if [[ -z "$N8N_URL" ]]; then
  echo "❌ 无法获取 n8n ngrok 地址"
  exit 1
fi

echo "✅ 当前 n8n ngrok 地址: $N8N_URL"

# =============================
# 替换 docker-compose 中 webhook 地址
# =============================
sed -i "s|WEBHOOK_TUNNEL_URL=.*|WEBHOOK_TUNNEL_URL=$N8N_URL|" "$COMPOSE_FILE"
sed -i "s|WEBHOOK_URL=.*|WEBHOOK_URL=$N8N_URL|" "$COMPOSE_FILE"
sed -i "s|VUE_APP_URL_BASE_API=.*|VUE_APP_URL_BASE_API=$N8N_URL|" "$COMPOSE_FILE"

# =============================
# 重启 n8n 容器
# =============================
cd /root/n8n
docker compose up -d --force-recreate
echo "🚀 n8n 容器重启完毕"

# =============================
# 获取 Ollama 公网地址并写入文件
# =============================
OLLAMA_URL=""
for i in {1..5}; do
  OLLAMA_URL=$(curl -s "$NGROK_API" | jq -r '.tunnels[] | select(.config.addr | test("11434")) | .public_url')
  if [[ -n "$OLLAMA_URL" ]]; then break; fi
  echo "⏳ 正在等待 Ollama ngrok 地址生成..."
  sleep 2
done

if [[ -z "$OLLAMA_URL" ]]; then
  echo "❌ 无法获取 Ollama ngrok 地址"
  exit 1
fi

echo "✅ 当前 Ollama ngrok 地址: $OLLAMA_URL"
echo "$OLLAMA_URL" > /root/n8n/ollama_ngrok_url.txt
