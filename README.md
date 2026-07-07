# StrawWU Public

公開發行倉庫：StrawWU ISO 下載站與版本清單。

- **下載站（CDN）**：https://download.strawwu.org/
- **備援（GitHub Releases）**：https://github.com/StrawCoding/strawwu-public/releases
- **舊 Pages 鏡像**：https://strawcoding.github.io/strawwu-public/

ISO 約 4–5 GiB，以 **分片（.part）** 發佈於 `download.strawwu.org/v<version>/`，下載後用 `join-iso.sh` 合併。

## 目錄

| 路徑 | 說明 |
|------|------|
| `docs/` | 下載站靜態頁（同步至 download.strawwu.org） |
| `docs/releases.json` | 所有 ISO 版本清單（自動產生） |
| `scripts/generate-manifest.sh` | 從本機 ISO 目錄 + GitHub Release 產生 manifest |
| `scripts/sync-release-assets.sh` | 同步 ISO 分片至 CDN 目錄 |
| `scripts/deploy-download.sh` | 部署下載站至 1Panel + nginx reload |
| `scripts/publish-github-release.sh` | 分片並上傳單一版本至 GitHub Release |
| `scripts/provision-strawwu-dns.sh` | strawwu.org Cloudflare DNS（需 zone token） |
| `scripts/join-iso.sh` | 合併下載的分片 |

## 發布新版本

```bash
# 1. 上傳 ISO 分片至 GitHub Release（備援鏡像）
./scripts/publish-github-release.sh 0.6.2.5

# 2. 更新 manifest（download.strawwu.org URL）
./scripts/generate-manifest.sh

# 3. 同步 CDN 並部署下載站
./scripts/deploy-download.sh

# 4. 推送 manifest / 網站變更
git add docs/releases.json docs/index.html
git commit -m "chore: update releases manifest"
git push
```

## 使用者下載與驗證

1. 開啟 https://download.strawwu.org/ 或版本目錄 `https://download.strawwu.org/v0.6.2.5/`
2. 下載該版本的全部 `*.part`、`SHA256SUMS`、`join-iso.sh`
3. 合併並驗證：

```bash
chmod +x join-iso.sh
./join-iso.sh StrawWU-0.6.2.5-amd64.iso StrawWU-0.6.2.5-amd64.iso.*.part
sha256sum -c SHA256SUMS
```

## DNS

`strawwu.org` 區域需在 Cloudflare 新增 CNAME（見 `scripts/provision-strawwu-dns.sh` 或 `StrawWUWeb/scripts/dns-strawwu.org.txt`）：

```
download.strawwu.org → 807e8f07-7a7d-4170-b061-d4efd86dcb0f.cfargotunnel.com
```

## 備註

- ISO 不放入 git tree（僅 manifest + 靜態網站在 repo 內）
- CDN 實體檔案位於 `/opt/1panel/www/sites/download.strawwu.org/releases/v<version>/`（nginx alias；與 `index/` 靜態頁分離）
- 首頁自動顯示 `releases.json` 中 `latest` 欄位的最新版本
