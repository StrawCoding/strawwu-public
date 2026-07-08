#!/usr/bin/env bash
# DEPRECATED: local CDN mirror on Hermes build machine is disabled.
set -euo pipefail

echo "ERROR: sync-release-assets.sh is disabled." >&2
echo "Use: ./scripts/publish-github-release.sh <version>" >&2
exit 1
