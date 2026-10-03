"""Dogtoujunshi's evidence-first reading of Jev's structured answers.

This module does not infer new facts from OCR. The short quotes are explicitly
marked as text to check in WeChat, and Jev confidence is never a success rate.
"""
from __future__ import annotations

from math import isfinite

try:
    from . import shared
    from .questions import CHOICE_LABELS, next_step
except ImportError:
    import shared
    from questions import CHOICE_LABELS, next_step


def _boundaries() -> dict:
    """No-contact terms and the stop line, shared by all three ports."""
    return shared.data("boundaries.json")


def _message_parts(message):
    if isinstance(message, dict):
        return message.get("from"), str(message.get("text") or "")
    return message[0], str(message[1])


def explicit_boundary(messages: list) -> bool:
    """Only the latest *other* message can trigger a conservative no-draft exit."""
    if not messages:
        return False
    who, text = _message_parts(messages[-1])
    if who != "other":
        return False
    return any(term in text for term in _boundaries()["no_contact_terms"])


def brief(messages: list, answers: dict) -> dict:
    """Compact display contract shared by the Windows overlay and CLI checks."""
    observed = []
    for message in messages[-8:]:
        who, text = _message_parts(message)
        if who in ("me", "other") and text.strip():
            observed.append(("我" if who == "me" else "对方") + "：「" + text.strip()[:100] + "」")
    intent_row = (answers.get("true_intent") or {})
    intent_key = intent_row.get("choice")
    intent = CHOICE_LABELS["true_intent"].get(intent_key, "暂无法判断")
    confidence = intent_row.get("confidence")
    if not isinstance(confidence, (int, float)) or isinstance(confidence, bool) or not isfinite(confidence) or not 0 <= confidence <= 1:
        confidence = None
    action_key = (answers.get("best_action") or {}).get("choice")
    action = CHOICE_LABELS["best_action"].get(action_key, "先核对原文")
    boundary = explicit_boundary(messages)
    return {
        "facts": observed[-3:],
        "intent": "可能是" + intent if intent_key else "证据不足，暂无法判断",
        "intent_confidence": confidence if observed and not boundary else None,
        "action": "尊重对方停止联系的要求" if boundary else action,
        "unknown": "仅凭屏幕片段无法确认对方内心、完整上下文和线下情况。",
        "next_step": "先停止联系；只有对方主动重启对话再评估。" if boundary else next_step(action_key),
        "stop_condition": _boundaries()["stop_condition"],
        "evidence_note": "以上引文来自 OCR，须核对原文和说话人；把握度是模型估计，不是对方真实意图概率。",
    }
