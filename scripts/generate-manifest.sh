#!/usr/bin/env bash
# Generate docs/releases.json from local ISO directory and optional mirror base URL.
set -euo pipefail

ISO_DIR="${STRAWWU_ISO_DIR:-/mnt/data/code/project/StrawCoding/StrawWU/os-image/output}"
DEST="$(dirname "$0")/../docs/releases.json"
MIRROR_BASE="${STRAWWU_MIRROR_BASE:-https://apt.strawwu.org/iso}"
GITHUB_REPO="${STRAWWU_PUBLIC_REPO:-StrawCoding/strawwu-public}"

if [[ ! -d "$ISO_DIR" ]]; then
  echo "ISO directory not found: $ISO_DIR" >&2
  exit 1
fi

python3 - "$ISO_DIR" "$DEST" "$MIRROR_BASE" "$GITHUB_REPO" <<'PY'
import json, re, sys
from datetime import datetime, timezone
from pathlib import Path

iso_dir = Path(sys.argv[1])
dest = sys.argv[2]
mirror_base = sys.argv[3].rstrip("/")
gh_repo = sys.argv[4]
entries = []
ver_re = re.compile(r"StrawWU-(\d+\.\d+\.\d+\.\d+)-amd64\.iso$")

for path in sorted(iso_dir.glob("StrawWU-*.iso"), key=lambda p: p.name, reverse=True):
    m = ver_re.match(path.name)
    if not m:
        continue
    version = m.group(1)
    size = path.stat().st_size
    sha_path = Path(iso_dir) / "SHA256SUMS"
    sha256 = None
    if sha_path.exists():
        for line in sha_path.read_text().splitlines():
            parts = line.split()
            if len(parts) >= 2 and parts[1] == path.name:
                sha256 = parts[0]
                break
    if not sha256:
        import hashlib
        h = hashlib.sha256()
        with path.open("rb") as f:
            for chunk in iter(lambda: f.read(8 * 1024 * 1024), b""):
                h.update(chunk)
        sha256 = h.hexdigest()
    entries.append({
        "version": version,
        "filename": path.name,
        "size": size,
        "size_human": f"{size / (1024**3):.2f} GiB",
        "sha256": sha256,
        "download_url": f"{mirror_base}/{path.name}",
        "release_url": f"https://github.com/{gh_repo}/releases/tag/v{version}",
        "published_at": datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    })

if not entries:
    raise SystemExit(f"No ISO files found in {iso_dir}")

latest = entries[0]["version"]
payload = {
    "schema": "strawwu-public-releases/v1",
    "updated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "latest": latest,
    "mirror_base": mirror_base,
    "github_repo": gh_repo,
    "releases": entries,
}
Path(dest).write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
print(f"Wrote {dest} ({len(entries)} releases, latest v{latest})")
PY
