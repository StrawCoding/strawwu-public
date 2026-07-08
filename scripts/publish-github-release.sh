#!/usr/bin/env bash
# Publish StrawWU ISO to GitHub Releases (split into <2 GiB parts for browser join).
set -euo pipefail

REPO="${STRAWWU_PUBLIC_REPO:-StrawCoding/strawwu-public}"
ISO_DIR="${STRAWWU_ISO_DIR:-/mnt/data/code/project/StrawCoding/StrawWU/os-image/output}"
PARTS_CACHE_DIR="${STRAWWU_PARTS_CACHE_DIR:-$(dirname "$0")/../.parts-cache}"
CHUNK_BYTES="${STRAWWU_RELEASE_CHUNK_BYTES:-$((1800 * 1024 * 1024))}"
VERSION="${1:-}"
SKIP_UPLOAD="${STRAWWU_SKIP_RELEASE_UPLOAD:-0}"

if [[ -z "$VERSION" ]]; then
  VERSION="$(ls -1 "$ISO_DIR"/StrawWU-*.iso 2>/dev/null \
    | sed -n 's|.*/StrawWU-\(.*\)-amd64\.iso|\1|p' \
    | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n \
    | tail -1)"
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
repo_parts_dir="$PARTS_CACHE_DIR/v${VERSION}"

reuse_parts=0
if [[ -d "$repo_parts_dir" ]] && [[ -f "$repo_parts_dir/SHA256SUMS" ]]; then
  if grep -qF "$sha256  $base" "$repo_parts_dir/SHA256SUMS"; then
    mapfile -t existing < <(find "$repo_parts_dir" -maxdepth 1 -name "${base}.*.part" -type f | sort -V)
    if [[ ${#existing[@]} -gt 0 ]]; then
      echo "Reusing ${#existing[@]} part(s) from .parts-cache/v${VERSION}/"
      for part in "${existing[@]}"; do
        cp "$part" "$tmpdir/"
      done
      reuse_parts=1
    fi
  fi
fi

if [[ "$reuse_parts" -eq 0 ]]; then
  echo "Splitting $iso into ${CHUNK_BYTES}-byte parts..."
  split -b "$CHUNK_BYTES" --numeric-suffixes=1 --additional-suffix=.part "$iso" "$tmpdir/${base}."
fi

mapfile -t parts < <(find "$tmpdir" -maxdepth 1 -name "${base}.*.part" -type f | sort -V)
[[ ${#parts[@]} -gt 0 ]] || { echo "No ISO parts prepared" >&2; exit 1; }

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

GitHub Release assets are limited to 2 GiB per file. The download page fetches all parts and merges them into one \`.iso\` in your browser.

CLI reassembly:

\`\`\`bash
chmod +x join-iso.sh
./join-iso.sh ${base} ${base}.*.part
sha256sum -c SHA256SUMS
\`\`\`

### Parts

${parts_md}

Web: https://strawcoding.github.io/strawwu-public/
GitHub: ${release_page}
EOF

if [[ "$SKIP_UPLOAD" == "1" ]]; then
  echo "SKIP_UPLOAD=1 — prepared assets in $tmpdir"
  ls -lh "$tmpdir"
  trap - EXIT
  exit 0
fi

upload_args=("${parts[@]}" "$tmpdir/SHA256SUMS" "$tmpdir/join-iso.sh")

if gh release view "$tag" --repo "$REPO" >/dev/null 2>&1; then
  echo "Release $tag exists — uploading ISO parts + checksums"
  for asset in "${upload_args[@]}"; do
    echo "  → $(basename "$asset") ($(numfmt --to=iec-i --suffix=B "$(stat -c%s "$asset")" 2>/dev/null || stat -c%s "$asset"))"
    gh release upload "$tag" "$asset" --repo "$REPO" --clobber
  done
  gh release edit "$tag" --repo "$REPO" --notes-file "$tmpdir/release-notes.md" --draft=false
else
  gh release create "$tag" \
    --repo "$REPO" \
    --title "StrawWU ${VERSION}" \
    --notes-file "$tmpdir/release-notes.md" \
    "${upload_args[@]}"
  gh release edit "$tag" --repo "$REPO" --draft=false
fi

echo "Published $tag (${#parts[@]} parts) → $release_page"
echo "Next: ./scripts/generate-manifest.sh && git add docs/releases.json && git commit && git push"
