# n8n_linux_ubuntu_ngrok
# n8n + ngrok 本地部署脚本

🚀 一键在无公网环境下部署 n8n（HTTPS 访问）并暴露本地 Ollama

## ✅ 使用方式

```bash
bash <(curl -s https://raw.githubusercontent.com/usbog232/n8n_linux_ubuntu_ngrok/main/install_n8n_ngrok_local.sh)

🧠 功能说明
安装 Docker & n8n

配置并运行 ngrok 隧道（HTTPS）

自动获取公网地址并写入环境变量

将 Ollama 地址写入：/root/n8n/ollama_ngrok_url.txt

支持 systemd 开机自动启动更新脚本

📁 默认安装路径
脚本会在 /root/n8n/ 目录中生成配置文件和数据目录。
✅ 查看 n8n 的公网地址
bash
複製
編輯
cat /root/n8n/docker-compose.yml | grep WEBHOOK_URL
你会看到类似这样：

env
複製
編輯
WEBHOOK_URL=https://39a7-103-xxx-xxx.ngrok-free.app/
✅ 查看 Ollama 的公网地址
bash
複製
編輯
cat /root/n8n/ollama_ngrok_url.txt
输出类似：

arduino
複製
編輯
https://c4e4-106-75-xxx-xxx.ngrok-free.app
