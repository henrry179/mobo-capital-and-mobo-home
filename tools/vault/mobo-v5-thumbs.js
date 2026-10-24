// 莫伯双站 V5 · ⚙4 缩略图/封面生成器（便携方案：sharp + pdfjs-dist + @napi-rs/canvas）
// 纪律：金库 10–80 资产区只读；产物先落临时区暂存，install 仅向 80-Site-Release 新增文件；
//       沿用 mobo-v5-build.js 的 isQuarantine/密钥隔离语义；重复件只登记不删除。
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const sharp = require('sharp');
const { createCanvas } = require('@napi-rs/canvas');

const VAULT = 'E:/01-文档资料/报告与规划/MoBo-Content-Vault-v5';
const INDEX = path.join(VAULT, '00-INDEX');
const REL80 = '80-Site-Release';
const sharedDir = path.join(VAULT, REL80, 'shared');
const STAGE = 'D:/DataRedirect/Temp/opencode/mobo-v5/thumbs-staging';
const REPORT_DIR = 'D:/DataRedirect/Temp/opencode/mobo-v5';
const ROUTING = path.join(INDEX, 'SITE-ROUTING.csv');
const LIMIT_BYTES = 60 * 1024;           // 列表图硬上限（README 规格）
const LONG_EDGE = 480;
const QUAL_STEPS = [82, 80, 78, 76, 72, 66, 60, 52, 44, 36];
const SHRINK_WIDTHS = [440, 384, 320, 260, 200];

// ---- 密钥隔离规则（沿用 mobo-v5-build.js，不放宽）----
const QUARANTINE_PATHS = new Set([
  '01-工作与项目\\AutopilotTradeBoMo\\010-分析报告\\CLAUDE_API_FIX_COMPLETE.md',
  '01-工作与项目\\AutopilotTradeBoMo\\010-分析报告\\AUTO_CHECK_REPORT.md',
  '01-工作与项目\\AutopilotTradeBoMo\\01_原始文档\\mobo-openclaw-setup-final.sh',
  '01-工作与项目\\WorkFiles\\WorkAnalysis\\WorkAnalysis\\dsapi.py',
  'hermes-migration\\henrry-push\\hermes\\config.yaml',
  'hermes-migration\\henrry-push\\hermes\\state-snapshots-2026-07-21\\config.yaml',
]);
const isQuarantine = rel => QUARANTINE_PATHS.has(rel) ||
  /Claude code\\(\.claude|backups\\original)\\projects\\.*\.jsonl$/i.test(rel) ||
  /Claude code\\backups\\original\\.*settings\.json$/i.test(rel);

// ---- CSV（RFC4180，与 build 写盘格式一致）----
function parseCsv(text) {
  if (text.charCodeAt(0) === 0xFEFF) text = text.slice(1);
  const rows = []; let row = [], field = '', inQ = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQ) { if (c === '"') { if (text[i + 1] === '"') { field += '"'; i++; } else inQ = false; } else field += c; }
    else if (c === '"') inQ = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\r') {}
    else if (c === '\n') { row.push(field); field = ''; if (row.length > 1 || row[0] !== '') rows.push(row); row = []; }
    else field += c;
  }
  if (field !== '' || row.length) { row.push(field); rows.push(row); }
  return rows;
}
function loadThumbItems() {
  const rows = parseCsv(fs.readFileSync(ROUTING, 'utf8'));
  const idx = Object.fromEntries(rows[0].map((h, i) => [h, i]));
  const items = [];
  for (const r of rows.slice(1)) {
    const key = r[idx.thumbnail_key];
    if (!key) continue;
    const m = key.match(/^(thumbnails|covers\/pdf)\/([0-9a-f]{2})\/([0-9a-f]{64})\.webp$/);
    if (!m) throw new Error('thumbnail_key 格式异常: ' + key);
    items.push({
      asset_id: r[idx.asset_id], site: r[idx.site], section: r[idx.section],
      visibility: r[idx.visibility], rel: r[idx.vault_path], key,
      kind: m[1] === 'thumbnails' ? 'image' : 'pdf', sha: m[3],
    });
  }
  return items;
}

// ---- 并发池（沿用 build 的 worker-pool 模式）----
async function pool(items, n, fn, label) {
  let i = 0, done = 0;
  async function worker() {
    while (i < items.length) {
      const k = i++;
      try { await fn(items[k], k); } catch (e) { e.itemKey = items[k].key; throw e; }
      done++;
      if (done % (label === 'pdf' ? 50 : 400) === 0 || done === items.length)
        console.log(`  [${label}] ${done}/${items.length}`);
    }
  }
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, worker));
}
const sha256File = async f => {
  const h = crypto.createHash('sha256');
  await new Promise((res, rej) => {
    const s = fs.createReadStream(f);
    s.on('error', rej); s.on('data', d => h.update(d)); s.on('end', res);
  });
  return h.digest('hex');
};
const stats = { image: [], pdf: [] };

// ---- 编码：按 60KB 上限降质降档 ----
async function encodeCap(input, kind) {
  for (const width of [LONG_EDGE, ...SHRINK_WIDTHS]) {
    for (const quality of QUAL_STEPS) {
      // 先 rotate（EXIF 方向）再 resize（长边压档）；webp 输出默认剥离全部元数据（GPS/相机/作者）
      const buf = await (kind === 'raw-png' ? sharp(input) : sharp(input, { failOn: 'none' }))
        .rotate().resize(width, width, { fit: 'inside', withoutEnlargement: true })
        .webp({ quality }).toBuffer();
      if (buf.length <= LIMIT_BYTES) return { buf, width, quality, oversize: false };
    }
  }
  const buf = await (kind === 'raw-png' ? sharp(input) : sharp(input, { failOn: 'none' }))
    .rotate().resize(200, 200, { fit: 'inside', withoutEnlargement: true })
    .webp({ quality: 30 }).toBuffer();
  return { buf, width: 200, quality: 30, oversize: buf.length > LIMIT_BYTES };
}
// 图片管线：sharp 直读源文件（读取的是金库副本），默认剥离全部 EXIF/GPS/相机/作者
async function makeThumb(srcAbs) {
  return encodeCap(srcAbs, 'img');
}
// PDF 管线：pdfjs 首页 render → canvas → PNG → sharp
async function makeCover(srcAbs) {
  const pdfjs = await import('pdfjs-dist/legacy/build/pdf.mjs');
  const pkgDir = path.dirname(require.resolve('pdfjs-dist/package.json'));
  const mkUrl = d => 'file:///' + pkgDir.replace(/\\/g, '/') + '/' + d + '/';
  const task = pdfjs.getDocument({
    data: new Uint8Array(fs.readFileSync(srcAbs)),
    cMapUrl: mkUrl('cmaps'), cMapPacked: true,
    standardFontDataUrl: mkUrl('standard_fonts'),
    isEvalSupported: false, verbosity: 0,
  });
  try {
    const doc = await task.promise;
    const page = await doc.getPage(1);
    const vp0 = page.getViewport({ scale: 1 });
    const longEdge = Math.min(LONG_EDGE, Math.max(vp0.width, vp0.height)) || LONG_EDGE;
    const scale = longEdge / Math.max(vp0.width, vp0.height);
    const vp = page.getViewport({ scale });
    const canvas = createCanvas(Math.max(1, Math.round(vp.width)), Math.max(1, Math.round(vp.height)));
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = '#ffffff'; ctx.fillRect(0, 0, canvas.width, canvas.height);
    await page.render({ canvasContext: ctx, viewport: vp }).promise;
    const png = canvas.toBuffer('image/png');
    return encodeCap(png, 'raw-png');
  } finally { try { await task.destroy(); } catch {} }
}

// ================= 子命令 =================
const failures = [];
async function cmdVerify(items, opts) {
  const uniqSha = new Map();
  for (const it of items) if (!uniqSha.has(it.sha)) uniqSha.set(it.sha, it);
  console.log(`verify: rows=${items.length} uniqueSha=${uniqSha.size}`);
  let done = 0, missing = 0, mismatch = 0;
  const bad = [];
  await pool([...uniqSha.values()], 6, async it => {
    const abs = path.join(VAULT, it.rel);
    done++;
    if ((done & 255) === 0) console.log(`  verify ${done}/${uniqSha.size}`);
    if (!fs.existsSync(abs)) { missing++; bad.push({ sha: it.sha, rel: it.rel, reason: 'MISSING' }); return; }
    const real = await sha256File(abs);
    if (real !== it.sha) { mismatch++; bad.push({ sha: it.sha, rel: it.rel, reason: 'SHA_MISMATCH', real }); }
    else if (isQuarantine(it.rel)) { bad.push({ sha: it.sha, rel: it.rel, reason: 'QUARANTINE_HIT' }); }
  }, 'verify');
  console.log(`verify: ✅ complete. missing=${missing} mismatch=${mismatch} quarantineHit=${bad.filter(b => b.reason === 'QUARANTINE_HIT').length}`);
  fs.writeFileSync(path.join(REPORT_DIR, 'thumbs-verify.json'), JSON.stringify({ rows: items.length, uniqueSha: uniqSha.size, bad, ok: bad.length === 0 }, null, 2));
  return bad.length === 0;
}
async function cmdRender(items, opts) {
  const uniq = new Map(); // key -> item（同 SHA 同 key，天然去重）
  for (const it of items) if (!uniq.has(it.key)) uniq.set(it.key, it);
  const list = [...uniq.values()];
  console.log(`render: keys=${list.length} (image=${list.filter(x => x.kind === 'image').length} pdf=${list.filter(x => x.kind === 'pdf').length}) -> ${STAGE}`);
  if (fs.existsSync(STAGE)) fs.rmSync(STAGE, { recursive: true, force: true });
  fs.mkdirSync(STAGE, { recursive: true });
  let oversize = 0, n = 0, written = 0;
  await pool(list, opts.limit ? 1 : 6, async it => {
    if (opts.limit && n >= opts.limit) return;
    n++;
    if (isQuarantine(it.rel)) { failures.push({ key: it.key, reason: 'QUARANTINE_HIT' }); return; }
    const abs = path.join(VAULT, it.rel);
    try {
      const r = it.kind === 'image' ? await makeThumb(abs) : await makeCover(abs);
      const outAbs = path.join(STAGE, ...it.key.split('/'));
      fs.mkdirSync(path.dirname(outAbs), { recursive: true });
      fs.writeFileSync(outAbs, r.buf);
      written++;
      if (r.oversize) { oversize++; failures.push({ key: it.key, reason: 'OVERSIZE', bytes: r.buf.length }); }
      stats[it.kind === 'image' ? 'image' : 'pdf'].push({ key: it.key, bytes: r.buf.length, w: r.width, q: r.quality });
    } catch (e) { failures.push({ key: it.key, rel: it.rel, reason: 'RENDER_ERROR', error: String(e && e.message || e).slice(0, 200) }); }
  }, 'pdf');
  console.log(`render: written=${written}/${list.length} oversize=${oversize} failures=${failures.length}`);
  fs.writeFileSync(path.join(REPORT_DIR, 'thumbs-render.json'), JSON.stringify({ keys: list.length, written, oversize, failures, stats: { image: stats.image.length, pdf: stats.pdf.length } }, null, 2));
  return failures.filter(f => f.reason !== 'OVERSIZE').length === 0;
}
async function cmdInstall(items) {
  const uniq = new Map(); for (const it of items) if (!uniq.has(it.key)) uniq.set(it.key, it);
  const list = [...uniq.values()];
  const renderLog = JSON.parse(fs.readFileSync(path.join(REPORT_DIR, 'thumbs-render.json'), 'utf8'));
  if (renderLog.failures.some(f => f.reason !== 'OVERSIZE')) throw new Error('render 阶段存在失败，禁止 install');
  let copied = 0; const errors = [];
  const re = /^(thumbnails|covers\/pdf)\/[0-9a-f]{2}\/[0-9a-f]{64}\.webp$/;
  for (const it of list) {
    if (!re.test(it.key)) { errors.push({ key: it.key, reason: 'KEY_SHAPE' }); continue; }
    const src = path.join(STAGE, ...it.key.split('/'));
    const dst = path.join(sharedDir, ...it.key.split('/'));
    if (!fs.existsSync(src) || fs.statSync(src).size === 0) { errors.push({ key: it.key, reason: 'STAGE_MISSING' }); continue; }
    if (fs.existsSync(dst)) { if (fs.statSync(dst).size === fs.statSync(src).size) copied++; else errors.push({ key: it.key, reason: 'DST_EXISTS_DIFF' }); continue; }
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.copyFileSync(src, dst); copied++;
  }
  console.log(`install: copied=${copied}/${list.length} errors=${errors.length}`);
  fs.writeFileSync(path.join(REPORT_DIR, 'thumbs-install.json'), JSON.stringify({ copied, expected: list.length, errors }, null, 2));
  return errors.length === 0;
}
async function cmdAudit(items) {
  const uniq = new Map(); for (const it of items) if (!uniq.has(it.key)) uniq.set(it.key, it);
  const list = [...uniq.values()];
  let present = 0, missing = [], bytes = 0, undecodable = 0, vault80Extra = 0;
  for (const it of list) {
    const dst = path.join(sharedDir, ...it.key.split('/'));
    if (!fs.existsSync(dst)) { missing.push(it.key); continue; }
    const s = fs.statSync(dst); bytes += s.size; present++;
    try { await sharp(dst).metadata(); } catch { undecodable++; }
  }
  vault80Extra = fs.readdirSync(path.join(VAULT, REL80), { recursive: true }).length;
  const idxFiles = fs.readdirSync(INDEX).filter(f => fs.statSync(path.join(INDEX, f)).isFile()).length;
  const summary = {
    expectedKeys: list.length, present, missing: missing.length, bytes, underLimit: undecodable === 0,
    undecodable, gib: +(bytes / 1073741824).toFixed(4), indexFiles: idxFiles,
    releaseEntries: vault80Extra, generatedAt: new Date().toISOString(),
  };
  console.log('audit:', JSON.stringify(summary));
  fs.writeFileSync(path.join(REPORT_DIR, 'thumbs-summary.json'), JSON.stringify(summary, null, 2));
  return missing.length === 0 && undecodable === 0 && idxFiles === 14;
}

(async () => {
  const cmd = process.argv[2];
  const opts = { limit: process.argv.includes('--limit') ? Number(process.argv[process.argv.indexOf('--limit') + 1]) : 0 };
  if (!fs.existsSync(REPORT_DIR)) fs.mkdirSync(REPORT_DIR, { recursive: true });
  const items = loadThumbItems();
  const img = items.filter(i => i.kind === 'image').length, pdf = items.filter(i => i.kind === 'pdf').length;
  console.log(`载入: rows=${items.length} image=${img} pdf=${pdf}`);
  if (img !== 2440 || pdf !== 279) throw new Error(`数量核对失败: image=${img}(期望2440) pdf=${pdf}(期望279)`);
  const uniq = new Map(); for (const it of items) if (!uniq.has(it.key)) uniq.set(it.key, it);
  console.log(`唯一 key=${uniq.size}（重复 SHA 计 ${items.length - uniq.size} 条，只登记不删除源）`);
  let ok;
  if (cmd === 'verify') ok = await cmdVerify(items, opts);
  else if (cmd === 'render') ok = await cmdRender(items, opts);
  else if (cmd === 'install') ok = await cmdInstall(items);
  else if (cmd === 'audit') ok = await cmdAudit(items);
  else throw new Error('用法: node mobo-v5-thumbs.js verify|render|install|audit [--limit N]');
  console.log(ok ? '✅ ' + cmd + ' 通过' : '❌ ' + cmd + ' 未通过');
  process.exit(ok ? 0 : 1);
})().catch(e => { console.error('FATAL', e && e.message || e); if (failures.length) { fs.mkdirSync(REPORT_DIR, { recursive: true }); fs.writeFileSync(path.join(REPORT_DIR, 'thumbs-fail.json'), JSON.stringify(failures, null, 2)); } process.exit(1); });
