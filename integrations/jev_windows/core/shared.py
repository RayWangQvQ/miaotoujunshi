# -*- coding: utf-8 -*-
"""Reads the material the three ports share, from this repository's own payload.

The tone rules, the judge question set, the strategy vocabulary, the CSV
contract and the demo cases belong to no single port, so they live in
`miaotoujunshi/` at the repository root and are read as files at runtime instead
of being inlined here (docs/adr/0006). A missing file is a hard error: a
forgotten packaging entry has to fail loudly at the first read rather than drift
into a second copy.
"""
from __future__ import annotations

import json
import sys
from functools import lru_cache
from pathlib import Path


def _root() -> Path:
    """Directory holding the shared directories, in source and when frozen."""
    if getattr(sys, "frozen", False):
        # PyInstaller onedir: `datas` (jev.spec) land beside the executable.
        return Path(getattr(sys, "_MEIPASS", Path(sys.executable).parent))
    return Path(__file__).resolve().parents[3]


REPO_ROOT = _root()


def read(relative: str) -> str:
    """One shared file, by its repository-relative path."""
    try:
        return (REPO_ROOT / relative).read_text(encoding="utf-8")
    except OSError as exc:
        raise FileNotFoundError(
            f"缺少跨端公用文件 {relative}；打包时须把它和程序一起分发") from exc


@lru_cache(maxsize=None)
def data(name: str) -> dict:
    """One miaotoujunshi/references/data/*.json, by file name."""
    try:
        return json.loads(read(f"miaotoujunshi/references/data/{name}"))
    except json.JSONDecodeError as exc:
        raise ValueError(
            f"跨端公用数据 miaotoujunshi/references/data/{name} 不是有效 JSON") from exc


def tone_rules() -> str:
    """The shared tone and trade-off rules, injected into the draft prompt."""
    return read("miaotoujunshi/references/knowledge/口吻与取舍.md")


def skill_document() -> str:
    """The upstream skill payload's entry document. Read-only: it stays byte-identical."""
    return read("goutoujunshi/SKILL.md")


def case_manifest() -> dict:
    """The demo case manifest: id, title and the CSV each case reads."""
    return json.loads(read("miaotoujunshi/examples/relationship_cases/manifest.json"))


def demo_candles() -> dict:
    """Illustrative candles per case id, from the same bundle as the manifest."""
    return json.loads(
        read("miaotoujunshi/examples/relationship_cases/demo_kline.json"))["cases"]
