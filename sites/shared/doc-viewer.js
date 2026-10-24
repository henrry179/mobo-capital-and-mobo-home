/* MoBo shared in-page Markdown / Word viewer (overlay + embed) */
(function (global) {
  'use strict';

  var CDN_MIRRORS = {
    marked: [
      'https://cdn.jsdelivr.net/npm/marked/marked.min.js',
      'https://unpkg.com/marked/marked.min.js',
      'https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.2/marked.min.js'
    ],
    purify: [
      'https://cdn.jsdelivr.net/npm/dompurify@3.1.6/dist/purify.min.js',
      'https://unpkg.com/dompurify@3.1.6/dist/purify.min.js',
      'https://cdnjs.cloudflare.com/ajax/libs/dompurify/3.1.6/purify.min.js'
    ],
    mammoth: [
      'https://cdn.jsdelivr.net/npm/mammoth@1.8.0/mammoth.browser.min.js',
      'https://unpkg.com/mammoth@1.8.0/mammoth.browser.min.js'
    ]
  };

  var libReady = { marked: null, purify: null, mammoth: null };
  var shellReady = false;

  function loadScriptOnce(src) {
    return new Promise(function (resolve, reject) {
      var existing = document.querySelector('script[src="' + src + '"]');
      if (existing && existing.getAttribute('data-mobo-loaded') === '1') {
        resolve();
        return;
      }
      var s = document.createElement('script');
      s.src = src;
      s.async = true;
      s.onload = function () {
        s.setAttribute('data-mobo-loaded', '1');
        resolve();
      };
      s.onerror = function () { reject(new Error('CDN load failed: ' + src)); };
      document.head.appendChild(s);
    });
  }

  function loadLib(name, readyCheck) {
    if (readyCheck()) return Promise.resolve();
    if (libReady[name]) return libReady[name];
    var urls = CDN_MIRRORS[name] || [];
    libReady[name] = urls.reduce(function (chain, url) {
      return chain.catch(function () {
        return loadScriptOnce(url).then(function () {
          if (!readyCheck()) throw new Error(name + ' loaded but global missing');
        });
      });
    }, Promise.reject(new Error('start'))).catch(function () {
      libReady[name] = null;
      throw new Error('全部 CDN 无法加载 ' + name + '（jsDelivr / unpkg / cdnjs）');
    });
    return libReady[name];
  }

  function ensureLibs(needMammoth) {
    var jobs = [
      loadLib('marked', function () { return !!(global.marked && marked.parse); }),
      loadLib('purify', function () { return !!(global.DOMPurify && DOMPurify.sanitize); })
    ];
    if (needMammoth) {
      jobs.push(loadLib('mammoth', function () { return !!(global.mammoth && mammoth.convertToHtml); }));
    }
    return Promise.all(jobs);
  }

  function ensureShell() {
    if (shellReady) return;
    var style = document.createElement('style');
    style.textContent = [
      '#mobo-doc-overlay{position:fixed;inset:0;z-index:9999;display:none;align-items:center;justify-content:center;',
      'background:rgba(5,10,20,.72);backdrop-filter:blur(6px);padding:16px}',
      '#mobo-doc-overlay.open{display:flex}',
      '#mobo-doc-panel{width:min(920px,100%);max-height:min(88vh,920px);overflow:auto;border-radius:14px;',
      'background:#0f172a;border:1px solid #1e293b;color:#e2e8f0;box-shadow:0 24px 80px rgba(0,0,0,.45)}',
      '#mobo-doc-head{position:sticky;top:0;display:flex;justify-content:space-between;gap:12px;align-items:flex-start;',
      'padding:14px 16px;background:rgba(15,23,42,.96);border-bottom:1px solid #1e293b;z-index:1}',
      '#mobo-doc-title{font-weight:650;font-size:15px;line-height:1.4;margin:0}',
      '#mobo-doc-sub{color:#94a3b8;font-size:11px;margin-top:4px;word-break:break-all}',
      '#mobo-doc-close{border:1px solid #334155;background:transparent;color:#e2e8f0;border-radius:8px;',
      'padding:6px 10px;cursor:pointer;font-size:12px}',
      '#mobo-doc-close:hover{border-color:#c9a227;color:#fff}',
      '#mobo-doc-body{padding:18px 20px 28px;line-height:1.7;font-size:14.5px}',
      '#mobo-doc-body h1,#mobo-doc-body h2,#mobo-doc-body h3{line-height:1.3;margin:1.1em 0 .5em}',
      '#mobo-doc-body pre{overflow:auto;padding:12px;border-radius:8px;background:#020617;border:1px solid #1e293b}',
      '#mobo-doc-body code{font-family:ui-monospace,Consolas,monospace;font-size:.88em}',
      '#mobo-doc-body table{border-collapse:collapse;width:100%;font-size:13px}',
      '#mobo-doc-body th,#mobo-doc-body td{border:1px solid #334155;padding:6px 8px}',
      '#mobo-doc-body a{color:#93c5fd}',
      '.mobo-doc-err{border:1px solid rgba(248,113,113,.4);background:rgba(248,113,113,.08);',
      'color:#fecaca;padding:12px;border-radius:10px;line-height:1.5}',
      '.mobo-doc-prose{line-height:1.7;font-size:15px}',
      '.mobo-doc-prose h1,.mobo-doc-prose h2,.mobo-doc-prose h3{line-height:1.3;margin:1.1em 0 .5em}',
      '.mobo-doc-prose pre{overflow:auto;padding:12px;border-radius:8px;background:#020617;border:1px solid #1e293b}',
      '.mobo-doc-prose code{font-family:ui-monospace,Consolas,monospace;font-size:.88em}',
      '.mobo-doc-prose table{border-collapse:collapse;width:100%;font-size:13px}',
      '.mobo-doc-prose th,.mobo-doc-prose td{border:1px solid #334155;padding:6px 8px}',
      '.mobo-doc-prose a{color:#93c5fd}',
      '.mobo-doc-prose img{max-width:100%}'
    ].join('');
    document.head.appendChild(style);

    var ov = document.createElement('div');
    ov.id = 'mobo-doc-overlay';
    ov.innerHTML = [
      '<div id="mobo-doc-panel" role="dialog" aria-modal="true">',
      '  <div id="mobo-doc-head">',
      '    <div><h2 id="mobo-doc-title"></h2><div id="mobo-doc-sub"></div></div>',
      '    <button type="button" id="mobo-doc-close">关闭</button>',
      '  </div>',
      '  <div id="mobo-doc-body"></div>',
      '</div>'
    ].join('');
    document.body.appendChild(ov);
    ov.addEventListener('click', function (e) { if (e.target === ov) close(); });
    document.getElementById('mobo-doc-close').addEventListener('click', close);
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && ov.classList.contains('open')) close();
    });
    shellReady = true;
  }

  function close() {
    var ov = document.getElementById('mobo-doc-overlay');
    if (ov) ov.classList.remove('open');
  }

  function escapeHtml(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function renderMarkdown(md) {
    var raw = (global.marked && marked.parse)
      ? marked.parse(md || '', { mangle: false, headerIds: true })
      : ('<pre>' + escapeHtml(md || '') + '</pre>');
    return (global.DOMPurify && DOMPurify.sanitize) ? DOMPurify.sanitize(raw) : raw;
  }

  function errHtml(msg) {
    return '<div class="mobo-doc-err"><b>无法打开文档</b><br/>' + escapeHtml(msg) + '</div>';
  }

  function deliver(opts, title, sub, html) {
    var mount = opts && opts.mount;
    if (mount) {
      if (opts.onMeta) opts.onMeta({ title: title, subtitle: sub });
      mount.innerHTML = '<div class="mobo-doc-prose">' + html + '</div>';
      return;
    }
    ensureShell();
    document.getElementById('mobo-doc-title').textContent = title || '文档';
    document.getElementById('mobo-doc-sub').textContent = sub || '';
    document.getElementById('mobo-doc-body').innerHTML = html;
    document.getElementById('mobo-doc-overlay').classList.add('open');
  }

  function openMarkdown(opts) {
    opts = opts || {};
    return ensureLibs(false).then(function () {
      deliver(opts, opts.title || '文档', opts.subtitle || '', renderMarkdown(opts.markdown || ''));
    }).catch(function (e) {
      deliver(opts, opts.title || '文档', opts.subtitle || '', errHtml(e.message));
    });
  }

  function guessType(path) {
    if (!path) return 'md';
    return /\.docx$/i.test(path) ? 'docx' : 'md';
  }

  function openFile(opts) {
    opts = opts || {};
    var path = opts.path;
    var type = (opts.type || guessType(path)).toLowerCase();
    var title = opts.title || path;
    var url = opts.url || path;
    deliver(opts, title, path || url, '<p style="color:#94a3b8">加载中…</p>');
    return ensureLibs(type === 'docx').then(function () {
      return fetch(url, { cache: 'no-store' }).then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status + ' · ' + path);
        if (type === 'docx') {
          return r.arrayBuffer().then(function (buf) {
            return mammoth.convertToHtml({ arrayBuffer: buf }).then(function (res) {
              var html = (DOMPurify && DOMPurify.sanitize) ? DOMPurify.sanitize(res.value || '') : res.value;
              deliver(opts, title, path, html || '<p>（空文档）</p>');
            });
          });
        }
        return r.text().then(function (text) {
          deliver(opts, title, path, renderMarkdown(text));
        });
      });
    }).catch(function (e) {
      deliver(opts, title, path || url, errHtml(e.message + (path ? ' · ' + path : '')));
    });
  }

  global.MoBoDocViewer = {
    openMarkdown: openMarkdown,
    openFile: openFile,
    close: close,
    ensureLibs: ensureLibs
  };
})(window);
