# 验收标准与 DoD

> 任何一项未通过，不得宣称“上线完成”。每项记录证据（截图/命令输出/日志）到 `tests/` 或发布记录。

## 1. 部署验收

| ID | 检查 | 方法 | 期望 |
|---|---|---|---|
| AC-D-01 | Compose 配置合法 | `docker compose config` | 无错误 |
| AC-D-02 | 六容器运行 | `docker compose ps` | 全部 running/healthy |
| AC-D-03 | 总内存 | `docker stats --no-stream` | 总 <3GB；Postgres <1GB |
| AC-D-04 | Postgres 健康 | `pg_isready` | accepting connections |
| AC-D-05 | 双库存在 | `psql -l` | `db_mobobrain`、`db_archive` |
| AC-D-06 | Schema/表 | `\dn`、`\dt` | `intel`、`n8n`、`archive`；表齐全 |
| AC-D-07 | 触发器 | `\df archive.fn_*`、`\dT+` | 4 个同步函数 + 触发器 |
| AC-D-08 | 迁移基线 | `schema_version` | 版本记录存在 |

## 2. 访问与安全验收

| ID | 检查 | 方法 | 期望 |
|---|---|---|---|
| AC-S-01 | 公开站 | `curl -I https://www...` | 200；HTTPS |
| AC-S-02 | 知识库匿名 | `curl -I https://kb...` | 401 |
| AC-S-03 | n8n 匿名 | `curl -I https://n8n...` | 401 |
| AC-S-04 | 档案匿名 | `curl -I https://archive...` | 401 + `noindex` |
| AC-S-05 | 操作台匿名 | `curl -I https://admin...` | 401 |
| AC-S-06 | 数据库端口 | `ss -lntp` / 安全组 | 无 0.0.0.0:5432 |
| AC-S-07 | 密钥 | `git check-ignore .env` | 已忽略；历史无密钥 |
| AC-S-08 | 安全头 | `curl -I` | HSTS、nosniff、frame DENY |
| AC-S-09 | SSH | `sshd -T` | `passwordauthentication no` |
| AC-S-10 | 防火墙 | `ufw status` | 仅 22/80/443 |

## 3. 网站 A 验收

| ID | 检查 | 方法 | 期望 |
|---|---|---|---|
| AC-A-01 | 思源登录 | 浏览器 | 可创建/编辑/搜索 |
| AC-A-02 | n8n 登录 | 浏览器 | 工作流列表可见 |
| AC-A-03 | 采集去重 | 同一 URL 投递两次 | 第二次不新增/不重复调 LLM |
| AC-A-04 | 文章入库 | `SELECT count(*) FROM intel.articles_vault` | 增加；字段完整 |
| AC-A-05 | 高分推思源 | 评分 ≥7 | 思源出现双链文档 |
| AC-A-06 | 低分不推送 | 评分 <7 | 仅入库，无思源文档 |
| AC-A-07 | 三端草稿 | 触发 #2 | 3 条 `content_drafts` |
| AC-A-08 | 公开页 | 浏览器 | 文章/图片正常 |

## 4. 网站 B 验收

| ID | 检查 | 方法 | 期望 |
|---|---|---|---|
| AC-B-01 | 时间线写入 | 手动 INSERT | 可查询 |
| AC-B-02 | 读完书籍 | `mobo_cli read --status COMPLETED` | timeline 1 条；重复幂等 |
| AC-B-03 | 运动记录 | `mobo_cli workout` | timeline 1 条；指标正确 |
| AC-B-04 | 复盘 | `mobo_cli retro` | timeline 1 条；摘要正确 |
| AC-B-05 | 状态回退 | 把书从 COMPLETED 改回 READING | timeline 节点删除 |
| AC-B-06 | 照片上传 | `mobo_cli upload` | 缩略图 + 原图；SHA 去重 |
| AC-B-07 | PDF | `mobo_cli upload` | `extracted_text` 非空 |
| AC-B-08 | 看板四模块 | 浏览器 | 均可交互 |
| AC-B-09 | 沙盒模式 | 停 DB/断连接 | 自动切 52 周合成数据 |
| AC-B-10 | 资产总账 | 看板 | 容量/层级/数量正确 |

## 5. 备份与灾备验收

| ID | 检查 | 方法 | 期望 |
|---|---|---|---|
| AC-R-01 | 首次备份 | `restic snapshots` | 有快照 |
| AC-R-02 | 数据库 dump | 备份日志 | 双库 dump 成功 |
| AC-R-03 | 控制台 | 莫伯系统控制台可用 | 6 入口可达性/运行时/投研风控/流水线/档案/任务与质量门同屏可见；未认证 401；数据契约检查通过 |
| AC-R-03 | 恢复演练 | `restore-drill.sh` | staging 对账一致 |
| AC-R-04 | 核心表计数 | 恢复后 SQL | 与源库一致 |
| AC-R-05 | RTO | 计时 | DB/配置 ≤2h |
| AC-R-06 | 密钥恢复 | 密码管理器 | 可解锁 Restic |
| AC-R-07 | 监控告警 | 停容器/模拟磁盘 | 5 分钟内通知 |

## 6. 成本验收

| ID | 检查 | 期望 |
|---|---|---|
| AC-C-01 | 首年账单 | ≤2,400 元 |
| AC-C-02 | 预算告警 | 50 元/月、80% 阈值生效 |
| AC-C-03 | 流量告警 | 5 分钟 >500MB 生效 |
| AC-C-04 | 余额熔断 | 账户仅 30 元 |
| AC-C-05 | 成本台账 | 每项有实际金额/日期 |

## 7. 文档验收

- [ ] 总册 v1.1、部署手册、运维手册、故障排查、备份演练、安全基线齐全。
- [ ] ADR-0001~0006 已确认。
- [ ] `.env.example` 与实际变量一致。
- [ ] 密钥清单、成本台账、ICP 清单已填。
- [ ] 发布记录与修订记录更新。

## 8. DoD 总定义

一个任务“完成”必须同时满足：

1. 功能实现并通过对应 AC。
2. 有测试/验证证据。
3. 文档更新（命令、变量、边界）。
4. 无新增 P0/P1 风险，或已登记缓解。
5. 回滚方案明确。
6. 代码/配置已提交（如使用 Git），密钥未入库。
