#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE_ROOT="${DOWNLOAD_SITE_ROOT:-/opt/1panel/www/sites/download.strawwu.org/index}"
RELEASES_ROOT="${DOWNLOAD_RELEASES_ROOT:-/opt/1panel/www/sites/download.strawwu.org/releases}"
BACKUP_DIR="/opt/1panel/www/sites/download.strawwu.org/changeBackup"

cd "$ROOT"
echo "==> sync branding"
bash scripts/sync-branding.sh

echo "==> sync latest release assets to CDN"
if [[ "${STRAWWU_SKIP_CDN_SYNC:-0}" != "1" ]]; then
  bash "$ROOT/scripts/sync-release-assets.sh" "${STRAWWU_SYNC_VERSION:-}"
fi

echo "==> deploy download page to $SITE_ROOT"
mkdir -p "$BACKUP_DIR" "$SITE_ROOT" "$RELEASES_ROOT"
STAMP="$(date +%Y%m%d-%H%M%S)"
if [[ -f "$SITE_ROOT/index.html" ]]; then
  tar -czf "$BACKUP_DIR/docs-$STAMP.tgz" \
    --exclude='v[0-9]*' \
    -C "$SITE_ROOT" index.html releases.json favicon.svg assets 2>/dev/null || true
  echo "  backup: $BACKUP_DIR/docs-$STAMP.tgz"
fi

rsync -a --delete --exclude='v[0-9]*' "$ROOT/docs/" "$SITE_ROOT/"
echo "  deployed $(find "$SITE_ROOT" -type f | wc -l) files"

echo "==> reload nginx"
docker kill -s HUP 1Panel-openresty-tApj >/dev/null

echo "DONE: download.strawwu.org deploy"
