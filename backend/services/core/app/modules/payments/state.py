"""ماشینِ حالتِ سفارشِ پرداخت — منطقِ خالص و بدونِ وابستگی (تست‌پذیر).

جدا از ORM نگه داشته می‌شود تا invariantهای گذارِ حالت مستقل تست شوند.
"""
from __future__ import annotations

from app.modules.payments.models import (
    STATUS_CAPTURED,
    STATUS_CREATED,
    STATUS_ESCROWED,
    STATUS_FAILED,
    STATUS_REFUNDED,
)

# گذارهای مجاز: از هر حالت به کدام حالت‌ها می‌توان رفت.
ALLOWED_TRANSITIONS: dict[str, frozenset[str]] = {
    STATUS_CREATED: frozenset({STATUS_ESCROWED, STATUS_FAILED}),
    STATUS_ESCROWED: frozenset({STATUS_CAPTURED, STATUS_REFUNDED, STATUS_FAILED}),
    STATUS_CAPTURED: frozenset(),  # نهایی
    STATUS_REFUNDED: frozenset(),  # نهایی
    STATUS_FAILED: frozenset(),  # نهایی
}


def can_transition(current: str, target: str) -> bool:
    return target in ALLOWED_TRANSITIONS.get(current, frozenset())


def is_terminal(status: str) -> bool:
    return not ALLOWED_TRANSITIONS.get(status, frozenset())
