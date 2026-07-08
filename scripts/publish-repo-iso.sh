#!/usr/bin/env bash
# DEPRECATED: ISO assets are published via GitHub Releases (scripts/publish-github-release.sh).
set -euo pipefail

echo "ERROR: publish-repo-iso.sh is disabled." >&2
echo "Use GitHub Releases instead: ./scripts/publish-github-release.sh <version>" >&2
exit 1
