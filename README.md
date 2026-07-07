# StrawWU Public

公開發行倉庫：StrawWU ISO 下載站與版本清單。

- **網站（GitHub Pages）**：https://strawcoding.github.io/strawwu-public/
- **ISO 下載（GitHub Releases）**：https://github.com/StrawCoding/strawwu-public/releases

ISO 約 4–5 GiB，超過 GitHub 單檔 2 GiB 上限，因此每個版本以 **分片（.part）** 上傳至 GitHub Release，下載後用 `join-iso.sh` 合併。

## 目錄

| 路徑 | 說明 |
|------|------|
| `docs/` | GitHub Pages 靜態下載站 |
| `docs/releases.json` | 所有 ISO 版本清單（自動產生） |
| `scripts/generate-manifest.sh` | 從本機 ISO 目錄 + GitHub Release 產生 manifest |
| `scripts/publish-github-release.sh` | 分片並上傳單一版本至 GitHub Release |
| `scripts/publish-all-releases.sh` | 上傳所有本機 ISO |
| `scripts/join-iso.sh` | 合併下載的分片 |

## 發布新版本

```bash
# 1. 上傳 ISO 分片至 GitHub Release
./scripts/publish-github-release.sh 0.6.2.5

# 2. 更新 manifest
./scripts/generate-manifest.sh

# 3. 推送網站
git add docs/releases.json
git commit -m "chore: update releases manifest"
git push
```

一次發布所有本機 ISO：

```bash
./scripts/publish-all-releases.sh
```

## 使用者下載與驗證

1. 開啟 [GitHub Releases](https://github.com/StrawCoding/strawwu-public/releases) 或首頁「下載」按鈕
2. 下載該版本的全部 `*.part`、`SHA256SUMS`、`join-iso.sh`
3. 合併並驗證：

```bash
chmod +x join-iso.sh
./join-iso.sh StrawWU-0.6.2.5-amd64.iso StrawWU-0.6.2.5-amd64.iso.*.part
sha256sum -c SHA256SUMS
```

## 備註

- ISO 不放入 git tree（僅 manifest + 靜態網站在 repo 內）
- 首頁自動顯示 `releases.json` 中 `latest` 欄位的最新版本
