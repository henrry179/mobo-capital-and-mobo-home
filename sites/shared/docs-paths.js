/* Resolve docs asset paths for GitHub Pages (/sites/mobo*/) vs local Caddy (domain root). */
(function (global) {
  'use strict';
  var path = (global.location && global.location.pathname) || '/';
  var onPages = /\/sites\/mobo(capital|home)(\/|$)/.test(path);
  global.MoBoDocsPaths = onPages
    ? {
        sharedBase: '../shared/',
        catalogUrl: '../docs-portal/catalog.json',
        repoBase: '../../'
      }
    : {
        sharedBase: '/shared/',
        catalogUrl: '/docs-portal/catalog.json',
        repoBase: '/'
      };
})(window);
