CF-Pro 面板 - Cloudflare 隧道管理面板

## 简介
这是一个基于 Flask 的 Web 面板，用于管理 Cloudflare Tunnel（cloudflared）和 Xray 节点。提供友好的图形化界面来创建、管理和启动隧道及代理节点。

## 快速开始

### 1. 安装依赖（Ubuntu ARM）
```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip
cd /opt/cf-panel
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 2. 持久化运行（systemd，推荐）
详见 [DEPLOYMENT.md](DEPLOYMENT.md)。快速步骤：

```bash
# 生成强随机 SECRET_KEY
python3 -c "import secrets; print(secrets.token_hex(32))"

# 创建日志目录
sudo mkdir -p /var/log/cfpanel

# 部署 systemd 单元
sudo cp cfpanel.service /etc/systemd/system/

# 编辑单元文件（替换 FLASK_SECRET_KEY）
sudo nano /etc/systemd/system/cfpanel.service

# 启动服务
sudo systemctl daemon-reload
sudo systemctl enable --now cfpanel.service
sudo systemctl status cfpanel.service
```

### 3. 首次访问
- **URL**: `http://127.0.0.1:5000`（本机）
- **用户名**: `admin`
- **密码**: `admin123`
- **必做**: 登录后立即修改密码！

## 功能

| 功能 | 说明 |
|------|------|
| 临时隧道 | 快速测试 Cloudflare TryCloudflare（无需账户） |
| 注册域名 | 链接 Cloudflare 账户，创建和管理自定义隧道 |
| 已保存域名 | 查看、启动、删除已配置的隧道 |
| 代理节点 | 生成 VMess/VLESS 链接用于客户端 |
| 密码管理 | 修改管理员密码 |

## 安全清单

- [ ] 首次登录后修改管理员密码
- [ ] 替换 `FLASK_SECRET_KEY` 为强随机值
- [ ] 部署 systemd 单元并验证自动启动
- [ ] 通过 nginx/Caddy 反向代理 + HTTPS 暴露
- [ ] （推荐）启用 Cloudflare Access（强制多因子认证）
- [ ] （推荐）用非 root 用户运行（见 DEPLOYMENT.md）
- [ ] （推荐）配置 fail2ban 防暴力破解
- [ ] 定期更新依赖: `pip install -U -r requirements.txt`

## 项目结构

```
cf-panel/
├── app.py                  # Flask 主应用
├── templates/
│   ├── index.html         # 主页面
│   └── login.html         # 登录页
├── static/
│   ├── style.css          # 样式表
│   └── main.js            # 前端逻辑
├── cfpanel.service        # systemd 单元
├── requirements.txt       # Python 依赖
├── DEPLOYMENT.md          # 部署详细说明
└── README.md             # 本文件
```

## 配置说明

### 环境变量
- `FLASK_ENV`: 设为 `production`（生产）或 `development`（开发）
- `FLASK_SECRET_KEY`: 强随机字符串（用于 session 加密），必须替换

### 文件权限
- 凭证文件（`/etc/cf_pro/creds/`）: `chmod 600`
- 配置文件（`/etc/cf_pro/configs/`）: `chmod 600`
- 面板目录（`/opt/cf-panel`）: 运行用户可读写

## 常见问题

**Q: SSH 断开后面板停止运行？**
A: 不要用 `python app.py &`，改用 systemd（见 DEPLOYMENT.md）

**Q: 忘记密码怎么办？**
A: 删除 `/etc/cf_pro/users.json`，重启面板自动创建默认用户（admin/admin123）

**Q: 日志在哪里？**
A: `/var/log/cfpanel/cfpanel.log` 和 `/var/log/cfpanel/cfpanel.err.log`
   或用 `sudo journalctl -u cfpanel -f` 查看实时日志

**Q: 如何修改监听端口？**
A: 编辑 `app.py` 最后一行，改 `port=5000` 为其他值，重启服务

**Q: 为什么要用反向代理？**
A: 面板绑定本地 127.0.0.1，反代提供 HTTPS、公网暴露、额外认证等安全能力

## 生产部署建议

1. **用非 root 用户运行**
   ```bash
   sudo useradd -r -s /usr/sbin/nologin cfpanel
   sudo chown -R cfpanel:cfpanel /opt/cf-panel /var/log/cfpanel
   # 编辑 cfpanel.service，改 User=cfpanel
   ```

2. **配置反向代理（nginx 示例）**
   ```nginx
   server {
       listen 80;
       server_name panel.example.com;
       location / {
           proxy_pass http://127.0.0.1:5000;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
       }
   }
   ```

3. **启用 HTTPS（Certbot）**
   ```bash
   sudo apt install -y certbot python3-certbot-nginx
   sudo certbot --nginx -d panel.example.com
   ```

4. **启用 Cloudflare Access（可选，强化安全）**
   - 在 Cloudflare 控制台配置 Access
   - 限制面板只能由特定邮箱/SSO 访问

5. **监控与告警**
   ```bash
   sudo journalctl -u cfpanel -n 100 | grep ERROR
   # 或设置 systemd 失败重启次数限制和告警
   ```

## 安全性注意

- **不要暴露 0.0.0.0 或公网 IP**：使用本地监听 + 反代
- **定期轮换凭证**：Cloudflare API Token、隧道 token 等
- **监控访问日志**：检查异常登录尝试
- **使用强密码**：至少 12+ 字符，包含大小写和特殊符号
- **备份配置**：定期备份 `/etc/cf_pro` 目录
- **及时更新**：跟进 Flask、依赖的安全补丁

## 许可与支持

本项目为开源项目。使用前请确认理解 Cloudflare Tunnel 的使用条款和风险。

## 更新日志

- **v1.0** (2026-02-07) 
  - 初始版本：登录认证、domain 管理、隧道启动、节点生成
  - 实现了速率限制和密码修改功能
  - 美化了 UI 并优化了响应式设计
