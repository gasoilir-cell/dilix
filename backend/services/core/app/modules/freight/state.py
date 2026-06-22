"""ماشینِ حالتِ بار — منطقِ خالص."""
from __future__ import annotations
from app.modules.freight.models import (
    CARGO_ASSIGNED, CARGO_BIDDING, CARGO_CANCELLED,
    CARGO_DELIVERED, CARGO_IN_TRANSIT, CARGO_OPEN, CARGO_SETTLED,
)

ALLOWED_TRANSITIONS: dict[str, frozenset[str]] = {
    CARGO_OPEN:       frozenset({CARGO_BIDDING, CARGO_CANCELLED}),
    CARGO_BIDDING:    frozenset({CARGO_ASSIGNED, CARGO_CANCELLED}),
    CARGO_ASSIGNED:   frozenset({CARGO_IN_TRANSIT, CARGO_CANCELLED}),
    CARGO_IN_TRANSIT: frozenset({CARGO_DELIVERED}),
    CARGO_DELIVERED:  frozenset({CARGO_SETTLED}),
    CARGO_SETTLED:    frozenset(),
    CARGO_CANCELLED:  frozenset(),
}


def can_transition(current: str, target: str) -> bool:
    return target in ALLOWED_TRANSITIONS.get(current, frozenset())


def is_terminal(status: str) -> bool:
    return not ALLOWED_TRANSITIONS.get(status, frozenset())
