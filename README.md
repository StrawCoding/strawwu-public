# StrawWU Public

公開發行倉庫：StrawWU ISO 下載站與版本清單。

- **下載站（GitHub Pages）**：https://strawcoding.github.io/strawwu-public/
- **ISO 檔案（GitHub Release）**：`releases/download/v<version>/`（分片；瀏覽器下載後本機合併或 `join-iso.sh`）

ISO 約 4–5 GiB。GitHub Release 單檔上限 **2 GiB**，因此以分片上傳；下載頁可按 **「下載並合併 ISO」** 在瀏覽器內抓取分片並組裝（經 `download.strawwu.org/gh-proxy` CORS 串流代理，不儲存 ISO）。

**禁止**在 Hermes 建置機上託管 ISO 鏡像；`gh-proxy` 僅串流 GitHub Release，不落地快取。

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
2. 按 **「下載並合併 ISO」**（Chromium 系瀏覽器；會提示選擇儲存位置）
3. 若自動合併不可用，可改下載分片後按「合併本機分片」，或執行 `join-iso.sh`
4. 驗證：

```bash
curl -fsSLO https://github.com/StrawCoding/strawwu-public/releases/download/v<version>/SHA256SUMS
sha256sum -c SHA256SUMS
```

## 備註

- `iso/` 倉庫目錄已停用；ISO 僅透過 GitHub Release 發布
- `sync-release-assets.sh` 與本機 1Panel ISO 鏡像已停用
