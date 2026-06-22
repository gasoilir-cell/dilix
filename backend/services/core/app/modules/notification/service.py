"""سرویس اعلان — ایجاد و علامت‌گذاریِ خواندن."""
from __future__ import annotations

import uuid

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.notification.models import CHANNEL_IN_APP, Notification


async def send(
    db: AsyncSession,
    *,
    recipient_earth_id: uuid.UUID,
    title: str,
    body: str,
    channel: str = CHANNEL_IN_APP,
    data: dict | None = None,
) -> Notification:
    notif = Notification(
        recipient_earth_id=recipient_earth_id,
        channel=channel,
        title=title,
        body=body,
        data=data or {},
    )
    db.add(notif)
    await db.flush()
    return notif


async def list_inbox(
    db: AsyncSession, recipient_earth_id: uuid.UUID, unread_only: bool = False, limit: int = 50
) -> list[Notification]:
    q = select(Notification).where(Notification.recipient_earth_id == recipient_earth_id)
    if unread_only:
        q = q.where(Notification.read.is_(False))
    q = q.order_by(Notification.created_at.desc()).limit(limit)
    return list((await db.execute(q)).scalars().all())


async def mark_read(
    db: AsyncSession, notification_id: uuid.UUID, recipient_earth_id: uuid.UUID
) -> None:
    await db.execute(
        update(Notification)
        .where(
            Notification.id == notification_id,
            Notification.recipient_earth_id == recipient_earth_id,
        )
        .values(read=True)
    )
    await db.flush()
