#!/usr/bin/env bash
set -euo pipefail
# one_click_deploy.sh
# Usage: sudo ./one_click_deploy.sh [--repo GIT_URL] [--install-path /opt/cf-panel] [--force]

REPO=""
INSTALL_DIR="/opt/cf-panel"
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2;;
    --install-path) INSTALL_DIR="$2"; shift 2;;
    --force) FORCE=1; shift;;
    -h|--help) echo "Usage: $0 [--repo GIT_URL] [--install-path PATH] [--force]"; exit 0;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root: sudo $0"; exit 1
fi

echo "One-click deploy starting. Install dir: $INSTALL_DIR"

# Ensure prerequisites
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y git curl wget unzip tar python3 python3-venv python3-pip openssl
else
  echo "apt-get not found. Please install prerequisites manually: git, curl, wget, python3, python3-venv, unzip, tar. Aborting."; exit 1
fi

# Clone or prepare directory
if [ -n "$REPO" ]; then
  if [ -d "$INSTALL_DIR" ]; then
    ts=$(date +%s)
    echo "Backing up existing $INSTALL_DIR to ${INSTALL_DIR}.bak.$ts"
    mv "$INSTALL_DIR" "${INSTALL_DIR}.bak.$ts"
  fi
  echo "Cloning $REPO -> $INSTALL_DIR"
  git clone "$REPO" "$INSTALL_DIR"
fi

if [ ! -d "$INSTALL_DIR" ]; then
  echo "$INSTALL_DIR does not exist. Aborting."; exit 1
fi

# Create venv and install requirements
echo "Creating Python virtualenv"
python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install --upgrade pip
if [ -f "$INSTALL_DIR/requirements.txt" ]; then
  "$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt" || true
fi

# Make deploy scripts executable
chmod +x "$INSTALL_DIR/deploy/setup_cfpanel.sh" || true
chmod +x "$INSTALL_DIR/deploy/install_binaries.sh" || true
chmod +x "$INSTALL_DIR/deploy/delete_all_files.sh" || true
chmod +x "$INSTALL_DIR/deploy/one_click_deploy.sh" || true

# Run setup script
cd "$INSTALL_DIR/deploy"
if [ $FORCE -eq 1 ]; then
  ./setup_cfpanel.sh --force
else
  ./setup_cfpanel.sh
fi

# Ensure systemd reload and start
systemctl daemon-reload || true
systemctl enable --now cfpanel.service || true

echo "Deployment finished. Check service status:"
systemctl status cfpanel.service --no-pager || true

echo "View logs: sudo journalctl -u cfpanel -f"

exit 0
