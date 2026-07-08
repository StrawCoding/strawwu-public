#!/usr/bin/env bash
# Publish StrawWU ISO to GitHub Releases (split into <2 GiB parts).
set -euo pipefail

REPO="${STRAWWU_PUBLIC_REPO:-StrawCoding/strawwu-public}"
ISO_DIR="${STRAWWU_ISO_DIR:-/mnt/data/code/project/StrawCoding/StrawWU/os-image/output}"
CHUNK_BYTES="${STRAWWU_RELEASE_CHUNK_BYTES:-$((1800 * 1024 * 1024))}"
VERSION="${1:-}"
SKIP_UPLOAD="${STRAWWU_SKIP_RELEASE_UPLOAD:-0}"

if [[ -z "$VERSION" ]]; then
  latest="$(ls -1t "$ISO_DIR"/StrawWU-*.iso 2>/dev/null | head -1)"
  VERSION="$(basename "$latest" | sed -n 's/StrawWU-\(.*\)-amd64\.iso/\1/p')"
fi

[[ -n "$VERSION" ]] || { echo "Usage: $0 [version]" >&2; exit 1; }

iso="$ISO_DIR/StrawWU-${VERSION}-amd64.iso"
[[ -f "$iso" ]] || { echo "ISO not found: $iso" >&2; exit 1; }

root="$(cd "$(dirname "$0")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

base="$(basename "$iso")"
sha256="$(sha256sum "$iso" | awk '{print $1}')"
size="$(stat -c%s "$iso")"
tag="v${VERSION}"
release_page="https://github.com/${REPO}/releases/tag/${tag}"
join_script="$root/scripts/join-iso.sh"

echo "Splitting $iso into ${CHUNK_BYTES}-byte parts..."
split -b "$CHUNK_BYTES" --numeric-suffixes=1 --additional-suffix=.part "$iso" "$tmpdir/${base}."
mapfile -t parts < <(find "$tmpdir" -maxdepth 1 -name "${base}.*.part" -type f | sort -V)
[[ ${#parts[@]} -gt 0 ]] || { echo "split produced no parts" >&2; exit 1; }

echo "${sha256}  ${base}" > "$tmpdir/SHA256SUMS"
cp "$join_script" "$tmpdir/join-iso.sh"
chmod +x "$tmpdir/join-iso.sh"

parts_md=""
for part in "${parts[@]}"; do
  pname="$(basename "$part")"
  psize="$(stat -c%s "$part")"
  parts_md+="- \`${pname}\` ($(numfmt --to=iec-i --suffix=B "$psize" 2>/dev/null || echo "${psize} B"))"$'\n'
done

cat > "$tmpdir/release-notes.md" <<EOF
# StrawWU v${VERSION}

| Field | Value |
|-------|-------|
| Version | ${VERSION} |
| File | ${base} |
| Size | $(numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "${size} bytes") |
| SHA256 | \`${sha256}\` |
| Parts | ${#parts[@]} |

## Download

GitHub Release assets are limited to 2 GiB per file. Download **all** parts below, then reassemble:

\`\`\`bash
chmod +x join-iso.sh
./join-iso.sh ${base} ${base}.*.part
sha256sum -c SHA256SUMS
\`\`\`

### Parts

${parts_md}

Web: https://strawcoding.github.io/strawwu-public/
GitHub: https://github.com/${REPO}/releases/tag/${tag}
EOF

if [[ "$SKIP_UPLOAD" == "1" ]]; then
  echo "SKIP_UPLOAD=1 — prepared assets in $tmpdir"
  ls -lh "$tmpdir"
  trap - EXIT
  exit 0
fi

upload_args=()
for part in "${parts[@]}"; do
  upload_args+=("$part")
done
upload_args+=("$tmpdir/SHA256SUMS" "$tmpdir/join-iso.sh")

if gh release view "$tag" --repo "$REPO" >/dev/null 2>&1; then
  echo "Release $tag exists — uploading ISO parts + checksums"
  gh release upload "$tag" "${upload_args[@]}" --repo "$REPO" --clobber
  gh release edit "$tag" --repo "$REPO" --notes-file "$tmpdir/release-notes.md"
else
  gh release create "$tag" \
    --repo "$REPO" \
    --title "StrawWU ${VERSION}" \
    --notes-file "$tmpdir/release-notes.md" \
    "${upload_args[@]}"
fi

echo "Published $tag (${#parts[@]} parts) → $release_page"
