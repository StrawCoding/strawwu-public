/**
 * StrawWU ISO download helpers.
 * GitHub Release assets block cross-origin fetch (no CORS), so remote join rarely works.
 * Preferred flow: download parts via links, then merge locally (file picker) or join-iso.sh.
 */
export function isoParts(release) {
  if (!release?.parts?.length) return []
  return release.parts
    .filter((p) => p.name?.endsWith('.part'))
    .sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true }))
}

export function hasChunkedParts(release) {
  return isoParts(release).length > 0
}

export function supportsSavePicker() {
  return typeof window !== 'undefined' && typeof window.showSaveFilePicker === 'function'
}

export function supportsOpenPicker() {
  return typeof window !== 'undefined' && typeof window.showOpenFilePicker === 'function'
}

let remoteFetchProbe = null

/** True only if GitHub Release parts are readable from this origin (usually false). */
export async function probeRemotePartFetch(release) {
  if (remoteFetchProbe !== null) return remoteFetchProbe
  const parts = isoParts(release)
  if (!parts.length) {
    remoteFetchProbe = false
    return false
  }
  const probe = parts.reduce((a, b) => ((a.size || 0) <= (b.size || 0) ? a : b))
  try {
    const resp = await fetch(probe.url, { method: 'GET', headers: { Range: 'bytes=0-0' } })
    remoteFetchProbe = resp.ok || resp.status === 206
  } catch {
    remoteFetchProbe = false
  }
  return remoteFetchProbe
}

export function canRemoteFetchJoin(release) {
  return remoteFetchProbe === true && hasChunkedParts(release) && supportsSavePicker()
}

export function canLocalMerge(release) {
  return hasChunkedParts(release) && supportsSavePicker() && supportsOpenPicker()
}

/** @deprecated use hasChunkedParts / canLocalMerge */
export function canBrowserJoin(release) {
  return canLocalMerge(release) || canRemoteFetchJoin(release)
}

export function releaseDownloadBase(release) {
  const parts = isoParts(release)
  if (!parts.length) return null
  const url = parts[0].url
  return url.slice(0, url.lastIndexOf('/'))
}

function reportProgress(onProgress, written, totalBytes) {
  if (typeof onProgress === 'function') {
    onProgress({
      written,
      totalBytes,
      percent: totalBytes ? (written / totalBytes) * 100 : 0,
    })
  }
}

export async function mergeLocalParts(release, { onProgress } = {}) {
  const expected = isoParts(release)
  if (!expected.length) {
    throw new Error('No ISO parts in release manifest')
  }
  if (!supportsOpenPicker() || !supportsSavePicker()) {
    throw new Error('此瀏覽器不支援本機合併；請改用 join-iso.sh')
  }

  const filename = release.filename || `StrawWU-${release.version}-amd64.iso`
  const totalBytes = release.size || expected.reduce((sum, p) => sum + (p.size || 0), 0)

  const picked = await window.showOpenFilePicker({
    multiple: true,
    types: [{ description: 'ISO parts', accept: { 'application/octet-stream': ['.part'] } }],
  })
  const files = [...picked].sort((a, b) =>
    a.name.localeCompare(b.name, undefined, { numeric: true }),
  )
  const names = new Set(files.map((f) => f.name))
  const missing = expected.filter((p) => !names.has(p.name))
  if (missing.length) {
    throw new Error(`缺少分片：${missing.map((p) => p.name).join(', ')}`)
  }

  const handle = await window.showSaveFilePicker({
    suggestedName: filename,
    types: [{ description: 'ISO image', accept: { 'application/x-iso9660-image': ['.iso'] } }],
  })
  const writable = await handle.createWritable()
  let written = 0

  try {
    for (const part of expected) {
      const file = files.find((f) => f.name === part.name)
      const reader = file.stream().getReader()
      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        await writable.write(value)
        written += value.byteLength
        reportProgress(onProgress, written, totalBytes)
      }
    }
  } catch (err) {
    try {
      await writable.abort()
    } catch {
      /* ignore */
    }
    throw err
  }

  await writable.close()
  reportProgress(onProgress, written, totalBytes)
  return { filename, bytes: written }
}

export async function downloadJoinedIso(release, { onProgress } = {}) {
  if (remoteFetchProbe === false) {
    throw new Error(
      'GitHub Release 分片無法跨網域抓取（CORS）。請先下載分片，再按「合併本機分片」或使用 join-iso.sh。',
    )
  }

  const parts = isoParts(release)
  if (!parts.length) {
    throw new Error('No ISO parts in release manifest')
  }
  const filename = release.filename || `StrawWU-${release.version}-amd64.iso`
  const totalBytes = release.size || parts.reduce((sum, p) => sum + (p.size || 0), 0)
  let written = 0

  if (!supportsSavePicker()) {
    const fallback = release.release_url || release.download_url
    if (fallback) window.open(fallback, '_blank', 'noopener')
    throw new Error('此瀏覽器無法直接儲存大檔；已開啟 GitHub Release 頁面')
  }

  const handle = await window.showSaveFilePicker({
    suggestedName: filename,
    types: [{ description: 'ISO image', accept: { 'application/x-iso9660-image': ['.iso'] } }],
  })
  const writable = await handle.createWritable()

  try {
    for (const part of parts) {
      const resp = await fetch(part.url)
      if (!resp.ok) {
        throw new Error(`Failed to fetch ${part.name}: HTTP ${resp.status}`)
      }
      const reader = resp.body?.getReader()
      if (!reader) {
        throw new Error(`No response body for ${part.name}`)
      }
      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        await writable.write(value)
        written += value.byteLength
        reportProgress(onProgress, written, totalBytes)
      }
    }
  } catch (err) {
    try {
      await writable.abort()
    } catch {
      /* ignore */
    }
    throw err
  }

  await writable.close()
  reportProgress(onProgress, written, totalBytes)
  return { filename, bytes: written }
}
