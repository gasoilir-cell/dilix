"""ماشینِ حالتِ بیمه‌نامه — منطقِ خالص و بدونِ وابستگیِ ORM (تست‌پذیر)."""
from __future__ import annotations

from app.modules.insurance.models import (
    STATUS_CANCELLED,
    STATUS_CLAIMED,
    STATUS_ISSUED,
    STATUS_QUOTED,
)

ALLOWED_TRANSITIONS: dict[str, frozenset[str]] = {
    STATUS_QUOTED: frozenset({STATUS_ISSUED, STATUS_CANCELLED}),
    STATUS_ISSUED: frozenset({STATUS_CLAIMED, STATUS_CANCELLED}),
    STATUS_CLAIMED: frozenset(),  # نهایی
    STATUS_CANCELLED: frozenset(),  # نهایی
}


def can_transition(current: str, target: str) -> bool:
    return target in ALLOWED_TRANSITIONS.get(current, frozenset())


def is_terminal(status: str) -> bool:
    return not ALLOWED_TRANSITIONS.get(status, frozenset())
