#!/usr/bin/env bash
# Smoke test strawwu-public manifest (repo direct ISO or CDN).
set -euo pipefail

BASE="${STRAWWU_PUBLIC_BASE:-http://127.0.0.1:9106}"
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
check "manifest schema v7" "curl -fsS '$BASE/releases.json' | grep -q 'strawwu-public-releases/v7'"
check "manifest no split parts" "! curl -fsS '$BASE/releases.json' | grep -q '\\.part'"

latest_json="$(curl -fsS "$BASE/releases.json")"
if python3 -c "import json,sys; d=json.loads(sys.argv[1]); r=next(x for x in d['releases'] if x['version']==sys.argv[2]); sys.exit(0 if r.get('join_mode')=='direct' and r.get('iso_url') else 1)" "$latest_json" "$LATEST_VER" 2>/dev/null; then
  check "manifest latest direct iso" "true"
  iso_url="$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); r=next(x for x in d['releases'] if x['version']==sys.argv[2]); print(r['iso_url'])" "$latest_json" "$LATEST_VER")"
  if curl -fsSI "$iso_url" | grep -qi '200\|302'; then
    check "latest iso url reachable" "true"
  else
    skip_check "latest iso url reachable ($iso_url)"
  fi
else
  skip_check "manifest latest direct iso (v${LATEST_VER} not published yet)"
fi

if curl -fsS "$PAGES_URL/releases.json" >/dev/null 2>&1; then
  check "pages releases.json" "curl -fsS '$PAGES_URL/releases.json' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get(\"schema\",\"\").startswith(\"strawwu-public-releases/v\")'"
else
  skip_check "live $PAGES_URL (push main to trigger Pages)"
fi

echo "---"
echo "PASS=$pass FAIL=$fail SKIP=$skip"
[[ "$fail" -eq 0 ]]
