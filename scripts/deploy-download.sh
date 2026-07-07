#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE_ROOT="${DOWNLOAD_SITE_ROOT:-/opt/1panel/www/sites/download.strawwu.org/index}"
BACKUP_DIR="/opt/1panel/www/sites/download.strawwu.org/changeBackup"

cd "$ROOT"
echo "==> sync branding"
bash scripts/sync-branding.sh

echo "==> deploy download page to $SITE_ROOT"
mkdir -p "$BACKUP_DIR" "$SITE_ROOT"
STAMP="$(date +%Y%m%d-%H%M%S)"
if [[ -f "$SITE_ROOT/index.html" ]]; then
  tar -czf "$BACKUP_DIR/docs-$STAMP.tgz" -C "$SITE_ROOT" .
  echo "  backup: $BACKUP_DIR/docs-$STAMP.tgz"
fi

rsync -a --delete "$ROOT/docs/" "$SITE_ROOT/"
echo "  deployed $(find "$SITE_ROOT" -type f | wc -l) files"

echo "==> reload nginx"
docker kill -s HUP 1Panel-openresty-tApj >/dev/null

echo "DONE: download.strawwu.org deploy"
