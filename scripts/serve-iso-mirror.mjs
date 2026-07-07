#!/usr/bin/env node
/**
 * Host-side ISO static server for apt.strawwu.org/iso/ (openresty cannot follow /mnt symlinks).
 */
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ISO_DIR = process.env.STRAWWU_ISO_DIR
  || '/mnt/data/code/project/StrawCoding/StrawWU/os-image/output';
const PORT = Number(process.env.STRAWWU_ISO_PORT || 9105);
const HOST = process.env.STRAWWU_ISO_HOST || '127.0.0.1';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function send(res, code, body, headers = {}) {
  res.writeHead(code, { 'Server': 'strawwu-iso-mirror', ...headers });
  res.end(body);
}

function parseVersion(name) {
  const m = name.match(/^StrawWU-(\d+\.\d+\.\d+\.\d+)-amd64\.iso$/);
  return m ? m[1] : null;
}

function listIsos() {
  return fs.readdirSync(ISO_DIR)
    .filter((f) => f.endsWith('.iso'))
    .map((f) => {
      const st = fs.statSync(path.join(ISO_DIR, f));
      return { name: f, size: st.size, mtime: st.mtime.toISOString(), version: parseVersion(f) };
    })
    .sort((a, b) => (b.version || '').localeCompare(a.version || '', undefined, { numeric: true }));
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url || '/', `http://${req.headers.host}`);
  let rel = decodeURIComponent(url.pathname.replace(/^\/+/, ''));
  if (!rel || rel === '/') {
    const latest = listIsos()[0];
    const body = JSON.stringify({ latest: latest?.name || null, files: listIsos() }, null, 2);
    return send(res, 200, body, { 'Content-Type': 'application/json; charset=utf-8' });
  }

  if (rel === 'StrawWU-latest-amd64.iso') {
    const latest = listIsos()[0];
    if (!latest) return send(res, 404, 'No ISO available\n');
    rel = latest.name;
  }

  const safe = path.basename(rel);
  if (safe !== rel) return send(res, 400, 'Bad path\n');

  const filePath = path.join(ISO_DIR, safe);
  if (!filePath.startsWith(ISO_DIR) || !fs.existsSync(filePath)) {
    return send(res, 404, 'Not found\n');
  }

  const stat = fs.statSync(filePath);
  const total = stat.size;
  const range = req.headers.range;

  if (range) {
    const m = /^bytes=(\d+)-(\d*)$/.exec(range);
    if (!m) return send(res, 416, 'Invalid range\n');
    const start = Number(m[1]);
    const end = m[2] ? Number(m[2]) : total - 1;
    if (start >= total || end >= total) return send(res, 416, 'Range not satisfiable\n');
    res.writeHead(206, {
      'Content-Range': `bytes ${start}-${end}/${total}`,
      'Accept-Ranges': 'bytes',
      'Content-Length': end - start + 1,
      'Content-Type': 'application/octet-stream',
      'Content-Disposition': `attachment; filename="${safe}"`,
    });
    fs.createReadStream(filePath, { start, end }).pipe(res);
    return;
  }

  res.writeHead(200, {
    'Content-Length': total,
    'Content-Type': 'application/octet-stream',
    'Accept-Ranges': 'bytes',
    'Content-Disposition': `attachment; filename="${safe}"`,
  });
  fs.createReadStream(filePath).pipe(res);
});

server.listen(PORT, HOST, () => {
  console.log(`strawwu-iso-mirror listening on http://${HOST}:${PORT}/ (${ISO_DIR})`);
});
