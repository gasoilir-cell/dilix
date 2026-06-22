"""سرویس عضویت — ارتقا و لغو."""
from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.errors import NotFoundError
from dilix_shared.events import DomainEvent

from app.core.events import publisher
from app.modules.membership.models import (
    PLAN_CASHBACK_BPS, PLAN_FREE, STATUS_ACTIVE, STATUS_CANCELLED,
    MembershipSubscription,
)


async def _get_or_create(db: AsyncSession, earth_id: uuid.UUID) -> MembershipSubscription:
    result = await db.execute(
        select(MembershipSubscription).where(MembershipSubscription.earth_id == earth_id)
    )
    sub = result.scalars().first()
    if sub is None:
        sub = MembershipSubscription(
            earth_id=earth_id, plan=PLAN_FREE, cashback_bps=0
        )
        db.add(sub)
        await db.flush()
    return sub


async def upgrade(
    db: AsyncSession, earth_id: uuid.UUID, plan: str, months: int = 1
) -> MembershipSubscription:
    if plan not in PLAN_CASHBACK_BPS:
        from dilix_shared.errors import ConflictError
        raise ConflictError(f"طرحِ نامعتبر: {plan}")
    sub = await _get_or_create(db, earth_id)
    sub.plan = plan
    sub.cashback_bps = PLAN_CASHBACK_BPS[plan]
    sub.status = STATUS_ACTIVE
    sub.expires_at = datetime.now(timezone.utc) + timedelta(days=30 * months)
    await db.flush()
    await publisher.publish(
        db,
        DomainEvent("membership.Upgraded", {"earth_id": str(earth_id), "plan": plan}),
    )
    return sub


async def cancel(db: AsyncSession, earth_id: uuid.UUID) -> MembershipSubscription:
    sub = await _get_or_create(db, earth_id)
    sub.status = STATUS_CANCELLED
    await db.flush()
    return sub


async def get(db: AsyncSession, earth_id: uuid.UUID) -> MembershipSubscription:
    return await _get_or_create(db, earth_id)
