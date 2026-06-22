"""ناشر رویداد (Event Publisher) با الگوی Transactional Outbox (سند ۴).

`publish()` رویداد را در جدول `events.outbox_event` و در **همان** session/تراکنشِ
تغییرِ دامنه می‌نویسد. ارسالِ واقعی به broker را relay جداگانه انجام می‌دهد
(`app/core/relay.py`). این از مشکلِ dual-write جلوگیری می‌کند.
"""
from __future__ import annotations

import logging

from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.events import DomainEvent, EventEnvelope

from app.core.config import get_settings
from app.core.outbox import OutboxEvent

logger = logging.getLogger("dilix.events")
_settings = get_settings()


class EventPublisher:
    """رویداد را به‌صورت اتمیک در outbox قرار می‌دهد (هنوز commit نمی‌کند)."""

    async def publish(
        self,
        db: AsyncSession,
        event: DomainEvent,
        *,
        correlation_id: str | None = None,
    ) -> None:
        envelope = EventEnvelope(
            event=event, region=_settings.region, correlation_id=correlation_id
        )
        db.add(
            OutboxEvent(
                id=envelope.event_id,
                name=event.name,
                schema_version=event.schema_version,
                region=envelope.region,
                correlation_id=correlation_id,
                payload=event.payload,
                occurred_at=envelope.occurred_at,
            )
        )
        logger.info("event.enqueued name=%s id=%s", event.name, envelope.event_id)


publisher = EventPublisher()
