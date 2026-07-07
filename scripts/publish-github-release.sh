#!/usr/bin/env bash
# Create GitHub release tag + checksum assets (ISO hosted on mirror; >2 GiB cannot use GH assets).
set -euo pipefail

REPO="${STRAWWU_PUBLIC_REPO:-StrawCoding/strawwu-public}"
ISO_DIR="${STRAWWU_ISO_DIR:-/mnt/data/code/project/StrawCoding/StrawWU/os-image/output}"
VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  latest="$(ls -1t "$ISO_DIR"/StrawWU-*.iso 2>/dev/null | head -1)"
  VERSION="$(basename "$latest" | sed -n 's/StrawWU-\(.*\)-amd64\.iso/\1/p')"
fi

[[ -n "$VERSION" ]] || { echo "Usage: $0 [version]" >&2; exit 1; }

iso="$ISO_DIR/StrawWU-${VERSION}-amd64.iso"
[[ -f "$iso" ]] || { echo "ISO not found: $iso" >&2; exit 1; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

sha256="$(sha256sum "$iso" | awk '{print $1}')"
size="$(stat -c%s "$iso")"
mirror_url="https://apt.strawwu.org/iso/$(basename "$iso")"

cat > "$tmpdir/release-notes.md" <<EOF
# StrawWU v${VERSION}

| Field | Value |
|-------|-------|
| Version | ${VERSION} |
| File | $(basename "$iso") |
| Size | $(numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "${size} bytes") |
| SHA256 | \`${sha256}\` |

## Download

ISO files exceed GitHub's 2 GiB release asset limit. Download from the official mirror:

**[Download $(basename "$iso")](${mirror_url})**

Verify:

\`\`\`bash
sha256sum -c SHA256SUMS
\`\`\`

Web: https://strawcoding.github.io/strawwu-public/
EOF

echo "${sha256}  $(basename "$iso")" > "$tmpdir/SHA256SUMS"

if gh release view "v${VERSION}" --repo "$REPO" >/dev/null 2>&1; then
  echo "Release v${VERSION} exists — uploading checksum assets"
  gh release upload "v${VERSION}" "$tmpdir/SHA256SUMS" --repo "$REPO" --clobber
else
  gh release create "v${VERSION}" \
    --repo "$REPO" \
    --title "StrawWU ${VERSION}" \
    --notes-file "$tmpdir/release-notes.md" \
    "$tmpdir/SHA256SUMS"
fi

echo "Published v${VERSION} metadata to GitHub; ISO at $mirror_url"
