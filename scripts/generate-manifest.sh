#!/usr/bin/env bash
# Generate docs/releases.json from local ISO directory + GitHub Release metadata.
set -euo pipefail

ISO_DIR="${STRAWWU_ISO_DIR:-/mnt/data/code/project/StrawCoding/StrawWU/os-image/output}"
DEST="$(dirname "$0")/../docs/releases.json"
GITHUB_REPO="${STRAWWU_PUBLIC_REPO:-StrawCoding/strawwu-public}"

if [[ ! -d "$ISO_DIR" ]]; then
  echo "ISO directory not found: $ISO_DIR" >&2
  exit 1
fi

python3 - "$ISO_DIR" "$DEST" "$GITHUB_REPO" <<'PY'
import json, re, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path

iso_dir = Path(sys.argv[1])
dest = sys.argv[2]
gh_repo = sys.argv[3]
entries = []
ver_re = re.compile(r"StrawWU-(\d+\.\d+\.\d+\.\d+)-amd64\.iso$")

def gh_release_assets(version: str):
    tag = f"v{version}"
    try:
        out = subprocess.check_output(
            ["gh", "release", "view", tag, "--repo", gh_repo, "--json", "assets,publishedAt"],
            text=True,
        )
        data = json.loads(out)
    except subprocess.CalledProcessError:
        return None
    assets = []
    for asset in data.get("assets") or []:
        name = asset.get("name") or ""
        if name.endswith(".part") or name == "join-iso.sh":
            assets.append({
                "name": name,
                "url": f"https://github.com/{gh_repo}/releases/download/{tag}/{name}",
                "size": asset.get("size"),
            })
    assets.sort(key=lambda a: a["name"])
    return {
        "published_at": data.get("publishedAt"),
        "parts": assets,
        "has_iso_parts": any(a["name"].endswith(".part") for a in assets),
    }

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

    rel = gh_release_assets(version)
    release_url = f"https://github.com/{gh_repo}/releases/tag/v{version}"
    entry = {
        "version": version,
        "filename": path.name,
        "size": size,
        "size_human": f"{size / (1024**3):.2f} GiB",
        "sha256": sha256,
        "download_url": release_url,
        "release_url": release_url,
        "published_at": datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    if rel:
        if rel.get("published_at"):
            entry["published_at"] = rel["published_at"]
        if rel.get("parts"):
            entry["parts"] = rel["parts"]
            entry["part_count"] = len([p for p in rel["parts"] if p["name"].endswith(".part")])
            entry["iso_published"] = rel.get("has_iso_parts", False)
    entries.append(entry)

if not entries:
    raise SystemExit(f"No ISO files found in {iso_dir}")

latest = entries[0]["version"]
payload = {
    "schema": "strawwu-public-releases/v2",
    "updated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "latest": latest,
    "download_base": f"https://github.com/{gh_repo}/releases/download",
    "github_repo": gh_repo,
    "releases": entries,
}
Path(dest).write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
print(f"Wrote {dest} ({len(entries)} releases, latest v{latest})")
PY
