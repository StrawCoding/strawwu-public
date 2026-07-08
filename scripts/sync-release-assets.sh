#!/usr/bin/env bash
# DEPRECATED: local CDN mirror on Hermes build machine is disabled.
# ISO assets are published only via external CDN (R2) + GitHub Release metadata.
set -euo pipefail

echo "ERROR: sync-release-assets.sh is disabled." >&2
echo "StrawWU ISO downloads must use Cloudflare R2 CDN — not this build machine." >&2
echo "Use: ./scripts/publish-github-release.sh <version>" >&2
exit 1
