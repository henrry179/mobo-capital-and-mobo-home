#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MoBo Dual-Site CLI (v2.0) — 莫伯资本 (MoBoCapital.com) & 莫伯之家 (MoBoHome.com) 双栖终端总控工具
路径: /opt/mobo-stack/scripts/mobo_cli.py
依赖: pip install psycopg2-binary oss2 Pillow pypdf python-dotenv pyyaml
"""

import os
import sys
import json
import yaml
import hashlib
import argparse
from io import BytesIO
from datetime import datetime, date
from decimal import Decimal
from pathlib import Path

import oss2
import psycopg2
from psycopg2.extras import RealDictCursor, Json
from PIL import Image
from dotenv import load_dotenv

# 加载 /opt/mobo-stack/.env 环境变量
ENV_PATH = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(dotenv_path=ENV_PATH)


# ============================================================================
# 1. 双数据库连接工厂与 OSS 双桶客户端初始化
# ============================================================================
def get_db_conn(target_site: str):
    """
    根据目标站点返回严格隔离的数据库连接:
    - 'capital' -> 连接 db_mobobrain (使用 user_mobobrain)
    - 'home'    -> 连接 db_archive (使用 user_archive)
    """
    host = os.getenv("PG_HOST", "127.0.0.1")
    port = int(os.getenv("PG_PORT", "5432"))

    if target_site == "capital":
        return psycopg2.connect(
            host=host,
            port=port,
            dbname=os.getenv("PG_DB_MOBOBRAIN", "db_mobobrain"),
            user=os.getenv("PG_USER_MOBOBRAIN", "user_mobobrain"),
            password=os.getenv("PG_PASS_MOBOBRAIN"),
        )
    elif target_site == "home":
        return psycopg2.connect(
            host=host,
            port=port,
            dbname=os.getenv("PG_DB_ARCHIVE", "db_archive"),
            user=os.getenv("PG_USER_ARCHIVE", "user_archive"),
            password=os.getenv("PG_PASS_ARCHIVE"),
        )
    else:
        raise ValueError(f"未知的目标站点类型: {target_site}")


def get_oss_buckets():
    """初始化阿里云 OSS 公有图床桶与私有档案桶"""
    ak = os.getenv("ALIYUN_ACCESS_KEY_ID")
    sk = os.getenv("ALIYUN_ACCESS_KEY_SECRET")
    # 在 ECS 容器内优先走 -internal 免流量费，在本地终端走公网 Endpoint
    endpoint = os.getenv("OSS_ENDPOINT", "https://oss-cn-hangzhou.aliyuncs.com")
    auth = oss2.Auth(ak, sk)

    pub_bucket_name = os.getenv("OSS_BUCKET_PUBLIC", "mobobrain-assets-pub")
    priv_bucket_name = os.getenv("OSS_BUCKET_PRIVATE", "mobo-archive-private-hz")

    return (
        oss2.Bucket(auth, endpoint, pub_bucket_name),
        oss2.Bucket(auth, endpoint, priv_bucket_name),
        pub_bucket_name,
        priv_bucket_name,
    )


def compute_sha256(file_path: Path) -> str:
    """流式计算文件 SHA-256 哈希，用于秒传去重与命名"""
    h = hashlib.sha256()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


# ============================================================================
# 2. OSS 双轨上传流水线 (私有交割单原件 vs 公有图表 WebP 压缩)
# ============================================================================
def upload_private_blotter(file_path: str) -> str:
    """
    将实盘交割单 (PDF/PNG/CSV) 加密上传至私有桶 mobo-archive-private-hz/blotters/
    返回 OSS Object Key
    """
    p = Path(file_path).expanduser().resolve()
    if not p.exists():
        raise FileNotFoundError(f"找不到交割单文件: {p}")

    sha256_hex = compute_sha256(p)
    ext = p.suffix.lower()
    now_prefix = datetime.now().strftime("%Y/%m")
    oss_key = f"blotters/{now_prefix}/{sha256_hex[:16]}_{p.stem}{ext}"

    _, priv_bucket, _, priv_name = get_oss_buckets()

    if priv_bucket.object_exists(oss_key):
        print(f"⚡ [OSS 秒传命中] 私有交割单已存在: oss://{priv_name}/{oss_key}")
    else:
        priv_bucket.put_object_from_file(oss_key, str(p))
        print(f"🔒 [OSS 私有归档成功] 已上传至: oss://{priv_name}/{oss_key}")

    return oss_key


def upload_public_chart_webp(file_path: str, max_width: int = 1200) -> str:
    """
    将技术分析或期权波动率图表自动压缩为高清晰度 WebP，并上传至公有图床 mobobrain-assets-pub
    返回完整的公网 HTTPS URL
    """
    p = Path(file_path).expanduser().resolve()
    if not p.exists():
        raise FileNotFoundError(f"找不到图表文件: {p}")

    sha256_hex = compute_sha256(p)
    now_prefix = datetime.now().strftime("%Y/%m")
    oss_key = f"charts/{now_prefix}/{sha256_hex[:16]}.webp"

    pub_bucket, _, pub_name, _ = get_oss_buckets()
    public_domain = os.getenv(
        "OSS_PUBLIC_CDN_DOMAIN",
        f"https://{pub_name}.oss-cn-hangzhou.aliyuncs.com",
    ).rstrip("/")

    if pub_bucket.object_exists(oss_key):
        print(f"⚡ [OSS 秒传命中] 公开图表已存在: {public_domain}/{oss_key}")
        return f"{public_domain}/{oss_key}"

    # 使用 Pillow 自动转换为 RGB 并等比缩放压缩为 WebP
    with Image.open(p) as img:
        if img.mode in ("RGBA", "P"):
            img = img.convert("RGB")
        if img.width > max_width:
            ratio = max_width / float(img.width)
            new_height = int(float(img.height) * ratio)
            img = img.resize((max_width, new_height), Image.Resampling.LANCZOS)

        buf = BytesIO()
        img.save(buf, format="WEBP", quality=85, method=6)
        buf.seek(0)

    pub_bucket.put_object(
        oss_key,
        buf.read(),
        headers={"Content-Type": "image/webp", "Cache-Control": "public, max-age=31536000"},
    )
    url = f"{public_domain}/{oss_key}"
    print(f"🌐 [公有图床发布成功] WebP 图表已生成: {url}")
    return url


# ============================================================================
# 3. Markdown 复盘模板解析器 (--from-md 模式)
# ============================================================================
def parse_trade_markdown(md_path: str) -> dict:
    """
    解析带有 YAML Frontmatter 的交易复盘 Markdown 文件
    正文支持以 '## Pre-Trade Thesis' / '## Execution Review' / '## Lessons Learned' 分段
    """
    p = Path(md_path).expanduser().resolve()
    content = p.read_text(encoding="utf-8")

    if not content.startswith("---"):
        raise ValueError("Markdown 复盘文件必须包含顶部 YAML Frontmatter (以 --- 开头)")

    parts = content.split("---", 2)
    frontmatter = yaml.safe_load(parts[1])
    body = parts[2].strip()

    sections = {"pre_trade": "", "execution": "", "lessons": ""}
    current_sec = "pre_trade"

    for line in body.splitlines():
        header_lower = line.strip().lower()
        if header_lower.startswith("## ") and ("pre-trade" in header_lower or "建仓前" in header_lower):
            current_sec = "pre_trade"
            continue
        elif header_lower.startswith("## ") and ("execution" in header_lower or "持仓" in header_lower or "平仓" in header_lower):
            current_sec = "execution"
            continue
        elif header_lower.startswith("## ") and ("lesson" in header_lower or "心得" in header_lower or "教训" in header_lower):
            current_sec = "lessons"
            continue
        sections[current_sec] += line + "\n"

    frontmatter["pre_trade_thesis_md"] = sections["pre_trade"].strip()
    frontmatter["execution_review_md"] = sections["execution"].strip()
    frontmatter["lessons_learned_md"] = sections["lessons"].strip()
    return frontmatter


# ============================================================================
# 4. 录入/更新实盘交易复盘 (写入 db_mobobrain.trade_reviews)
# ============================================================================
def upsert_trade_review(args):
    """将交易复盘数据幂等写入 db_mobobrain.trade_reviews，并自动关联策略与宏观主线"""
    data = {}
    if args.from_md:
        data = parse_trade_markdown(args.from_md)

    # 命令行参数优先级高于 Markdown Frontmatter
    trade_code = args.code or data.get("trade_code")
    strategy_code = args.strategy or data.get("strategy_code")
    thesis_code = args.thesis or data.get("thesis_code")
    ticker = args.ticker or data.get("underlying_ticker")
    asset_name = args.asset_name or data.get("asset_name", ticker)
    direction = (args.direction or data.get("direction", "LONG")).upper()
    structure = args.structure or data.get("instrument_structure", "Spot")
    entry_date = args.entry_date or str(data.get("entry_date", date.today()))
    exit_date = args.exit_date or (str(data["exit_date"]) if data.get("exit_date") else None)
    status = (args.status or data.get("trade_status", "CLOSED")).upper()

    init_risk = float(args.init_risk if args.init_risk is not None else data.get("initial_risk_pct", 1.0))
    r_mult = args.r_multiple if args.r_multiple is not None else data.get("realized_r_multiple")
    ret_pct = args.return_pct if args.return_pct is not None else data.get("realized_return_pct")
    impact_bps = args.impact_bps if args.impact_bps is not None else data.get("portfolio_impact_bps")
    discipline = int(args.discipline if args.discipline is not None else data.get("discipline_score", 9))
    emotion = (args.emotion or data.get("emotional_state_tag", "CALM_SYSTEMATIC")).upper()
    visibility = (args.visibility or data.get("visibility", "PUBLIC")).upper()

    pre_thesis = args.pre_thesis or data.get("pre_trade_thesis_md", "")
    exec_review = args.exec_review or data.get("execution_review_md", "")
    lessons = args.lessons or data.get("lessons_learned_md", "")

    # 解析 Greeks JSON
    if args.greeks:
        greeks_dict = json.loads(args.greeks)
    else:
        greeks_dict = data.get("greeks_snapshot", {})

    if not all([trade_code, strategy_code, ticker, pre_thesis]):
        raise ValueError("必填字段缺失：必须提供 trade_code, strategy_code, ticker 以及建仓前逻辑 pre_thesis")

    # 处理 OSS 交割单与公开图表上传
    blotter_oss_key = data.get("private_blotter_oss_key")
    if args.blotter:
        blotter_oss_key = upload_private_blotter(args.blotter)

    chart_oss_url = data.get("public_chart_oss_url")
    if args.chart:
        chart_oss_url = upload_public_chart_webp(args.chart)

    conn = get_db_conn("capital")
    try:
        with conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                # 1. 查询 strategy_id
                cur.execute(
                    "SELECT id FROM strategy_playbooks WHERE strategy_code = %s;",
                    (strategy_code,),
                )
                strat_row = cur.fetchone()
                if not strat_row:
                    raise ValueError(
                        f"策略代码 '{strategy_code}' 在 strategy_playbooks 表中不存在，请先核对！"
                    )
                strategy_id = strat_row["id"]

                # 2. 查询可选的 thesis_id
                thesis_id = None
                if thesis_code:
                    cur.execute(
                        "SELECT id FROM macro_theses WHERE thesis_code = %s;",
                        (thesis_code,),
                    )
                    t_row = cur.fetchone()
                    if t_row:
                        thesis_id = t_row["id"]
                    else:
                        print(f"⚠️ 提示: 未找到宏观主线 '{thesis_code}'，将保持 thesis_id 为空。")

                # 3. 幂等 UPSERT 交易复盘记录
                upsert_sql = """
                INSERT INTO trade_reviews (
                    trade_code, thesis_id, strategy_id, underlying_ticker, asset_name,
                    direction, instrument_structure, entry_date, exit_date, trade_status,
                    initial_risk_pct, realized_r_multiple, realized_return_pct, portfolio_impact_bps,
                    greeks_snapshot, pre_trade_thesis_md, execution_review_md, lessons_learned_md,
                    discipline_score, emotional_state_tag, private_blotter_oss_key, public_chart_oss_url,
                    visibility, updated_at
                ) VALUES (
                    %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s,
                    %s, %s, %s, %s,
                    %s, %s, %s, %s,
                    %s, %s, %s, %s,
                    %s, CURRENT_TIMESTAMP
                )
                ON CONFLICT (trade_code) DO UPDATE SET
                    thesis_id = EXCLUDED.thesis_id,
                    strategy_id = EXCLUDED.strategy_id,
                    underlying_ticker = EXCLUDED.underlying_ticker,
                    asset_name = EXCLUDED.asset_name,
                    direction = EXCLUDED.direction,
                    instrument_structure = EXCLUDED.instrument_structure,
                    entry_date = EXCLUDED.entry_date,
                    exit_date = EXCLUDED.exit_date,
                    trade_status = EXCLUDED.trade_status,
                    initial_risk_pct = EXCLUDED.initial_risk_pct,
                    realized_r_multiple = EXCLUDED.realized_r_multiple,
                    realized_return_pct = EXCLUDED.realized_return_pct,
                    portfolio_impact_bps = EXCLUDED.portfolio_impact_bps,
                    greeks_snapshot = EXCLUDED.greeks_snapshot,
                    pre_trade_thesis_md = EXCLUDED.pre_trade_thesis_md,
                    execution_review_md = EXCLUDED.execution_review_md,
                    lessons_learned_md = EXCLUDED.lessons_learned_md,
                    discipline_score = EXCLUDED.discipline_score,
                    emotional_state_tag = EXCLUDED.emotional_state_tag,
                    private_blotter_oss_key = COALESCE(EXCLUDED.private_blotter_oss_key, trade_reviews.private_blotter_oss_key),
                    public_chart_oss_url = COALESCE(EXCLUDED.public_chart_oss_url, trade_reviews.public_chart_oss_url),
                    visibility = EXCLUDED.visibility,
                    updated_at = CURRENT_TIMESTAMP
                RETURNING id, trade_code, realized_r_multiple, discipline_score;
                """
                cur.execute(
                    upsert_sql,
                    (
                        trade_code,
                        thesis_id,
                        strategy_id,
                        ticker,
                        asset_name,
                        direction,
                        structure,
                        entry_date,
                        exit_date,
                        status,
                        init_risk,
                        r_mult,
                        ret_pct,
                        impact_bps,
                        Json(greeks_dict),
                        pre_thesis,
                        exec_review,
                        lessons,
                        discipline,
                        emotion,
                        blotter_oss_key,
                        chart_oss_url,
                        visibility,
                    ),
                )
                res = cur.fetchone()
                print(
                    f"✅ [db_mobobrain 入库成功] 战役 {res['trade_code']} | 实现 R 乘数: {res['realized_r_multiple']}R | 纪律分: {res['discipline_score']}/10"
                )
    finally:
        conn.close()

    # 自动触发前端静态 JSON 导出
    if not args.skip_sync:
        export_capital_frontend_json(args.web_dir)


# ============================================================================
# 5. 自动导出并物理脱敏 MoBoCapital.com 前端静态数据包
# ============================================================================
def json_serial(obj):
    """处理日期与 Decimal 的 JSON 序列化"""
    if isinstance(obj, (datetime, date)):
        return obj.isoformat()
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Type {type(obj)} not serializable")


def export_capital_frontend_json(web_dir_override: str = None):
    """
    从 db_mobobrain 导出最新统计数据，生成两份物理隔离的前端数据文件:
    1. data/public-data.json   -> 供公域与 LP_PROSPECT 视图读取（物理剥离私有交割单 Key 与 INTERNAL 记录）
    2. internal/internal-data.json -> 供 Caddy BasicAuth 保护的内网驾驶舱读取（含私有交割单 1 小时临时签名 URL）
    """
    base_dir = Path(
        web_dir_override
        or os.getenv("MOBOCAPITAL_WEB_DIR", "/opt/mobo-stack/sites/mobocapital")
    )
    pub_data_dir = base_dir / "data"
    int_data_dir = base_dir / "internal"
    pub_data_dir.mkdir(parents=True, exist_ok=True)
    int_data_dir.mkdir(parents=True, exist_ok=True)

    conn = get_db_conn("capital")
    _, priv_bucket, _, _ = get_oss_buckets()

    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            # 1. 拉取策略绩效汇总视图 (v_strategy_performance_summary)
            cur.execute("SELECT * FROM v_strategy_performance_summary ORDER BY strategy_code;")
            strategies_perf = cur.fetchall()

            # 2. 拉取宏观投研主线 (macro_theses)
            cur.execute(
                """
                SELECT thesis_code, title, region, asset_class, time_horizon,
                       directional_bias, conviction_score, leading_indicators,
                       core_logic_md, invalidation_criteria, status, visibility, created_at
                FROM macro_theses
                WHERE status IN ('ACTIVE', 'VALIDATED')
                ORDER BY created_at DESC;
                """
            )
            theses_all = cur.fetchall()

            # 3. 拉取实战复盘台账 (trade_reviews 关联 strategy_code)
            cur.execute(
                """
                SELECT tr.trade_code, sp.strategy_code, mt.thesis_code,
                       tr.underlying_ticker, tr.asset_name, tr.direction, tr.instrument_structure,
                       tr.entry_date, tr.exit_date, tr.trade_status, tr.initial_risk_pct,
                       tr.realized_r_multiple, tr.realized_return_pct, tr.portfolio_impact_bps,
                       tr.greeks_snapshot, tr.pre_trade_thesis_md, tr.execution_review_md,
                       tr.lessons_learned_md, tr.discipline_score, tr.emotional_state_tag,
                       tr.private_blotter_oss_key, tr.public_chart_oss_url, tr.visibility
                FROM trade_reviews tr
                JOIN strategy_playbooks sp ON tr.strategy_id = sp.id
                LEFT JOIN macro_theses mt ON tr.thesis_id = mt.id
                ORDER BY tr.entry_date DESC;
                """
            )
            trades_all = cur.fetchall()

            # 4. 拉取基金孵化里程碑 (fund_incubation_milestones)
            cur.execute(
                """
                SELECT phase_number, phase_name, domain_category, milestone_title,
                       target_metric_desc, current_progress_pct, target_date, status, visibility
                FROM fund_incubation_milestones
                ORDER BY phase_number ASC, target_date ASC;
                """
            )
            milestones_all = cur.fetchall()

            # 5. 拉取自媒体转化漏斗视图 (v_media_conversion_funnel)
            cur.execute("SELECT * FROM v_media_conversion_funnel;")
            media_funnel = cur.fetchall()

        # 组装 PUBLIC / LP_PROSPECT 安全脱敏包
        public_trades = []
        internal_trades = []

        for t in trades_all:
            t_int = dict(t)
            # 为内网驾驶舱生成 3600 秒有效期的 OSS 私有交割单临时签名链接
            if t_int.get("private_blotter_oss_key"):
                try:
                    t_int["signed_blotter_url"] = priv_bucket.sign_url(
                        "GET", t_int["private_blotter_oss_key"], 3600
                    )
                except Exception:
                    t_int["signed_blotter_url"] = None
            internal_trades.append(t_int)

            # 物理过滤 INTERNAL 级别的交易，且彻底移除 private_blotter_oss_key
            if t["visibility"] in ("PUBLIC", "LP_PROSPECT"):
                t_pub = dict(t)
                t_pub.pop("private_blotter_oss_key", None)
                public_trades.append(t_pub)

        public_payload = {
            "generated_at": datetime.now().isoformat(),
            "clearance_scope": "PUBLIC_AND_LP_PROSPECT",
            "strategies_summary": strategies_perf,
            "macro_theses": [m for m in theses_all if m["visibility"] != "INTERNAL"],
            "trade_reviews": public_trades,
            "incubation_milestones": [
                ms for ms in milestones_all if ms["visibility"] != "INTERNAL"
            ],
            "media_funnel": media_funnel,
        }

        internal_payload = {
            "generated_at": datetime.now().isoformat(),
            "clearance_scope": "INTERNAL_FULL_COCKPIT",
            "strategies_summary": strategies_perf,
            "macro_theses": theses_all,
            "trade_reviews": internal_trades,
            "incubation_milestones": milestones_all,
            "media_funnel": media_funnel,
        }

        pub_file = pub_data_dir / "public-data.json"
        int_file = int_data_dir / "internal-data.json"

        pub_file.write_text(
            json.dumps(public_payload, default=json_serial, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        int_file.write_text(
            json.dumps(internal_payload, default=json_serial, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

        print(f"🚀 [MoBoCapital 前端数据已同步]")
        print(f"   ├─ 公域脱敏数据包: {pub_file} (共 {len(public_trades)} 笔公开/LP战役)")
        print(f"   └─ 内网全量数据包: {int_file} (共 {len(internal_trades)} 笔全量战役，含私有交割单签名链接)")

    finally:
        conn.close()


# ============================================================================
# 6. CLI 命令路由定义
# ============================================================================
def build_parser():
    parser = argparse.ArgumentParser(
        description="MoBo Dual-Site CLI v2.0 — 莫伯资本 & 莫伯之家双站终端录入与同步引擎"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # 子命令 1: trade (录入/更新莫伯资本实战交易复盘)
    p_trade = subparsers.add_parser(
        "trade", help="[MoBoCapital] 录入或更新一笔实盘交易复盘，支持期权 Greeks 与私有交割单归档"
    )
    p_trade.add_argument("--from-md", type=str, help="从带 YAML Frontmatter 的 Markdown 文件直接解析复盘")
    p_trade.add_argument("--code", type=str, help="战役唯一编号，如 TRD-202610-300ETF-CALL")
    p_trade.add_argument("--strategy", type=str, help="关联策略编号，如 OPT-VOL-SKEW-01")
    p_trade.add_argument("--thesis", type=str, help="关联宏观主线编号，如 THESIS-2026Q4-CN-RETAIL")
    p_trade.add_argument("--ticker", type=str, help="交易标的代码，如 510300.SH 或 SPY")
    p_trade.add_argument("--asset-name", type=str, help="标的名称，如 沪深300 ETF")
    p_trade.add_argument(
        "--direction",
        type=str,
        choices=["LONG", "SHORT", "DELTA_NEUTRAL", "RELATIVE_VALUE"],
        help="头寸方向",
    )
    p_trade.add_argument("--structure", type=str, help="工具与期权结构，如 Bull Call Spread (45DTE)")
    p_trade.add_argument("--entry-date", type=str, help="建仓日期 YYYY-MM-DD")
    p_trade.add_argument("--exit-date", type=str, help="平仓日期 YYYY-MM-DD")
    p_trade.add_argument(
        "--status", type=str, choices=["OPEN", "CLOSED", "STOPPED_OUT"], help="交易状态"
    )
    p_trade.add_argument("--init-risk", type=float, help="初始风险敞口占 NAV 百分比 (如 1.20)")
    p_trade.add_argument("--r-multiple", type=float, help="实现 R 乘数 (如 3.15 或 -0.85)")
    p_trade.add_argument("--return-pct", type=float, help="单笔头寸收益率百分比")
    p_trade.add_argument("--impact-bps", type=int, help="对组合净值贡献基点 (bps，如 378)")
    p_trade.add_argument("--greeks", type=str, help="期权 Greeks 快照 JSON 字符串")
    p_trade.add_argument("--discipline", type=int, help="交易纪律执行打分 (1-10)")
    p_trade.add_argument("--emotion", type=str, help="心理状态标签，如 CALM_SYSTEMATIC")
    p_trade.add_argument("--pre-thesis", type=str, help="建仓前逻辑与赔率推演 (Markdown)")
    p_trade.add_argument("--exec-review", type=str, help="持仓调仓与平仓执行复盘 (Markdown)")
    p_trade.add_argument("--lessons", type=str, help="交易心得与认知复盘 (Markdown)")
    p_trade.add_argument("--blotter", type=str, help="本地私有交割单文件路径 (自动上传至私有 OSS 桶)")
    p_trade.add_argument("--chart", type=str, help="本地公开图表路径 (自动转 WebP 上传至公有图床)")
    p_trade.add_argument(
        "--visibility",
        type=str,
        choices=["PUBLIC", "LP_PROSPECT", "INTERNAL"],
        help="访问权限层级",
    )
    p_trade.add_argument("--web-dir", type=str, help="MoBoCapital 静态站点根目录覆盖")
    p_trade.add_argument("--skip-sync", action="store_true", help="仅入库，暂不触发前端 JSON 导出")

    # 子命令 2: sync-capital-web (手动触发 MoBoCapital.com 前端静态 JSON 更新)
    p_sync = subparsers.add_parser(
        "sync-capital-web", help="[MoBoCapital] 导出 PostgreSQL 最新统计数据至前端静态 JSON"
    )
    p_sync.add_argument("--web-dir", type=str, help="MoBoCapital 静态站点根目录覆盖")

    # 子命令 3: milestone (快速更新莫伯资本对冲基金孵化里程碑进度)
    p_ms = subparsers.add_parser(
        "milestone", help="[MoBoCapital] 更新对冲基金三阶段孵化里程碑完成度"
    )
    p_ms.add_argument("--title-keyword", type=str, required=True, help="里程碑标题关键词匹配")
    p_ms.add_argument("--progress", type=int, required=True, help="最新进度百分比 (0-100)")
    p_ms.add_argument("--status", type=str, default="IN_PROGRESS", help="PLANNED | IN_PROGRESS | COMPLETED")
    p_ms.add_argument("--web-dir", type=str, help="MoBoCapital 静态站点根目录覆盖")

    return parser


def update_milestone(args):
    conn = get_db_conn("capital")
    try:
        with conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    UPDATE fund_incubation_milestones
                    SET current_progress_pct = %s,
                        status = %s,
                        completed_date = CASE WHEN %s = 100 THEN CURRENT_DATE ELSE completed_date END
                    WHERE milestone_title ILIKE %s
                    RETURNING milestone_title, current_progress_pct, status;
                    """,
                    (args.progress, args.status, args.progress, f"%{args.title_keyword}%"),
                )
                rows = cur.fetchall()
                if not rows:
                    print(f"⚠️ 未匹配到包含 '{args.title_keyword}' 的孵化里程碑。")
                for r in rows:
                    print(f"✅ [里程碑已更新] {r['milestone_title']} -> {r['current_progress_pct']}% ({r['status']})")
    finally:
        conn.close()
    export_capital_frontend_json(args.web_dir)


if __name__ == "__main__":
    parser = build_parser()
    cli_args = parser.parse_args()

    if cli_args.command == "trade":
        upsert_trade_review(cli_args)
    elif cli_args.command == "sync-capital-web":
        export_capital_frontend_json(cli_args.web_dir)
    elif cli_args.command == "milestone":
        update_milestone(cli_args)