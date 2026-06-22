"""قرارداد رویدادهای دامنه (Published Language) — مطابق AsyncAPI فاز ۵.

هر رویداد یک نام نسخه‌دار و payload دارد. انتشار اتمیک از طریق Outbox
(سند ۴) انجام می‌شود؛ این‌جا فقط ساختار پیام تعریف می‌شود.
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


@dataclass(frozen=True, slots=True)
class DomainEvent:
    """رویداد دامنه‌ی پایه. زیرکلاس‌ها فقط payload و name را مشخص می‌کنند."""

    name: str
    payload: dict[str, Any]
    schema_version: int = 1


@dataclass(frozen=True, slots=True)
class EventEnvelope:
    """پاکت انتقال رویداد روی Event Backbone (Kafka/NATS)."""

    event: DomainEvent
    event_id: uuid.UUID = field(default_factory=uuid.uuid4)
    occurred_at: datetime = field(default_factory=_utcnow)
    region: str | None = None
    correlation_id: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "event_id": str(self.event_id),
            "name": self.event.name,
            "schema_version": self.event.schema_version,
            "occurred_at": self.occurred_at.isoformat(),
            "region": self.region,
            "correlation_id": self.correlation_id,
            "payload": self.event.payload,
        }
