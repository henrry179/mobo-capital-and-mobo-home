# tools/vault — 金库构建与审计脚本（入库留档）

轻量入库版：本目录存放 V5 金库的可复现脚本副本，原始执行底稿在临时区（`D:\DataRedirect\Temp\opencode\`）。

## mobo-v5-thumbs.js · ⚙4 缩略图/封面生成器（2026-10-23）

- 用途：按 `SITE-ROUTING.csv` 的 `thumbnail_key` 计划生成图片列表缩略（长边 480px）与 PDF 首页封面 WebP。
- 四个子命令：`verify`（源文件 SHA-256 全量核对）→ `render`（产物先落临时区暂存）→ `install`（仅新增写入金库 `80-Site-Release/shared/`，拒绝覆盖）→ `audit`（回读验证 + `00-INDEX` 计数）。
- 依赖（便携 npm，无系统级安装）：`npm i sharp pdfjs-dist @napi-rs/canvas`（Node ≥ 20）。
- 用法：`node mobo-v5-thumbs.js verify|render|install|audit [--limit N]`；`VAULT`/`STAGE` 常量在文件头可改。
- 纪律：源只读；重复 SHA 只登记不删除；沿用 `mobo-v5-build.js` 的 `isQuarantine()` 密钥隔离语义。
- 本轮实测：2,542/2,542（= 2,719 计划 key 按 SHA 去重）· 37,625,230 B · 0 超限/0 失败/0 不可解码 · 27,035 副本 0 缺失 0 冲突。
