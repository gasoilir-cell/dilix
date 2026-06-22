"""سرویس Discovery — کشفِ افراد/کسب‌وکار با حفظِ حریمِ خصوصی.

قواعدِ privacy (سند ۷ + ADR-06):
- فقط کاربرانِ opt-in (discoverable=True و is_visible=True) در نتایج می‌آیند.
- مختصاتِ ذخیره‌شده از پیش fuzz شده‌اند؛ هیچ مختصاتِ دقیقی برنمی‌گردد.
- audience: public → همه | verified → فقط درخواست‌کننده‌ی KYC≥۱ | connections → فقط آشنایان.
- هر فیلدِ پروفایل فقط در صورتِ حضور در visible_fields افشا می‌شود؛ و فیلترِ روی فیلدِ
  افشانشده، آن کاربر را از نتایج حذف می‌کند (نشت نمی‌کند).
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.errors import ConflictError, ForbiddenError, NotFoundError
from dilix_shared.events import DomainEvent

from app.core.events import publisher
from app.modules.discovery.models import CONTACT_PENDING, ContactRequest
from app.modules.discovery.schemas import NearbyPerson
from app.modules.earth.models import LocationPin
from app.modules.identity.models import EarthIdentity, Profile, VisibilitySettings
from app.modules.social.models import Follow

# فیلدهایی که افشای آن‌ها مشروط به visible_fields است
_GATED_FIELDS = frozenset({"gender", "age_range", "marital_status", "profession", "interests"})


def _age_from_birth(birth_date: datetime | None) -> int | None:
    if birth_date is None:
        return None
    today = datetime.now(timezone.utc)
    years = today.year - birth_date.year
    if (today.month, today.day) < (birth_date.month, birth_date.day):
        years -= 1
    return years


def _age_to_range(age: int | None) -> str | None:
    if age is None:
        return None
    lo = (age // 10) * 10
    return f"{lo}-{lo + 9}"


def _age_in_range(age: int | None, age_range: str) -> bool:
    if age is None:
        return False
    try:
        lo_s, hi_s = age_range.split("-", 1)
        return int(lo_s) <= age <= int(hi_s)
    except (ValueError, AttributeError):
        return False


async def _connection_ids(db: AsyncSession, earth_id: uuid.UUID) -> set[uuid.UUID]:
    """مجموعه‌ی earth_idهایی که با کاربر رابطه‌ی فالو (هر جهت) دارند."""
    result = await db.execute(
        select(Follow.follower_earth_id, Follow.followee_earth_id).where(
            or_(
                Follow.follower_earth_id == earth_id,
                Follow.followee_earth_id == earth_id,
            )
        )
    )
    ids: set[uuid.UUID] = set()
    for follower, followee in result.all():
        ids.add(followee if follower == earth_id else follower)
    return ids


async def search_nearby(
    db: AsyncSession,
    *,
    requester_earth_id: uuid.UUID,
    min_lat: float | None = None,
    max_lat: float | None = None,
    min_lon: float | None = None,
    max_lon: float | None = None,
    entity_type: str | None = None,
    gender: str | None = None,
    age_range: str | None = None,
    profession: str | None = None,
    business_category: str | None = None,
    language: str | None = None,
    marital_status: str | None = None,
    limit: int = 100,
) -> list[NearbyPerson]:
    q = (
        select(LocationPin, EarthIdentity, Profile, VisibilitySettings)
        .join(EarthIdentity, EarthIdentity.earth_id == LocationPin.earth_id)
        .join(VisibilitySettings, VisibilitySettings.earth_id == LocationPin.earth_id)
        .join(Profile, Profile.earth_id == LocationPin.earth_id)
        .where(
            VisibilitySettings.discoverable.is_(True),
            LocationPin.is_visible.is_(True),
            LocationPin.earth_id != requester_earth_id,
            EarthIdentity.status == "active",
        )
    )
    # محدوده‌ی نقشه (bbox) — روی مختصاتِ از‌پیش‌fuzzشده
    if min_lat is not None and max_lat is not None:
        q = q.where(LocationPin.lat >= min_lat, LocationPin.lat <= max_lat)
    if min_lon is not None and max_lon is not None:
        q = q.where(LocationPin.lon >= min_lon, LocationPin.lon <= max_lon)
    if entity_type:
        q = q.where(EarthIdentity.entity_type == entity_type)
    # business_category در عمل روی همان فیلدِ profession سازمان‌ها اعمال می‌شود
    profession_filter = profession or business_category

    rows = (await db.execute(q.limit(limit * 3))).all()

    # تعیینِ سطحِ دسترسی درخواست‌کننده برای audienceهای verified/connections
    requester = await db.get(EarthIdentity, requester_earth_id)
    requester_kyc = requester.kyc_level if requester else 0
    connections = await _connection_ids(db, requester_earth_id)

    out: list[NearbyPerson] = []
    for pin, ident, profile, vis in rows:
        if not _audience_ok(vis.audience, requester_kyc, ident.earth_id, connections):
            continue

        visible = set(vis.visible_fields or [])
        age = _age_from_birth(profile.birth_date)

        # فیلترها: روی فیلدِ gated فقط وقتی هدف آن را افشا کرده باشد
        if gender is not None:
            if "gender" not in visible or profile.gender != gender:
                continue
        if marital_status is not None:
            if "marital_status" not in visible or profile.marital_status != marital_status:
                continue
        if profession_filter is not None:
            if "profession" not in visible or profile.profession != profession_filter:
                continue
        if age_range is not None:
            if "age_range" not in visible or not _age_in_range(age, age_range):
                continue
        if language is not None and language not in (profile.languages or []):
            continue

        out.append(NearbyPerson(
            earth_id=ident.earth_id,
            entity_type=ident.entity_type,
            display_name=profile.display_name,
            avatar_url=profile.avatar_url,
            lat=pin.lat,
            lon=pin.lon,
            geo_precision=pin.geo_precision,
            gender=profile.gender if "gender" in visible else None,
            age_range=_age_to_range(age) if "age_range" in visible else None,
            marital_status=profile.marital_status if "marital_status" in visible else None,
            profession=profile.profession if "profession" in visible else None,
            interests=list(profile.interests or []) if "interests" in visible else None,
            languages=list(profile.languages or []),
        ))
        if len(out) >= limit:
            break
    return out


def _audience_ok(
    audience: str,
    requester_kyc: int,
    target_earth_id: uuid.UUID,
    connections: set[uuid.UUID],
) -> bool:
    if audience == "public":
        return True
    if audience == "verified":
        return requester_kyc >= 1
    if audience == "connections":
        return target_earth_id in connections
    return False


async def create_contact_request(
    db: AsyncSession,
    *,
    requester_earth_id: uuid.UUID,
    target_earth_id: uuid.UUID,
    message: str | None,
) -> ContactRequest:
    if requester_earth_id == target_earth_id:
        raise ConflictError("نمی‌توانید به خودتان درخواستِ تماس بدهید.")

    target = await db.get(EarthIdentity, target_earth_id)
    if target is None:
        raise NotFoundError("کاربرِ هدف یافت نشد.")

    vis = await db.get(VisibilitySettings, target_earth_id)
    if vis is None or not vis.discoverable:
        raise ForbiddenError("این کاربر قابلِ کشف نیست.")

    dup = await db.execute(
        select(ContactRequest).where(
            ContactRequest.requester_earth_id == requester_earth_id,
            ContactRequest.target_earth_id == target_earth_id,
        )
    )
    existing = dup.scalar_one_or_none()
    if existing is not None:
        raise ConflictError("قبلاً به این کاربر درخواست داده‌اید.")

    req = ContactRequest(
        requester_earth_id=requester_earth_id,
        target_earth_id=target_earth_id,
        message=message,
        status=CONTACT_PENDING,
    )
    db.add(req)
    await db.flush()

    await publisher.publish(
        db,
        DomainEvent(
            name="discovery.ContactRequested",
            payload={
                "requester": str(requester_earth_id),
                "target": str(target_earth_id),
                "request_id": str(req.id),
            },
        ),
    )
    return req
