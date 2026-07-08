#!/usr/bin/env bash
# Reassemble a chunked StrawWU ISO downloaded from GitHub Releases.
# Usage: join-iso.sh <output.iso> <part-files...>
# Example:
#   ./join-iso.sh StrawWU-0.6.2.5-amd64.iso StrawWU-0.6.2.5-amd64.iso.*.part
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <output.iso> <part-file> [part-file...]" >&2
  exit 1
fi

out="$1"
shift
parts=("$@")

for part in "${parts[@]}"; do
  [[ -f "$part" ]] || { echo "Missing part: $part" >&2; exit 1; }
done

tmp="${out}.partial"
rm -f "$tmp"
cat "${parts[@]}" > "$tmp"
mv -f "$tmp" "$out"
echo "Wrote $out ($(numfmt --to=iec-i --suffix=B "$(stat -c%s "$out")" 2>/dev/null || stat -c%s "$out"))"

if [[ -f SHA256SUMS ]]; then
  echo "Verifying SHA256SUMS..."
  sha256sum -c SHA256SUMS
else
  echo "No SHA256SUMS in current directory — skip checksum verify"
fi
