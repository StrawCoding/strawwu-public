#!/usr/bin/env bash
# Generate docs/releases.json from local ISO directory + CDN / GitHub Release metadata.
set -euo pipefail

ISO_DIR="${STRAWWU_ISO_DIR:-/mnt/data/code/project/StrawCoding/StrawWU/os-image/output}"
DEST="$(dirname "$0")/../docs/releases.json"
GITHUB_REPO="${STRAWWU_PUBLIC_REPO:-StrawCoding/strawwu-public}"
RELEASES_DOWNLOAD_BASE="${STRAWWU_RELEASES_DOWNLOAD_BASE:-https://github.com/${GITHUB_REPO}/releases/download}"
PAGES_BASE="${STRAWWU_PAGES_BASE:-https://strawcoding.github.io/strawwu-public}"
CDN_BASE="${STRAWWU_ISO_CDN_BASE:-https://download.strawwu.org}"
S3_PREFIX="${STRAWWU_ISO_S3_PREFIX:-releases}"

if [[ ! -d "$ISO_DIR" ]]; then
  echo "ISO directory not found: $ISO_DIR" >&2
  exit 1
fi

python3 - "$ISO_DIR" "$DEST" "$GITHUB_REPO" "$RELEASES_DOWNLOAD_BASE" "$PAGES_BASE" "$CDN_BASE" "$S3_PREFIX" <<'PY'
import json, re, subprocess, sys, urllib.request
from datetime import datetime, timezone
from pathlib import Path

iso_dir = Path(sys.argv[1])
dest = sys.argv[2]
gh_repo = sys.argv[3]
releases_download_base = sys.argv[4].rstrip("/")
pages_base = sys.argv[5].rstrip("/")
cdn_base = sys.argv[6].rstrip("/")
s3_prefix = sys.argv[7].strip("/")
entries = []
ver_re = re.compile(r"StrawWU-(\d+\.\d+\.\d+\.\d+)-amd64\.iso$")


def url_exists(url: str) -> bool:
    try:
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req, timeout=30) as resp:
            return 200 <= resp.status < 400
    except Exception:
        return False


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
    checksum_url = None
    release_iso_url = None
    for asset in data.get("assets") or []:
        name = asset.get("name") or ""
        url = asset.get("url") or f"{releases_download_base}/{tag}/{name}"
        if name.endswith(".iso") and not name.endswith(".part"):
            release_iso_url = url
        if name == "SHA256SUMS":
            checksum_url = url
    return {
        "published_at": data.get("publishedAt"),
        "release_url": data.get("url") or f"https://github.com/{gh_repo}/releases/tag/{tag}",
        "release_iso_url": release_iso_url,
        "checksum_url": checksum_url,
    }


dest_path = Path(dest)
withdrawn_meta = {
    "1.0.0.0": {
        "status": "withdrawn",
        "withdrawn_reason": "未經使用者授權發布；未完成 boot-test 與 install E2E 驗證，請勿使用",
        "withdrawn_at": "2026-07-08T09:05:00Z",
    },
}
if dest_path.exists():
    try:
        existing = json.loads(dest_path.read_text())
        for old in existing.get("releases") or []:
            if old.get("status") == "withdrawn":
                withdrawn_meta[old["version"]] = {
                    k: old[k]
                    for k in (
                        "status", "withdrawn_reason", "withdrawn_at",
                    )
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
    cdn_iso_url = f"{cdn_base}/{s3_prefix}/{tag}/{path.name}"
    cdn_checksum_url = f"{cdn_base}/{s3_prefix}/{tag}/SHA256SUMS"
    iso_url = None
    if rel and rel.get("release_iso_url"):
        iso_url = rel["release_iso_url"]
    elif url_exists(cdn_iso_url):
        iso_url = cdn_iso_url

    entry = {
        "version": version,
        "filename": path.name,
        "size": size,
        "size_human": f"{size / (1024**3):.2f} GiB",
        "sha256": sha256,
        "has_full_iso": bool(iso_url),
        "download_url": iso_url or release_url,
        "release_url": release_url,
        "published_at": datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    if iso_url:
        entry["iso_url"] = iso_url
    elif version not in withdrawn_meta:
        # Expected direct-ISO CDN URL (available after publish-github-release.sh).
        entry["iso_url"] = cdn_iso_url
        entry["download_url"] = cdn_iso_url
    if version in withdrawn_meta:
        entry.update(withdrawn_meta[version])
        entry["download_url"] = entry.get("release_url") or entry["download_url"]
        entry.pop("iso_url", None)
    if rel:
        if rel.get("published_at"):
            entry["published_at"] = rel["published_at"]
        if rel.get("checksum_url"):
            entry["checksum_url"] = rel["checksum_url"]
        elif url_exists(cdn_checksum_url):
            entry["checksum_url"] = cdn_checksum_url
        entry["iso_published"] = bool(iso_url)
    entries.append(entry)

if not entries:
    raise SystemExit(f"No ISO files found in {iso_dir}")

dest_path = Path(dest)
if dest_path.exists():
    try:
        existing = json.loads(dest_path.read_text())
        known_versions = {e["version"] for e in entries}
        for old in existing.get("releases") or []:
            if old.get("status") == "withdrawn" and old.get("version") not in known_versions:
                preserved = dict(old)
                preserved["download_url"] = preserved.get("release_url") or preserved.get("download_url")
                for key in ("iso_url", "parts", "part_count"):
                    preserved.pop(key, None)
                entries.insert(0, preserved)
    except (json.JSONDecodeError, KeyError):
        pass

def version_key(v: str):
    return tuple(int(x) for x in v.split("."))

active = [e for e in entries if e.get("status") != "withdrawn"]
released = [e for e in active if e.get("iso_published") or e.get("checksum_url")]
latest = None
if released:
    latest = max((e["version"] for e in released), key=version_key)
elif active:
    latest = max((e["version"] for e in active), key=version_key)
else:
    latest = entries[0]["version"]

payload = {
    "schema": "strawwu-public-releases/v5",
    "updated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "latest": latest,
    "download_base": cdn_base,
    "pages_base": pages_base,
    "releases_download_base": releases_download_base,
    "iso_cdn_base": cdn_base,
    "github_repo": gh_repo,
    "releases": entries,
}
Path(dest).write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
print(f"Wrote {dest} ({len(entries)} releases, latest v{latest})")
PY
