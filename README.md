# StrawWU Public

公開發行倉庫：StrawWU ISO 下載站與版本清單。

- **下載站（GitHub Pages）**：https://strawcoding.github.io/strawwu-public/
- **ISO 檔案（Git 倉庫）**：`iso/v<version>/`（Git LFS，**單一完整 .iso，禁止分片**）
- **GitHub Release**：僅 SHA256SUMS（選用，非 ISO 本體）

ISO 約 4–5 GiB。GitHub LFS 單檔上限依方案為 **2–5 GiB**；超過時請改用 Cloudflare R2（`scripts/publish-github-release.sh` + `iso-cdn.env`）。

**禁止**在 Hermes 建置機或 wastebase tunnel 上託管 ISO 下載鏡像。

## 目錄

| 路徑 | 說明 |
|------|------|
| `docs/` | 下載站靜態頁（GitHub Pages 自動部署） |
| `docs/releases.json` | 所有 ISO 版本清單（自動產生） |
| `iso/v<version>/` | 完整 ISO + SHA256SUMS（Git LFS） |
| `scripts/publish-repo-iso.sh` | 上傳完整 ISO 至倉庫（LFS，不分片） |
| `scripts/publish-github-release.sh` | 上傳完整 ISO 至 R2 CDN（備援，>LFS 上限時） |
| `scripts/generate-manifest.sh` | 從本機 ISO + 倉庫 / CDN 產生 manifest |

## 發布新版本（倉庫，推薦）

```bash
./scripts/publish-repo-iso.sh 0.7.0.12
./scripts/generate-manifest.sh
git add docs/releases.json docs/index.html
git commit -m "chore: update releases manifest"
git push
```

若 ISO 超過 Git LFS 單檔上限，改用 R2：

```bash
source scripts/iso-cdn.env
./scripts/publish-github-release.sh 0.7.0.12
./scripts/generate-manifest.sh
```

## 使用者下載與驗證

1. 開啟 https://strawcoding.github.io/strawwu-public/
2. 點「下載 ISO」— 直連完整 `.iso`（倉庫 LFS 或 CDN）
3. 驗證：

```bash
curl -fsSLO <checksum_url>
sha256sum -c SHA256SUMS
```

## 備註

- 禁止將 ISO 切成 `.part` 分片
- `sync-release-assets.sh` 與本機 1Panel ISO 鏡像已停用
