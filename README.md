# StrawWU Public

公開發行倉庫：StrawWU ISO 下載站與版本清單。

- **下載站（GitHub Pages）**：https://strawcoding.github.io/strawwu-public/
- **ISO 檔案（GitHub Release）**：`releases/download/v<version>/`（分片，瀏覽器合併）

ISO 約 4–5 GiB。GitHub Release 單檔上限 **2 GiB**，因此以分片上傳；下載頁會在瀏覽器內合併成完整 `.iso`。

**禁止**在 Hermes 建置機或 wastebase tunnel 上託管 ISO 下載鏡像。

## 目錄

| 路徑 | 說明 |
|------|------|
| `docs/` | 下載站靜態頁（GitHub Pages 自動部署） |
| `docs/releases.json` | 所有 ISO 版本清單（自動產生） |
| `scripts/publish-github-release.sh` | 上傳 ISO 分片至 GitHub Release |
| `scripts/generate-manifest.sh` | 從本機 ISO + GitHub Release 產生 manifest |

## 發布新版本

```bash
./scripts/publish-github-release.sh 0.7.0.13
./scripts/generate-manifest.sh
git add docs/releases.json docs/index.html
git commit -m "chore: update releases manifest"
git push
```

## 使用者下載與驗證

1. 開啟 https://strawcoding.github.io/strawwu-public/
2. 點「下載 ISO」— 瀏覽器抓取 Release 分片並合併
3. 驗證：

```bash
curl -fsSLO https://github.com/StrawCoding/strawwu-public/releases/download/v<version>/SHA256SUMS
sha256sum -c SHA256SUMS
```

## 備註

- `iso/` 倉庫目錄已停用；ISO 僅透過 GitHub Release 發布
- `sync-release-assets.sh` 與本機 1Panel ISO 鏡像已停用
