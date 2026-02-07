# CF-Panel Server Deployment

This document describes step-by-step deployment on an Ubuntu (ARM or x86_64) server.
It assumes you will place the project at `/opt/cf-panel`.

IMPORTANT: The scripts in `deploy/` perform administrative actions. Review before running.

## 1. Copy repository to server

Option A — clone from GitHub on server:
```bash
sudo mkdir -p /opt
sudo chown $(whoami):$(whoami) /opt
cd /opt
git clone <your-repo-url> cf-panel
cd cf-panel
```

Option B — upload archive and extract:
```bash
scp myrepo.tar.gz user@server:/tmp/
ssh user@server
sudo mkdir -p /opt/cf-panel
sudo tar -C /opt/cf-panel -xzf /tmp/myrepo.tar.gz --strip-components=1
sudo chown -R $(whoami):$(whoami) /opt/cf-panel
cd /opt/cf-panel
```

## 2. Prepare Python venv and install requirements (as deploy user)
```bash
cd /opt/cf-panel
python3 -m venv venv
./venv/bin/pip install --upgrade pip
./venv/bin/pip install -r requirements.txt
```
If you prefer the system Python packages, adapt accordingly.

## 3. Run the setup script (creates service user, env, installs gunicorn, binaries)
The `setup_cfpanel.sh` handles creating the `cfpanel` user, directories, env file and will call the binary installer.

Run as root (recommended):
```bash
cd /opt/cf-panel/deploy
sudo bash ./setup_cfpanel.sh
```
To force re-download of cloudflared/xray:
```bash
sudo bash ./setup_cfpanel.sh --force
```

Notes:
- The script will create `/etc/cfpanel/env` containing `FLASK_SECRET_KEY`. Change that secret after install.
- Downloaded binaries are placed under the project `bin/` by default (e.g. `/opt/cf-panel/bin`).

## 4. Verify and enable the systemd service
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now cfpanel.service
sudo systemctl status cfpanel.service
sudo journalctl -u cfpanel -f
```
If the service fails, check `journalctl -xe` and the journal for startup errors.

## 5. Change default admin password and secure env
- If you used the bundled default admin account, change the password immediately via the panel or API.
- Secure `/etc/cfpanel/env`:
```bash
sudo chmod 600 /etc/cfpanel/env
sudo chown root:cfpanel /etc/cfpanel/env
```

## 6. (Optional) Run behind nginx reverse proxy with TLS
Example `nginx` site file (adjust domain and paths):
```nginx
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
```
Then obtain TLS with Certbot:
```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d example.com
```

Important: If nginx is used, keep the panel bound on `127.0.0.1:5000` and do not expose it directly.

## 7. Configure cloudflared & xray services (recommended)
Instead of letting the panel fork background processes, create dedicated systemd units for `cloudflared` and `xray`. Example units are provided in `deploy/` — adapt tokens/paths and enable them with:
```bash
sudo cp deploy/cloudflared.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cloudflared.service
```

## 8. Firewall and system hardening
- Allow only needed ports (80/443 for nginx, otherwise none):
```bash
sudo apt install ufw
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw enable
```
- Consider Fail2Ban to protect SSH and HTTP endpoints.

## 9. Logs and troubleshooting
- Panel logs via systemd:
```bash
sudo journalctl -u cfpanel -f
```
- cloudflared/xray logs: check their respective systemd units or `deploy/bin` files if running directly.

## 10. Rollback / cleanup
To remove downloaded binaries and temporary files created by the deploy scripts, use the provided cleanup script (interactive):
```bash
cd /opt/cf-panel/deploy
sudo bash ./delete_all_files.sh
```
To remove system installed files as well (dangerous):
```bash
sudo bash ./delete_all_files.sh --yes --system
```

## 11. Post-deploy checklist
- Confirm `cfpanel` user exists and `cfpanel.service` is running under that user.
- Verify `FLASK_SECRET_KEY` in `/etc/cfpanel/env` is unique and not the default.
- Change admin password.
- Ensure `/opt/cf-panel` and `/etc/cfpanel` ownership and permissions are appropriate (owned by `cfpanel` where needed, `chmod 750` for dirs storing secrets).

## 12. Common issues
- "Port already in use": ensure no other process binds 5000 or the port used by gunicorn.
- "cloudflared not found": confirm downloaded binary exists in `/opt/cf-panel/bin` or `/etc/cf_pro/bin`, and its mode is executable.
- API rate limits when downloading many times: use `--force` sparingly.

## 13. If you want me to finish remotely
I cannot run commands on your server without access. I can, however, generate a one-line script that you can copy and run to perform the whole process automatically. Ask me to prepare that if desired.

---

If anything above should be adjusted to the specifics of your target server (non-default install path, custom domain, separate cloudflared path), tell me and I will update the instructions and scripts accordingly.
