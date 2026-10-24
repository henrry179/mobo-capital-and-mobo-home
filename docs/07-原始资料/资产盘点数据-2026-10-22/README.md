# 资产盘点机读 · 阅读优先级（簇 G）

> 不删除任何 JSON/CSV。指导开工时按下列优先级，避免把 v3 快照数字当成 V5 执行账。

| 优先级 | 文件 | 角色 |
|---|---|---|
| **读** | `sync-v5.json` | 规划期四分区真源（拍板前口径） |
| **可不读** | `sync-v5-category.csv`、`sync-v5-local.csv`、`sync-v5-p2.csv` | JSON 扁平导出，可由 `build_sync_v5.py` 再生 |
| **降权** | `summary.json`、`duplicate-summary.json` | **2026-10-22 / v3 基线快照**。勿与 V5 执行数字（金库 `COUNTS.json`、执行报告）混用 |

执行期数字以金库 `MoBo-Content-Vault-v5/00-INDEX/` 与 [`莫伯双站V5执行报告-2026-10-23.md`](../莫伯双站V5执行报告-2026-10-23.md) 为准。
