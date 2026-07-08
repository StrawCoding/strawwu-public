#!/usr/bin/env bash
# Install GitHub Release CORS proxy snippet on download.strawwu.org (1panel OpenResty).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE_PROXY="/opt/1panel/www/sites/download.strawwu.org/proxy"
SNIPPET="$ROOT/scripts/nginx-gh-proxy.conf"
TARGET="$SITE_PROXY/gh-proxy.conf"

[[ -f "$SNIPPET" ]] || { echo "Missing $SNIPPET" >&2; exit 1; }
[[ -d "$SITE_PROXY" ]] || { echo "1panel site proxy dir not found: $SITE_PROXY" >&2; exit 1; }

cp "$SNIPPET" "$TARGET"
echo "Installed $TARGET"

chmod +x "$ROOT/scripts/gh-release-proxy.mjs"
systemctl daemon-reload
systemctl enable --now gh-release-proxy.service 2>/dev/null \
  || systemctl enable --now "$(basename "$ROOT/scripts/gh-release-proxy.service")" 2>/dev/null \
  || {
    cp "$ROOT/scripts/gh-release-proxy.service" /etc/systemd/system/gh-release-proxy.service
    systemctl daemon-reload
    systemctl enable --now gh-release-proxy.service
  }

OR_CONTAINER="$(docker ps --format '{{.Names}}' | grep '^1Panel-openresty-' | head -1)"
if [[ -n "$OR_CONTAINER" ]]; then
  docker exec "$OR_CONTAINER" nginx -t
  docker exec "$OR_CONTAINER" nginx -s reload
  echo "OpenResty reloaded ($OR_CONTAINER)"
else
  echo "WARN: openresty container not found — reload nginx manually"
fi
