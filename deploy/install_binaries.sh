#!/usr/bin/env bash
set -euo pipefail
# install_binaries.sh
# Detect architecture and download cloudflared + xray-core to /usr/local/bin (idempotent)
# Run as root.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# install into project root's bin directory (parent of deploy)
INSTALL_DIR_BIN="$(dirname "$SCRIPT_DIR")/bin"
TMPDIR=${TMPDIR:-/tmp}
FORCE=0

if [ "${1:-}" = "--force" ]; then
  FORCE=1
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

arch=$(uname -m)
case "$arch" in
  x86_64|amd64) CF_ARCH="amd64"; XRAY_PREF="linux-64";;
  aarch64|arm64) CF_ARCH="arm64"; XRAY_PREF="linux-arm64-v8a";;
  armv7l|armv7) CF_ARCH="arm"; XRAY_PREF="linux-arm32-v7a";;
  armv6l) CF_ARCH="arm"; XRAY_PREF="linux-arm32-v5";;
  *) echo "Unsupported architecture: $arch"; exit 1;;
esac

# helper to try a list of candidate assets from a GitHub latest/download base
mkdir -p "$INSTALL_DIR_BIN"
echo "Installing binaries into $INSTALL_DIR_BIN"

# cloudflared: try a list of common filenames under releases/latest/download
CF_BIN="$INSTALL_DIR_BIN/cloudflared"
CF_BASE="https://github.com/cloudflare/cloudflared/releases/latest/download"
CF_CAND=(
  "cloudflared-linux-${CF_ARCH}"
  "cloudflared-linux-${CF_ARCH}.tgz"
  "cloudflared-linux-${CF_ARCH}.deb"
  "cloudflared-amd64.pkg"
)

found=0
for cand in "${CF_CAND[@]}"; do
  url="$CF_BASE/$cand"
  echo "Trying $url"
  if curl -fL -o "$INSTALL_DIR_BIN/$cand" "$url"; then
    echo "Downloaded $cand"
    case "$cand" in
      *.tgz)
        tar -xzf "$INSTALL_DIR_BIN/$cand" -C "$TMPDIR" || { echo "extract failed"; continue; }
        if [ -f "$TMPDIR/cloudflared" ]; then mv -f "$TMPDIR/cloudflared" "$CF_BIN"; fi
        ;;
      *.deb)
        dpkg -x "$INSTALL_DIR_BIN/$cand" "$TMPDIR/debroot" || true
        if [ -f "$TMPDIR/debroot/usr/bin/cloudflared" ]; then mv -f "$TMPDIR/debroot/usr/bin/cloudflared" "$CF_BIN"; fi
        ;;
      *)
        mv -f "$INSTALL_DIR_BIN/$cand" "$CF_BIN" || true
        ;;
    esac
    found=1
    break
  else
    rm -f "$INSTALL_DIR_BIN/$cand" 2>/dev/null || true
  fi
done

if [ $found -eq 0 ]; then
  echo "Failed to download any cloudflared candidate for ${CF_ARCH}"; exit 1
fi
chmod 755 "$CF_BIN" || true
echo "Installed cloudflared -> $CF_BIN"

# xray: try common filenames
XRAY_BIN="$INSTALL_DIR_BIN/xray"
XRAY_BASE="https://github.com/XTLS/Xray-core/releases/latest/download"

XRAY_CAND=(
  "Xray-${XRAY_PREF}.zip"
  "Xray-linux-64.zip"
  "Xray-linux-arm64-v8a.zip"
  "Xray-linux-arm32-v7a.zip"
  "Xray-linux-arm32-v5.zip"
)

found=0
for cand in "${XRAY_CAND[@]}"; do
  url="$XRAY_BASE/$cand"
  echo "Trying $url"
  if curl -fL -o "$INSTALL_DIR_BIN/$cand" "$url"; then
    echo "Downloaded $cand"
    mkdir -p "$TMPDIR/unpack"
    if command -v unzip >/dev/null 2>&1; then
      unzip -o "$INSTALL_DIR_BIN/$cand" -d "$TMPDIR/unpack" >/dev/null
    else
      python3 - <<PY
import zipfile,sys
with zipfile.ZipFile(sys.argv[1]) as z:
    z.extractall(sys.argv[2])
PY "$INSTALL_DIR_BIN/$cand" "$TMPDIR/unpack"
    fi
    src=$(find "$TMPDIR/unpack" -type f -name xray -o -name Xray | head -n1 || true)
    if [ -n "$src" ] && [ -f "$src" ]; then
      mv -f "$src" "$XRAY_BIN"
      chmod 755 "$XRAY_BIN"
      echo "Installed xray -> $XRAY_BIN"
      found=1
      break
    else
      echo "xray binary not found inside $cand"
    fi
  else
    rm -f "$INSTALL_DIR_BIN/$cand" 2>/dev/null || true
  fi
done

if [ $found -eq 0 ]; then
  echo "Failed to download any xray candidate for ${arch}"; exit 1
fi

echo "Binary installation complete. Files are in $INSTALL_DIR_BIN"

# final checks
if command -v cloudflared >/dev/null 2>&1; then
  echo "cloudflared: $(cloudflared --version 2>/dev/null | head -n1)"
fi
if command -v xray >/dev/null 2>&1; then
  echo "xray: $(xray version 2>/dev/null || true)"
fi

echo "Binary installation complete."
