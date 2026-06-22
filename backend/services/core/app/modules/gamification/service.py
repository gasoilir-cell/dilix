"""سرویس گیمیفیکیشن — اعطایِ امتیاز و نشان."""
from __future__ import annotations

import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.events import DomainEvent

from app.core.events import publisher
from app.modules.gamification.models import Badge, PointLedger


async def add_points(
    db: AsyncSession,
    *,
    earth_id: uuid.UUID,
    delta: int,
    reason: str,
    ref_id: uuid.UUID | None = None,
) -> PointLedger:
    entry = PointLedger(earth_id=earth_id, delta=delta, reason=reason, ref_id=ref_id)
    db.add(entry)
    await db.flush()
    await publisher.publish(
        db,
        DomainEvent("gamification.PointsAdded", {"earth_id": str(earth_id), "delta": delta, "reason": reason}),
    )
    return entry


async def get_balance(db: AsyncSession, earth_id: uuid.UUID) -> int:
    result = await db.execute(
        select(func.coalesce(func.sum(PointLedger.delta), 0))
        .where(PointLedger.earth_id == earth_id)
    )
    return int(result.scalar() or 0)


async def award_badge(
    db: AsyncSession,
    *,
    earth_id: uuid.UUID,
    badge_code: str,
    description: str | None = None,
) -> Badge:
    badge = Badge(earth_id=earth_id, badge_code=badge_code, description=description)
    db.add(badge)
    await db.flush()
    await publisher.publish(
        db,
        DomainEvent("gamification.BadgeAwarded", {"earth_id": str(earth_id), "badge": badge_code}),
    )
    return badge


async def list_badges(db: AsyncSession, earth_id: uuid.UUID) -> list[Badge]:
    result = await db.execute(
        select(Badge).where(Badge.earth_id == earth_id).order_by(Badge.awarded_at.desc())
    )
    return list(result.scalars().all())
