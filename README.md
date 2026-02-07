## 📋 CF-Panel 启动使用教程

### 一、部署检查清单

确认服务器上已完成以下步骤：

```bash
# 1. 检查服务状态（应显示 Active: active (running)）
sudo systemctl status cfpanel.service --no-pager

# 2. 检查二进制文件
ls -lh /opt/cf-panel/bin/
# 输出应包含 cloudflared 和 xray

# 3. 检查用户账户
sudo cat /etc/cf_pro/users.json

# 4. 检查 systemd 日志（应无错误）
sudo journalctl -u cfpanel.service -n 20 --no-pager
```

---

### 二、访问面板

**本地访问（服务器本机）：**
```bash
# 获取 IP
ip addr | grep "inet " | grep -v 127.0.0.1

# 浏览器访问
http://127.0.0.1:5000
```

**远程访问（从其他机器）：**

1) **直接访问**（如果防火墙允许）：
```bash
# 服务器上允许 5000 端口
sudo ufw allow 5000
# 然后在客户端访问：http://<服务器IP>:5000
```

2) **推荐：使用 Nginx 反向代理 + TLS**：
```bash
# 服务器上安装 Nginx
sudo apt-get install nginx certbot python3-certbot-nginx

# 创建 Nginx 配置（替换 example.com）
sudo tee /etc/nginx/sites-available/cf-panel > /dev/null << 'EOF'
server {
  listen 80;
  server_name example.com;
  
  location / {
    proxy_pass http://127.0.0.1:5000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
EOF

# 启用 Nginx 配置
sudo ln -s /etc/nginx/sites-available/cf-panel /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# 获取免费 SSL 证书（需要域名指向服务器）
sudo certbot --nginx -d example.com

# 自动续期
sudo systemctl enable certbot.timer
```

---

### 三、登录面板

打开浏览器访问 `http://127.0.0.1:5000` 或你的域名，使用默认账户登录：

```
用户名: admin
密码: admin123
```

**⚠️ 首次登录后，立即修改密码！**

---

### 四、基本操作

#### 1. 获取临时 Cloudflare 域名

面板会自动轮询获取免费的 `trycloudflare.com` 临时域名。

#### 2. 添加自己的域名

在面板中添加你自己的 Cloudflare 域名（需要 API Token）。

#### 3. 启动/停止隧道和节点

使用面板的 UI 启动或停止 cloudflared 和 xray 进程。

#### 4. 查看日志

```bash
# 面板服务日志
sudo journalctl -u cfpanel.service -f

# 如果运行 cloudflared/xray 服务，查看各自的日志
sudo journalctl -u cloudflared.service -f
sudo journalctl -u xray.service -f
```

---

### 五、重要的配置和密钥

**修改 Flask Secret（推荐首次部署后立即做）：**

```bash
# 生成新密钥
openssl rand -hex 32

# 编辑环境文件
sudo nano /etc/cfpanel/env
# 修改 FLASK_SECRET_KEY=<新值>

# 重启服务
sudo systemctl restart cfpanel.service
```

**设置 Cloudflare API Token（可选）：**

```bash
# 编辑环境文件
sudo nano /etc/cfpanel/env
# 添加：CF_API_TOKEN=<你的 API Token>

# 重启服务
sudo systemctl restart cfpanel.service
```

---

### 六、启动/停止/重启服务

```bash
# 启动
sudo systemctl start cfpanel.service

# 停止
sudo systemctl stop cfpanel.service

# 重启
sudo systemctl restart cfpanel.service

# 查看状态
sudo systemctl status cfpanel.service

# 查看实时日志
sudo journalctl -u cfpanel.service -f

# 启用/禁用开机自启
sudo systemctl enable cfpanel.service
sudo systemctl disable cfpanel.service
```

---

### 七、更新和维护

**拉取最新代码：**
```bash
cd /opt/cf-panel
sudo git pull origin main
sudo systemctl restart cfpanel.service
```

**更新依赖：**
```bash
sudo /opt/cf-panel/venv/bin/pip install --upgrade -r /opt/cf-panel/requirements.txt
sudo systemctl restart cfpanel.service
```

**重新下载二进制文件：**
```bash
sudo /opt/cf-panel/deploy/install_binaries.sh --force
```

---

### 八、备份和恢复

**备份配置：**
```bash
# 备份用户数据
sudo cp /etc/cf_pro/users.json /opt/cf-panel/backup/users.json.bak

# 备份环境配置
sudo cp /etc/cfpanel/env /opt/cf-panel/backup/env.bak

# 备份整个项目
sudo tar -czf /opt/cf-panel-backup-$(date +%Y%m%d).tar.gz /opt/cf-panel /etc/cf_pro /etc/cfpanel
```

**恢复：**
```bash
# 从备份恢复
sudo tar -xzf /opt/cf-panel-backup-20260207.tar.gz -C /
sudo systemctl restart cfpanel.service
```

---

### 九、常见故障排查

| 问题 | 解决方案 |
|------|--------|
| **服务无法启动** | `sudo journalctl -u cfpanel.service -n 50` 查看日志 |
| **登录失败** | 检查 `/etc/cf_pro/users.json` 权限：`sudo chmod 600 /etc/cf_pro/users.json` |
| **cloudflared/xray 找不到** | 确认 `/opt/cf-panel/bin/` 中的二进制存在：`ls -la /opt/cf-panel/bin/` |
| **无法从外网访问** | 检查防火墙：`sudo ufw allow 5000` 或 `sudo ufw allow http` |
| **端口被占用** | 检查：`sudo lsof -i :5000` 或 `sudo netstat -tlnp \| grep 5000` |

---

### 十、安全建议

1. **修改默认密码** ✓
2. **更改 Flask Secret** ✓
3. **设置防火墙规则**：仅允许必要的端口（SSH、HTTP、HTTPS）
4. **启用 SELinux 或 AppArmor**（可选）
5. **定期备份**：至少每周备份一次
6. **监控日志**：设置日志告警
7. **使用 Nginx + TLS**：不要直接暴露 gunicorn 到互联网
8. **限制 SSH 访问**：只允许特定 IP 或使用密钥认证

---

### 十一、完全卸载和清理

如需完全移除：

```bash
# 停止服务
sudo systemctl stop cfpanel.service
sudo systemctl disable cfpanel.service

# 删除 systemd 单元
sudo rm cfpanel.service
sudo systemctl daemon-reload

# 删除项目目录
sudo rm -rf /opt/cf-panel

# 删除配置和数据
sudo rm -rf /etc/cf_pro /etc/cfpanel

# 删除系统用户
sudo userdel cfpanel
sudo groupdel cfpanel

# 清理日志
sudo rm -rf /var/log/cfpanel
```

---

### 十二、获取帮助

- **查看面板日志**：`sudo journalctl -u cfpanel.service -f`
- **查看系统日志**：`sudo dmesg | tail -50`
- **GitHub 仓库**：https://github.com/psjiqi0/cf-panel
- **报告问题**：在 GitHub Issues 中提出

---

**祝你使用愉快！** 🎉---
