#!/usr/bin/env node
/**
 * 莫伯双站 · 本地预览网关（零依赖，Node 内置模块）
 *
 * 目的：在没有 Docker / PostgreSQL 的机器上，用与生产 Caddy 等价的方式把两个站点跑起来：
 *   - 双主站分别独立端口（等价双主域）
 *   - /data/*.json 公域短缓存 60s（等价 Caddy public_json 规则）
 *   - /internal/* 强制 BasicAuth + no-store + noindex（等价 Caddy protected 片段）
 *   - 单页应用回退 try_files {path} /index.html（等价 SPA 路由）
 *   - 统一安全响应头（等价 security_headers 片段）
 *
 * 用法：
 *   node tools/local-preview/serve.js
 *   node tools/local-preview/serve.js --capital 8080 --home 8081 --console 8082
 *
 * 环境变量：
 *   LOCAL_PREVIEW_USER  BasicAuth 用户名（默认 mobo）
 *   LOCAL_PREVIEW_PASS  BasicAuth 密码（默认 mobo-local；仅本地使用）
 */
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..', '..');
const arg = (name, dflt) => {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? Number(process.argv[i + 1]) : dflt;
};
const PORT_CAPITAL = arg('capital', 8080);
const PORT_HOME = arg('home', 8081);
const PORT_CONSOLE = arg('console', 8082);

const USER = process.env.LOCAL_PREVIEW_USER || 'mobo';
const PASS = process.env.LOCAL_PREVIEW_PASS || 'mobo-local';

const SITES = {
  capital: { name: '莫伯资本 MoBoCapital', root: path.join(ROOT, 'sites', 'mobocapital'), port: PORT_CAPITAL },
  home: { name: '莫伯之家 MoBoHome', root: path.join(ROOT, 'sites', 'mobohome'), port: PORT_HOME },
};
const CONSOLE_ROOT = __dirname;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
  '.md': 'text/markdown; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
};

const startedAt = new Date().toISOString();
const requestLog = [];

function securityHeaders(res) {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'SAMEORIGIN');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('Permissions-Policy', 'geolocation=(), microphone=(), camera=()');
  res.removeHeader('Server');
}

function authorized(req) {
  const h = req.headers.authorization || '';
  if (!h.startsWith('Basic ')) return false;
  const [u, p] = Buffer.from(h.slice(6), 'base64').toString('utf8').split(':');
  return u === USER && p === PASS;
}

function sendFile(res, file, status = 200, extraHeaders = {}) {
  const ext = path.extname(file).toLowerCase();
  const data = fs.readFileSync(file);
  res.writeHead(status, {
    'Content-Type': MIME[ext] || 'application/octet-stream',
    'Content-Length': data.length,
    ...extraHeaders,
  });
  res.end(data);
}

function json(res, obj, status = 200, extraHeaders = {}) {
  const data = Buffer.from(JSON.stringify(obj, null, 2), 'utf8');
  res.writeHead(status, { 'Content-Type': MIME['.json'], 'Content-Length': data.length, ...extraHeaders });
  res.end(data);
}

function safeJoin(root, urlPath) {
  const decoded = decodeURIComponent(urlPath.split('?')[0]);
  const target = path.resolve(root, '.' + path.posix.normalize(decoded));
  if (!target.startsWith(path.resolve(root))) return null; // 目录穿越防护
  return target;
}

/** 原始请求里出现 .. 段：浏览器会自动归一化，这是给原始客户端的兜底 */
function hasTraversal(urlPath) {
  return urlPath.split('?')[0].split('/').some(seg => seg === '..');
}

/** 单站处理：与 Caddyfile 规则等价 */
function handleSite(site, req, res) {
  const urlPath = req.url.split('?')[0];
  securityHeaders(res);

  // 0) 目录穿越兜底：显式 400，不落到 SPA 回退
  if (hasTraversal(urlPath)) {
    res.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('400 Bad Request\n');
    log(site, req, 400, 'traversal-blocked');
    return;
  }

  // 1) /internal/* → BasicAuth + no-store + noindex
  if (urlPath.startsWith('/internal/')) {
    if (!authorized(req)) {
      res.writeHead(401, {
        'WWW-Authenticate': 'Basic realm="MoBo Internal"',
        'Cache-Control': 'no-store, no-cache, must-revalidate',
        'X-Robots-Tag': 'noindex, nofollow, noarchive',
        'Content-Type': 'text/plain; charset=utf-8',
      });
      res.end('401 Unauthorized — /internal/* 需要 BasicAuth\n');
      log(site, req, 401);
      return;
    }
    let file = safeJoin(site.root, urlPath);
    if (!file || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('404 Not Found\n');
      log(site, req, 404);
      return;
    }
    sendFile(res, file, 200, {
      'Cache-Control': 'no-store, no-cache, must-revalidate',
      'X-Robots-Tag': 'noindex, nofollow, noarchive',
    });
    log(site, req, 200);
    return;
  }

  // 2) /lab/* → 实验���占位（真实 Streamlit 需 Docker 全栈）
  if (urlPath.startsWith('/lab')) {
    res.writeHead(302, { Location: `http://127.0.0.1:${PORT_CONSOLE}/lab.html` });
    res.end();
    log(site, req, 302);
    return;
  }

  // 3) /data/*.json → 公域短缓存
  if (/^\/data\/.*\.json$/.test(urlPath)) {
    const file = safeJoin(site.root, urlPath);
    if (!file || !fs.existsSync(file)) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('404 Not Found — 尚未生成数据包，请先运行：node tools/local-preview/generate-sample-data.js\n');
      log(site, req, 404);
      return;
    }
    sendFile(res, file, 200, { 'Cache-Control': 'public, max-age=60, must-revalidate' });
    log(site, req, 200);
    return;
  }

  // 4) 静态资源 → 常规分发
  let file = safeJoin(site.root, urlPath);
  if (file && fs.existsSync(file) && fs.statSync(file).isFile()) {
    sendFile(res, file, 200);
    log(site, req, 200);
    return;
  }

  // 5) SPA 回退 → index.html
  const index = path.join(site.root, 'index.html');
  if (fs.existsSync(index)) {
    sendFile(res, index, 200);
    log(site, req, 200, 'spa');
    return;
  }
  res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('404 Not Found\n');
  log(site, req, 404);
}

function log(site, req, status, extra = '') {
  const entry = { ts: new Date().toISOString(), site: site.name, method: req.method, path: req.url, status, extra };
  requestLog.push(entry);
  if (requestLog.length > 500) requestLog.shift();
  console.log(`[${entry.ts}] ${site.name} ${req.method} ${req.url} -> ${status} ${extra}`);
}

function dataStatus() {
  const files = [
    'sites/mobocapital/data/public-data.json',
    'sites/mobocapital/data/terminal-snapshot.json',
    'sites/mobocapital/internal/internal-data.json',
    'sites/mobohome/data/public-home-data.json',
    'sites/mobohome/internal/internal-home-data.json',
  ];
  return files.map(f => {
    const p = path.join(ROOT, f);
    const ok = fs.existsSync(p);
    const stat = ok ? fs.statSync(p) : null;
    let bytes = 0;
    if (ok) {
      try { bytes = JSON.parse(fs.readFileSync(p, 'utf8')).length ? fs.statSync(p).size : 0; } catch (e) { bytes = stat.size; }
    }
    return { file: f, present: ok, size: bytes, mtime: ok ? stat.mtime.toISOString() : null };
  });
}

function handleConsole(req, res) {
  const urlPath = req.url.split('?')[0];
  securityHeaders(res);

  if (hasTraversal(urlPath)) {
    res.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('400 Bad Request\n');
    return;
  }

  if (urlPath === '/status.json') {
    json(res, {
      ok: true,
      started_at: startedAt,
      mode: 'local-preview (no Docker)',
      ports: { capital: PORT_CAPITAL, home: PORT_HOME, console: PORT_CONSOLE },
      sites: Object.values(SITES).map(s => ({
        name: s.name, port: s.port, root: path.relative(ROOT, s.root).split(path.sep).join('/'),
        url: `http://127.0.0.1:${s.port}/`,
      })),
      internal: { user: USER, note: '仅本地；生产请使用 20+ 位强密码' },
      data_files: dataStatus(),
      recent_requests: requestLog.slice(-20),
    });
    return;
  }

  if (urlPath === '/lab.html') {
    const f = path.join(CONSOLE_ROOT, 'lab-placeholder.html');
    if (fs.existsSync(f)) { sendFile(res, f, 200); return; }
  }

  const f = urlPath === '/' || urlPath === '/index.html'
    ? path.join(CONSOLE_ROOT, 'architecture.html')
    : safeJoin(CONSOLE_ROOT, urlPath);
  if (!f || !fs.existsSync(f) || fs.statSync(f).isDirectory()) {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('404 Not Found\n');
    return;
  }
  sendFile(res, f, 200);
}

function makeServer(site) {
  return http.createServer((req, res) => {
    try { handleSite(site, req, res); }
    catch (e) {
      res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('500 ' + e.message);
    }
  });
}

const servers = [];
for (const site of Object.values(SITES)) {
  const s = makeServer(site);
  s.listen(site.port, '127.0.0.1', () => {
    console.log(`[preview] ${site.name.padEnd(20)} → http://127.0.0.1:${site.port}/  (root: ${path.relative(ROOT, site.root)})`);
  });
  servers.push(s);
}
const consoleSrv = http.createServer((req, res) => {
  try { handleConsole(req, res); }
  catch (e) { res.writeHead(500); res.end('500 ' + e.message); }
});
consoleSrv.listen(PORT_CONSOLE, '127.0.0.1', () => {
  console.log(`[preview] ${'架构与入口总览'.padEnd(20)} → http://127.0.0.1:${PORT_CONSOLE}/`);
  console.log(`[preview] /internal/* 认证：用户 ${USER} / 密码 ${PASS}（仅本地）`);
  console.log('[preview] Ctrl+C 停止');
});
servers.push(consoleSrv);

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => {
    console.log('\n[preview] 正在关闭…');
    servers.forEach(s => s.close());
    process.exit(0);
  });
}
