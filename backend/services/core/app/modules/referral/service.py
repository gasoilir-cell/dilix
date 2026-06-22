"""سرویس رفرال — ثبت زنجیرِ رفرال و اعطایِ پاداشِ گره‌خورده به تراکنش (ADR-08)."""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.errors import ConflictError
from dilix_shared.events import DomainEvent

from app.core.events import publisher
from app.modules.referral.models import (
    MAX_REFERRAL_LEVELS, STATUS_PENDING, STATUS_REWARDED, Referral,
)


async def register(
    db: AsyncSession,
    *,
    referred_earth_id: uuid.UUID,
    referrer_earth_id: uuid.UUID,
) -> list[Referral]:
    """ثبتِ زنجیرِ رفرال تا ۳ سطح. فقط یک‌بار برای هر referred ثبت می‌شود."""
    existing = await db.execute(
        select(Referral).where(Referral.referred_earth_id == referred_earth_id)
    )
    if existing.scalars().first():
        raise ConflictError("این کاربر قبلاً از طریقِ رفرال ثبت‌نام کرده.")

    # پیداکردنِ زنجیرِ بالایی (referrer ← referrer.referrer ← ...)
    chain: list[uuid.UUID] = [referrer_earth_id]
    current = referrer_earth_id
    for _ in range(MAX_REFERRAL_LEVELS - 1):
        parent_res = await db.execute(
            select(Referral.referrer_earth_id).where(Referral.referred_earth_id == current)
        )
        parent = parent_res.scalars().first()
        if parent is None:
            break
        chain.append(parent)
        current = parent

    created: list[Referral] = []
    for level, ref_id in enumerate(chain, start=1):
        r = Referral(
            referrer_earth_id=ref_id,
            referred_earth_id=referred_earth_id,
            level=level,
        )
        db.add(r)
        created.append(r)

    await db.flush()
    return created


async def reward(
    db: AsyncSession,
    *,
    referred_earth_id: uuid.UUID,
    reward_event_id: uuid.UUID,
    reward_minor: int,
    currency: str = "IRR",
) -> list[Referral]:
    """اعطایِ پاداش به تمامِ سطوحِ زنجیر پس از وقوعِ تراکنشِ واقعی (Invariant ADR-08)."""
    result = await db.execute(
        select(Referral).where(
            Referral.referred_earth_id == referred_earth_id,
            Referral.status == STATUS_PENDING,
        )
    )
    referrals = list(result.scalars().all())
    rewarded = []
    for r in referrals:
        r.status = STATUS_REWARDED
        r.reward_event_id = reward_event_id
        r.reward_minor = reward_minor // r.level  # سطحِ بالاتر پاداشِ بیشتر
        r.currency = currency
        r.rewarded_at = datetime.now(timezone.utc)
        rewarded.append(r)

    await db.flush()
    for r in rewarded:
        await publisher.publish(
            db,
            DomainEvent(
                name="referral.RewardIssued",
                payload={
                    "referral_id": str(r.id),
                    "referrer": str(r.referrer_earth_id),
                    "level": r.level,
                    "reward_minor": r.reward_minor,
                },
            ),
        )
    return rewarded
