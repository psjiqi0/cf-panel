CF-Pro 面板 (轻量版)

简介
- 这是一个基于 Flask 的简易面板，用于管理 Cloudflare 隧道（cloudflared）和 Xray 节点，面板包装了你提供的脚本的常用功能。

部署（在 Ubuntu ARM 上）
1. 将你的原始安装脚本放到 `/etc/cf_pro`，或运行脚本来安装 `cloudflared` 与 `xray`。脚本也已复制到本仓库的 `cf_pro.sh` 供参考。
2. 在服务器上安装 Python 依赖：

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip
cd /path/to/cf-panel
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

3. 以 root 权限运行面板（需要对 `/etc/cf_pro` 写权限并能启动 cloudflared/xray）：

```bash
sudo -E venv/bin/python app.py
# 或使用 systemd 创建服务，把工作目录设为 cf-panel
```

使用
- 打开浏览器访问 `http://<server-ip>:5000`。
- 面板提供：启动临时隧道、注册并绑定域名、列出并启动保存的域名、启动 VMess/VLESS 节点等。

注意
- 面板会尝试在 `/etc/cf_pro` 下读写文件，请保证运行用户有权限（建议使用 sudo 运行）。
- 这只是轻量版本，线上运行请考虑反向代理、HTTPS、认证和进程管理（systemd）。

文件说明
- app.py: Flask 后端
- templates/index.html: 简单前端
- static/: 前端静态资源
- cf_pro.sh: 你的原始脚本副本
- requirements.txt: Python 依赖

安全与生产
- 强烈建议在生产环境前添加身份认证（例如 nginx + basic auth 或 OAuth）
- 使用 systemd 管理面板进程并使用 nginx 做 TLS 终端
