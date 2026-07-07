# StrawWU Public

公開發行倉庫：StrawWU ISO 下載站與版本清單。

- **下載站（GitHub Pages）**：https://download.strawwu.org/
- **ISO 檔案（GitHub Releases）**：https://github.com/StrawCoding/strawwu-public/releases
- **備援 Pages URL**：https://strawcoding.github.io/strawwu-public/

ISO 約 4–5 GiB，以 **分片（.part）** 發佈於 GitHub Releases，下載後用 `join-iso.sh` 合併。

## 目錄

| 路徑 | 說明 |
|------|------|
| `docs/` | 下載站靜態頁（GitHub Pages → download.strawwu.org） |
| `docs/CNAME` | Pages 自訂網域 |
| `docs/releases.json` | 所有 ISO 版本清單（自動產生） |
| `scripts/generate-manifest.sh` | 從本機 ISO 目錄 + GitHub Release 產生 manifest |
| `scripts/publish-github-release.sh` | 分片並上傳單一版本至 GitHub Release |
| `scripts/provision-strawwu-dns.sh` | strawwu.org Cloudflare DNS（需 zone token） |
| `scripts/join-iso.sh` | 合併下載的分片 |

## 發布新版本

```bash
# 1. 上傳 ISO 分片至 GitHub Release
./scripts/publish-github-release.sh 0.6.2.5

# 2. 更新 manifest（GitHub Releases URL）
./scripts/generate-manifest.sh

# 3. 推送 manifest / 網站變更（觸發 GitHub Pages 部署）
git add docs/releases.json docs/index.html docs/CNAME
git commit -m "chore: update releases manifest"
git push
```

## 使用者下載與驗證

1. 開啟 https://download.strawwu.org/
2. 點「下載 ISO」或進入 GitHub Release 頁面，下載該版本的全部 `*.part`、`SHA256SUMS`、`join-iso.sh`
3. 合併並驗證：

```bash
chmod +x join-iso.sh
./join-iso.sh StrawWU-0.6.2.5-amd64.iso StrawWU-0.6.2.5-amd64.iso.*.part
sha256sum -c SHA256SUMS
```

## DNS

`download.strawwu.org` 指向 GitHub Pages（非自架 CDN）：

```
download.strawwu.org CNAME strawcoding.github.io
```

其他子網域（strawwu.org / www / apt）見 `scripts/provision-strawwu-dns.sh`。

## 備註

- ISO 不放入 git tree（僅 manifest + 靜態網站在 repo 內）
- 首頁自動顯示 `releases.json` 中 `latest` 欄位的最新版本
- ISO 大檔僅託管於 GitHub Releases；`download.strawwu.org` 只提供下載首頁與版本清單
