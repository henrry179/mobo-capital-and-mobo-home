/* =============================================================================
   莫伯系统控制台 · 逻辑
   数据源（全部同源，无需 CORS）：
     /api/capital/data/public-data.json      莫伯资本公域包（脱敏）
     /api/capital/data/terminal-snapshot.json 宏观/期权/NAV 快照
     /api/home/data/public-home-data.json     莫伯之家公域包（脱敏）
     /data/status.json                        运行时状态（由 collect-status.sh 生成，可缺失）
   ============================================================================= */
(function () {
  'use strict';

  /** 本机 Caddy 用绝对同源路径；GitHub Pages 用相对路径指向仓库内公域 JSON */
  function resolveAPI() {
    var pages = /\.github\.io$/i.test(location.hostname);
    if (pages) {
      return {
        capital: '../../sites/mobocapital/data/public-data.json',
        terminal: '../../sites/mobocapital/data/terminal-snapshot.json',
        home: '../../sites/mobohome/data/public-home-data.json',
        status: './data/status.json'
      };
    }
    return {
      capital: '/api/capital/data/public-data.json',
      terminal: '/api/capital/data/terminal-snapshot.json',
      home: '/api/home/data/public-home-data.json',
      status: '/data/status.json'
    };
  }
  var API = resolveAPI();

  var state = { clearance: 'PUBLIC', data: {}, status: null, errors: [] };

  // ---------------------------------------------------------------- helpers
  function $(id) { return document.getElementById(id); }
  function esc(s) {
    return String(s === null || s === undefined ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
  function num(v, d) { var n = Number(v); return isFinite(n) ? n.toFixed(d === undefined ? 2 : d) : '—'; }
  function fetchJSON(url) {
    return fetch(url, { cache: 'no-store' })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(new Error(url + ' → HTTP ' + r.status)); })
      .catch(function (e) { state.errors.push(e.message); return null; });
  }
  function fmtTime(iso) {
    if (!iso) return '—';
    var d = new Date(iso);
    return isNaN(d.getTime()) ? String(iso).slice(0, 16).replace('T', ' ') : d.toLocaleString('zh-CN', { hour12: false });
  }
  function relTime(iso) {
    if (!iso) return '—';
    var diff = (Date.now() - new Date(iso).getTime()) / 1000;
    if (isNaN(diff)) return '—';
    if (diff < 60) return Math.max(0, Math.round(diff)) + ' 秒前';
    if (diff < 3600) return Math.round(diff / 60) + ' 分钟前';
    if (diff < 86400) return Math.round(diff / 3600) + ' 小时前';
    return Math.round(diff / 86400) + ' 天前';
  }
  function visible(rec) {
    var lvl = state.clearance;
    var v = String(rec.visibility || 'PUBLIC').toUpperCase();
    if (lvl === 'INTERNAL') return true;
    if (lvl === 'LP_PROSPECT') return v === 'PUBLIC' || v === 'LP_PROSPECT';
    return v === 'PUBLIC';
  }
  function byId(id, html) { var el = $(id); if (el) el.innerHTML = html; }

  // ---------------------------------------------------------------- KPI
  function renderKPI() {
    var cap = state.data.capital || {};
    var term = state.data.terminal || {};
    var home = state.data.home || {};
    var nav = term.portfolio_nav || {};
    var st = state.status || {};
    var svc = st.services || [];
    var up = svc.filter(function (s) { return s.code === 200; }).length;

    var mem = st.memory || {};
    var lim = mem.limit_mib || 1550;
    var used = mem.used_mib || 0;
    var pct = Math.min(100, Math.round((used / lim) * 100));

    var pending = (cap.publications || []).filter(function (p) {
      return String(p.publish_status || '').toUpperCase() === 'PENDING_REVIEW';
    }).length;

    var risk = String(nav.risk_regime_status || 'NORMAL').toUpperCase();
    var riskCls = risk === 'NORMAL' ? 'good' : (risk === 'YELLOW_ALERT' ? 'warn' : 'bad');

    var items = [
      { k: 'ENTRY REACHABILITY', v: up + '/' + (svc.length || 6), s: '可达入口 / 总入口', c: up >= (svc.length || 6) ? 'good' : 'warn' },
      { k: 'MEMORY', v: used + ' MiB', s: '常驻 / 限额 ' + lim + ' MiB（' + pct + '%）', c: pct > 85 ? 'bad' : (pct > 65 ? 'warn' : 'good') },
      { k: 'NAV', v: nav.net_nav !== undefined ? num(nav.net_nav, 4) : '—', s: '回撤 ' + num(nav.current_drawdown_pct, 2) + '% · 累计R ' + num(nav.cumulative_r_multiple, 2), c: riskCls },
      { k: 'RISK REGIME', v: risk.replace(/_/g, ' '), s: nav.risk_action_note ? String(nav.risk_action_note).slice(0, 42) + '…' : '风控状态', c: riskCls },
      { k: 'PENDING REVIEW', v: String(pending), s: '待人工终审发布', c: pending > 0 ? 'warn' : 'good' },
      { k: 'THESES / PLAYS', v: (cap.macro_theses || []).length + '/' + (cap.strategy_playbooks || []).length, s: '论点 / 策略手册', c: '' },
      { k: 'TIMELINE / ASSETS', v: (home.timeline_stories || home.timeline_events || []).length + '/' + (home.gallery_assets || home.archive_assets || []).length, s: '档案事件 / 影像', c: '' },
      { k: 'LAST REFRESH', v: relTime(st.generated_at), s: fmtTime(st.generated_at), c: '' }
    ];

    byId('kpis', items.map(function (i) {
      return '<div class="kpi ' + (i.c || '') + '"><div class="k">' + esc(i.k) + '</div><div class="v">' + esc(i.v) + '</div><div class="s">' + esc(i.s) + '</div></div>';
    }).join(''));
  }

  // ---------------------------------------------------------------- 入口矩阵
  /** 兜底：没有 status.json 时，按当前域名推导同族入口（保证卡片始终是真链接） */
  function deriveServices() {
    var host = location.hostname || 'localhost';
    if (/\.github\.io$/i.test(host)) {
      var root = location.pathname.replace(/\/services\/console\/?.*$/, '/');
      return [
        { name: '莫伯资本 主站', url: root + 'sites/mobocapital/', auth: '公开', code: 200 },
        { name: '莫伯之家 主站', url: root + 'sites/mobohome/', auth: '公开', code: 200 },
        { name: '思源 知识库', url: '#', auth: '仓外', code: null },
        { name: 'n8n 自动化', url: '#', auth: '仓外', code: null },
        { name: '生命体征 实验室', url: '#', auth: '仓外', code: null },
        { name: '莫伯系统 控制台', url: root + 'services/console/', auth: '公开', code: 200 }
      ];
    }
    var parts = host.split('.');
    var isLocal = host === 'localhost' || /\.localhost$/.test(host) || host === '127.0.0.1';
    var base = isLocal ? 'localhost' : parts.slice(-2).join('.');
    var fam = isLocal ? 'localhost' : base;
    function u(label) { return 'http://' + label + '.' + fam + '/'; }
    return [
      { name: '莫伯资本 主站', url: isLocal ? 'http://localhost/' : 'http://' + base + '/', auth: '公开', code: null },
      { name: '莫伯之家 主站', url: isLocal ? 'http://mobohome.localhost/' : 'http://mobohome.' + base + '/', auth: '公开', code: null },
      { name: '思源 知识库', url: u('kb'), auth: 'BasicAuth', code: null },
      { name: 'n8n 自动化', url: u('n8n'), auth: 'BasicAuth', code: null },
      { name: '生命体征 实验室', url: u('lab'), auth: 'BasicAuth', code: null },
      { name: '莫伯系统 控制台', url: u('admin'), auth: 'BasicAuth', code: null }
    ];
  }

  /** 单个入口卡片的 HTML（导出以便做契约测试） */
  function buildServiceCard(s) {
    var dot = s.code === 200 ? 'up' : (s.code === 401 ? 'auth' : 'down');
    var stateTxt = s.code === 200 ? 'OK' : (s.code === 401 ? '需认证' : (s.code ? 'HTTP ' + s.code : '未探测'));
    var href = s.url || '#';
    var isSelf = /admin/.test(href) || /控制台/.test(s.name || '');
    var label = isSelf ? '当前页' : '打开 ↗';
    return '<a class="svc' + (isSelf ? ' self' : '') + '" href="' + esc(href) + '"' +
      (isSelf ? '' : ' target="_blank" rel="noopener"') + ' title="' + esc(href) + '">' +
      '<div class="row1"><span class="name">' + esc(s.name) + '</span>' +
      '<span class="open">' + label + '</span>' +
      '<span class="dot ' + dot + '" title="' + esc(stateTxt) + '"></span></div>' +
      '<div class="url">' + esc(s.url || '') + '</div>' +
      '<div class="tags"><span class="tag ' + (/公开/.test(s.auth) ? 'pub' : 'auth') + '">' + esc(s.auth || '') + '</span>' +
      '<span class="tag">' + esc(stateTxt) + '</span></div>' +
      '</a>';
  }

  function renderServices() {
    var st = state.status || {};
    var list = (st.services && st.services.length) ? st.services : deriveServices();
    byId('services', list.map(buildServiceCard).join(''));
  }

  // ---------------------------------------------------------------- 运行时
  function renderRuntime() {
    var st = state.status;
    if (!st) { byId('runtime', '<div class="empty">未找到 /data/status.json —— 运行 <code>bash tools/wsl/collect-status.sh</code> 生成。</div>'); return; }
    var host = st.host || {}, git = st.git || {}, backup = st.backup || {}, db = st.db || {};
    var mem = st.memory || {};

    var cells = [
      ['CONTAINERS', (st.containers || []).filter(function (c) { return c.healthy; }).length + '/' + (st.containers || []).length, 'healthy / 总数'],
      ['DISK', (host.disk_used_pct || 0) + '%', '根分区使用率'],
      ['HOST MEM', (host.mem_used_mib || 0) + ' MiB', '宿主机已用 / 总量 ' + (host.mem_total_mib || 0) + ' MiB'],
      ['GIT', String(git.commit || '—').slice(0, 8), (git.dirty ? '有未提交变更' : '工作区干净') + ' · ' + (git.branch || '')]
    ];
    var html = '<div class="rt-grid">' + cells.map(function (c) {
      return '<div class="rt-cell"><div class="k">' + esc(c[0]) + '</div><div class="v">' + esc(c[1]) + '</div><div class="k" style="margin-top:3px">' + esc(c[2]) + '</div></div>';
    }).join('') + '</div>';

    var list = (st.containers || []).map(function (c) {
      var pct = c.mem_pct || 0;
      var cls = pct > 90 ? 'bad' : (pct > 75 ? 'warn' : 'ok');
      return '<tr><td>' + esc(c.name) + '</td>' +
        '<td><span class="pill ' + (c.healthy ? 'ok' : 'warn') + '">' + esc(c.status) + '</span></td>' +
        '<td class="num">' + esc(c.mem) + '</td>' +
        '<td style="width:120px"><div class="bar ' + cls + '"><i style="width:' + Math.min(100, pct) + '%"></i></div></td></tr>';
    }).join('');
    if (list) {
      html += '<table class="t"><thead><tr><th>容器</th><th>状态</th><th class="num">内存</th><th></th></tr></thead><tbody>' + list + '</tbody></table>';
    }
    html += '<table class="t" style="margin-top:10px"><tbody>' +
      '<tr><td>最近备份</td><td class="num">' + esc(backup.last_snapshot || '未记录') + '</td><td class="num">' + esc(backup.age || '') + '</td></tr>' +
      '<tr><td>数据库计数</td><td colspan="2" class="num">时间线 ' + (db.timeline_events || 0) + ' · 交易 ' + (db.trade_reviews || 0) + ' · 发布 ' + (db.publications || 0) + ' · 待审 ' + (db.pending_review || 0) + '</td></tr>' +
      '</tbody></table>';
    byId('runtime', html);
  }

  // ---------------------------------------------------------------- 投研与风控
  function renderResearch() {
    var term = state.data.terminal || {};
    var nav = term.portfolio_nav || {};
    var inds = term.macro_indicators || [];
    var vol = term.options_vol_surface || [];
    var html = '';

    if (Object.keys(nav).length) {
      var risk = String(nav.risk_regime_status || 'NORMAL').toUpperCase();
      html += '<div class="nav-hero">' +
        '<div><div class="k">毛净值</div><div class="v">' + num(nav.gross_nav, 4) + '</div></div>' +
        '<div><div class="k">高水位</div><div class="v">' + num(nav.high_water_mark, 4) + '</div></div>' +
        '<div><div class="k">净净值</div><div class="v">' + num(nav.net_nav, 4) + '</div></div>' +
        '<div><div class="k">回撤</div><div class="v">' + num(nav.current_drawdown_pct, 2) + '%</div></div>' +
        '<div><div class="k">风控状态</div><div class="v"><span class="regime ' + esc(risk) + '">' + esc(risk.replace(/_/g, ' ')) + '</span></div></div>' +
        '</div>';
    } else {
      html += '<div class="empty">尚无 NAV 快照（用 <code>mobo-cli capital-trade --close</code> 触发触发器核算）。</div>';
    }

    if (inds.length) {
      html += '<div class="panel-head" style="margin:6px 0 6px"><span class="muted mono" style="font-size:11px">宏观先行指标</span></div>';
      html += '<table class="t"><thead><tr><th>指标</th><th>观测</th><th class="num">Z-Score</th><th>状态</th></tr></thead><tbody>' +
        inds.slice(0, 6).map(function (i) {
          return '<tr><td>' + esc(i.indicator_name || i.indicator_code) + '<div class="muted mono" style="font-size:10.5px">' + esc(i.indicator_code) + '</div></td>' +
            '<td class="num">' + num(i.raw_value, 2) + '</td>' +
            '<td class="num">' + num(i.z_score, 2) + '</td>' +
            '<td><span class="pill ' + (Number(i.z_score) > 0.5 ? 'ok' : (Number(i.z_score) < -0.5 ? 'warn' : '')) + '">' + esc(i.regime_tag) + '</span></td></tr>';
        }).join('') + '</tbody></table>';
    }

    if (vol.length) {
      html += '<div class="panel-head" style="margin:10px 0 6px"><span class="muted mono" style="font-size:11px">期权波动率曲面</span></div>';
      html += '<table class="t"><thead><tr><th>标的</th><th class="num">IV30</th><th class="num">分位</th><th class="num">25D 偏度</th><th>建议结构</th></tr></thead><tbody>' +
        vol.map(function (v) {
          return '<tr><td>' + esc(v.asset_name || v.underlying_ticker) + '</td>' +
            '<td class="num">' + num(v.iv_30d, 1) + '</td>' +
            '<td class="num">' + num(v.iv_percentile_1y, 1) + '</td>' +
            '<td class="num">' + num(v.skew_25d, 1) + '</td>' +
            '<td class="muted">' + esc(v.recommended_structure || '') + '</td></tr>';
        }).join('') + '</tbody></table>';
    }
    byId('research', html || '<div class="empty">等待数据…</div>');
  }

  // ---------------------------------------------------------------- 内容流水线
  function renderPipeline() {
    var cap = state.data.capital || {};
    var pubs = cap.publications || [];
    var metrics = cap.media_metrics || [];
    var shown = pubs.filter(visible);
    var pending = pubs.filter(function (p) { return String(p.publish_status).toUpperCase() === 'PENDING_REVIEW'; });
    var pub = shown.filter(function (p) { return String(p.publish_status).toUpperCase() === 'PUBLISHED'; });
    var imps = 0, reads = 0, fans = 0;
    metrics.forEach(function (m) { imps += Number(m.impressions || 0); reads += Number(m.views_or_reads || 0); fans += Number(m.net_new_followers || 0); });

    var html = '<div class="ch">' +
      '<div class="ch-card"><div class="k">THESES</div><div class="v">' + (cap.macro_theses || []).length + '</div><div class="n">宏观论点</div></div>' +
      '<div class="ch-card"><div class="k">PLAYBOOKS</div><div class="v">' + (cap.strategy_playbooks || []).length + '</div><div class="n">策略手册</div></div>' +
      '<div class="ch-card"><div class="k">PUBLISHED</div><div class="v">' + pub.length + '</div><div class="n">已发布（当前可见性）</div></div>' +
      '<div class="ch-card"><div class="k">PENDING</div><div class="v">' + pending.length + '</div><div class="n">待人工终审</div></div>' +
      '</div>';

    html += '<div class="four">' +
      '<div><div class="t">WEB</div><div class="s">' + (pub.length ? '已发布 ' + pub.length : '无') + '</div></div>' +
      '<div><div class="t">WECHAT</div><div class="s off">阶段二禁用</div></div>' +
      '<div><div class="t">XUEQIU</div><div class="s off">阶段二禁用</div></div>' +
      '<div><div class="t">X (TWITTER)</div><div class="s off">阶段二禁用</div></div>' +
      '</div>';

    html += '<div class="panel-head" style="margin:12px 0 6px"><span class="muted mono" style="font-size:11px">渠道指标累计</span></div>';
    html += '<table class="t"><tbody>' +
      '<tr><td>曝光 / 阅读 / 净增粉丝</td><td class="num">' + imps + ' / ' + reads + ' / ' + fans + '</td></tr>' +
      '</tbody></table>';

    if (shown.length) {
      html += '<div class="panel-head" style="margin:12px 0 6px"><span class="muted mono" style="font-size:11px">内容清单（' + state.clearance + '）</span></div>';
      html += '<table class="t"><thead><tr><th>标题</th><th>分类</th><th>状态</th><th>可见性</th></tr></thead><tbody>' +
        shown.slice(0, 8).map(function (p) {
          return '<tr><td>' + esc(p.title || p.slug) + '<div class="muted mono" style="font-size:10.5px">/' + esc(p.slug) + '</div></td>' +
            '<td>' + esc(p.category) + '</td>' +
            '<td><span class="pill ' + (String(p.publish_status).toUpperCase() === 'PUBLISHED' ? 'ok' : 'warn') + '">' + esc(p.publish_status) + '</span></td>' +
            '<td><span class="pill ' + (String(p.visibility).toUpperCase() === 'PUBLIC' ? 'gold' : '') + '">' + esc(p.visibility) + '</span></td></tr>';
        }).join('') + '</tbody></table>';
    }
    byId('pipeline', html);
  }

  // ---------------------------------------------------------------- 个人档案
  function renderArchive() {
    var home = state.data.home || {};
    var stories = home.timeline_stories || home.timeline_events || [];
    var assets = home.gallery_assets || home.archive_assets || [];
    var books = home.reading_library || [];
    var workouts = home.workouts || [];
    var retros = home.retrospectives || [];

    var html = '<div class="ch">' +
      '<div class="ch-card"><div class="k">STORIES</div><div class="v">' + stories.length + '</div><div class="n">人生篇章</div></div>' +
      '<div class="ch-card"><div class="k">GALLERY</div><div class="v">' + assets.length + '</div><div class="n">影像资产</div></div>' +
      '<div class="ch-card"><div class="k">BOOKS</div><div class="v">' + books.length + '</div><div class="n">藏书馆</div></div>' +
      '<div class="ch-card"><div class="k">WORKOUTS</div><div class="v">' + workouts.length + '</div><div class="n">训练记录</div></div>' +
      '</div>';

    if (stories.length) {
      html += '<table class="t"><thead><tr><th>事件</th><th>日期</th><th>章节</th><th class="num">重要度</th></tr></thead><tbody>' +
        stories.slice(0, 6).map(function (s) {
          return '<tr><td>' + esc(s.title) + '</td><td class="num">' + esc(s.event_date || '') + '</td>' +
            '<td>' + esc((s.metadata && s.metadata.life_chapter) || s.domain || '') + '</td>' +
            '<td class="num">' + esc(s.importance || s.importance_score || '') + '</td></tr>';
        }).join('') + '</tbody></table>';
    } else {
      html += '<div class="empty">尚无档案数据（灌 <code>seeds/52-week-sandbox.sql</code> 或用 CLI 录入）。</div>';
    }

    if (workouts.length) {
      var mins = workouts.reduce(function (a, w) { return a + Number(w.duration_minutes || 0); }, 0);
      var km = workouts.reduce(function (a, w) { return a + Number(w.distance_meters || 0); }, 0) / 1000;
      html += '<table class="t" style="margin-top:8px"><tbody>' +
        '<tr><td>累计训练</td><td class="num">' + mins + ' 分钟 · ' + km.toFixed(1) + ' km</td></tr>' +
        '<tr><td>结构化复盘</td><td class="num">' + retros.length + ' 篇</td></tr>' +
        '</tbody></table>';
    }
    byId('archive', html);
  }

  // ---------------------------------------------------------------- 计划与质量门
  var PLAN = [
    { id: 'L0', name: '本地环境与编排基线', st: 'DONE' },
    { id: 'L1', name: '数据库内核落地验证', st: 'DONE' },
    { id: 'L2', name: '应用与门户本地跑通', st: 'DOING' },
    { id: 'L3', name: 'n8n 阶段一联调', st: 'TODO' },
    { id: 'L4', name: '备份与恢复演练', st: 'TODO' },
    { id: 'L5', name: '质量门与封版', st: 'DOING' },
    { id: 'L6', name: '公网就绪包', st: 'TODO' }
  ];

  function renderPlan() {
    var st = state.status || {};
    var gate = st.gate || null;
    var html = PLAN.map(function (p) {
      var pct = p.st === 'DONE' ? 100 : (p.st === 'DOING' ? 45 : 0);
      var cls = p.st === 'DONE' ? 'ok' : (p.st === 'DOING' ? 'warn' : '');
      return '<div class="ph"><span class="code">' + p.id + '</span>' +
        '<div class="bar ' + cls + '"><i style="width:' + pct + '%"></i></div>' +
        '<span class="st">' + p.st + '</span>' +
        '<span class="muted" style="font-size:12px;flex:1">' + p.name + '</span></div>';
    }).join('');

    if (gate) {
      var gp = gate.pass || 0, gf = gate.fail || 0;
      html += '<div class="panel-head" style="margin:12px 0 6px"><span class="muted mono" style="font-size:11px">质量门 Q0–Q14</span></div>';
      html += '<table class="t"><tbody>' +
        '<tr><td>最近一次执行</td><td class="num">' + esc(fmtTime(gate.at)) + '</td>' +
        '<td class="num"><span class="pill ' + (gf === 0 ? 'ok' : 'bad') + '">PASS ' + gp + ' / FAIL ' + gf + '</span></td></tr>' +
        '</tbody></table>';
      if (gate.items && gate.items.length) {
        html += '<table class="t" style="margin-top:6px"><thead><tr><th>检查</th><th>结果</th></tr></thead><tbody>' +
          gate.items.map(function (i) {
            return '<tr><td>' + esc(i.id + ' ' + i.name) + '</td><td><span class="pill ' + (i.ok ? 'ok' : 'bad') + '">' + (i.ok ? 'PASS' : 'FAIL') + '</span></td></tr>';
          }).join('') + '</tbody></table>';
      }
    } else {
      html += '<div class="empty">尚无质量门结果 —— 运行 <code>bash tools/wsl/quality-gate.sh</code>。</div>';
    }
    byId('plan', html);
  }

  // ---------------------------------------------------------------- 运维动作
  var ACTIONS = [
    ['启动全栈', 'bash tools/wsl/wsl-up.sh'],
    ['停止全栈', 'docker compose -f docker-compose.yml -f docker-compose.wsl.yml --env-file .env.local down'],
    ['质量门（21 项）', 'bash tools/wsl/quality-gate.sh'],
    ['数据库冒烟（9 组）', 'docker compose -f docker-compose.yml -f docker-compose.wsl.yml --env-file .env.local exec -T postgres psql -U postgres -d db_archive -f /tmp/smoke.sql'],
    ['导出双站数据包', 'mobo-cli --env-file .env.local export-site --site all'],
    ['脱敏审计', 'pytest services/mobo-cli/tests/test_exporters.py -q'],
    ['投研录入 / 平仓', 'mobo-cli capital-trade --trade-code T-001 --close --exit-date 2026-10-21 --r-multiple 1.8 --impact-bps 180'],
    ['查看 NAV 与风控', 'mobo-cli --env-file .env.local capital-nav'],
    ['恢复演练（本地）', './deploy/backup/restore-drill.sh'],
    ['巡检哨兵', '*/15 * * * * /opt/mobo-stack/deploy/scripts/mobo_watchdog.sh'],
    ['收集运行时状态', 'bash tools/wsl/collect-status.sh']
  ];

  function renderActions() {
    byId('actions', ACTIONS.map(function (a) {
      return '<div class="cmd"><code>' + esc(a[1]) + '</code><button data-cmd="' + esc(a[1]) + '">复制</button></div>';
    }).join(''));
    Array.prototype.forEach.call(document.querySelectorAll('.actions button'), function (b) {
      b.addEventListener('click', function () {
        var txt = b.getAttribute('data-cmd');
        if (navigator.clipboard) { navigator.clipboard.writeText(txt); }
        b.textContent = '已复制';
        setTimeout(function () { b.textContent = '复制'; }, 1200);
      });
    });
  }

  // ---------------------------------------------------------------- 预算
  function renderBudget() {
    var st = state.status || {};
    var rows = [
      ['云服务器 2C4G', 200, 500, 360],
      ['域名（双主域）', 100, 180, 130],
      ['OSS 存储/流量', 100, 300, 250],
      ['备份/快照', 50, 150, 80],
      ['监控/拨测', 0, 30, 10]
    ];
    var infra = rows.reduce(function (a, r) { return a + r[3]; }, 0);
    var html = rows.map(function (r) {
      var pct = Math.min(100, Math.round((r[3] / 500) * 100));
      return '<div class="brow"><span class="lbl">' + esc(r[0]) + '</span>' +
        '<div class="bar ok"><i style="width:' + pct + '%"></i></div>' +
        '<span class="val">¥' + r[3] + ' / 年</span></div>';
    }).join('');
    html += '<div class="brow" style="border-top:1px solid var(--line);padding-top:9px;margin-top:4px">' +
      '<span class="lbl"><b>基础设施小计</b></span><div></div>' +
      '<span class="val" style="color:var(--gold-2)">¥' + infra + ' / 2,400</span></div>';
    html += '<div class="brow"><span class="lbl">AI 消耗（单列）</span>' +
      '<div class="bar warn"><i style="width:' + Math.min(100, Math.round((150 / 1800) * 100)) + '%"></i></div>' +
      '<span class="val">≤ ¥150 / 月</span></div>';
    if (st.cost) {
      html += '<table class="t" style="margin-top:8px"><tbody><tr><td>本月实测</td><td class="num">¥' + esc(st.cost.month_total || 0) + '（LLM ¥' + esc(st.cost.llm || 0) + '）</td></tr></tbody></table>';
    }
    byId('budget', html);
  }

  // ---------------------------------------------------------------- 凭据提示
  function renderCredentials() {
    fetchJSON('./data/credentials.local.json').then(function (c) {
      if (!c || !c.layers) return;
      var html = '<div class="panel-head" style="margin:10px 0 6px"><span class="muted mono" style="font-size:11px">本地开发凭据（仅本地模式）</span></div>';
      html += '<table class="t"><thead><tr><th>层</th><th>在哪里输</th><th>用户名</th><th>密码 / 码</th></tr></thead><tbody>' +
        c.layers.map(function (l) {
          return '<tr><td>' + esc(l.layer) + '</td><td class="muted">' + esc(l.where) + '</td>' +
            '<td class="mono">' + esc(l.username || '—') + '</td>' +
            '<td class="mono">' + esc(l.password || '—') + '</td></tr>';
        }).join('') + '</tbody></table>';
      if (c.public_sites) {
        html += '<div class="muted" style="font-size:12px;margin-top:6px">公开无需凭据：' + esc(c.public_sites.join('、')) + '</div>';
      }
      var el = $('credentials');
      if (el) el.innerHTML = html;
    });
  }

  // ---------------------------------------------------------------- 顶部交互
  function bindTop() {
    Array.prototype.forEach.call(document.querySelectorAll('#clearance button'), function (b) {
      b.addEventListener('click', function () {
        Array.prototype.forEach.call(document.querySelectorAll('#clearance button'), function (x) { x.classList.remove('on'); });
        b.classList.add('on');
        state.clearance = b.getAttribute('data-lvl');
        renderPipeline();
      });
    });
    $('autoRefresh').addEventListener('change', function () {
      if (this.checked) { startAuto(); } else { clearInterval(timer); }
    });
  }

  var timer = null;
  function startAuto() {
    clearInterval(timer);
    timer = setInterval(load, 15000);
  }

  // ---------------------------------------------------------------- 载入
  function load() {
    $('clock').textContent = new Date().toLocaleTimeString('zh-CN', { hour12: false });
    Promise.all([
      fetchJSON(API.capital), fetchJSON(API.terminal), fetchJSON(API.home), fetchJSON(API.status)
    ]).then(function (r) {
      state.data.capital = r[0] || {};
      state.data.terminal = r[1] || {};
      state.data.home = r[2] || {};
      state.status = r[3] || null;
      renderKPI(); renderServices(); renderRuntime(); renderResearch();
      renderPipeline(); renderArchive(); renderPlan(); renderBudget(); renderCredentials();
      var b = $('banner');
      if (state.errors.length) {
        b.className = 'banner err';
        b.textContent = '数据源异常：' + state.errors.slice(0, 3).join('；');
      } else { b.className = 'banner hidden'; }
      state.errors = [];
    });
  }

  var docsPaneApi = null;

  function openRepoDoc(title, path, type) {
    if (docsPaneApi && path) {
      var idMap = {
        'docs/01-项目治理/开发部署任务执行时间线.md': 'timeline',
        'docs/00-总册/莫伯双站系统全栈架构与部署总册-v2.1.md': 'zongce'
      };
      var id = idMap[path];
      if (id) {
        docsPaneApi.openDoc(id);
        var root = $('docs-pane-root');
        if (root) root.scrollIntoView({ behavior: 'smooth', block: 'start' });
        return;
      }
    }
    if (!window.MoBoDocViewer) return;
    MoBoDocViewer.openFile({
      title: title,
      path: path,
      type: type || (/\.docx$/i.test(path) ? 'docx' : 'md'),
      url: '../../' + path.split('/').map(encodeURIComponent).join('/')
    });
  }

  function mountDocsPane() {
    var el = $('docs-pane-root');
    if (!el || !window.MoBoDocsPane) return;
    MoBoDocsPane.mount(el, {
      catalogUrl: '../../sites/docs-portal/catalog.json',
      repoBase: '../../',
      defaultId: 'zongce',
      height: '70vh'
    }).then(function (api) {
      docsPaneApi = api;
    });
  }

  document.addEventListener('DOMContentLoaded', function () {
    bindTop();
    renderActions();
    mountDocsPane();
    var tl = $('open-doc-timeline');
    var zc = $('open-doc-zongce');
    if (tl) tl.addEventListener('click', function (e) {
      e.preventDefault();
      openRepoDoc('开发部署任务执行时间线', 'docs/01-项目治理/开发部署任务执行时间线.md', 'md');
    });
    if (zc) zc.addEventListener('click', function (e) {
      e.preventDefault();
      openRepoDoc('全栈总册 v2.1', 'docs/00-总册/莫伯双站系统全栈架构与部署总册-v2.1.md', 'md');
    });
    load();
    startAuto();
  });

  // 导出纯函数，供契约测试（services/console/tests/contract-check.mjs）调用
  if (typeof window !== 'undefined') {
    window.MoboConsole = { buildServiceCard: buildServiceCard, deriveServices: deriveServices };
  }
})();
