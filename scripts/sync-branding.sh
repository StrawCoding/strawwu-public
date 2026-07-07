#!/usr/bin/env bash
set -euo pipefail
SRC="${STRAWWU_BRAND_DIR:-/mnt/data/Data/檔案/專案資料/StrawWU}"
DEST="$(dirname "$0")/../docs/assets/branding"
mkdir -p "$DEST"

resolve_src() {
  local base="$1"
  shift
  for name in "$@"; do
    if [[ -f "$SRC/$name" ]]; then
      echo "$SRC/$name"
      return 0
    fi
  done
  return 1
}

icon_src="$(resolve_src icon StrawWU-icon.svg strawwu-icon.svg)" \
  || { echo "missing icon source under $SRC" >&2; exit 1; }
lockup_src="$(resolve_src lockup StrawWU-lockup.svg strawwu-lockup.svg)" \
  || { echo "missing lockup source under $SRC" >&2; exit 1; }

cp -f "$icon_src" "$DEST/strawwu-icon.svg"
cp -f "$lockup_src" "$DEST/strawwu-lockup.svg"
cp -f "$icon_src" "$(dirname "$0")/../docs/favicon.svg"

rm -f "$DEST"/strawwu-icon.webp "$DEST"/strawwu-momo.webp "$DEST"/strawwu-momo-light.webp "$DEST"/strawwu-primary.webp

echo "Synced SVG branding to $DEST"
