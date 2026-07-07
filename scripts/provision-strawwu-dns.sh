#!/usr/bin/env bash
# Provision strawwu.org DNS on Cloudflare.
# - download.strawwu.org → GitHub Pages (strawcoding.github.io)
# - strawwu.org / www / apt → wastebase-origin Cloudflare Tunnel
# Preview: *.strawwu.org.wastebase.xyz (wastebase.xyz zone token from cert.pem or 1Panel).
# Apex: strawwu.org / www / download / apt (STRAWWU_CF_API_TOKEN or CLOUDFLARE_API_TOKEN + zone).
set -euo pipefail

ZONE_NAME="${STRAWWU_ZONE_NAME:-strawwu.org}"
TUNNEL_CNAME="${STRAWWU_TUNNEL_CNAME:-807e8f07-7a7d-4170-b061-d4efd86dcb0f.cfargotunnel.com}"
GITHUB_PAGES_CNAME="${STRAWWU_GITHUB_PAGES_CNAME:-strawcoding.github.io}"
TUNNEL_NAMES=(strawwu.org www apt)
DOWNLOAD_NAME="download"

cert_token() {
  python3 - <<'PY'
import base64, json, re
from pathlib import Path
p = Path("/root/.cloudflared/cert.pem")
if not p.exists():
    raise SystemExit
text = p.read_text()
m = re.search(r"-----BEGIN ARGO TUNNEL TOKEN-----\n(.+?)\n-----END", text, re.S)
if not m:
    raise SystemExit
data = json.loads(base64.b64decode("".join(m.group(1).split())))
print(data["apiToken"])
PY
}

panel_token() {
  [[ -f /opt/1panel/db/1Panel.db ]] || return 1
  python3 - <<'PY'
import json, sqlite3
db = sqlite3.connect("/opt/1panel/db/1Panel.db")
row = db.execute(
    "SELECT authorization FROM website_dns_accounts WHERE name='CF' AND type='CloudFlare' LIMIT 1"
).fetchone()
if row:
    print(json.loads(row[0])["apiKey"])
PY
}

hermes_token() {
  [[ -f /root/.hermes/.env ]] || return 1
  grep -m1 '^CLOUDFLARE_API_TOKEN=' /root/.hermes/.env | cut -d= -f2-
}

apex_token() {
  if [[ -n "${STRAWWU_CF_API_TOKEN:-}" ]]; then
    printf '%s' "$STRAWWU_CF_API_TOKEN"
    return 0
  fi
  hermes_token
}

api_upsert_cname() {
  local token="$1" zone_id="$2" record_name="$3" content="$4" proxied="${5:-true}"
  local payload rec_id resp
  payload="$(python3 - "$record_name" "$content" "$proxied" <<'PY'
import json, sys
name, content, proxied = sys.argv[1:4]
print(json.dumps({
  "type": "CNAME",
  "name": name,
  "content": content,
  "proxied": proxied.lower() == "true",
}))
PY
)"
  rec_id="$(curl -fsS -H "Authorization: Bearer $token" \
    "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?type=CNAME&name=${record_name}" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); r=d.get('result') or []; print(r[0]['id'] if r else '')")"
  if [[ -n "$rec_id" ]]; then
    curl -fsS -X PUT -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
      "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${rec_id}" \
      --data "$payload" >/dev/null
    echo "UPDATED: $record_name → $content (proxied=$proxied)"
    return 0
  fi
  resp="$(curl -fsS -X POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records" \
    --data "$payload")"
  if echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('success') else 1)"; then
    echo "CREATED: $record_name → $content (proxied=$proxied)"
    return 0
  fi
  echo "FAIL: $record_name" >&2
  echo "$resp" >&2
  return 1
}

preview_token=""
for candidate in "$(cert_token 2>/dev/null || true)" "$(panel_token 2>/dev/null || true)"; do
  [[ -n "$candidate" ]] || continue
  if curl -fsS -H "Authorization: Bearer $candidate" \
    "https://api.cloudflare.com/client/v4/zones/${WASTEBASE_ZONE_ID:-2264dfaaa1ab77b5278b281cc43b2a7d}" \
    | python3 -c "import json,sys; sys.exit(0 if json.load(sys.stdin).get('success') else 1)"; then
    preview_token="$candidate"
    break
  fi
done
[[ -n "$preview_token" ]] || { echo "No token with wastebase.xyz zone access." >&2; exit 1; }

WASTEBASE_ZONE_ID="${WASTEBASE_ZONE_ID:-2264dfaaa1ab77b5278b281cc43b2a7d}"

echo "==> preview DNS on wastebase.xyz (zone ${WASTEBASE_ZONE_ID})"
for name in "${TUNNEL_NAMES[@]}"; do
  if [[ "$name" == "strawwu.org" ]]; then
    preview_name="strawwu.org.wastebase.xyz"
  else
    preview_name="${name}.strawwu.org.wastebase.xyz"
  fi
  api_upsert_cname "$preview_token" "$WASTEBASE_ZONE_ID" "$preview_name" "$TUNNEL_CNAME" true
done
api_upsert_cname "$preview_token" "$WASTEBASE_ZONE_ID" \
  "${DOWNLOAD_NAME}.strawwu.org.wastebase.xyz" "$GITHUB_PAGES_CNAME" false

apex_tok="$(apex_token || true)"
if [[ -z "${apex_tok:-}" ]]; then
  echo "WARN: no apex token; preview only"
  exit 0
fi

zone_id="${STRAWWU_ZONE_ID:-}"
if [[ -z "$zone_id" ]]; then
  zone_id="$(curl -fsS -H "Authorization: Bearer $apex_tok" \
    "https://api.cloudflare.com/client/v4/zones?name=${ZONE_NAME}" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); r=d.get('result') or []; print(r[0]['id'] if r else '')")"
fi

if [[ -z "$zone_id" ]]; then
  echo "WARN: ${ZONE_NAME} zone not visible to apex token."
  echo "      Export STRAWWU_ZONE_ID=<zone_id> if token is DNS-only for that zone."
  echo "      Or add ${ZONE_NAME} to the tunnel Cloudflare account."
  echo "DONE: preview subdomains only"
  exit 0
fi

echo "==> apex DNS on ${ZONE_NAME} (zone ${zone_id})"
for name in "${TUNNEL_NAMES[@]}"; do
  if [[ "$name" == "strawwu.org" ]]; then
    record_name="$ZONE_NAME"
  else
    record_name="${name}.${ZONE_NAME}"
  fi
  api_upsert_cname "$apex_tok" "$zone_id" "$record_name" "$TUNNEL_CNAME" true
done
api_upsert_cname "$apex_tok" "$zone_id" \
  "${DOWNLOAD_NAME}.${ZONE_NAME}" "$GITHUB_PAGES_CNAME" false

echo "DONE: strawwu.org DNS (download → GitHub Pages, others → tunnel)"
