#!/usr/bin/env bash
# Generate docs/releases.json from local ISO directory + repo iso/ tree.
set -euo pipefail

ISO_DIR="${STRAWWU_ISO_DIR:-/mnt/data/code/project/StrawCoding/StrawWU/os-image/output}"
ISO_REPO_DIR="${STRAWWU_ISO_REPO_DIR:-$(dirname "$0")/../iso}"
DEST="$(dirname "$0")/../docs/releases.json"
GITHUB_REPO="${STRAWWU_PUBLIC_REPO:-StrawCoding/strawwu-public}"
RAW_BASE="${STRAWWU_RAW_BASE:-https://media.githubusercontent.com/media/${GITHUB_REPO}}"
RELEASES_DOWNLOAD_BASE="${STRAWWU_RELEASES_DOWNLOAD_BASE:-https://github.com/${GITHUB_REPO}/releases/download}"
PAGES_BASE="${STRAWWU_PAGES_BASE:-https://strawcoding.github.io/strawwu-public}"
BRANCH="${STRAWWU_ISO_BRANCH:-main}"

if [[ ! -d "$ISO_DIR" ]]; then
  echo "ISO directory not found: $ISO_DIR" >&2
  exit 1
fi

python3 - "$ISO_DIR" "$ISO_REPO_DIR" "$DEST" "$GITHUB_REPO" "$RAW_BASE" "$RELEASES_DOWNLOAD_BASE" "$PAGES_BASE" "$BRANCH" <<'PY'
import hashlib
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

iso_dir = Path(sys.argv[1])
iso_repo_dir = Path(sys.argv[2])
dest = sys.argv[3]
gh_repo = sys.argv[4]
raw_base = sys.argv[5].rstrip("/")
releases_download_base = sys.argv[6].rstrip("/")
pages_base = sys.argv[7].rstrip("/")
branch = sys.argv[8]
entries = []
ver_re = re.compile(r"StrawWU-(\d+\.\d+\.\d+\.\d+)-amd64\.iso$")


def repo_iso_assets(version: str):
    repo_ver = iso_repo_dir / f"v{version}"
    if not repo_ver.is_dir():
        return None
    assets = []
    full_iso_url = None
    for path in sorted(repo_ver.iterdir()):
        if not path.is_file():
            continue
        name = path.name
        url = f"{raw_base}/{branch}/iso/v{version}/{name}"
        size = path.stat().st_size
        if name.endswith(".iso") and not name.endswith(".part"):
            full_iso_url = url
        if name in ("SHA256SUMS", "SHA256SUMS.asc"):
            assets.append({"name": name, "url": url, "size": size})
    if not full_iso_url:
        return None
    checksum = next((a for a in assets if a["name"] == "SHA256SUMS"), None)
    return {
        "published_at": datetime.fromtimestamp(repo_ver.stat().st_mtime, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "release_url": f"https://github.com/{gh_repo}/tree/{branch}/iso/v{version}",
        "full_iso_url": full_iso_url,
        "checksum_url": checksum["url"] if checksum else None,
        "source": "repo",
    }


def cdn_iso_assets(version: str, iso_path: Path):
    cdn_base = __import__("os").environ.get("STRAWWU_ISO_CDN_BASE", "https://download.strawwu.org").rstrip("/")
    tag = f"v{version}"
    base = iso_path.name
    object_key = f"releases/{tag}/{base}"
    url = f"{cdn_base}/{object_key}"
    return {
        "published_at": datetime.fromtimestamp(iso_path.stat().st_mtime, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "release_url": f"https://github.com/{gh_repo}/releases/tag/{tag}",
        "full_iso_url": url,
        "checksum_url": f"{cdn_base}/releases/{tag}/SHA256SUMS",
        "source": "cdn",
    }


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
    for asset in data.get("assets") or []:
        name = asset.get("name") or ""
        if name.endswith(".iso") and not name.endswith(".part"):
            url = asset.get("url") or f"{releases_download_base}/{tag}/{name}"
            return {
                "published_at": data.get("publishedAt"),
                "release_url": data.get("url") or f"https://github.com/{gh_repo}/releases/tag/{tag}",
                "full_iso_url": url,
                "source": "release",
            }
    return None


withdrawn_meta = {}

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
        h = hashlib.sha256()
        with path.open("rb") as f:
            for chunk in iter(lambda: f.read(8 * 1024 * 1024), b""):
                h.update(chunk)
        sha256 = h.hexdigest()

    rel = repo_iso_assets(version)
    if not rel and __import__("os").environ.get("STRAWWU_ISO_CDN_BASE"):
        rel = cdn_iso_assets(version, path)
    if not rel:
        rel = gh_release_assets(version)

    release_url = rel["release_url"] if rel else f"https://github.com/{gh_repo}/tree/{branch}/iso/v{version}"
    entry = {
        "version": version,
        "filename": path.name,
        "size": size,
        "size_human": f"{size / (1024**3):.2f} GiB",
        "sha256": sha256,
        "has_full_iso": False,
        "download_url": release_url,
        "release_url": release_url,
        "published_at": datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    if rel:
        if rel.get("published_at"):
            entry["published_at"] = rel["published_at"]
        if rel.get("source"):
            entry["storage"] = rel["source"]
        if rel.get("full_iso_url"):
            entry["has_full_iso"] = True
            entry["iso_url"] = rel["full_iso_url"]
            entry["download_url"] = rel["full_iso_url"]
            entry["join_mode"] = "direct"
            entry["iso_published"] = True
        if rel.get("checksum_url"):
            entry["checksum_url"] = rel["checksum_url"]
    if version in withdrawn_meta:
        entry.update(withdrawn_meta[version])
        entry["download_url"] = entry.get("release_url") or entry["download_url"]
        for key in ("iso_url", "join_mode", "storage"):
            entry.pop(key, None)
        entry["has_full_iso"] = False
        entry["iso_published"] = False
    entries.append(entry)

if not entries:
    raise SystemExit(f"No ISO files found in {iso_dir}")


def version_key(v: str):
    return tuple(int(x) for x in v.split("."))

active = [e for e in entries if e.get("status") != "withdrawn"]
published = [e for e in active if e.get("iso_published") or e.get("has_full_iso")]
if published:
    latest = max((e["version"] for e in published), key=version_key)
elif active:
    latest = max((e["version"] for e in active), key=version_key)
else:
    latest = entries[0]["version"]

payload = {
    "schema": "strawwu-public-releases/v7",
    "updated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "latest": latest,
    "download_base": raw_base,
    "pages_base": pages_base,
    "raw_base": raw_base,
    "github_repo": gh_repo,
    "releases": entries,
}
Path(dest).write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
print(f"Wrote {dest} ({len(entries)} releases, latest v{latest})")
PY
