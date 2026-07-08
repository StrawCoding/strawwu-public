/** Stream GitHub Release assets with CORS for strawwu-public browser ISO join. */
const ALLOWED_PREFIX =
  'https://github.com/StrawCoding/strawwu-public/releases/download/'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
  'Access-Control-Allow-Headers': 'Range, Accept',
  'Access-Control-Max-Age': '86400',
  'Access-Control-Expose-Headers':
    'Content-Length, Content-Range, Accept-Ranges, Content-Type, Content-Disposition',
}

export default {
  async fetch(request) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS })
    }
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method not allowed', { status: 405, headers: CORS })
    }

    const url = new URL(request.url)
    let target = url.searchParams.get('url')
    if (!target) {
      const path = decodeURIComponent(url.pathname.replace(/^\/+/, ''))
      if (!path) {
        return new Response('StrawWU GitHub Release CORS proxy (GET /vX.Y.Z.W/file.part)', {
          headers: CORS,
        })
      }
      target = `${ALLOWED_PREFIX}${path}`
    }

    if (!target.startsWith(ALLOWED_PREFIX)) {
      return new Response('Forbidden', { status: 403, headers: CORS })
    }

    const upstreamHeaders = new Headers()
    const range = request.headers.get('Range')
    if (range) upstreamHeaders.set('Range', range)
    const accept = request.headers.get('Accept')
    if (accept) upstreamHeaders.set('Accept', accept)

    const upstream = await fetch(target, {
      method: request.method,
      headers: upstreamHeaders,
      redirect: 'follow',
    })

    const headers = new Headers(upstream.headers)
    for (const [k, v] of Object.entries(CORS)) headers.set(k, v)

    return new Response(request.method === 'HEAD' ? null : upstream.body, {
      status: upstream.status,
      headers,
    })
  },
}
