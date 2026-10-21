/**
 * 莫伯系统控制台 · 数据契约检查
 * 用法：node services/console/tests/contract-check.mjs
 * 退出码：0 = 契约满足；1 = 存在缺失字段
 *
 * 目的：控制台消费的是"数据包 + 运行时状态"两类 JSON。
 *      这里静态断言 console.js 读取的每个键都真实存在，避免页面静默空白。
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..', '..', '..');
const readJson = p => JSON.parse(fs.readFileSync(path.join(ROOT, p), 'utf8'));
const exists = p => fs.existsSync(path.join(ROOT, p));

const problems = [];
const need = (obj, key, where) => {
  if (obj === null || obj === undefined) { problems.push(`${where}: 数据缺失`); return; }
  if (!(key in obj)) problems.push(`${where}: 缺少字段 "${key}"`);
};

// 1) 静态资源与脚本
for (const f of ['services/console/index.html', 'services/console/assets/console.css', 'services/console/assets/console.js']) {
  if (!exists(f)) problems.push(`文件缺失: ${f}`);
}
const html = exists('services/console/index.html') ? fs.readFileSync(path.join(ROOT, 'services/console/index.html'), 'utf8') : '';
for (const ref of ['assets/console.css', 'assets/console.js']) {
  if (!html.includes(ref)) problems.push(`index.html 未引用 ${ref}`);
}
if (/https?:\/\/(?!fonts\.|cdn\.tailwindcss)/.test(html)) {
  problems.push('index.html 含外部脚本/样式依赖（应保持零构建零依赖）');
}

// 2) 资本站数据包
const capitalPath = 'sites/mobocapital/data/public-data.json';
if (!exists(capitalPath)) {
  problems.push(`缺少数据包 ${capitalPath}（先运行 mobo-cli export-site）`);
} else {
  const cap = readJson(capitalPath);
  for (const k of ['macro_theses', 'strategy_playbooks', 'trade_reviews', 'publications', 'media_metrics']) need(cap, k, capitalPath);
  if (Array.isArray(cap.trade_reviews) && cap.trade_reviews.length) {
    for (const k of ['trade_code', 'underlying_ticker', 'direction', 'initial_risk_pct', 'realized_r_multiple', 'visibility']) {
      need(cap.trade_reviews[0], k, `${capitalPath}.trade_reviews[]`);
    }
  }
  if (Array.isArray(cap.publications) && cap.publications.length) {
    for (const k of ['slug', 'category', 'title', 'publish_status', 'visibility']) need(cap.publications[0], k, `${capitalPath}.publications[]`);
  }
}

// 3) 终端快照
const termPath = 'sites/mobocapital/data/terminal-snapshot.json';
if (!exists(termPath)) {
  problems.push(`缺少数据包 ${termPath}`);
} else {
  const t = readJson(termPath);
  for (const k of ['macro_indicators', 'options_vol_surface', 'portfolio_nav']) need(t, k, termPath);
  if (t.portfolio_nav) {
    for (const k of ['gross_nav', 'high_water_mark', 'net_nav', 'current_drawdown_pct', 'cumulative_r_multiple', 'risk_regime_status']) {
      need(t.portfolio_nav, k, `${termPath}.portfolio_nav`);
    }
  }
  if (Array.isArray(t.options_vol_surface) && t.options_vol_surface.length) {
    for (const k of ['asset_name', 'iv_30d', 'iv_percentile_1y', 'skew_25d', 'recommended_structure']) {
      need(t.options_vol_surface[0], k, `${termPath}.options_vol_surface[]`);
    }
  }
  if (Array.isArray(t.macro_indicators) && t.macro_indicators.length) {
    for (const k of ['indicator_name', 'indicator_code', 'raw_value', 'z_score', 'regime_tag']) {
      need(t.macro_indicators[0], k, `${termPath}.macro_indicators[]`);
    }
  }
}

// 4) 家庭站数据包（门户形态 + 原始形态）
const homePath = 'sites/mobohome/data/public-home-data.json';
if (!exists(homePath)) {
  problems.push(`缺少数据包 ${homePath}`);
} else {
  const h = readJson(homePath);
  for (const k of ['timeline_stories', 'gallery_assets', 'reading_library']) need(h, k, `${homePath}（门户形态）`);
  for (const k of ['timeline_events', 'archive_assets', 'retrospectives', 'workouts']) need(h, k, `${homePath}（原始形态）`);
  if (Array.isArray(h.timeline_stories) && h.timeline_stories.length) {
    for (const k of ['id', 'event_date', 'title', 'summary', 'importance', 'tags', 'metadata']) {
      need(h.timeline_stories[0], k, `${homePath}.timeline_stories[]`);
    }
  }
  if (Array.isArray(h.gallery_assets) && h.gallery_assets.length) {
    need(h.gallery_assets[0], 'public_thumb_url', `${homePath}.gallery_assets[]`);
  }
  if (Array.isArray(h.reading_library) && h.reading_library.length) {
    for (const k of ['id', 'title', 'author', 'status', 'rating', 'core_takeaway']) {
      need(h.reading_library[0], k, `${homePath}.reading_library[]`);
    }
  }
}

// 5) 运行时状态（可选，但有则必须完整）
const stPath = 'services/console/data/status.json';
if (exists(stPath)) {
  const st = readJson(stPath);
  for (const k of ['generated_at', 'containers', 'memory', 'host', 'git', 'db', 'services']) need(st, k, stPath);
  if (Array.isArray(st.services) && st.services.length) {
    for (const k of ['name', 'url', 'auth', 'code']) need(st.services[0], k, `${stPath}.services[]`);
  }
  if (Array.isArray(st.containers) && st.containers.length) {
    for (const k of ['name', 'status', 'mem', 'mem_pct']) need(st.containers[0], k, `${stPath}.containers[]`);
  }
}

// 6) 脱敏：公域包不得含私有字段
const PRIVATE = ['private_blotter_oss_key', 'signed_blotter_url', 'private_attachment_oss_key', 'oss_object_key', 'signed_url'];
for (const p of [capitalPath, homePath]) {
  if (!exists(p)) continue;
  const raw = fs.readFileSync(path.join(ROOT, p), 'utf8');
  for (const key of PRIVATE) if (raw.includes(key)) problems.push(`${p} 含私有字段 "${key}"（公域包禁止）`);
}

// 7) 入口卡片必须是可点击链接（不是纯文本）
if (exists('services/console/assets/console.js')) {
  const js = fs.readFileSync(path.join(ROOT, 'services/console/assets/console.js'), 'utf8');
  // 在最小 DOM 桩上执行，取出导出的纯函数
  const stub = {
    window: {},
    document: { addEventListener: () => {}, getElementById: () => null, querySelectorAll: () => [] },
    location: { hostname: 'admin.localhost', protocol: 'http:' },
    fetch: () => Promise.reject(new Error('offline')),
    setInterval: () => 0, clearInterval: () => {}, setTimeout: () => 0,
    navigator: { clipboard: { writeText: async () => {} } },
    Array, Object, JSON, Math, Date, String, Number, isFinite, isNaN, Promise, console,
  };
  stub.window.document = stub.document;
  stub.window.location = stub.location;
  try {
    const fn = new Function('window', 'document', 'location', 'fetch', 'navigator', 'setInterval', 'clearInterval', 'setTimeout', 'Array', 'Object', 'JSON', 'Math', 'Date', 'String', 'Number', 'isFinite', 'isNaN', 'Promise', 'console',
      js);
    fn(stub.window, stub.document, stub.location, stub.fetch, stub.navigator, stub.setInterval, stub.clearInterval, stub.setTimeout,
      Array, Object, JSON, Math, Date, String, Number, isFinite, isNaN, Promise, console);
    const api = stub.window.MoboConsole;
    if (!api || typeof api.buildServiceCard !== 'function') {
      problems.push('console.js 未导出 MoboConsole.buildServiceCard（契约测试入口丢失）');
    } else {
      const card = api.buildServiceCard({ name: '莫伯之家 主站', url: 'http://mobohome.localhost/', auth: '公开', code: 200 });
      if (!/<a class="svc[^"]*" href="http:\/\/mobohome\.localhost\/"/.test(card)) {
        problems.push('入口卡片未渲染为可点击 <a href>：' + card.slice(0, 90));
      }
      if (!card.includes('target="_blank"')) problems.push('入口卡片缺少 target="_blank"（新标签打开）');
      if (!/class="dot up"/.test(card)) problems.push('入口卡片缺少状态点');
      const derived = api.deriveServices();
      if (!Array.isArray(derived) || derived.length !== 6) problems.push('deriveServices 未返回 6 个入口');
      for (const s of derived) {
        if (!/^https?:\/\//.test(s.url || '')) problems.push(`兜底入口 URL 非法: ${s.url}`);
      }
    }
  } catch (e) {
    problems.push('console.js 无法在测试桩中执行: ' + e.message);
  }
}

if (problems.length) {
  console.error('契约检查未通过：');
  problems.forEach(p => console.error('  - ' + p));
  process.exit(1);
}
console.log('控制台数据契约检查通过 ✅');
