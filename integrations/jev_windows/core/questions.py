"""Fixed Jev question set. Instructions/criteria in English; chat text stays Chinese.

The wording is shared by all three ports and lives in
`references/data/judge-questions.json` — see docs/adr/0005. It is the wording
that passed calibration, so it is read, never retyped.
"""

from __future__ import annotations

try:
    from . import shared
except ImportError:
    import shared


def judge_questions() -> dict:
    """The seven judge questions, in the order they are asked."""
    return dict(shared.data("judge-questions.json")["questions"])


def next_step(action: str) -> str:
    """Display line for a best_action choice; shared with the task list wording."""
    questions = shared.data("judge-questions.json")
    return questions["next_step"].get(action, questions["next_step_fallback"])


# choice 类答案的中文说法，界面和起草小抄共用这一份（app/overlay.py 从这里导）。
CHOICE_LABELS: dict = {
    "true_intent": {
        "confirm_you_care": "希望确认你在意", "vent_anger": "表达不满或受伤",
        "request_action": "希望你采取行动", "seek_explanation": "希望了解原因",
        "casual_chat": "轻松交流", "close_topic": "平和结束话题",
    },
    "best_action": {
        "check_history": "先核对聊天记录", "apologize": "为已知问题道歉",
        "give_commitment": "给出具体承诺", "explain": "说明事实与原因",
        "acknowledge": "回应并表达理解", "say_less": "简短回应或留白",
        "make_plan": "商量具体安排",
    },
    "she_needs": {
        "apology": "真诚道歉", "action": "具体行动或安排", "explanation": "清楚的解释",
        "care": "关注与在意", "nothing": "可能无需补充回应",
    },
}

_GUIDE_FIELDS = (("true_intent", "对方意图"), ("she_needs", "对方需要"),
                 ("best_action", "建议动作"))


def guidance_text(answers: dict) -> str:
    """Jev 判断 → 喂给起草的中文小抄。只写有答案的那几项；没答案返回空串。"""
    lines = []
    for name, title in _GUIDE_FIELDS:
        choice = ((answers or {}).get(name) or {}).get("choice")
        label = CHOICE_LABELS[name].get(choice)
        if label:
            lines.append(f"- {title}：{label}（{choice}）")
    tail = []
    score = ((answers or {}).get("danger_level") or {}).get("score")
    if isinstance(score, (int, float)) and not isinstance(score, bool):
        tail.append(f"紧张度：{score:.0f}/9")
    noul = ((answers or {}).get("literal_question") or {}).get("noul")
    if isinstance(noul, (int, float)) and not isinstance(noul, bool):
        tail.append("字面意思：" + ("是" if noul >= 0.5 else "否（有潜台词）"))
    if tail:
        lines.append("- " + "；".join(tail))
    if not lines:
        return ""
    return "判断参考（Jev 给的，起草要顺着它写，但口吻仍按我的）：\n" + "\n".join(lines)


def build_state(messages: list, relationship: str, keep: int = 10,
                reply_to: str | None = None) -> dict:
    """messages: (from, text) / (from, text, name) / dict（name 可选）。from 只认 her/me。

    name = 群里的发言人；有 name 就当群聊（chat.is_group）。reply_to = 群里指定的回复对象。
    """
    cleaned = []
    for item in messages:
        if isinstance(item, dict):
            who, text, name = item.get("from"), item.get("text"), item.get("name")
        else:
            who, text = item[0], item[1]
            name = item[2] if len(item) > 2 else None
        if who not in ("her", "me"):
            raise ValueError(f"message from must be 'her' or 'me', got {who!r}")
        message = {"from": who, "text": str(text)}
        if name:
            message["name"] = str(name)
        cleaned.append(message)
    cleaned = cleaned[-keep:]
    latest_from = cleaned[-1]["from"] if cleaned else "her"
    chat = {
        "relationship": relationship,
        "messages": cleaned,
        "latest_from": latest_from,
        "is_group": any("name" in m for m in cleaned),
    }
    if reply_to:
        chat["reply_to"] = str(reply_to)
    return {"chat": chat}


def build_rank_question(candidates: list[str]) -> dict:
    """Build the best_reply choice question. criteria values stay in original Chinese."""
    if not 2 <= len(candidates) <= 3:
        raise ValueError("build_rank_question expects 2 or 3 candidate replies")
    keys = ("reply_a", "reply_b", "reply_c")[:len(candidates)]
    return {
        "best_reply": {
            "type": "choice",
            "instructions": shared.data("judge-questions.json")["rank_instructions"],
            "criteria": {key: text for key, text in zip(keys, candidates)},
        }
    }
