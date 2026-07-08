#!/usr/bin/env bash
# Generate docs/releases.json from local ISO directory + repo iso/ tree.
set -euo pipefail

ISO_DIR="${STRAWWU_ISO_DIR:-/mnt/data/code/project/StrawCoding/StrawWU/os-image/output}"
ISO_REPO_DIR="${STRAWWU_ISO_REPO_DIR:-$(dirname "$0")/../iso}"
SF_MARKER_DIR="${STRAWWU_SF_MARKER_DIR:-$(dirname "$0")/../docs/sf-releases}"
DEST="$(dirname "$0")/../docs/releases.json"
GITHUB_REPO="${STRAWWU_PUBLIC_REPO:-StrawCoding/strawwu-public}"
RAW_BASE="${STRAWWU_RAW_BASE:-https://media.githubusercontent.com/media/${GITHUB_REPO}}"
RELEASES_DOWNLOAD_BASE="${STRAWWU_RELEASES_DOWNLOAD_BASE:-https://github.com/${GITHUB_REPO}/releases/download}"
PAGES_BASE="${STRAWWU_PAGES_BASE:-https://strawcoding.github.io/strawwu-public}"
BRANCH="${STRAWWU_ISO_BRANCH:-main}"
SF_CDN_BASE="${STRAWWU_SF_CDN_BASE:-https://sourceforge.net/projects}"

if [[ ! -d "$ISO_DIR" ]]; then
  echo "ISO directory not found: $ISO_DIR" >&2
  exit 1
fi

python3 - "$ISO_DIR" "$ISO_REPO_DIR" "$DEST" "$GITHUB_REPO" "$RAW_BASE" "$RELEASES_DOWNLOAD_BASE" "$PAGES_BASE" "$BRANCH" "$SF_MARKER_DIR" "$SF_CDN_BASE" <<'PY'
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
sf_marker_dir = Path(sys.argv[9])
sf_cdn_base = sys.argv[10].rstrip("/")
entries = []
ver_re = re.compile(r"StrawWU-(\d+\.\d+\.\d+\.\d+)-amd64\.iso$")


def sf_iso_assets(version: str):
    marker = sf_marker_dir / f"v{version}.json"
    if not marker.is_file():
        return None
    try:
        data = json.loads(marker.read_text())
    except (json.JSONDecodeError, OSError):
        return None
    iso_url = data.get("iso_url")
    if not iso_url:
        project = data.get("project")
        prefix = data.get("prefix") or "releases"
        filename = data.get("filename") or f"StrawWU-{version}-amd64.iso"
        if not project:
            return None
        iso_url = f"{sf_cdn_base}/{project}/files/{prefix}/v{version}/{filename}/download"
    checksum_url = data.get("checksum_url")
    if not checksum_url and data.get("project"):
        prefix = data.get("prefix") or "releases"
        checksum_url = (
            f"{sf_cdn_base}/{data['project']}/files/{prefix}/v{version}/SHA256SUMS/download"
        )
    release_url = data.get("release_url") or (
        f"{sf_cdn_base}/{data['project']}/files/{data.get('prefix') or 'releases'}/v{version}/"
        if data.get("project")
        else None
    )
    return {
        "published_at": data.get("published_at"),
        "release_url": release_url,
        "parts": [],
        "part_assets": [],
        "has_iso_parts": False,
        "full_iso_url": iso_url,
        "checksum_url": checksum_url,
        "source": "sourceforge",
        "prefer_direct": True,
    }


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
        if name.endswith(".part") or name in ("join-iso.sh", "SHA256SUMS", "SHA256SUMS.asc"):
            assets.append({"name": name, "url": url, "size": size})
    part_assets = [a for a in assets if a["name"].endswith(".part")]
    if not full_iso_url and not part_assets:
        return None
    assets.sort(key=lambda a: a["name"])
    checksum = next((a for a in assets if a["name"] == "SHA256SUMS"), None)
    return {
        "published_at": datetime.fromtimestamp(repo_ver.stat().st_mtime, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "release_url": f"https://github.com/{gh_repo}/tree/{branch}/iso/v{version}",
        "parts": assets,
        "part_assets": part_assets,
        "has_iso_parts": bool(part_assets),
        "full_iso_url": full_iso_url,
        "checksum_url": checksum["url"] if checksum else None,
        "source": "repo",
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
    assets = []
    full_iso_url = None
    for asset in data.get("assets") or []:
        name = asset.get("name") or ""
        url = asset.get("url") or f"{releases_download_base}/{tag}/{name}"
        if name.endswith(".iso") and not name.endswith(".part"):
            full_iso_url = url
        if name.endswith(".part") or name in ("join-iso.sh", "SHA256SUMS", "SHA256SUMS.asc"):
            assets.append({"name": name, "url": url, "size": asset.get("size")})
    part_assets = [a for a in assets if a["name"].endswith(".part")]
    if not full_iso_url and not part_assets:
        return None
    assets.sort(key=lambda a: a["name"])
    checksum = next((a for a in assets if a["name"] == "SHA256SUMS"), None)
    return {
        "published_at": data.get("publishedAt"),
        "release_url": data.get("url") or f"https://github.com/{gh_repo}/releases/tag/{tag}",
        "parts": assets,
        "part_assets": part_assets,
        "has_iso_parts": bool(part_assets),
        "full_iso_url": full_iso_url,
        "checksum_url": checksum["url"] if checksum else None,
        "source": "release",
    }


def resolve_publish_assets(version: str):
    # SourceForge whole-file ISO wins over GitHub LFS split parts.
    return sf_iso_assets(version) or repo_iso_assets(version) or gh_release_assets(version)


dest_path = Path(dest)
withdrawn_meta = {}
existing_sha = {}
if dest_path.exists():
    try:
        existing_doc = json.loads(dest_path.read_text())
        for old in existing_doc.get("releases") or []:
            if old.get("sha256") and old.get("version"):
                existing_sha[old["version"]] = old["sha256"]
            if old.get("status") == "withdrawn":
                withdrawn_meta[old["version"]] = {
                    k: old[k]
                    for k in ("status", "withdrawn_reason", "withdrawn_at")
                    if k in old
                }
    except (json.JSONDecodeError, KeyError):
        pass

for path in sorted(iso_dir.glob("StrawWU-*.iso"), key=lambda p: p.name, reverse=True):
    m = ver_re.match(path.name)
    if not m:
        continue
    version = m.group(1)
    size = path.stat().st_size
    sha_path = Path(iso_dir) / "SHA256SUMS"
    sha256 = None
    repo_sha = iso_repo_dir / f"v{version}" / "SHA256SUMS"
    if repo_sha.exists():
        for line in repo_sha.read_text().splitlines():
            parts = line.split()
            if len(parts) >= 2 and parts[1] == path.name:
                sha256 = parts[0]
                break
    if not sha256 and sha_path.exists():
        for line in sha_path.read_text().splitlines():
            parts = line.split()
            if len(parts) >= 2 and parts[1] == path.name:
                sha256 = parts[0]
                break
    if not sha256 and version in existing_sha:
        sha256 = existing_sha[version]
    if not sha256:
        h = hashlib.sha256()
        with path.open("rb") as f:
            for chunk in iter(lambda: f.read(8 * 1024 * 1024), b""):
                h.update(chunk)
        sha256 = h.hexdigest()

    rel = resolve_publish_assets(version)

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
        elif rel.get("has_iso_parts"):
            entry["has_full_iso"] = True
            entry["join_mode"] = "browser"
            entry["download_url"] = f"{pages_base}/?version={version}#download"
            entry["parts"] = rel["part_assets"]
            entry["part_count"] = len(rel["part_assets"])
            entry["iso_published"] = True
        if rel.get("checksum_url"):
            entry["checksum_url"] = rel["checksum_url"]
    if version in withdrawn_meta:
        entry.update(withdrawn_meta[version])
        entry["download_url"] = entry.get("release_url") or entry["download_url"]
        for key in ("iso_url", "parts", "part_count", "join_mode", "storage"):
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
if active:
    latest = max((e["version"] for e in active), key=version_key)
else:
    latest = entries[0]["version"]
latest_published = (
    max((e["version"] for e in published), key=version_key) if published else None
)

payload = {
    "schema": "strawwu-public-releases/v8",
    "updated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "latest": latest,
    "latest_published": latest_published,
    "download_base": sf_cdn_base if any(e.get("storage") == "sourceforge" for e in entries) else raw_base,
    "pages_base": pages_base,
    "raw_base": raw_base,
    "sourceforge_base": sf_cdn_base,
    "github_repo": gh_repo,
    "iso_policy": "whole-file-preferred",
    "releases": entries,
}
Path(dest).write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
print(f"Wrote {dest} ({len(entries)} releases, latest v{latest})")
PY
