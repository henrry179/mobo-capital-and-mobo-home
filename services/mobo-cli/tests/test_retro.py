from __future__ import annotations

from mobo_cli.retro import parse_action_items, parse_kv_lines, parse_retro_markdown, pace_sec_per_km


def test_parse_kv_lines() -> None:
    assert parse_kv_lines(["- 阅读小时: 6.5", "- 训练次数=4", "- done: true", "noise"]) == {
        "阅读小时": 6.5,
        "训练次数": 4,
        "done": True,
    }


def test_parse_action_items() -> None:
    items = parse_action_items(["- 整理离线包 owner: 我 due: 周日", "- 预约体检"])
    assert items[0]["text"].startswith("整理离线包")
    assert items[0]["owner"] == "我"
    assert items[0]["due"] == "周日"
    assert items[1]["text"] == "预约体检"


def test_parse_retro_markdown() -> None:
    text = """
## 初始假设
早起阅读更稳定。

## 实际执行
完成 4 天。

## 根因分析
出差中断。

## 原则迭代
提前下载离线材料。

## KPI
- 阅读小时: 6.5
- 训练次数: 4

## 行动项
- 周日晚整理离线包
"""
    parsed = parse_retro_markdown(text)
    assert parsed["initial_hypothesis"] == "早起阅读更稳定。"
    assert parsed["actual_execution"] == "完成 4 天。"
    assert parsed["root_cause_analysis"] == "出差中断。"
    assert parsed["codified_principles"] == "提前下载离线材料。"
    assert parsed["kpi_snapshot"] == {"阅读小时": 6.5, "训练次数": 4}
    assert parsed["action_items"][0]["text"] == "周日晚整理离线包"


def test_pace_sec_per_km() -> None:
    assert pace_sec_per_km(10000, 50) == 300
    assert pace_sec_per_km(None, 50) is None
    assert pace_sec_per_km(0, 50) is None
