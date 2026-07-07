#!/usr/bin/env bash
# Smoke test strawwu-public download site and ISO mirror.
set -euo pipefail

BASE="${STRAWWU_PUBLIC_BASE:-http://127.0.0.1:9106}"
PAGES_URL="${STRAWWU_PAGES_URL:-https://strawcoding.github.io/strawwu-public/}"
ISO_URL="${STRAWWU_ISO_TEST_URL:-http://apt.strawwu.org.wastebase.xyz/iso/StrawWU-latest-amd64.iso}"

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

# Local static preview of docs/
if ! curl -fsS "$BASE/releases.json" >/dev/null 2>&1; then
  (cd "$(dirname "$0")/../docs" && python3 -m http.server 9106 >/tmp/strawwu-public-preview.log 2>&1 &)
  sleep 1
fi

check "local index.html" "curl -fsS '$BASE/index.html' | grep -q 'StrawWU'"
check "local releases.json" "curl -fsS '$BASE/releases.json' | grep -q '0.6.2.5'"
check "local branding webp" "curl -fsSI '$BASE/assets/branding/strawwu-icon.webp' | grep -q '200'"
check "iso mirror head" "curl -fsSI '$ISO_URL' | grep -q '200'"
check "iso mirror size" "curl -fsSI '$ISO_URL' | grep -qi 'content-length: 5096343552'"

echo "---"
echo "PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]]
