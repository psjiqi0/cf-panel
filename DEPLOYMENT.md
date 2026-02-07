# CF-Pro Panel - systemd 部署与运行说明

## 快速部署（复制粘贴）

### 1. 停止当前运行
```bash
# SSH 中按 Ctrl+C 停止 python app.py
```

### 2. 生成强随机 SECRET_KEY
```bash
python3 -c "import secrets; print(secrets.token_hex(32))"
```
记下输出的字符串（形如 `a1b2c3d4...`）

### 3. 创建日志目录
```bash
sudo mkdir -p /var/log/cfpanel
```

### 4. 部署 systemd 单元
```bash
sudo cp /opt/cf-panel/cfpanel.service /etc/systemd/system/
```

### 5. 编辑并替换 SECRET_KEY
```bash
sudo nano /etc/systemd/system/cfpanel.service
```
找到这一行：
```ini
Environment=FLASK_SECRET_KEY=change_this_to_random_string_min_32_chars
```
改为：
```ini
Environment=FLASK_SECRET_KEY=<粘贴第2步生成的随机字符串>
```
保存（Ctrl+X → Y → Enter）

### 6. 重新加载并启动
```bash
sudo systemctl daemon-reload
sudo systemctl enable cfpanel.service
sudo systemctl start cfpanel.service
sudo systemctl status cfpanel.service
```

### 7. 查看日志（实时）
```bash
sudo journalctl -u cfpanel -f
```

或查看最近 50 行：
```bash
sudo journalctl -u cfpanel -n 50
```

### 8. 重启或停止
```bash
sudo systemctl restart cfpanel.service
sudo systemctl stop cfpanel.service
```

## 验证运行

访问 `http://127.0.0.1:5000`（本机），确认登录页面加载。

SSH 断开重连后：
```bash
sudo systemctl status cfpanel.service
```
应显示 `active (running)`

## 常见问题

**Q: 日志在哪？**
```bash
sudo tail -f /var/log/cfpanel/cfpanel.log
sudo tail -f /var/log/cfpanel/cfpanel.err.log
```

**Q: 如何自动轮转日志？**
创建 `/etc/logrotate.d/cfpanel`：
```
/var/log/cfpanel/*.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    create 0644 root root
    postrotate
        systemctl reload cfpanel > /dev/null 2>&1 || true
    endscript
}
```

**Q: 如何修改端口（例如改为 8000）？**
编辑 `/opt/cf-panel/app.py`，最后改为：
```python
if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8000, debug=False)
```
然后 `sudo systemctl restart cfpanel.service`

**Q: 为什么还是用 root？**
为简化初期部署。生产建议用非 root 用户（示例见下文）。

## 进阶：用非 root 用户运行（推荐安全做法）

```bash
# 创建 cfpanel 用户
sudo useradd -r -s /usr/sbin/nologin cfpanel || true

# 调整权限
sudo chown -R cfpanel:cfpanel /opt/cf-panel /var/log/cfpanel
sudo chmod 750 /opt/cf-panel /var/log/cfpanel
sudo chmod 600 /opt/cf-panel/venv
```

在 `/etc/systemd/system/cfpanel.service` 中改 `User=cfpanel` 和 `Group=cfpanel`：
```ini
User=cfpanel
Group=cfpanel
```

重新启动：
```bash
sudo systemctl daemon-reload
sudo systemctl restart cfpanel.service
```

## 安全清单

- [ ] 修改了管理员密码（登录后使用"修改密码"）
- [ ] 替换了 `FLASK_SECRET_KEY` 为强随机值
- [ ] systemd 单元已部署并自动启动
- [ ] 日志目录已创建（`/var/log/cfpanel`）
- [ ] 验证了 SSH 断开后面板仍在运行
- [ ] （推荐）用非 root 用户运行
- [ ] （推荐）配置反向代理（nginx）+ HTTPS + 额外认证

## 监控与告警（可选）

```bash
# 检查服务是否运行
sudo systemctl is-active cfpanel.service

# 若失败，查看错误
sudo journalctl -u cfpanel -n 100 --priority=err
```

定期检查日志和资源使用，必要时设置告警（例如用 monit 或 nagios）。
