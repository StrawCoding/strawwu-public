#!/usr/bin/env bash
# Smoke test download.strawwu.org CDN and strawwu-public manifest.
set -euo pipefail

BASE="${STRAWWU_PUBLIC_BASE:-http://127.0.0.1:9106}"
CDN_URL="${STRAWWU_CDN_URL:-https://download.strawwu.org}"
DOWNLOAD_BASE="${STRAWWU_DOWNLOAD_BASE:-https://download.strawwu.org}"
REPO="${STRAWWU_PUBLIC_REPO:-StrawCoding/strawwu-public}"
LATEST_TAG="${STRAWWU_LATEST_TAG:-v0.6.2.5}"
TMP_PAGES="/tmp/strawwu-public-pages-smoke.html"

pass=0
fail=0
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

if ! curl -fsS "$BASE/releases.json" >/dev/null 2>&1; then
  (cd "$(dirname "$0")/../docs" && python3 -m http.server 9106 >/tmp/strawwu-public-preview.log 2>&1 &)
  sleep 1
fi

check "local index.html" "curl -fsS '$BASE/index.html' -o /tmp/strawwu-index.html && grep -q 'StrawWU' /tmp/strawwu-index.html"
check "local releases.json" "curl -fsS '$BASE/releases.json' | python3 -c 'import json,sys; json.load(sys.stdin)'"
check "local branding icon svg" "curl -fsSI '$BASE/assets/branding/strawwu-icon.svg' | grep -q '200'"
check "local branding lockup svg" "curl -fsSI '$BASE/assets/branding/strawwu-lockup.svg' | grep -q '200'"
check "manifest no wastebase mirror" "! curl -fsS '$BASE/releases.json' | grep -q 'wastebase.xyz'"
check "manifest download.strawwu.org base" "curl -fsS '$BASE/releases.json' | grep -q 'download.strawwu.org'"
check "manifest cdn part urls" "curl -fsS '$BASE/releases.json' | grep -q '${DOWNLOAD_BASE}/${LATEST_TAG}/'"
check "github release exists" "gh release view '$LATEST_TAG' --repo '$REPO' >/dev/null"

if curl -fsS "$CDN_URL/releases.json" >/dev/null 2>&1; then
  check "cdn index" "curl -fsSL '$CDN_URL/' -o '$TMP_PAGES' && grep -q 'StrawWU' '$TMP_PAGES'"
  check "cdn releases.json" "curl -fsS '$CDN_URL/releases.json' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"download_base\"].startswith(\"https://download.strawwu.org\")'"
  check "cdn iso part" "curl -fsSI '$CDN_URL/${LATEST_TAG}/StrawWU-${LATEST_TAG#v}-amd64.iso.01.part' | grep -qi '200\\|206'"
  check "cdn SHA256SUMS" "curl -fsS '$CDN_URL/${LATEST_TAG}/SHA256SUMS' | grep -q 'StrawWU-'"
else
  echo "SKIP: live $CDN_URL (DNS/tunnel not ready yet)"
fi

echo "---"
echo "PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]]
