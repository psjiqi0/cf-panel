#!/usr/bin/env bash
set -euo pipefail

# install_binaries.sh
# Download cloudflared and Xray binaries for the current architecture
# Usage: install_binaries.sh [bin_dir]
# Default bin_dir: /opt/cf-panel/bin

BIN_DIR="${1:-/opt/cf-panel/bin}"
mkdir -p "$BIN_DIR"
chmod 755 "$BIN_DIR"
echo "Installing binaries into $BIN_DIR"

# Detect architecture
MACHINE="$(uname -m)"
case "$MACHINE" in
  aarch64|arm64)
    CLOUD_ARCH="arm64"
    XRAY_PATTERNS="arm64|aarch64"
    ;;
  armv7l|armv7)
    CLOUD_ARCH="arm"
    XRAY_PATTERNS="armv7|arm"
    ;;
  x86_64|amd64)
    CLOUD_ARCH="amd64"
    XRAY_PATTERNS="amd64|x86_64|64"
    ;;
  i386|i686)
    CLOUD_ARCH="386"
    XRAY_PATTERNS="386|32"
    ;;
  *)
    echo "Unsupported architecture: $MACHINE" >&2
    exit 1
    ;;
esac

echo "Detected architecture: $MACHINE -> cloudflared: $CLOUD_ARCH, xray: $XRAY_PATTERNS"

# Download cloudflared
echo ""
echo "=== Downloading cloudflared ==="
CLOUD_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$CLOUD_ARCH"
echo "URL: $CLOUD_URL"

if curl -fsSL -o "$BIN_DIR/cloudflared" "$CLOUD_URL"; then
  chmod +x "$BIN_DIR/cloudflared"
  echo "✓ Installed cloudflared -> $BIN_DIR/cloudflared"
else
  echo "✗ Failed to download cloudflared" >&2
  exit 1
fi

# Download and extract Xray
echo ""
echo "=== Downloading Xray ==="

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

API_URL="https://api.github.com/repos/XTLS/Xray-core/releases/latest"
echo "Querying GitHub API: $API_URL"

# Try to find a matching asset URL
ASSET_URL=$(curl -s "$API_URL" \
  | grep -Po '"browser_download_url":\s*"\K[^"]*' \
  | grep -i linux \
  | grep -E -i "$XRAY_PATTERNS" \
  | head -n1 || true)

if [ -z "$ASSET_URL" ]; then
  echo "Automatic detection failed, trying common fallback URLs..."
  
  candidates=(
    "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${CLOUD_ARCH}.zip"
    "https://github.com/XTLS/Xray-core/releases/latest/download/xray-linux-${CLOUD_ARCH}.zip"
    "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${MACHINE}.zip"
  )
  
  for cand in "${candidates[@]}"; do
    echo "Checking: $cand"
    if curl -fsSL -I "$cand" >/dev/null 2>&1; then
      ASSET_URL="$cand"
      echo "Found!"
      break
    fi
  done
fi

if [ -z "$ASSET_URL" ]; then
  echo "Could not find Xray asset for architecture $MACHINE" >&2
  exit 1
fi

echo "Downloading: $ASSET_URL"
ARCHIVE="$TMPDIR/xray.zip"

if ! curl -fsSL -o "$ARCHIVE" "$ASSET_URL"; then
  echo "Failed to download Xray" >&2
  exit 1
fi

# Ensure unzip is available
if ! command -v unzip >/dev/null 2>&1; then
  echo "unzip not found, attempting to install..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y && apt-get install -y unzip
  else
    echo "Please install unzip and re-run this script" >&2
    exit 1
  fi
fi

# Extract archive
echo "Extracting archive..."
unzip -q "$ARCHIVE" -d "$TMPDIR"

# Find xray binary
XRAY_BIN=""
XRAY_BIN=$(find "$TMPDIR" -type f -iname 'xray' -executable | head -n1 || true)

if [ -z "$XRAY_BIN" ]; then
  XRAY_BIN=$(find "$TMPDIR" -type f -iname 'xray' | head -n1 || true)
fi

if [ -z "$XRAY_BIN" ]; then
  echo "Xray binary not found in archive. Contents:" >&2
  ls -R "$TMPDIR" >&2
  exit 1
fi

mv "$XRAY_BIN" "$BIN_DIR/xray"
chmod +x "$BIN_DIR/xray"
echo "✓ Installed xray -> $BIN_DIR/xray"

echo ""
echo "=== Verification ==="
ls -lh "$BIN_DIR"

echo ""
echo "✓ All binaries installed successfully"
