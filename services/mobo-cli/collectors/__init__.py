"""独立采集器包（不属于 mobo_cli 运行时包，但随 venv 一起可导入）。

放在包外是为了让脚本能以 ``python services/mobo-cli/collectors/macro_iv_collector.py``
直接执行（cron 场景），同时仍可被 pytest 以 ``collectors.macro_iv_collector`` 引用。
"""
