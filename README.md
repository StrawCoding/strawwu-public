# StrawWU Public

公開發行倉庫：StrawWU ISO 下載站與版本清單。

- **網站（GitHub Pages）**：https://strawcoding.github.io/strawwu-public/
- **ISO 鏡像**：https://apt.strawwu.org/iso/
- **GitHub Releases**：校驗碼與發行說明（ISO 超過 GitHub 2 GiB 上限，實際檔案在鏡像）

## 目錄

| 路徑 | 說明 |
|------|------|
| `docs/` | GitHub Pages 靜態下載站 |
| `docs/releases.json` | 所有 ISO 版本清單（自動產生） |
| `scripts/generate-manifest.sh` | 從本機 ISO 目錄產生 manifest |
| `scripts/sync-iso-mirror.sh` | 同步 ISO 至 apt.strawwu.org |
| `scripts/publish-github-release.sh` | 建立 GitHub Release（SHA256 + 說明） |

## 發布新版本

```bash
# 1. 同步 ISO 至公開鏡像
./scripts/sync-iso-mirror.sh

# 2. 更新 manifest
./scripts/generate-manifest.sh

# 3. 推送網站
git add docs/releases.json
git commit -m "chore: update releases manifest"
git push

# 4. 建立 GitHub Release 標籤
./scripts/publish-github-release.sh 0.6.2.5
```

## 驗證

```bash
wget https://apt.strawwu.org/iso/SHA256SUMS
sha256sum -c SHA256SUMS
```

## 備註

- ISO 檔案約 4–5 GiB，不放入 git 或 GitHub Release assets
- 首頁自動顯示 `releases.json` 中 `latest` 欄位的最新版本
