"""Outbox Relay — ردیف‌های pending را به NATS JetStream می‌فرستد (سند ۴).

به‌صورت یک حلقه‌ی پس‌زمینه اجرا می‌شود. هر دور:
1. ردیف‌های pending را با FOR UPDATE SKIP LOCKED قفل می‌گیرد (امن برای چند instance).
2. به broker منتشر می‌کند (با msg_id = شناسه‌ی رویداد برای dedup).
3. موفق → published؛ ناموفق → افزایش attempts؛ پس از سقف → dead (DLQ).
"""
from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timezone

from sqlalchemy import select, update

from app.core.broker import broker
from app.core.database import SessionLocal
from app.core.outbox import STATUS_DEAD, STATUS_PENDING, STATUS_PUBLISHED, OutboxEvent

logger = logging.getLogger("dilix.relay")

MAX_ATTEMPTS = 8
BATCH_SIZE = 100
POLL_INTERVAL_SECONDS = 1.0


def _serialize(row: OutboxEvent) -> bytes:
    occurred = row.occurred_at.isoformat() if row.occurred_at else None
    return json.dumps(
        {
            "event_id": str(row.id),
            "name": row.name,
            "schema_version": row.schema_version,
            "occurred_at": occurred,
            "region": row.region,
            "correlation_id": row.correlation_id,
            "payload": row.payload,
        },
        ensure_ascii=False,
    ).encode("utf-8")


async def relay_once() -> int:
    """یک دور drain. تعداد رویدادهای منتشرشده را برمی‌گرداند."""
    published = 0
    async with SessionLocal() as db:
        result = await db.execute(
            select(OutboxEvent)
            .where(OutboxEvent.status == STATUS_PENDING)
            .order_by(OutboxEvent.occurred_at)
            .limit(BATCH_SIZE)
            .with_for_update(skip_locked=True)
        )
        rows = list(result.scalars().all())
        for row in rows:
            try:
                await broker.publish(row.name, _serialize(row), msg_id=str(row.id))
                row.status = STATUS_PUBLISHED
                row.published_at = datetime.now(timezone.utc)
                published += 1
            except Exception as exc:  # noqa: BLE001 — هر خطای انتقال را مدیریت می‌کنیم
                row.attempts += 1
                row.last_error = str(exc)[:500]
                if row.attempts >= MAX_ATTEMPTS:
                    row.status = STATUS_DEAD
                    logger.error("relay.dead id=%s name=%s err=%s", row.id, row.name, exc)
                else:
                    logger.warning("relay.retry id=%s attempt=%s", row.id, row.attempts)
        await db.commit()
    return published


async def run_relay(stop: asyncio.Event | None = None) -> None:
    """حلقه‌ی همیشگیِ relay برای اجرا به‌عنوان worker یا lifespan task."""
    await broker.connect()
    logger.info("relay.started")
    while stop is None or not stop.is_set():
        try:
            count = await relay_once()
        except Exception:  # noqa: BLE001
            logger.exception("relay.loop_error")
            count = 0
        await asyncio.sleep(0.05 if count else POLL_INTERVAL_SECONDS)


# نشانه برای جلوگیری از انتشارِ مجددِ ردیف‌های dead در آینده
__all__ = ["relay_once", "run_relay", "MAX_ATTEMPTS", "STATUS_DEAD"]
