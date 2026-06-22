"""ماشینِ حالتِ محموله — منطقِ خالص و بدونِ وابستگیِ ORM (تست‌پذیر)."""
from __future__ import annotations

from app.modules.carrier.models import (
    STATUS_CANCELLED,
    STATUS_CREATED,
    STATUS_DELIVERED,
    STATUS_DISPATCHED,
    STATUS_IN_TRANSIT,
)

ALLOWED_TRANSITIONS: dict[str, frozenset[str]] = {
    STATUS_CREATED: frozenset({STATUS_DISPATCHED, STATUS_CANCELLED}),
    STATUS_DISPATCHED: frozenset({STATUS_IN_TRANSIT, STATUS_CANCELLED}),
    STATUS_IN_TRANSIT: frozenset({STATUS_DELIVERED, STATUS_CANCELLED}),
    STATUS_DELIVERED: frozenset(),  # نهایی
    STATUS_CANCELLED: frozenset(),  # نهایی
}

# نگاشتِ وضعیتِ گزارش‌شده از سمتِ متصدی به وضعیتِ دامنه (track)
CARRIER_STATUS_MAP: dict[str, str] = {
    "dispatched": STATUS_DISPATCHED,
    "in_transit": STATUS_IN_TRANSIT,
    "delivered": STATUS_DELIVERED,
    "cancelled": STATUS_CANCELLED,
}


def can_transition(current: str, target: str) -> bool:
    return target in ALLOWED_TRANSITIONS.get(current, frozenset())


def is_terminal(status: str) -> bool:
    return not ALLOWED_TRANSITIONS.get(status, frozenset())
