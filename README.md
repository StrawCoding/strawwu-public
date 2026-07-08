# StrawWU Public

公開發行倉庫：StrawWU ISO 下載站與版本清單。

- **下載站（GitHub Pages）**：https://strawcoding.github.io/strawwu-public/
- **ISO 檔案（GitHub Releases）**：https://github.com/StrawCoding/strawwu-public/releases

ISO 約 4–5 GiB。GitHub Releases 以分片（`.part`）發布（單檔 2 GiB 上限），下載後用 `join-iso.sh` 合併並以 `SHA256SUMS` 驗證。

**禁止**在 Hermes 建置機或 wastebase 上託管 ISO 下載鏡像。

## 目錄

| 路徑 | 說明 |
|------|------|
| `docs/` | 下載站靜態頁（GitHub Pages 自動部署） |
| `docs/releases.json` | 所有 ISO 版本清單（自動產生） |
| `scripts/generate-manifest.sh` | 從本機 ISO 目錄 + GitHub Release 產生 manifest |
| `scripts/publish-github-release.sh` | 分片並上傳單一版本至 GitHub Release |
| `scripts/join-iso.sh` | 合併下載的分片 |

## 發布新版本

```bash
# 1. 上傳 ISO 分片至 GitHub Release
./scripts/publish-github-release.sh 0.6.2.5

# 2. 更新 manifest（GitHub URL）
./scripts/generate-manifest.sh

# 3. 推送 manifest / 網站變更（GitHub Pages 自動部署）
git add docs/releases.json docs/index.html
git commit -m "chore: update releases manifest"
git push
```

## 使用者下載與驗證

1. 開啟 https://strawcoding.github.io/strawwu-public/ 或 https://github.com/StrawCoding/strawwu-public/releases
2. 下載全部 `*.part`、`SHA256SUMS`、`join-iso.sh`
3. 合併並驗證：

```bash
chmod +x join-iso.sh
./join-iso.sh StrawWU-0.6.2.5-amd64.iso StrawWU-0.6.2.5-amd64.iso.*.part
sha256sum -c SHA256SUMS
```

## 備註

- ISO 不放入 git tree（僅 manifest + 靜態網站在 repo 內）
- 首頁自動顯示 `releases.json` 中 `latest` 欄位的最新版本
- `sync-release-assets.sh` 與本機 CDN 部署已停用
