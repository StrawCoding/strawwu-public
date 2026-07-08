#!/usr/bin/env bash
# Publish StrawWU ISO: whole .iso to Cloudflare R2 CDN, metadata/SHA256 to GitHub Release.
# GitHub Release/LFS caps ~2 GiB — ISOs (~5 GiB) must NOT be split.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
[[ -f "$SCRIPT_DIR/iso-cdn.env" ]] && source "$SCRIPT_DIR/iso-cdn.env"

REPO="${STRAWWU_PUBLIC_REPO:-StrawCoding/strawwu-public}"
ISO_DIR="${STRAWWU_ISO_DIR:-/mnt/data/code/project/StrawCoding/StrawWU/os-image/output}"
VERSION="${1:-}"
SKIP_UPLOAD="${STRAWWU_SKIP_RELEASE_UPLOAD:-0}"
DELETE_PART_ASSETS="${STRAWWU_DELETE_PART_ASSETS:-1}"

# Public CDN base for direct ISO URLs (NOT the Hermes build machine).
CDN_BASE="${STRAWWU_ISO_CDN_BASE:-https://pub-5f85d511d7344db2be8308026a082b13.r2.dev}"
S3_ENDPOINT="${STRAWWU_ISO_S3_ENDPOINT:-}"
S3_BUCKET="${STRAWWU_ISO_S3_BUCKET:-strawwu-releases}"
S3_PREFIX="${STRAWWU_ISO_S3_PREFIX:-releases}"
S3_ACCESS_KEY="${STRAWWU_ISO_S3_ACCESS_KEY:-${AWS_ACCESS_KEY_ID:-}}"
S3_SECRET_KEY="${STRAWWU_ISO_S3_SECRET_KEY:-${AWS_SECRET_ACCESS_KEY:-}}"
S3_REGION="${STRAWWU_ISO_S3_REGION:-auto}"

if [[ -z "$VERSION" ]]; then
  VERSION="$(ls -1 "$ISO_DIR"/StrawWU-*.iso 2>/dev/null \
    | sed -n 's|.*/StrawWU-\(.*\)-amd64\.iso|\1|p' \
    | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n \
    | tail -1)"
fi

[[ -n "$VERSION" ]] || { echo "Usage: $0 [version]" >&2; exit 1; }

iso="$ISO_DIR/StrawWU-${VERSION}-amd64.iso"
[[ -f "$iso" ]] || { echo "ISO not found: $iso" >&2; exit 1; }

root="$(cd "$SCRIPT_DIR/.." && pwd)"
base="$(basename "$iso")"
tag="v${VERSION}"
object_key="${S3_PREFIX}/${tag}/${base}"
iso_url="${CDN_BASE%/}/${object_key}"
checksum_url="${CDN_BASE%/}/${S3_PREFIX}/${tag}/SHA256SUMS"
release_page="https://github.com/${REPO}/releases/tag/${tag}"
sha256="$(sha256sum "$iso" | awk '{print $1}')"
size="$(stat -c%s "$iso")"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "${sha256}  ${base}" > "$tmpdir/SHA256SUMS"

cat > "$tmpdir/release-notes.md" <<EOF
# StrawWU v${VERSION}

| Field | Value |
|-------|-------|
| Version | ${VERSION} |
| File | ${base} |
| Size | $(numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "${size} bytes") |
| SHA256 | \`${sha256}\` |

## Download

Direct ISO (single file, no split parts):

\`\`\`
${iso_url}
\`\`\`

Verify after download:

\`\`\`bash
sha256sum -c SHA256SUMS
\`\`\`

Web: https://strawcoding.github.io/strawwu-public/
GitHub: ${release_page}
EOF

if [[ "$SKIP_UPLOAD" == "1" ]]; then
  echo "SKIP_UPLOAD=1 — prepared metadata in $tmpdir"
  echo "ISO URL: $iso_url"
  ls -lh "$tmpdir"
  trap - EXIT
  exit 0
fi

if [[ -z "$S3_ENDPOINT" || -z "$S3_ACCESS_KEY" || -z "$S3_SECRET_KEY" ]]; then
  cat >&2 <<EOF
ERROR: STRAWWU ISO CDN credentials are not configured.

GitHub Release assets and Git LFS are limited to 2 GiB per file on Free/Pro plans.
StrawWU ISO (~5 GiB) must be uploaded to external object storage (e.g. Cloudflare R2).

Set before running:
  STRAWWU_ISO_S3_ENDPOINT   # e.g. https://<account>.r2.cloudflarestorage.com
  STRAWWU_ISO_S3_BUCKET     # e.g. strawwu-releases
  STRAWWU_ISO_S3_ACCESS_KEY
  STRAWWU_ISO_S3_SECRET_KEY
  STRAWWU_ISO_CDN_BASE      # e.g. https://download.strawwu.org

See scripts/setup-iso-cdn-r2.sh for R2 provisioning steps.
EOF
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "Installing awscli for S3-compatible upload..."
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq awscli >/dev/null
fi

echo "Uploading ${base} ($(numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "${size} B")) to s3://${S3_BUCKET}/${object_key}"
AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY" AWS_DEFAULT_REGION="$S3_REGION" \
  aws s3 cp "$iso" "s3://${S3_BUCKET}/${object_key}" \
    --endpoint-url "$S3_ENDPOINT" \
    --only-show-errors

AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY" AWS_DEFAULT_REGION="$S3_REGION" \
  aws s3 cp "$tmpdir/SHA256SUMS" "s3://${S3_BUCKET}/${S3_PREFIX}/${tag}/SHA256SUMS" \
    --endpoint-url "$S3_ENDPOINT" \
    --content-type 'text/plain' \
    --only-show-errors

if gh release view "$tag" --repo "$REPO" >/dev/null 2>&1; then
  echo "Updating GitHub Release $tag (checksums only)"
  gh release upload "$tag" "$tmpdir/SHA256SUMS" --repo "$REPO" --clobber
  gh release edit "$tag" --repo "$REPO" --notes-file "$tmpdir/release-notes.md"
else
  gh release create "$tag" \
    --repo "$REPO" \
    --title "StrawWU ${VERSION}" \
    --notes-file "$tmpdir/release-notes.md" \
    "$tmpdir/SHA256SUMS"
fi

if [[ "$DELETE_PART_ASSETS" == "1" ]]; then
  release_id="$(gh api "repos/${REPO}/releases/tags/${tag}" --jq .id)"
  mapfile -t stale < <(gh api "repos/${REPO}/releases/${release_id}/assets" --jq '.[].name' \
    | grep -E '\.part$|^join-iso\.sh$' || true)
  for name in "${stale[@]}"; do
    asset_id="$(gh api "repos/${REPO}/releases/${release_id}/assets" --jq ".[] | select(.name==\"${name}\") | .id")"
    if [[ -n "$asset_id" ]]; then
      echo "Removing stale split asset: $name"
      gh api -X DELETE "repos/${REPO}/releases/assets/${asset_id}" >/dev/null
    fi
  done
fi

marker_dir="$root/docs/r2-releases"
mkdir -p "$marker_dir"
python3 - "$marker_dir/v${VERSION}.json" "$VERSION" "$base" "$size" "$sha256" "$iso_url" "$checksum_url" "$release_page" "$S3_PREFIX" <<'PY'
import json, sys
from datetime import datetime, timezone
out, version, filename, size, sha256, iso_url, checksum_url, release_url, prefix = sys.argv[1:]
payload = {
    "version": version,
    "filename": filename,
    "size": int(size),
    "sha256": sha256,
    "iso_url": iso_url,
    "checksum_url": checksum_url,
    "release_url": release_url,
    "prefix": prefix,
    "storage": "r2",
    "published_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
open(out, "w").write(json.dumps(payload, indent=2) + "\n")
print(f"Wrote {out}")
PY

echo "Published ${tag}"
echo "  ISO: ${iso_url}"
echo "  Release: ${release_page}"
echo "Next: ./scripts/generate-manifest.sh && git add docs/r2-releases docs/releases.json && git commit && git push"
