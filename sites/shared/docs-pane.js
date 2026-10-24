/* MoBo shared left-nav + right-reader docs pane */
(function (global) {
  'use strict';

  var STYLE_ID = 'mobo-docs-pane-style';

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function injectStyle() {
    if (document.getElementById(STYLE_ID)) return;
    var style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = [
      '.mobo-docs-pane{display:grid;grid-template-columns:minmax(220px,280px) 1fr;min-height:min(72vh,820px);',
      'border:1px solid rgba(148,163,184,.25);border-radius:14px;overflow:hidden;background:rgba(15,23,42,.55)}',
      '@media (max-width:860px){.mobo-docs-pane{grid-template-columns:1fr}',
      '.mobo-docs-side{max-height:38vh;border-right:none!important;border-bottom:1px solid rgba(148,163,184,.2)}}',
      '.mobo-docs-side{overflow:auto;padding:12px 10px 20px;border-right:1px solid rgba(148,163,184,.2);background:rgba(2,6,23,.35)}',
      '.mobo-docs-group{margin-bottom:14px}',
      '.mobo-docs-group h3{margin:0 0 6px;padding:0 8px;font-size:11px;letter-spacing:.06em;text-transform:uppercase;',
      'color:#94a3b8;font-weight:600}',
      '.mobo-docs-item{display:block;width:100%;text-align:left;cursor:pointer;background:transparent;',
      'border:1px solid transparent;color:#e2e8f0;padding:8px 10px;border-radius:8px;font-size:13px;line-height:1.35}',
      '.mobo-docs-item:hover{background:rgba(255,255,255,.04);border-color:rgba(148,163,184,.25)}',
      '.mobo-docs-item.active{background:rgba(201,162,39,.12);border-color:rgba(201,162,39,.45)}',
      '.mobo-docs-badge{display:inline-block;margin-left:6px;font-size:10px;color:#fbbf24;',
      'border:1px solid rgba(251,191,36,.35);padding:0 5px;border-radius:999px}',
      '.mobo-docs-main{display:flex;flex-direction:column;min-width:0;min-height:0}',
      '.mobo-docs-toolbar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;padding:10px 14px;',
      'border-bottom:1px solid rgba(148,163,184,.2);color:#94a3b8;font-size:12px}',
      '.mobo-docs-toolbar a{color:#93c5fd;text-decoration:none}',
      '.mobo-docs-toolbar a:hover{text-decoration:underline}',
      '.mobo-docs-content{flex:1;overflow:auto;padding:18px 20px 36px;color:#e2e8f0}',
      '.mobo-docs-muted{color:#94a3b8;line-height:1.6}'
    ].join('');
    document.head.appendChild(style);
  }

  function encodePath(path) {
    return path.split('/').map(encodeURIComponent).join('/');
  }

  function joinBase(repoBase, path) {
    var base = repoBase || '';
    if (base && !/\/$/.test(base)) base += '/';
    return base + encodePath(path);
  }

  function githubBlob(catalog, path) {
    var repo = (catalog && catalog.repo) || 'henrry179/mobo-capital-and-mobo-home';
    var branch = (catalog && catalog.branch) || 'main';
    return 'https://github.com/' + repo + '/blob/' + branch + '/' + encodePath(path);
  }

  /**
   * @param {HTMLElement} root
   * @param {{ catalogUrl: string, repoBase?: string, defaultId?: string, height?: string }} opts
   */
  function mountDocsPane(root, opts) {
    opts = opts || {};
    if (!root) throw new Error('mountDocsPane: root required');
    injectStyle();

    var catalogUrl = opts.catalogUrl;
    var repoBase = opts.repoBase != null ? opts.repoBase : '../../';
    var defaultId = opts.defaultId || 'zongce';
    var byId = {};
    var catalog = null;
    var activeId = null;

    root.innerHTML =
      '<div class="mobo-docs-pane"' + (opts.height ? ' style="min-height:' + escapeHtml(opts.height) + '"' : '') + '>' +
      '  <aside class="mobo-docs-side" data-role="side"><div class="mobo-docs-muted" style="padding:8px">加载目录…</div></aside>' +
      '  <section class="mobo-docs-main">' +
      '    <div class="mobo-docs-toolbar" data-role="toolbar">选择左侧文档开始阅读</div>' +
      '    <article class="mobo-docs-content" data-role="content"><p class="mobo-docs-muted">工程说明书与 Word 归档将显示在此处。</p></article>' +
      '  </section>' +
      '</div>';

    var side = root.querySelector('[data-role="side"]');
    var toolbar = root.querySelector('[data-role="toolbar"]');
    var content = root.querySelector('[data-role="content"]');

    function markActive(id) {
      activeId = id;
      Array.prototype.forEach.call(side.querySelectorAll('.mobo-docs-item'), function (el) {
        el.classList.toggle('active', el.getAttribute('data-id') === id);
      });
    }

    function openDoc(id) {
      var item = byId[id];
      if (!item) {
        content.innerHTML = '<div class="mobo-doc-err">目录中不存在：' + escapeHtml(id) + '</div>';
        return;
      }
      if (!global.MoBoDocViewer) {
        content.innerHTML = '<div class="mobo-doc-err">文档阅读器未加载（缺少 doc-viewer.js）</div>';
        return;
      }
      markActive(id);
      toolbar.innerHTML =
        '<strong style="color:#e2e8f0">' + escapeHtml(item.title) + '</strong>' +
        '<span>·</span><span style="word-break:break-all">' + escapeHtml(item.path) + '</span>' +
        '<span>·</span><a href="' + githubBlob(catalog, item.path) + '" target="_blank" rel="noopener">GitHub 源文件</a>' +
        '<span>·</span><a href="' + joinBase(repoBase, item.path) + '" target="_blank" rel="noopener">原件</a>';

      MoBoDocViewer.openFile({
        title: item.title,
        path: item.path,
        type: item.type || 'md',
        url: joinBase(repoBase, item.path),
        mount: content,
        onMeta: function () {}
      });
    }

    function renderSidebar() {
      var html = '';
      (catalog.groups || []).forEach(function (g) {
        html += '<div class="mobo-docs-group"><h3>' + escapeHtml(g.title) + '</h3>';
        (g.items || []).forEach(function (it) {
          byId[it.id] = it;
          html += '<button type="button" class="mobo-docs-item" data-id="' + escapeHtml(it.id) + '">' +
            escapeHtml(it.title) +
            (it.badge ? '<span class="mobo-docs-badge">' + escapeHtml(it.badge) + '</span>' : '') +
            '</button>';
        });
        html += '</div>';
      });
      side.innerHTML = html;
      Array.prototype.forEach.call(side.querySelectorAll('.mobo-docs-item'), function (btn) {
        btn.addEventListener('click', function () {
          openDoc(btn.getAttribute('data-id'));
        });
      });
    }

    if (global.MoBoDocViewer && MoBoDocViewer.ensureLibs) {
      MoBoDocViewer.ensureLibs(true).catch(function () {});
    }

    return fetch(catalogUrl, { cache: 'no-store' })
      .then(function (r) {
        if (!r.ok) throw new Error('catalog HTTP ' + r.status + ' · ' + catalogUrl);
        return r.json();
      })
      .then(function (data) {
        catalog = data;
        renderSidebar();
        if (byId[defaultId]) openDoc(defaultId);
        else {
          var first = catalog.groups && catalog.groups[0] && catalog.groups[0].items && catalog.groups[0].items[0];
          if (first) openDoc(first.id);
        }
        return {
          openDoc: openDoc,
          getActiveId: function () { return activeId; },
          catalog: catalog
        };
      })
      .catch(function (e) {
        side.innerHTML = '';
        content.innerHTML = '<div class="mobo-doc-err"><b>文档目录加载失败</b><br/>' +
          escapeHtml(e.message) + '</div>';
        return null;
      });
  }

  global.MoBoDocsPane = { mount: mountDocsPane };
})(window);
