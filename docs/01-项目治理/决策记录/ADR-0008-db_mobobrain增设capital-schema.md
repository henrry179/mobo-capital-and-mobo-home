# ADR-0008：db_mobobrain 增设 capital Schema（投研域）

- **状态**：已接受
- **日期**：2026-10-21
- **相关**：ADR-0001（双库与 Schema 隔离）、CLAUDE.md 红线二

> **Canonical**：本议题「为何如此」以本文为真源；总册 / docs/03 / 整合总览仅保留结论指针，勿复制背景/替代方案/后果长文。

## 背景

v1.1 的 `db_mobobrain` 只有 `intel`（RSS 采集、文章、草稿、运行记录、LLM 用量）一个业务 Schema。v2.1 新增了一整套投研域对象：

- 宏观论点 `macro_theses`、策略手册 `strategy_playbooks`、交易复盘 `trade_reviews`；
- 基金孵化里程碑 `fund_incubation_milestones`、治理文档 `fund_governance_docs`；
- 四端发布主表 `capital_publications`、渠道指标 `media_channel_metrics`；
- 净值台账 `portfolio_nav_ledger`、宏观指标 `macro_indicator_series`、期权曲面 `options_vol_surface_daily`。

这些对象有三个特征：**生命周期独立**（不像文章会被清空重采）、**敏感度更高**（含实盘复盘与交割单引用）、**写入方不同**（CLI 与 n8n 工作流 #2）。若直接混在 `intel` 或 `public` 里，会同时破坏"采集域可重置""敏感数据可单独授权""表名不冲突"三个目标。

## 决策

在 `db_mobobrain` 内新增第三个 Schema：**`capital`**，属主 `user_mobobrain`。

```text
db_mobobrain
├─ intel    采集与发布流水（可整域重建，不影响投研数据）
├─ capital  投研、基金、量化终端（v2.1 新增）
└─ n8n      n8n 自动化内部表（n8n 自管迁移）
```

规范：

1. `capital` 域所有对象必须带 `capital.` 限定或 `SET search_path TO capital, public`；禁止落到 `public`。
2. 触发器函数显式 `SET search_path = capital, public`，避免执行时受会话影响。
3. `user_n8n` 只对 `capital.capital_publications` 拥有写权限，对其余表只读；`capital` 不向看板只读账号开放（看板只服务网站 B）。
4. `user_backup` 对 `capital` 只读。
5. 初始化序列顺延为 01–09（见总册 4.2）。

## 理由

- 保持"双库物理隔离"不变，只在库内细分域，符合最小改动原则。
- `intel` 可被"重新采集"而不影响投研数据；投研数据的备份与授权可以独立处理。
- 与 ADR-0009 的可见性字段（`visibility`）配合，敏感数据集中在可审计的域内。

## 代价与缓解

| 代价 | 缓解 |
|---|---|
| 多一层 Schema 概念 | 命名统一（`intel`/`capital`/`archive`/`n8n`），CLI 与 SQL 全部显式限定 |
| 迁移脚本需按域执行 | `migrations/apply.sh` 支持按库执行；`08-indexes-grants.sql` 集中授权 |
| 旧 CLI（v2.1 单文件版）使用未限定表名 | 已归档至 `docs/07-原始资料/归档-代码/`，差异清单见该目录 README；主线 CLI 全部限定 `capital.` |

## 备选方案

- **全部放 `public`**：被否。等同于放弃 Schema 隔离，与 ADR-0001 冲突。
- **为投研域单独建第三个数据库**：被否。2C4G 内存下多一个实例不合规；且"双库"是已公告的架构承诺。
