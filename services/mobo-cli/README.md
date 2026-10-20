# mobo-cli

网站 B（个人数字档案）的本地/云端录入工具。只使用应用账号，不使用 `postgres` 超级用户。

## 安装

```bash
cd services/mobo-cli
python -m venv .venv
# Windows
.venv\Scripts\activate
# Linux/macOS
source .venv/bin/activate

pip install -e ".[dev]"
```

在项目根目录准备 `.env`（至少包含 `CLI_*` 与 OSS 变量），或使用 `--env-file`。

## 命令

```bash
mobo-cli doctor

# 资产：上传原片 + WebP 缩略图 + SHA-256 去重
mobo-cli upload ~/Pictures/2026-10/photo.jpg \
  --category PHOTO --title "秋日骑行" --domain FAMILY_LIFE \
  --tags "骑行,家庭" --captured-at 2026-10-18

# 阅读：新增/更新书目，并写阅读日志
mobo-cli read --title "反脆弱" --author "纳西姆·塔勒布" \
  --status COMPLETED --rating 9 --total-pages 480 \
  --started 2026-09-01 --finished 2026-10-18 \
  --minutes 45 --start-page 420 --end-page 460 \
  --summary "从波动中受益的结构性策略。"

# 运动
mobo-cli workout --type RUNNING --minutes 51 --distance-km 10 \
  --avg-hr 152 --rpe 7 --title "西湖晨跑"

# 生理基线
mobo-cli bio --sleep 7.4 --resting-hr 56 --weight 70.2 --energy 8

# 结构化复盘：Markdown 二级标题
mobo-cli retro --file weekly.md --type WEEKLY --domain SYSTEM_TECH
```

## Markdown 复盘格式

```markdown
## 初始假设
本周把阅读放在早晨，能提高完成率。

## 实际执行
周一至周三完成，周四出差中断。

## 根因分析
出差期间没有准备离线阅读材料。

## 原则迭代
出差前预先下载 2 小时阅读材料。

## KPI
- 阅读小时: 6.5
- 训练次数: 4

## 行动项
- 周日晚整理下周离线包 owner: 我 due: 周日
```

## 安全

- `.env` 不进入 Git；真实密钥只存服务器与密码管理器。
- `upload` 默认写入私有 Bucket，输出 1 小时签名 URL；不要把私有 Bucket 改为公共读。
- 数据库连接默认 `127.0.0.1:5432`；生产环境通过 SSH 隧道或服务器本地执行。
