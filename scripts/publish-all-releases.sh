#!/usr/bin/env bash
# Publish every local StrawWU ISO to CDN (direct .iso) + GitHub Release metadata.
set -euo pipefail

ISO_DIR="${STRAWWU_ISO_DIR:-/mnt/data/code/project/StrawCoding/StrawWU/os-image/output}"
SCRIPT="$(dirname "$0")/publish-github-release.sh"

mapfile -t versions < <(
  ls -1 "$ISO_DIR"/StrawWU-*.iso 2>/dev/null \
    | sed -n 's|.*/StrawWU-\(.*\)-amd64\.iso|\1|p' \
    | sort -Vr
)

[[ ${#versions[@]} -gt 0 ]] || { echo "No ISO files in $ISO_DIR" >&2; exit 1; }

for version in "${versions[@]}"; do
  echo "=== Publishing v${version} ==="
  "$SCRIPT" "$version"
done

"$(dirname "$0")/generate-manifest.sh"
echo "All releases published."
