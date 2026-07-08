#!/usr/bin/env node
/**
 * Stream GitHub Release assets with CORS for browser ISO join.
 * Follows GitHub → release-assets redirects server-side (nginx cannot).
 */
import http from 'node:http'
import https from 'node:https'

const PORT = Number(process.env.GH_RELEASE_PROXY_PORT || 3911)
const ALLOWED_PREFIX =
  'https://github.com/StrawCoding/strawwu-public/releases/download/'
const MAX_REDIRECTS = 8

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
  'Access-Control-Allow-Headers': 'Range, Accept',
  'Access-Control-Max-Age': '86400',
  'Access-Control-Expose-Headers':
    'Content-Length, Content-Range, Accept-Ranges, Content-Type, Content-Disposition',
}

function pickHeaders(up) {
  const out = {}
  for (const key of [
    'content-type',
    'content-length',
    'content-range',
    'accept-ranges',
    'content-disposition',
    'etag',
    'last-modified',
  ]) {
    if (up.headers[key]) out[key] = up.headers[key]
  }
  return out
}

function follow(url, req, res, redirects = 0) {
  const lib = url.startsWith('https:') ? https : http
  const target = new URL(url)
  const opts = {
    method: req.method,
    hostname: target.hostname,
    port: target.port || (url.startsWith('https:') ? 443 : 80),
    path: `${target.pathname}${target.search}`,
    headers: {
      Host: target.host,
      'User-Agent': 'strawwu-gh-release-proxy/1.0',
    },
  }
  if (req.headers.range) opts.headers.Range = req.headers.range
  if (req.headers.accept) opts.headers.Accept = req.headers.accept

  const upReq = lib.request(opts, (up) => {
    const code = up.statusCode || 502
    if ([301, 302, 303, 307, 308].includes(code) && up.headers.location && redirects < MAX_REDIRECTS) {
      const next = new URL(up.headers.location, url).toString()
      up.resume()
      return follow(next, req, res, redirects + 1)
    }
    res.writeHead(code, { ...CORS, ...pickHeaders(up) })
    if (req.method === 'HEAD') {
      up.resume()
      return res.end()
    }
    up.pipe(res)
  })
  upReq.on('error', (err) => {
    if (!res.headersSent) {
      res.writeHead(502, { ...CORS, 'Content-Type': 'text/plain; charset=utf-8' })
    }
    res.end(`Upstream error: ${err.message}`)
  })
  upReq.end()
}

const server = http.createServer((req, res) => {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, CORS)
    return res.end()
  }
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, CORS)
    return res.end('Method not allowed')
  }

  const path = decodeURIComponent(req.url || '').replace(/^\/gh-proxy\/?/, '').replace(/^\//, '')
  if (!path) {
    res.writeHead(200, { ...CORS, 'Content-Type': 'text/plain; charset=utf-8' })
    return res.end('StrawWU GitHub Release CORS proxy')
  }

  const target = `${ALLOWED_PREFIX}${path}`
  if (!target.startsWith(ALLOWED_PREFIX)) {
    res.writeHead(403, CORS)
    return res.end('Forbidden')
  }

  follow(target, req, res)
})

server.listen(PORT, '127.0.0.1', () => {
  console.log(`gh-release-proxy listening on 127.0.0.1:${PORT}`)
})
