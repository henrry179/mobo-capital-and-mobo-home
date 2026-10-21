#!/usr/bin/env node
/**
 * 莫伯双站 · 本地预览一键启动
 *
 *   node tools/local-preview/start.js
 *
 * 步骤：生成样例数据包 → 启动预览网关（8080 莫伯资本 / 8081 莫伯之家 / 8082 架构总览）
 */
'use strict';

const { spawn } = require('child_process');
const path = require('path');
const http = require('http');

const DIR = __dirname;
const node = process.execPath;

function run(cmd, args, opts = {}) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { stdio: 'inherit', cwd: path.resolve(DIR, '..', '..'), ...opts });
    p.on('exit', code => (code === 0 ? resolve() : reject(new Error(`${cmd} 退出码 ${code}`))));
    p.on('error', reject);
  });
}

function waitPort(port, timeoutMs = 8000) {
  const started = Date.now();
  return new Promise((resolve, reject) => {
    const attempt = () => {
      const req = http.get({ host: '127.0.0.1', port, path: '/status.json', timeout: 1500 }, res => {
        res.resume();
        if (res.statusCode === 200) return resolve();
        retry();
      });
      req.on('error', retry);
      req.on('timeout', () => { req.destroy(); retry(); });
    };
    const retry = () => {
      if (Date.now() - started > timeoutMs) return reject(new Error('网关启动超时'));
      setTimeout(attempt, 300);
    };
    attempt();
  });
}

(async () => {
  console.log('=== 莫伯双站 · 本地预览启动 ===\n');
  console.log('[1/2] 生成样例数据包…');
  await run(node, [path.join(DIR, 'generate-sample-data.js')]);

  console.log('\n[2/2] 启动预览网关…\n');
  const server = spawn(node, [path.join(DIR, 'serve.js')], { stdio: 'inherit', cwd: path.resolve(DIR, '..', '..') });

  try {
    await waitPort(8082);
  } catch (e) {
    console.error('[启动失败] ' + e.message);
    server.kill();
    process.exit(1);
  }

  console.log('\n────────────────────────────────────────────');
  console.log('  架构与入口总览  http://127.0.0.1:8082/');
  console.log('  莫伯资本        http://127.0.0.1:8080/');
  console.log('  莫伯之家        http://127.0.0.1:8081/');
  console.log('  状态 JSON       http://127.0.0.1:8082/status.json');
  console.log('  /internal/*     BasicAuth：mobo / mobo-local（仅本地）');
  console.log('────────────────────────────────────────────');
  console.log('  Ctrl+C 停止\n');

  const stop = () => { server.kill(); process.exit(0); };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
  server.on('exit', code => process.exit(code === null ? 0 : code));
})();
