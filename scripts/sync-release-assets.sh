#!/usr/bin/env bash
# Mirror release assets (ISO parts, SHA256SUMS, join-iso.sh) to download.strawwu.org CDN.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${STRAWWU_PUBLIC_REPO:-StrawCoding/strawwu-public}"
ISO_DIR="${STRAWWU_ISO_DIR:-/mnt/data/code/project/StrawCoding/StrawWU/os-image/output}"
CDN_ROOT="${STRAWWU_CDN_ROOT:-/opt/1panel/www/sites/download.strawwu.org/releases}"
CHUNK_BYTES="${STRAWWU_RELEASE_CHUNK_BYTES:-$((1800 * 1024 * 1024))}"
VERSION="${1:-}"
SOURCE="${STRAWWU_SYNC_SOURCE:-auto}" # auto | local | github

usage() {
  echo "Usage: $0 [version]" >&2
  echo "  Sync ISO parts to \$STRAWWU_CDN_ROOT/v<version>/" >&2
  exit 1
}

if [[ -z "$VERSION" ]]; then
  latest="$(ls -1t "$ISO_DIR"/StrawWU-*.iso 2>/dev/null | head -1 || true)"
  VERSION="$(basename "${latest:-}" | sed -n 's/StrawWU-\(.*\)-amd64\.iso/\1/p')"
fi
[[ -n "$VERSION" ]] || usage

tag="v${VERSION}"
iso_name="StrawWU-${VERSION}-amd64.iso"
dest_dir="$CDN_ROOT/${tag}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$dest_dir"

split_local_iso() {
  local iso="$ISO_DIR/$iso_name"
  [[ -f "$iso" ]] || return 1
  echo "==> split local ISO: $iso"
  split -b "$CHUNK_BYTES" --numeric-suffixes=1 --additional-suffix=.part "$iso" "$tmpdir/${iso_name}."
  sha256sum "$iso" | awk -v f="$iso_name" '{print $1 "  " f}' > "$tmpdir/SHA256SUMS"
  cp "$ROOT/scripts/join-iso.sh" "$tmpdir/join-iso.sh"
  chmod +x "$tmpdir/join-iso.sh"
}

fetch_github_assets() {
  echo "==> fetch GitHub release assets: $tag"
  gh release download "$tag" --repo "$REPO" --dir "$tmpdir" \
    --pattern '*.part' --pattern 'SHA256SUMS' --pattern 'join-iso.sh'
}

pick_source() {
  local mode="$SOURCE"
  if [[ "$mode" == "auto" ]]; then
    if [[ -f "$ISO_DIR/$iso_name" ]]; then
      mode="local"
    else
      mode="github"
    fi
  fi
  case "$mode" in
    local)
      split_local_iso || { echo "local ISO missing: $ISO_DIR/$iso_name" >&2; return 1; }
      ;;
    github)
      fetch_github_assets
      ;;
    *)
      echo "unknown STRAWWU_SYNC_SOURCE=$SOURCE" >&2
      return 1
      ;;
  esac
}

pick_source

mapfile -t assets < <(find "$tmpdir" -maxdepth 1 -type f | sort -V)
[[ ${#assets[@]} -gt 0 ]] || { echo "no assets prepared for $tag" >&2; exit 1; }

echo "==> rsync to $dest_dir"
for f in "${assets[@]}"; do
  cp -a "$f" "$dest_dir/$(basename "$f")"
done

part_count="$(find "$dest_dir" -maxdepth 1 -name '*.part' | wc -l)"
echo "DONE: $tag → $dest_dir ($part_count parts, $(find "$dest_dir" -maxdepth 1 -type f | wc -l) files)"
