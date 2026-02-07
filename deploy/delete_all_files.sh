#!/usr/bin/env bash
set -euo pipefail
# delete_all_files.sh
# Safely remove project-managed downloaded binaries and temporary files.
# Usage: sudo ./delete_all_files.sh [--yes] [--system]
# --yes  : skip interactive confirmation
# --system : also remove system install dir /etc/cf_pro/bin (requires root)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

TARGETS=(
  "$PROJECT_ROOT/bin"
  "$SCRIPT_DIR/bin"
  "$SCRIPT_DIR"/*.tgz
  "$SCRIPT_DIR"/*.zip
  "$SCRIPT_DIR"/*.deb
  "$SCRIPT_DIR"/*.pkg
  "$SCRIPT_DIR"/*.exe
  "$SCRIPT_DIR"/*cloudflared*
  "$SCRIPT_DIR"/*xray*
)

REMOVE_SYSTEM=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --system) REMOVE_SYSTEM=1; shift;;
    --yes) FORCE=1; shift;;
    *) ;;
  esac
done

if [ $REMOVE_SYSTEM -eq 1 ] && [ "$(id -u)" -ne 0 ]; then
  echo "--system requires root. Re-run with sudo."; exit 1
fi

echo "The following paths will be deleted (if they exist):"
for p in "${TARGETS[@]}"; do
  # expand globs for display
  for f in $p; do
    [ -e "$f" ] && echo "  $f"
  done
done
if [ $REMOVE_SYSTEM -eq 1 ]; then
  echo "  /etc/cf_pro/bin (system binaries)"
fi

if [ $FORCE -eq 0 ]; then
  echo
  read -rp "Type DELETE to confirm removal: " confirm
  if [ "$confirm" != "DELETE" ]; then
    echo "Aborted by user."; exit 0
  fi
fi

# perform deletions
for p in "${TARGETS[@]}"; do
  for f in $p; do
    if [ -e "$f" ]; then
      echo "Removing $f"
      rm -rf "$f" || echo "Failed to remove $f"
    fi
  done
done

if [ $REMOVE_SYSTEM -eq 1 ]; then
  if [ -d "/etc/cf_pro/bin" ]; then
    echo "Removing /etc/cf_pro/bin"
    rm -rf /etc/cf_pro/bin || echo "Failed to remove /etc/cf_pro/bin"
  fi
fi

echo "Cleanup complete."
