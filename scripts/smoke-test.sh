#!/usr/bin/env bash
# Smoke test strawwu-public manifest and CDN / GitHub Release metadata.
set -euo pipefail

BASE="${STRAWWU_PUBLIC_BASE:-http://127.0.0.1:9106}"
CDN_BASE="${STRAWWU_ISO_CDN_BASE:-https://download.strawwu.org}"
GITHUB_DOWNLOAD_BASE="${STRAWWU_RELEASES_DOWNLOAD_BASE:-https://github.com/StrawCoding/strawwu-public/releases/download}"
PAGES_URL="${STRAWWU_PAGES_URL:-https://strawcoding.github.io/strawwu-public}"
REPO="${STRAWWU_PUBLIC_REPO:-StrawCoding/strawwu-public}"
LATEST_TAG="${STRAWWU_LATEST_TAG:-v0.6.2.5}"
LATEST_VER="${LATEST_TAG#v}"

pass=0
fail=0
skip=0
check() {
  local name="$1" cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    echo "PASS: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name"
    fail=$((fail + 1))
  fi
}
skip_check() {
  echo "SKIP: $1"
  skip=$((skip + 1))
}

if ! curl -fsS "$BASE/releases.json" >/dev/null 2>&1; then
  (cd "$(dirname "$0")/../docs" && python3 -m http.server 9106 >/tmp/strawwu-public-preview.log 2>&1 &)
  sleep 1
fi

check "local index.html" "curl -fsS '$BASE/index.html' -o /tmp/strawwu-index.html && grep -q 'StrawWU' /tmp/strawwu-index.html"
check "local releases.json" "curl -fsS '$BASE/releases.json' | python3 -c 'import json,sys; json.load(sys.stdin)'"
check "local branding icon svg" "curl -fsSI '$BASE/assets/branding/strawwu-icon.svg' | grep -q '200'"
check "local branding lockup svg" "curl -fsSI '$BASE/assets/branding/strawwu-lockup.svg' | grep -q '200'"
check "manifest no wastebase mirror" "! curl -fsS '$BASE/releases.json' | grep -q 'wastebase.xyz'"
check "manifest no split parts" "! curl -fsS '$BASE/releases.json' | grep -q '\\.part'"
check "manifest schema v5" "curl -fsS '$BASE/releases.json' | grep -q 'strawwu-public-releases/v5'"
check "manifest cdn base" "curl -fsS '$BASE/releases.json' | grep -q 'download.strawwu.org'"
check "github release exists" "gh release view '$LATEST_TAG' --repo '$REPO' >/dev/null"
check "github SHA256SUMS" "curl -fsSL '${GITHUB_DOWNLOAD_BASE}/${LATEST_TAG}/SHA256SUMS' | grep -q 'StrawWU-'"

iso_head="$(curl -fsSI "${CDN_BASE}/releases/${LATEST_TAG}/StrawWU-${LATEST_VER}-amd64.iso" 2>/dev/null || true)"
if echo "$iso_head" | grep -qi '200\|206' && echo "$iso_head" | grep -qi 'octet-stream\|iso9660\|binary'; then
  check "cdn direct iso" "true"
elif echo "$iso_head" | grep -qi '200\|206' && echo "$iso_head" | grep -qi 'text/html'; then
  skip_check "cdn direct iso (CDN returns HTML placeholder — upload ISO to R2 first)"
else
  skip_check "cdn direct iso (upload pending — source scripts/iso-cdn.env && ./scripts/publish-github-release.sh ${LATEST_VER})"
fi

if curl -fsS "$PAGES_URL/releases.json" >/dev/null 2>&1; then
  check "pages releases.json" "curl -fsS '$PAGES_URL/releases.json' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get(\"schema\",\"\").startswith(\"strawwu-public-releases/v\")'"
else
  skip_check "live $PAGES_URL (push main to trigger Pages)"
fi

echo "---"
echo "PASS=$pass FAIL=$fail SKIP=$skip"
[[ "$fail" -eq 0 ]]
