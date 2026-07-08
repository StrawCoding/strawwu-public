#!/usr/bin/env bash
# Smoke test strawwu-public manifest and GitHub Release metadata.
set -euo pipefail

BASE="${STRAWWU_PUBLIC_BASE:-http://127.0.0.1:9106}"
PAGES_URL="${STRAWWU_PAGES_URL:-https://strawcoding.github.io/strawwu-public}"
REPO="${STRAWWU_PUBLIC_REPO:-StrawCoding/strawwu-public}"

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
check "manifest schema v8" "curl -fsS '$BASE/releases.json' | grep -q 'strawwu-public-releases/v8'"
check "manifest release-chunked policy" "curl -fsS '$BASE/releases.json' | grep -q 'release-chunked'"
check "manifest has github_repo field" "curl -fsS '$BASE/releases.json' | grep -q '\"github_repo\"'"
check "local download-iso.js has local merge" "grep -q 'mergeLocalParts' docs/assets/download-iso.js"
check "local download-iso.js has cors proxy fetch" "grep -q 'partFetchUrl' docs/assets/download-iso.js"
check "manifest has cors_proxy_base" "curl -fsS '$BASE/releases.json' | grep -q 'cors_proxy_base'"
check "index mentions browser join" "grep -q '下載並合併 ISO' docs/index.html"

latest_json="$(curl -fsS "$BASE/releases.json")"
LATEST_VER="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['latest'])" "$latest_json")"
DOWNLOAD_VER="$(python3 -c "
import json,sys
d=json.loads(sys.argv[1])
lp=d.get('latest_published')
print(lp if lp else d['latest'])
" "$latest_json")"

check "manifest latest is highest build" "python3 -c \"
import json,sys
d=json.loads(sys.argv[1])
vers=[r['version'] for r in d['releases'] if r.get('status')!='withdrawn']
def vk(v): return tuple(int(x) for x in v.split('.'))
assert d['latest']==max(vers, key=vk)
\" '$latest_json'"

if python3 -c "import json,sys; d=json.loads(sys.argv[1]); r=next(x for x in d['releases'] if x['version']==sys.argv[2]); sys.exit(0 if r.get('iso_published') or r.get('has_full_iso') else 1)" "$latest_json" "$DOWNLOAD_VER" 2>/dev/null; then
  check "manifest latest published" "true"
  part_url="$(python3 -c "
import json,sys
d=json.loads(sys.argv[1])
r=next(x for x in d['releases'] if x['version']==sys.argv[2])
parts=r.get('parts') or []
iso=r.get('iso_url')
if parts:
    print(next(p['url'] for p in parts if p['name'].endswith('.part')))
elif iso:
    print(iso)
" "$latest_json" "$DOWNLOAD_VER" 2>/dev/null || true)"
  if [[ -n "$part_url" ]] && curl -fsSI "$part_url" | grep -qi '200\|302'; then
    check "latest iso asset reachable" "true"
  else
    skip_check "latest iso asset reachable (publish release first: $part_url)"
  fi
else
  skip_check "manifest latest published (v${DOWNLOAD_VER})"
fi

if python3 -c "import json,sys; d=json.loads(sys.argv[1]); r=next(x for x in d['releases'] if x['version']==sys.argv[2]); sys.exit(0 if r.get('storage')=='release' else 1)" "$latest_json" "$DOWNLOAD_VER" 2>/dev/null; then
  check "latest uses github release storage" "true"
fi

if curl -fsS "$PAGES_URL/releases.json" >/dev/null 2>&1; then
  check "pages releases.json" "curl -fsS '$PAGES_URL/releases.json' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get(\"schema\",\"\").startswith(\"strawwu-public-releases/v\")'"
else
  skip_check "live $PAGES_URL (push main to trigger Pages)"
fi

echo "---"
echo "PASS=$pass FAIL=$fail SKIP=$skip"
[[ "$fail" -eq 0 ]]
