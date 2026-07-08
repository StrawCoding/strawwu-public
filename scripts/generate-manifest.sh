#!/usr/bin/env bash
# Generate docs/releases.json from local ISO directory + GitHub Release metadata.
set -euo pipefail

ISO_DIR="${STRAWWU_ISO_DIR:-/mnt/data/code/project/StrawCoding/StrawWU/os-image/output}"
DEST="$(dirname "$0")/../docs/releases.json"
GITHUB_REPO="${STRAWWU_PUBLIC_REPO:-StrawCoding/strawwu-public}"
RELEASES_DOWNLOAD_BASE="${STRAWWU_RELEASES_DOWNLOAD_BASE:-https://github.com/${GITHUB_REPO}/releases/download}"
PAGES_BASE="${STRAWWU_PAGES_BASE:-https://strawcoding.github.io/strawwu-public}"

if [[ ! -d "$ISO_DIR" ]]; then
  echo "ISO directory not found: $ISO_DIR" >&2
  exit 1
fi

python3 - "$ISO_DIR" "$DEST" "$GITHUB_REPO" "$RELEASES_DOWNLOAD_BASE" "$PAGES_BASE" <<'PY'
import json, re, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path

iso_dir = Path(sys.argv[1])
dest = sys.argv[2]
gh_repo = sys.argv[3]
releases_download_base = sys.argv[4].rstrip("/")
pages_base = sys.argv[5].rstrip("/")
entries = []
ver_re = re.compile(r"StrawWU-(\d+\.\d+\.\d+\.\d+)-amd64\.iso$")

def gh_release_assets(version: str):
    tag = f"v{version}"
    try:
        out = subprocess.check_output(
            ["gh", "release", "view", tag, "--repo", gh_repo, "--json", "assets,publishedAt,url"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        data = json.loads(out)
    except subprocess.CalledProcessError:
        return None
    assets = []
    full_iso_url = None
    for asset in data.get("assets") or []:
        name = asset.get("name") or ""
        url = asset.get("url") or f"{releases_download_base}/{tag}/{name}"
        if name.endswith(".iso") and not name.endswith(".part"):
            full_iso_url = url
        if name.endswith(".part") or name in ("join-iso.sh", "SHA256SUMS", "SHA256SUMS.asc"):
            assets.append({
                "name": name,
                "url": url,
                "size": asset.get("size"),
            })
    assets.sort(key=lambda a: a["name"])
    return {
        "published_at": data.get("publishedAt"),
        "release_url": data.get("url") or f"https://github.com/{gh_repo}/releases/tag/{tag}",
        "parts": assets,
        "has_iso_parts": any(a["name"].endswith(".part") for a in assets),
        "full_iso_url": full_iso_url,
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
    tag = f"v{version}"
    release_url = rel["release_url"] if rel else f"https://github.com/{gh_repo}/releases/tag/{tag}"
    entry = {
        "version": version,
        "filename": path.name,
        "size": size,
        "size_human": f"{size / (1024**3):.2f} GiB",
        "sha256": sha256,
        "has_full_iso": bool(rel and rel.get("full_iso_url")),
        "download_url": release_url,
        "release_url": release_url,
        "published_at": datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    if rel and rel.get("full_iso_url"):
        entry["iso_url"] = rel["full_iso_url"]
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

# Preserve manually curated withdrawn releases from existing manifest.
dest_path = Path(dest)
if dest_path.exists():
    try:
        existing = json.loads(dest_path.read_text())
        known_versions = {e["version"] for e in entries}
        for old in existing.get("releases") or []:
            if old.get("status") == "withdrawn" and old.get("version") not in known_versions:
                old["download_url"] = old.get("release_url") or old.get("download_url")
                old.pop("iso_url", None)
                entries.insert(0, old)
    except (json.JSONDecodeError, KeyError):
        pass

latest = next((e["version"] for e in entries if e.get("status") != "withdrawn"), entries[0]["version"])
payload = {
    "schema": "strawwu-public-releases/v4",
    "updated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "latest": latest,
    "download_base": releases_download_base,
    "pages_base": pages_base,
    "releases_download_base": releases_download_base,
    "github_repo": gh_repo,
    "releases": entries,
}
Path(dest).write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
print(f"Wrote {dest} ({len(entries)} releases, latest v{latest})")
PY
