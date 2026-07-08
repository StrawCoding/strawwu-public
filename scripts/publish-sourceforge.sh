#!/usr/bin/env bash
# Publish StrawWU ISO as a single whole file to SourceForge FRS (rsync over SSH).
# No split parts. GitHub only keeps SHA256SUMS + download notes.
set -euo pipefail

REPO="${STRAWWU_PUBLIC_REPO:-StrawCoding/strawwu-public}"
ISO_DIR="${STRAWWU_ISO_DIR:-/mnt/data/code/project/StrawCoding/StrawWU/os-image/output}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-}"
SKIP_UPLOAD="${STRAWWU_SKIP_SF_UPLOAD:-0}"
SKIP_MANIFEST="${STRAWWU_SKIP_SF_MANIFEST:-0}"
SKIP_GH="${STRAWWU_SKIP_SF_GITHUB:-0}"

SF_USER="${STRAWWU_SF_USER:-}"
SF_PROJECT="${STRAWWU_SF_PROJECT:-}"
SF_HOST="${STRAWWU_SF_HOST:-frs.sourceforge.net}"
SF_REMOTE_ROOT="${STRAWWU_SF_REMOTE_ROOT:-/home/frs/project}"
SF_PREFIX="${STRAWWU_SF_PREFIX:-releases}"
SF_PASS="${STRAWWU_SF_PASS:-}"
SF_API_KEY="${STRAWWU_SF_API_KEY:-}"
SF_CDN_BASE="${STRAWWU_SF_CDN_BASE:-https://sourceforge.net/projects}"

ENV_FILE="$ROOT/scripts/iso-sourceforge.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  SF_USER="${STRAWWU_SF_USER:-$SF_USER}"
  SF_PROJECT="${STRAWWU_SF_PROJECT:-$SF_PROJECT}"
  SF_HOST="${STRAWWU_SF_HOST:-$SF_HOST}"
  SF_REMOTE_ROOT="${STRAWWU_SF_REMOTE_ROOT:-$SF_REMOTE_ROOT}"
  SF_PREFIX="${STRAWWU_SF_PREFIX:-$SF_PREFIX}"
  SF_PASS="${STRAWWU_SF_PASS:-$SF_PASS}"
  SF_API_KEY="${STRAWWU_SF_API_KEY:-$SF_API_KEY}"
  SF_CDN_BASE="${STRAWWU_SF_CDN_BASE:-$SF_CDN_BASE}"
fi

if [[ -z "$VERSION" ]]; then
  VERSION="$(ls -1 "$ISO_DIR"/StrawWU-*.iso 2>/dev/null \
    | sed -n 's|.*/StrawWU-\(.*\)-amd64\.iso|\1|p' \
    | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n \
    | tail -1)"
fi

[[ -n "$VERSION" ]] || { echo "Usage: $0 [version]" >&2; exit 1; }

iso="$ISO_DIR/StrawWU-${VERSION}-amd64.iso"
[[ -f "$iso" ]] || { echo "ISO not found: $iso" >&2; exit 1; }

if [[ -z "$SF_USER" || -z "$SF_PROJECT" ]]; then
  cat >&2 <<EOF
ERROR: SourceForge credentials not configured.

Copy scripts/iso-sourceforge.env.example → scripts/iso-sourceforge.env and set:
  STRAWWU_SF_USER
  STRAWWU_SF_PROJECT

Then either:
  - add this machine's SSH public key to your SourceForge account, or
  - set STRAWWU_SF_PASS (uses sshpass)

Create the SF project first if it does not exist:
  https://sourceforge.net/create/
EOF
  exit 1
fi

base="$(basename "$iso")"
tag="v${VERSION}"
remote_dir="${SF_REMOTE_ROOT}/${SF_PROJECT}/${SF_PREFIX}/${tag}"
iso_page="${SF_CDN_BASE%/}/${SF_PROJECT}/files/${SF_PREFIX}/${tag}/${base}"
iso_url="${iso_page}/download"
checksum_url="${SF_CDN_BASE%/}/${SF_PROJECT}/files/${SF_PREFIX}/${tag}/SHA256SUMS/download"
files_url="${SF_CDN_BASE%/}/${SF_PROJECT}/files/${SF_PREFIX}/${tag}/"
sha256="$(sha256sum "$iso" | awk '{print $1}')"
size="$(stat -c%s "$iso")"
size_human="$(numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "${size} bytes")"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
echo "${sha256}  ${base}" > "$tmpdir/SHA256SUMS"

marker_dir="$ROOT/docs/sf-releases"
mkdir -p "$marker_dir"
marker="$marker_dir/v${VERSION}.json"

cat > "$tmpdir/release-notes.md" <<EOF
# StrawWU v${VERSION}

| Field | Value |
|-------|-------|
| Version | ${VERSION} |
| File | ${base} |
| Size | ${size_human} |
| SHA256 | \`${sha256}\` |

## Download

Whole ISO on SourceForge (single file, **no split parts**):

\`\`\`
${iso_url}
\`\`\`

Files folder: ${files_url}

Verify after download:

\`\`\`bash
curl -fsSLO ${checksum_url}
sha256sum -c SHA256SUMS
\`\`\`

Web: https://strawcoding.github.io/strawwu-public/
EOF

cat > "$marker" <<EOF
{
  "version": "${VERSION}",
  "filename": "${base}",
  "size": ${size},
  "size_human": "${size_human}",
  "sha256": "${sha256}",
  "storage": "sourceforge",
  "project": "${SF_PROJECT}",
  "prefix": "${SF_PREFIX}",
  "iso_url": "${iso_url}",
  "checksum_url": "${checksum_url}",
  "release_url": "${files_url}",
  "published_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

if [[ "$SKIP_UPLOAD" == "1" ]]; then
  echo "SKIP_UPLOAD=1 — wrote marker $marker"
  echo "ISO URL: $iso_url"
  trap - EXIT
  exit 0
fi

rsync_ssh=(ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes)
rsync_rsh="ssh -o StrictHostKeyChecking=accept-new"
if [[ -n "$SF_PASS" ]]; then
  if ! command -v sshpass >/dev/null 2>&1; then
    echo "Installing sshpass for password auth..."
    apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sshpass >/dev/null
  fi
  export SSHPASS="$SF_PASS"
  rsync_rsh="sshpass -e ssh -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password -o PubkeyAuthentication=no"
  rsync_ssh=(sshpass -e ssh -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password -o PubkeyAuthentication=no)
fi

echo "Ensuring remote directory ${remote_dir}/ ..."
# FRS: create path via sftp batch (shell/mkdir often unavailable on frs).
sftp_batch="$tmpdir/sftp-mkdir.batch"
{
  echo "-mkdir ${SF_REMOTE_ROOT}/${SF_PROJECT}"
  echo "-mkdir ${SF_REMOTE_ROOT}/${SF_PROJECT}/${SF_PREFIX}"
  echo "-mkdir ${remote_dir}"
} > "$sftp_batch"
if [[ -n "$SF_PASS" ]]; then
  sshpass -e sftp -o StrictHostKeyChecking=accept-new \
    -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    -b "$sftp_batch" "${SF_USER}@${SF_HOST}" >/dev/null 2>&1 || true
else
  sftp -o StrictHostKeyChecking=accept-new -o BatchMode=yes \
    -b "$sftp_batch" "${SF_USER}@${SF_HOST}" >/dev/null 2>&1 || true
fi

echo "Uploading ${base} (${size_human}) → ${SF_USER}@${SF_HOST}:${remote_dir}/"
rsync -avP --partial \
  -e "$rsync_rsh" \
  "$iso" "$tmpdir/SHA256SUMS" \
  "${SF_USER}@${SF_HOST}:${remote_dir}/"

if [[ -n "$SF_API_KEY" ]]; then
  echo "Setting SourceForge default download (linux)..."
  api_url="${iso_page}"
  resp="$(curl -fsS -H "Accept: application/json" -X PUT \
    -d "default=linux&default=bsd&default=solaris&default=others" \
    -d "api_key=${SF_API_KEY}" \
    "$api_url" || true)"
  if echo "$resp" | grep -q '"error"'; then
    echo "WARN: Release API: $resp" >&2
  else
    echo "Default download set for linux/others"
  fi
fi

if [[ "$SKIP_GH" != "1" ]]; then
  release_page="https://github.com/${REPO}/releases/tag/${tag}"
  if gh release view "$tag" --repo "$REPO" >/dev/null 2>&1; then
    echo "Updating GitHub Release $tag (checksums + SF notes)"
    gh release upload "$tag" "$tmpdir/SHA256SUMS" --repo "$REPO" --clobber
    gh release edit "$tag" --repo "$REPO" --notes-file "$tmpdir/release-notes.md"
  else
    gh release create "$tag" \
      --repo "$REPO" \
      --title "StrawWU ${VERSION}" \
      --notes-file "$tmpdir/release-notes.md" \
      "$tmpdir/SHA256SUMS"
  fi
  echo "GitHub metadata: $release_page"
fi

if [[ "$SKIP_MANIFEST" != "1" ]]; then
  "$ROOT/scripts/generate-manifest.sh"
fi

echo "Published StrawWU v${VERSION} to SourceForge"
echo "  ISO:      $iso_url"
echo "  Checksum: $checksum_url"
echo "  Marker:   $marker"
