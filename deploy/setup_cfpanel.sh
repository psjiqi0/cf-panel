#!/usr/bin/env bash
set -euo pipefail
# usage: sudo ./setup_cfpanel.sh
# Creates cfpanel user, dirs, env, installs gunicorn in venv if present, and installs service unit
INSTALL_DIR="/opt/cf-panel"
SERVICE_SRC="$(pwd)/cfpanel.service"
SYSTEMD_DEST="/etc/systemd/system/cfpanel.service"
RUNTIME_USER="cfpanel"

# parse optional args: --force to force re-download binaries
FORCE_INSTALL=0
if [ "${1:-}" = "--force" ]; then
  FORCE_INSTALL=1
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo $0"
  exit 1
fi

# create system user
if ! id -u "$RUNTIME_USER" >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "$RUNTIME_USER"
  echo "Created user $RUNTIME_USER"
else
  echo "User $RUNTIME_USER already exists"
fi

# create dirs
mkdir -p /var/log/cfpanel /etc/cfpanel
chown -R "$RUNTIME_USER":"$RUNTIME_USER" /var/log/cfpanel /etc/cfpanel "$INSTALL_DIR" || true
chmod 750 /var/log/cfpanel

# create env file if not exists
ENVFILE=/etc/cfpanel/env
if [ ! -f "$ENVFILE" ]; then
  SECRET=$(openssl rand -hex 24)
  cat > "$ENVFILE" <<EOF
FLASK_ENV=production
FLASK_SECRET_KEY=$SECRET
#CF_API_TOKEN=
EOF
  chmod 600 "$ENVFILE"
  chown root:"$RUNTIME_USER" "$ENVFILE"
  echo "Created $ENVFILE"
else
  echo "$ENVFILE already exists"
fi

# install gunicorn if venv exists, force install all dependencies
if [ -d "$INSTALL_DIR/venv" ]; then
  echo "Installing Python dependencies via venv..."
  chmod +x "$INSTALL_DIR/venv/bin/python3" 2>/dev/null || true
  "$INSTALL_DIR/venv/bin/python3" -m pip install --upgrade pip --quiet 2>/dev/null || true
  "$INSTALL_DIR/venv/bin/python3" -m pip install -r "$INSTALL_DIR/requirements.txt" --quiet 2>/dev/null || true
  "$INSTALL_DIR/venv/bin/python3" -m pip install gunicorn --quiet 2>/dev/null || true
  echo "Installed dependencies and gunicorn into venv"
else
  echo "No venv found at $INSTALL_DIR/venv. Skipping dependency install."
fi

# install systemd unit
if [ -f "$SERVICE_SRC" ]; then
  cp "$SERVICE_SRC" "$SYSTEMD_DEST"
  chmod 644 "$SYSTEMD_DEST"
  systemctl daemon-reload
  systemctl enable --now cfpanel.service
  echo "Installed and started cfpanel.service"
else
  echo "Service file $SERVICE_SRC not found. Copy manually to $SYSTEMD_DEST"
fi

# attempt to install cloudflared and xray if installer present
if [ -f "$(pwd)/install_binaries.sh" ]; then
  echo "Running install_binaries.sh to fetch cloudflared and xray"
  if [ $FORCE_INSTALL -eq 1 ]; then
    bash "$(pwd)/install_binaries.sh" --force || echo "install_binaries.sh exited with error"
  else
    bash "$(pwd)/install_binaries.sh" || echo "install_binaries.sh exited with error"
  fi
else
  echo "install_binaries.sh not found; skipping cloudflared/xray install"
fi

echo "Done. Check status with: systemctl status cfpanel.service"
