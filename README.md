# StrawWU Public

公開發行倉庫：StrawWU ISO 下載站與版本清單。

- **下載站（GitHub Pages）**：https://strawcoding.github.io/strawwu-public/
- **ISO 檔案（CDN 直連）**：https://download.strawwu.org/releases/v&lt;version&gt;/StrawWU-&lt;version&gt;-amd64.iso
- **GitHub Release**：僅 SHA256SUMS 與版本說明（非 ISO 本體）

ISO 約 4–5 GiB。GitHub Release / LFS 單檔上限 **2 GiB**，無法存放完整 ISO，因此採 **Cloudflare R2**（或相容 S3）託管**單一完整 `.iso` 直連下載**，禁止分片。

**禁止**在 Hermes 建置機或 wastebase tunnel 上託管 ISO 下載鏡像。

## 目錄

| 路徑 | 說明 |
|------|------|
| `docs/` | 下載站靜態頁（GitHub Pages 自動部署） |
| `docs/releases.json` | 所有 ISO 版本清單（自動產生） |
| `scripts/setup-iso-cdn-r2.sh` | 建立 R2 bucket 並產生 `iso-cdn.env` 範本 |
| `scripts/publish-github-release.sh` | 上傳完整 ISO 至 CDN + 更新 GitHub Release |
| `scripts/generate-manifest.sh` | 從本機 ISO + CDN / GitHub 產生 manifest |

## 首次設定（R2 + download.strawwu.org）

```bash
export STRAWWU_CF_API_TOKEN='...'   # strawwu.org Cloudflare 帳號
./scripts/setup-iso-cdn-r2.sh
# 依輸出指示：R2 API token、Custom Domain download.strawwu.org（取代 tunnel）
source scripts/iso-cdn.env
```

## 發布新版本

```bash
source scripts/iso-cdn.env
./scripts/publish-github-release.sh 0.6.2.5
./scripts/generate-manifest.sh
git add docs/releases.json docs/index.html
git commit -m "chore: update releases manifest"
git push
```

## 使用者下載與驗證

1. 開啟 https://strawcoding.github.io/strawwu-public/ 或 manifest 中的 `iso_url`
2. 直接下載完整 `StrawWU-<version>-amd64.iso`（單檔，無分片）
3. 從 GitHub Release 或 CDN 下載 `SHA256SUMS` 並驗證：

```bash
sha256sum -c SHA256SUMS
```

直連 URL 格式：

```
https://download.strawwu.org/releases/v<version>/StrawWU-<version>-amd64.iso
```

## 備註

- ISO 不放入 git tree（僅 manifest + 靜態網站在 repo 內）
- 舊版 `.part` 分片會在重新發布時自 GitHub Release 移除
- `sync-release-assets.sh` 與本機 1Panel ISO 鏡像已停用
