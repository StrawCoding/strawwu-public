#!/usr/bin/env bash
# Smoke test strawwu-public GitHub Pages site and release assets.
set -euo pipefail

BASE="${STRAWWU_PUBLIC_BASE:-http://127.0.0.1:9106}"
PAGES_URL="${STRAWWU_PAGES_URL:-https://strawcoding.github.io/strawwu-public/}"
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
check "manifest github download base" "curl -fsS '$BASE/releases.json' | grep -q 'github.com/${REPO}'"
check "github release exists" "gh release view '$LATEST_TAG' --repo '$REPO' >/dev/null"
check "github release has iso part" "gh release view '$LATEST_TAG' --repo '$REPO' --json assets -q '.assets[].name' | grep -q '.part'"
check "github release SHA256SUMS" "curl -fsSL 'https://github.com/${REPO}/releases/download/${LATEST_TAG}/SHA256SUMS' | grep -q 'StrawWU-'"
check "pages site (if deployed)" "curl -fsSL '$PAGES_URL' -o '$TMP_PAGES' && grep -q 'StrawWU' '$TMP_PAGES'"

echo "---"
echo "PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]]
