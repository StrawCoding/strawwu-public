/**
 * Download a complete StrawWU ISO from GitHub Release parts.
 * Uses the File System Access API when available; falls back to release page.
 */
export function isoParts(release) {
  if (!release?.parts?.length) return []
  return release.parts
    .filter((p) => p.name?.endsWith('.part'))
    .sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true }))
}

export function canBrowserJoin(release) {
  return isoParts(release).length > 0 && typeof window !== 'undefined'
}

export function supportsSavePicker() {
  return typeof window !== 'undefined' && typeof window.showSaveFilePicker === 'function'
}

export async function downloadJoinedIso(release, { onProgress } = {}) {
  const parts = isoParts(release)
  if (!parts.length) {
    throw new Error('No ISO parts in release manifest')
  }
  const filename = release.filename || `StrawWU-${release.version}-amd64.iso`
  const totalBytes = release.size || parts.reduce((sum, p) => sum + (p.size || 0), 0)
  let written = 0

  const report = () => {
    if (typeof onProgress === 'function') {
      onProgress({ written, totalBytes, percent: totalBytes ? (written / totalBytes) * 100 : 0 })
    }
  }

  if (!supportsSavePicker()) {
    const fallback = release.release_url || release.download_url
    if (fallback) window.open(fallback, '_blank', 'noopener')
    throw new Error('Browser cannot save large joined ISO directly; opened source page instead')
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
        report()
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
  report()
  return { filename, bytes: written }
}
