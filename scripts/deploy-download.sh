#!/usr/bin/env bash
# Regenerate manifest and remind to push — local CDN deploy is disabled.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT"
echo "==> sync branding"
bash scripts/sync-branding.sh

echo "==> generate manifest (GitHub URLs only)"
bash scripts/generate-manifest.sh

echo ""
echo "Local CDN mirror deploy is DISABLED (Hermes build machine is not a download node)."
echo "Push docs/ to main — GitHub Pages workflow deploys the download page."
echo ""
echo "  git add docs/releases.json docs/index.html docs/assets"
echo "  git commit -m 'chore: update releases manifest (GitHub-only)'"
echo "  git push"
echo ""
echo "DONE: manifest refreshed at docs/releases.json"
