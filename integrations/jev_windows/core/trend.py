"""Local chat-message balance candles. No model call and no relationship score."""
from __future__ import annotations

import csv
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

try:
    from . import shared
except ImportError:
    import shared

# The CSV contract and its limits are shared by all three ports
# (references/data/trend-rules.json, see docs/adr/0005).
_RULES = shared.data("trend-rules.json")
MAX_BYTES = _RULES["max_bytes"]
MAX_MESSAGES = _RULES["max_messages"]
COLUMNS = tuple(_RULES["columns"])
SENDERS = tuple(_RULES["senders"])


@dataclass(frozen=True)
class Candle:
    date: str
    open: int
    high: int
    low: int
    close: int


def demo_cases() -> tuple[tuple[str, str], ...]:
    """(case id, display title) for every demo case, from the shared case bundle."""
    return tuple((row["id"], row["title"]) for row in shared.case_manifest()["cases"])


def demo(case_id: str) -> tuple[Candle, ...]:
    """Illustrative candles for one demo case; the file sits in examples/, not here."""
    rows = shared.demo_candles().get(case_id)
    if rows is None:
        raise ValueError("没有这个示例走势")
    return tuple(Candle(date, open_, high, low, close)
                 for date, open_, high, low, close in rows)


def load_csv(path: str | Path) -> tuple[Candle, ...]:
    """timestamp,sender,message; sender is me/other, sorted ascending."""
    source = Path(path)
    if source.suffix.lower() != ".csv" or not source.is_file():
        raise ValueError("请选择聊天 CSV 文件")
    if source.stat().st_size > MAX_BYTES:
        raise ValueError("CSV 超过 4 MB，请缩小时间范围")
    balance = 0
    rows = []
    previous = None
    count = 0
    try:
        with source.open(encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            if not reader.fieldnames or not set(COLUMNS).issubset(reader.fieldnames):
                raise ValueError("CSV 需要 timestamp,sender,message 三列")
            for item in reader:
                count += 1
                if count > MAX_MESSAGES:
                    raise ValueError("聊天超过 20000 条，请缩小范围")
                at = datetime.fromisoformat((item.get("timestamp") or "").strip())
                if previous and at < previous:
                    raise ValueError("聊天时间必须按升序排列")
                previous = at
                sender = (item.get("sender") or "").strip()
                if sender not in SENDERS or not (item.get("message") or "").strip():
                    raise ValueError("请核对 sender（me／other）和消息正文")
                date = at.date().isoformat()
                if not rows or rows[-1].date != date:
                    rows.append(Candle(date, balance, balance, balance, balance))
                balance += 1 if sender == "other" else -1
                old = rows[-1]
                rows[-1] = Candle(date, old.open, max(old.high, balance),
                                  min(old.low, balance), balance)
    except (UnicodeError, csv.Error) as exc:
        raise ValueError("CSV 无法读取，请检查编码和列名") from exc
    if not rows:
        raise ValueError("CSV 没有聊天记录")
    return tuple(rows)
