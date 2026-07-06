"""منطق دامنه‌ی Identity. Invariantها این‌جا اعمال می‌شوند."""
from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.earth_id import SELF_SERVICE_ROLES, EarthId, EntityType
from dilix_shared.errors import ForbiddenError, NotFoundError
from dilix_shared.events import DomainEvent

from app.core.events import publisher
from app.modules.identity.models import EarthIdentity, Profile, VisibilitySettings
from app.modules.identity.schemas import ProfileUpdate, VisibilityUpdate


async def create_identity(
    db: AsyncSession,
    *,
    entity_type: EntityType,
    display_name: str,
    home_region: str,
) -> EarthIdentity:
    """ساخت Earth ID جدید + پروفایل + تنظیمات حریم خصوصی پیش‌فرض (خاموش)."""
    earth_id = EarthId.new().value
    identity = EarthIdentity(
        earth_id=earth_id,
        entity_type=entity_type.value,
        home_region=home_region,
        kyc_level=0,
    )
    identity.profile = Profile(earth_id=earth_id, display_name=display_name)
    identity.visibility = VisibilitySettings(earth_id=earth_id, discoverable=False)
    db.add(identity)
    await db.flush()

    await publisher.publish(
        db,
        DomainEvent(
            name="identity.EarthIdRegistered",
            payload={
                "earth_id": str(earth_id),
                "entity_type": entity_type.value,
                "home_region": home_region,
            },
        ),
    )
    return identity


async def get_identity(db: AsyncSession, earth_id: uuid.UUID) -> EarthIdentity:
    result = await db.execute(
        select(EarthIdentity).where(EarthIdentity.earth_id == earth_id)
    )
    identity = result.scalar_one_or_none()
    if identity is None:
        raise NotFoundError("Earth ID یافت نشد.")
    return identity


async def update_profile(
    db: AsyncSession, earth_id: uuid.UUID, data: ProfileUpdate
) -> Profile:
    identity = await get_identity(db, earth_id)
    profile = identity.profile
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(profile, field, value)
    await db.flush()
    return profile


async def update_visibility(
    db: AsyncSession, earth_id: uuid.UUID, data: VisibilityUpdate
) -> VisibilitySettings:
    identity = await get_identity(db, earth_id)
    vis = identity.visibility
    vis.discoverable = data.discoverable
    vis.audience = data.audience
    vis.geo_precision = data.geo_precision
    vis.visible_fields = data.visible_fields
    await db.flush()

    await publisher.publish(
        db,
        DomainEvent(
            name="identity.VisibilityChanged",
            payload={"earth_id": str(earth_id), "discoverable": data.discoverable},
        ),
    )
    return vis


async def change_role(
    db: AsyncSession, earth_id: uuid.UUID, target: EntityType
) -> EarthIdentity:
    """سوییچِ نقشِ کاربر بینِ نقش‌های خودسرویس.

    Invariant امنیتی: کاربر فقط می‌تواند به نقشی در ``SELF_SERVICE_ROLES`` سوییچ کند.
    نقش‌های ممتاز (moderator/*_admin) و دارای مجوز (insurer/telecom/…) از این مسیر
    قابلِ خوداعطا نیستند — جلوگیری از privilege escalation.
    """
    if target not in SELF_SERVICE_ROLES:
        raise ForbiddenError(
            "این نقش خوداعطا نیست؛ نیازمندِ احرازِ کسب‌وکار (KYB) یا اعطای مدیر است."
        )

    identity = await get_identity(db, earth_id)
    previous = identity.entity_type
    if previous == target.value:
        return identity

    identity.entity_type = target.value
    await db.flush()

    await publisher.publish(
        db,
        DomainEvent(
            name="identity.RoleChanged",
            payload={
                "earth_id": str(earth_id),
                "from_role": previous,
                "to_role": target.value,
            },
        ),
    )
    return identity
