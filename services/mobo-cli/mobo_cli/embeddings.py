"""OpenAI-compatible Embedding 适配层（可选）。"""
from __future__ import annotations

import json

import requests

from .config import Settings


def vector_literal(values: list[float]) -> str:
    return "[" + ",".join(f"{float(v):.8f}" for v in values) + "]"


def embed_text(settings: Settings, text: str) -> list[float] | None:
    if not (settings.embedding_api_base and settings.embedding_api_key and settings.embedding_model):
        return None
    text = (text or "").strip()
    if not text:
        return None
    url = settings.embedding_api_base.rstrip("/") + "/embeddings"
    resp = requests.post(
        url,
        headers={
            "Authorization": f"Bearer {settings.embedding_api_key}",
            "Content-Type": "application/json",
        },
        data=json.dumps({"model": settings.embedding_model, "input": text[:6000]}),
        timeout=45,
    )
    resp.raise_for_status()
    payload = resp.json()
    vector = payload["data"][0]["embedding"]
    if len(vector) != settings.embedding_dim:
        raise ValueError(
            f"Embedding 维度不匹配：模型返回 {len(vector)}，数据库/配置期望 {settings.embedding_dim}。"
            "请修改 EMBEDDING_DIM 并执行维度迁移。"
        )
    return [float(x) for x in vector]
