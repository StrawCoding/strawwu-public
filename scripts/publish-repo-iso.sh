#!/usr/bin/env bash
# Publish StrawWU ISO into the git repository (iso/v<version>/ via Git LFS).
# GitHub LFS caps each object at 2 GiB on Free/Pro — larger ISOs are stored as
# ordered parts in iso/v<version>/; the download page merges them into one .iso.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ISO_DIR="${STRAWWU_ISO_DIR:-/mnt/data/code/project/StrawCoding/StrawWU/os-image/output}"
ISO_REPO_DIR="${STRAWWU_ISO_REPO_DIR:-$REPO_ROOT/iso}"
CHUNK_BYTES="${STRAWWU_REPO_CHUNK_BYTES:-$((1800 * 1024 * 1024))}"
BRANCH="${STRAWWU_ISO_BRANCH:-main}"
VERSION="${1:-}"
SKIP_PUSH="${STRAWWU_SKIP_REPO_PUSH:-0}"

if [[ -z "$VERSION" ]]; then
  latest="$(ls -1t "$ISO_DIR"/StrawWU-*.iso 2>/dev/null | head -1)"
  VERSION="$(basename "$latest" | sed -n 's/StrawWU-\(.*\)-amd64\.iso/\1/p')"
fi

[[ -n "$VERSION" ]] || { echo "Usage: $0 [version]" >&2; exit 1; }

iso="$ISO_DIR/StrawWU-${VERSION}-amd64.iso"
[[ -f "$iso" ]] || { echo "ISO not found: $iso" >&2; exit 1; }

cd "$REPO_ROOT"
git lfs install --local >/dev/null

dest_dir="$ISO_REPO_DIR/v${VERSION}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

base="$(basename "$iso")"
sha256="$(sha256sum "$iso" | awk '{print $1}')"
size="$(stat -c%s "$iso")"

if [[ "$size" -le 2147483648 ]]; then
  cp "$iso" "$tmpdir/$base"
  part_count=1
else
  echo "Splitting $iso into ${CHUNK_BYTES}-byte parts for Git LFS..."
  split -b "$CHUNK_BYTES" --numeric-suffixes=1 --additional-suffix=.part "$iso" "$tmpdir/${base}."
  part_count="$(find "$tmpdir" -maxdepth 1 -name "${base}.*.part" -type f | wc -l)"
fi

if [[ "$part_count" -lt 1 ]]; then
  echo "No ISO assets prepared" >&2
  exit 1
fi

echo "${sha256}  ${base}" > "$tmpdir/SHA256SUMS"
cp "$REPO_ROOT/scripts/join-iso.sh" "$tmpdir/join-iso.sh"
chmod +x "$tmpdir/join-iso.sh"

rm -rf "$dest_dir"
mkdir -p "$dest_dir"
cp -a "$tmpdir"/. "$dest_dir/"

size_human="$(numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "${size} bytes")"
echo "Prepared iso/v${VERSION}/ (${part_count} file(s), ${size_human})"
ls -lh "$dest_dir"

git add .gitattributes "$dest_dir"
if git diff --cached --quiet; then
  echo "No changes to commit for v${VERSION}"
else
  git commit -m "iso: add StrawWU v${VERSION} (${part_count} LFS object(s))"
fi

if [[ "$SKIP_PUSH" == "1" ]]; then
  echo "SKIP_PUSH=1 — committed locally only"
  trap - EXIT
  exit 0
fi

echo "Pushing LFS objects and commit to origin/${BRANCH}..."
git lfs push origin "$BRANCH" --all
git push origin "$BRANCH"

echo "Published v${VERSION} to repo → iso/v${VERSION}/"
echo "Raw base: https://raw.githubusercontent.com/StrawCoding/strawwu-public/${BRANCH}/iso/v${VERSION}"
