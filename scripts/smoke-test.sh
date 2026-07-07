#!/usr/bin/env bash
# Smoke test download.strawwu.org (GitHub Pages) + GitHub Releases assets.
set -euo pipefail

BASE="${STRAWWU_PUBLIC_BASE:-http://127.0.0.1:9106}"
DOWNLOAD_SITE="${STRAWWU_DOWNLOAD_BASE:-https://download.strawwu.org}"
REPO="${STRAWWU_PUBLIC_REPO:-StrawCoding/strawwu-public}"
LATEST_TAG="${STRAWWU_LATEST_TAG:-v0.6.2.5}"
RELEASES_BASE="https://github.com/${REPO}/releases/download"

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
check "local CNAME" "grep -qx 'download.strawwu.org' '$(dirname "$0")/../docs/CNAME'"
check "local branding icon svg" "curl -fsSI '$BASE/assets/branding/strawwu-icon.svg' | grep -q '200'"
check "local branding lockup svg" "curl -fsSI '$BASE/assets/branding/strawwu-lockup.svg' | grep -q '200'"
check "manifest no wastebase mirror" "! curl -fsS '$BASE/releases.json' | grep -q 'wastebase.xyz'"
check "manifest download site base" "curl -fsS '$BASE/releases.json' | grep -q 'download.strawwu.org'"
check "manifest github releases base" "curl -fsS '$BASE/releases.json' | grep -q 'github.com/${REPO}/releases/download'"
check "manifest part urls use github" "curl -fsS '$BASE/releases.json' | grep -q 'github.com/${REPO}/releases/download/${LATEST_TAG}/'"
check "manifest no cdn part paths" "! curl -fsS '$BASE/releases.json' | grep -q '${DOWNLOAD_SITE}/${LATEST_TAG}/'"
check "github release exists" "gh release view '$LATEST_TAG' --repo '$REPO' >/dev/null"
check "github iso part" "curl -fsSI '${RELEASES_BASE}/${LATEST_TAG}/StrawWU-${LATEST_TAG#v}-amd64.iso.01.part' | grep -qi '200\\|302'"
check "github SHA256SUMS" "curl -fsSL '${RELEASES_BASE}/${LATEST_TAG}/SHA256SUMS' | grep -q 'StrawWU-'"

if curl -fsS "$DOWNLOAD_SITE/releases.json" >/dev/null 2>&1; then
  check "live download.strawwu.org" "curl -fsSL '$DOWNLOAD_SITE/' | grep -q 'StrawWU'"
  check "live releases.json" "curl -fsS '$DOWNLOAD_SITE/releases.json' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert \"github.com\" in d.get(\"releases_download_base\",\"\")'"
else
  echo "SKIP: live $DOWNLOAD_SITE (DNS/Pages not ready yet)"
fi

echo "---"
echo "PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]]
