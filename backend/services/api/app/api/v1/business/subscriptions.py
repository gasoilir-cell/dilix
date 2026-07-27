"""
Dilix — اشتراکِ پولیِ سازندگان (Creator Subscriptions) — فاز ۴

    GET    /api/v1/subscriptions/tiers/mine        پلن‌های من (سازنده)
    POST   /api/v1/subscriptions/tiers             ساختِ پلن
    PATCH  /api/v1/subscriptions/tiers/{id}        ویرایشِ پلن
    DELETE /api/v1/subscriptions/tiers/{id}        غیرفعال‌کردنِ پلن
    GET    /api/v1/subscriptions/tiers/of/{earth}  پلن‌های عمومیِ یک سازنده
    POST   /api/v1/subscriptions/subscribe         اشتراک + پرداختِ دورهٔ اول
    GET    /api/v1/subscriptions/mine              اشتراک‌های من
    GET    /api/v1/subscriptions/subscribers       مشترکانِ من
    POST   /api/v1/subscriptions/{id}/cancel       لغوِ تمدیدِ خودکار
    POST   /api/v1/subscriptions/{id}/renew        تمدیدِ دستیِ دورهٔ بعد

قواعدِ پولی
    مبلغ به **ریال** است و از کیفِ مشترک به کیفِ سازنده با همان روالِ اتمیکِ
    مشترکِ پلتفرم (`app/services/wallet_ops.py`) منتقل می‌شود.
    هر دوره یک ردیفِ `subscription_charges` با شمارهٔ دورهٔ یکتا دارد؛ این
    ایندکسِ یکتا تنها چیزی است که جلوی «دوبار پول‌گرفتن برای یک دوره» را
    می‌گیرد — نه بررسیِ نرم در کد، چون دو تمدیدِ هم‌زمان از آن رد می‌شوند.
"""
import uuid as _uuid
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import (
    BigInteger, Boolean, Column, DateTime, ForeignKey, Index, Integer, String,
    Text, func, select,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import Base, get_db
from app.models.user import User
from app.services.wallet_ops import move_money

router = APIRouter(prefix="/subscriptions", tags=["Subscriptions"])

PERIOD_DAYS = 30
TIER_MIN_PRICE = 10_000          # ۱٬۰۰۰ تومان
TIER_MAX_PRICE = 5_000_000_000   # ۵۰۰٬۰۰۰٬۰۰۰ تومان


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── مدل‌ها ────────────────────────────────────────────────────────────────────
class SubscriptionTier(Base):
    """پلنِ اشتراکِ ماهانهٔ یک سازنده."""
    __tablename__ = "subscription_tiers"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    owner_id   = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                        nullable=False, index=True)
    name       = Column(String(80), nullable=False)
    price      = Column(BigInteger, nullable=False)      # ریال، برای هر دورهٔ ۳۰روزه
    perks      = Column(Text, nullable=True)
    is_active  = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("uq_tier_owner_name", "owner_id", "name", unique=True),
    )


class Subscription(Base):
    """اشتراکِ یک کاربر در یک سازنده.

    برای هر زوجِ (مشترک، سازنده) فقط **یک** ردیف وجود دارد و در اشتراکِ دوباره
    همان ردیف زنده می‌شود؛ اگر به‌جای آن ردیفِ تازه ساخته می‌شد، یک کاربر
    می‌توانست چند اشتراکِ فعالِ هم‌زمان داشته باشد و دوبار پول بدهد.
    """
    __tablename__ = "subscriptions"

    id            = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    subscriber_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                           nullable=False, index=True)
    owner_id      = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                           nullable=False, index=True)
    tier_id       = Column(UUID(as_uuid=True), ForeignKey("subscription_tiers.id", ondelete="RESTRICT"),
                           nullable=False)
    status        = Column(String(12), nullable=False, default="active")  # active | cancelled | expired
    auto_renew    = Column(Boolean, nullable=False, default=True)
    started_at    = Column(DateTime(timezone=True), nullable=False, default=_now)
    current_period_end = Column(DateTime(timezone=True), nullable=False)
    created_at    = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("uq_subscription_pair", "subscriber_id", "owner_id", unique=True),
        Index("ix_subscription_renew", "auto_renew", "status", "current_period_end"),
    )


class SubscriptionCharge(Base):
    """رسیدِ پرداختِ یک دوره. `period_no` از ۱ شروع می‌شود و یکتاست."""
    __tablename__ = "subscription_charges"

    id              = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    subscription_id = Column(UUID(as_uuid=True), ForeignKey("subscriptions.id", ondelete="CASCADE"),
                             nullable=False, index=True)
    period_no       = Column(Integer, nullable=False)
    amount          = Column(BigInteger, nullable=False)   # ریال
    period_start    = Column(DateTime(timezone=True), nullable=False)
    period_end      = Column(DateTime(timezone=True), nullable=False)
    paid_at         = Column(DateTime(timezone=True), nullable=False, default=_now, index=True)

    __table_args__ = (
        Index("uq_charge_period", "subscription_id", "period_no", unique=True),
    )


# ── Schemas ──────────────────────────────────────────────────────────────────
class TierIn(BaseModel):
    name: str = Field(..., min_length=1, max_length=80)
    price: int = Field(..., ge=TIER_MIN_PRICE, le=TIER_MAX_PRICE)   # ریال
    perks: Optional[str] = Field(None, max_length=2000)


class TierPatch(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=80)
    price: Optional[int] = Field(None, ge=TIER_MIN_PRICE, le=TIER_MAX_PRICE)
    perks: Optional[str] = Field(None, max_length=2000)
    is_active: Optional[bool] = None


class TierOut(BaseModel):
    id: str
    owner_earth_id: str
    name: str
    price: int
    perks: Optional[str] = None
    is_active: bool
    subscriber_count: int = 0
    created_at: datetime


class SubscribeIn(BaseModel):
    tier_id: str


class SubscriptionOut(BaseModel):
    id: str
    owner_earth_id: str
    owner_name: Optional[str] = None
    subscriber_earth_id: str
    subscriber_name: Optional[str] = None
    tier_id: str
    tier_name: str
    price: int
    status: str
    auto_renew: bool
    started_at: datetime
    current_period_end: datetime
    periods_paid: int
    total_paid: int


# ── کمکی‌ها ──────────────────────────────────────────────────────────────────
def _effective_status(s: Subscription, now: datetime) -> str:
    """وضعیتِ واقعی. دوره‌ای که سررسیدش گذشته دیگر فعال نیست، حتی اگر ستونِ
    `status` هنوز `active` باشد — تا خواندن به اجرای cron وابسته نباشد."""
    if s.status == "active" and s.current_period_end <= now:
        return "expired"
    return s.status


async def _tier_or_404(db: AsyncSession, tier_id: str) -> SubscriptionTier:
    try:
        tid = _uuid.UUID(tier_id)
    except ValueError:
        raise HTTPException(404, detail="پلن پیدا نشد")
    t = await db.get(SubscriptionTier, tid)
    if t is None:
        raise HTTPException(404, detail="پلن پیدا نشد")
    return t


async def _sub_or_404(db: AsyncSession, sub_id: str) -> Subscription:
    try:
        sid = _uuid.UUID(sub_id)
    except ValueError:
        raise HTTPException(404, detail="اشتراک پیدا نشد")
    s = await db.get(Subscription, sid)
    if s is None:
        raise HTTPException(404, detail="اشتراک پیدا نشد")
    return s


async def _charge_stats(db: AsyncSession, sub_ids: List) -> dict:
    """(تعدادِ دوره‌های پرداخت‌شده، مجموعِ مبلغ) برای هر اشتراک."""
    if not sub_ids:
        return {}
    rows = (await db.execute(
        select(SubscriptionCharge.subscription_id,
               func.count(), func.coalesce(func.sum(SubscriptionCharge.amount), 0))
        .where(SubscriptionCharge.subscription_id.in_(sub_ids))
        .group_by(SubscriptionCharge.subscription_id)
    )).all()
    return {r[0]: (int(r[1]), int(r[2])) for r in rows}


def _sub_out(s: Subscription, owner: User, subscriber: User, tier: SubscriptionTier,
             stats: dict, now: datetime) -> SubscriptionOut:
    periods, total = stats.get(s.id, (0, 0))
    return SubscriptionOut(
        id=str(s.id),
        owner_earth_id=owner.earth_id, owner_name=owner.full_name or owner.username,
        subscriber_earth_id=subscriber.earth_id,
        subscriber_name=subscriber.full_name or subscriber.username,
        tier_id=str(tier.id), tier_name=tier.name, price=tier.price,
        status=_effective_status(s, now), auto_renew=s.auto_renew,
        started_at=s.started_at, current_period_end=s.current_period_end,
        periods_paid=periods, total_paid=total,
    )


async def _charge_period(db: AsyncSession, s: Subscription, tier: SubscriptionTier,
                         owner: User, subscriber: User, period_no: int,
                         start: datetime) -> None:
    """پرداختِ یک دوره: انتقالِ پول + ثبتِ رسید (بدونِ commit)."""
    end = start + timedelta(days=PERIOD_DAYS)
    await move_money(
        db, subscriber.id, owner.id, tier.price,
        out_desc=f"اشتراکِ «{tier.name}» از {owner.earth_id}",
        in_desc=f"درآمدِ اشتراکِ «{tier.name}» از {subscriber.earth_id}",
        reference_id=f"SUB-{s.id.hex[:12]}-{period_no}",
    )
    db.add(SubscriptionCharge(
        subscription_id=s.id, period_no=period_no, amount=tier.price,
        period_start=start, period_end=end,
    ))
    s.current_period_end = end
    s.status = "active"


# ── پلن‌ها (سازنده) ──────────────────────────────────────────────────────────
@router.get("/tiers/mine", response_model=List[TierOut])
async def my_tiers(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    tiers = (await db.execute(
        select(SubscriptionTier).where(SubscriptionTier.owner_id == me.id)
        .order_by(SubscriptionTier.price)
    )).scalars().all()
    counts = await _tier_counts(db, [t.id for t in tiers])
    return [
        TierOut(id=str(t.id), owner_earth_id=me.earth_id, name=t.name, price=t.price,
                perks=t.perks, is_active=t.is_active,
                subscriber_count=counts.get(t.id, 0), created_at=t.created_at)
        for t in tiers
    ]


async def _tier_counts(db: AsyncSession, tier_ids: List) -> dict:
    if not tier_ids:
        return {}
    now = _now()
    rows = (await db.execute(
        select(Subscription.tier_id, func.count())
        .where(Subscription.tier_id.in_(tier_ids),
               Subscription.status == "active",
               Subscription.current_period_end > now)
        .group_by(Subscription.tier_id)
    )).all()
    return {r[0]: int(r[1]) for r in rows}


@router.post("/tiers", response_model=TierOut, status_code=201)
async def create_tier(
    payload: TierIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    t = SubscriptionTier(owner_id=me.id, name=payload.name.strip(),
                         price=payload.price, perks=payload.perks)
    db.add(t)
    try:
        await db.commit()
    except Exception:
        await db.rollback()
        raise HTTPException(409, detail="پلنی با همین نام دارید")
    await db.refresh(t)
    return TierOut(id=str(t.id), owner_earth_id=me.earth_id, name=t.name, price=t.price,
                   perks=t.perks, is_active=t.is_active, subscriber_count=0,
                   created_at=t.created_at)


@router.patch("/tiers/{tier_id}", response_model=TierOut)
async def update_tier(
    tier_id: str,
    payload: TierPatch,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    t = await _tier_or_404(db, tier_id)
    if t.owner_id != me.id:
        raise HTTPException(404, detail="پلن پیدا نشد")
    for field, value in payload.model_dump(exclude_unset=True).items():
        if value is not None:
            setattr(t, field, value.strip() if isinstance(value, str) else value)
    try:
        await db.commit()
    except Exception:
        await db.rollback()
        raise HTTPException(409, detail="پلنی با همین نام دارید")
    await db.refresh(t)
    counts = await _tier_counts(db, [t.id])
    return TierOut(id=str(t.id), owner_earth_id=me.earth_id, name=t.name, price=t.price,
                   perks=t.perks, is_active=t.is_active,
                   subscriber_count=counts.get(t.id, 0), created_at=t.created_at)


@router.delete("/tiers/{tier_id}", status_code=204)
async def delete_tier(
    tier_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """پلن **غیرفعال** می‌شود، نه حذف: مشترکانِ فعلی و رسیدهای پرداخت‌شده باید
    سرِ جایشان بمانند."""
    t = await _tier_or_404(db, tier_id)
    if t.owner_id != me.id:
        raise HTTPException(404, detail="پلن پیدا نشد")
    t.is_active = False
    await db.commit()


@router.get("/tiers/of/{earth_id}", response_model=List[TierOut])
async def public_tiers(
    earth_id: str,
    db: AsyncSession = Depends(get_db),
):
    """پلن‌های فعالِ یک سازنده (عمومی)."""
    owner = (await db.execute(
        select(User).where(User.earth_id == earth_id)
    )).scalar_one_or_none()
    if owner is None:
        raise HTTPException(404, detail="کاربر پیدا نشد")
    tiers = (await db.execute(
        select(SubscriptionTier)
        .where(SubscriptionTier.owner_id == owner.id, SubscriptionTier.is_active.is_(True))
        .order_by(SubscriptionTier.price)
    )).scalars().all()
    counts = await _tier_counts(db, [t.id for t in tiers])
    return [
        TierOut(id=str(t.id), owner_earth_id=owner.earth_id, name=t.name, price=t.price,
                perks=t.perks, is_active=t.is_active,
                subscriber_count=counts.get(t.id, 0), created_at=t.created_at)
        for t in tiers
    ]


# ── اشتراک ───────────────────────────────────────────────────────────────────
@router.post("/subscribe", response_model=SubscriptionOut, status_code=201)
async def subscribe(
    payload: SubscribeIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """اشتراک در یک پلن؛ دورهٔ اول همین حالا از کیفِ پول پرداخت می‌شود."""
    tier = await _tier_or_404(db, payload.tier_id)
    if not tier.is_active:
        raise HTTPException(400, detail="این پلن غیرفعال است")
    if tier.owner_id == me.id:
        raise HTTPException(400, detail="نمی‌توانید مشترکِ خودتان شوید")

    owner = await db.get(User, tier.owner_id)
    if owner is None:
        raise HTTPException(404, detail="سازنده پیدا نشد")

    now = _now()
    s = (await db.execute(
        select(Subscription).where(Subscription.subscriber_id == me.id,
                                   Subscription.owner_id == owner.id)
    )).scalar_one_or_none()

    if s is not None and _effective_status(s, now) == "active":
        raise HTTPException(409, detail="اشتراکِ فعال دارید")

    if s is None:
        s = Subscription(subscriber_id=me.id, owner_id=owner.id, tier_id=tier.id,
                         current_period_end=now, started_at=now)
        db.add(s)
        await db.flush()
    else:
        # اشتراکِ دوباره: همان ردیف زنده می‌شود تا دو اشتراکِ فعال ساخته نشود.
        s.tier_id = tier.id
        s.auto_renew = True
        s.started_at = now

    period_no = int((await db.execute(
        select(func.count()).select_from(SubscriptionCharge)
        .where(SubscriptionCharge.subscription_id == s.id)
    )).scalar() or 0) + 1

    await _charge_period(db, s, tier, owner, me, period_no, now)
    try:
        await db.commit()
    except HTTPException:
        raise
    except Exception:
        # بازندهٔ مسابقهٔ دو اشتراکِ هم‌زمان نباید پولش کم شود.
        await db.rollback()
        raise HTTPException(409, detail="اشتراکِ فعال دارید")

    await db.refresh(s)
    stats = await _charge_stats(db, [s.id])
    return _sub_out(s, owner, me, tier, stats, _now())


@router.get("/mine", response_model=List[SubscriptionOut])
async def my_subscriptions(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    subs = (await db.execute(
        select(Subscription).where(Subscription.subscriber_id == me.id)
        .order_by(Subscription.created_at.desc())
    )).scalars().all()
    return await _expand(db, subs, me_is_subscriber=True, me=me)


@router.get("/subscribers", response_model=List[SubscriptionOut])
async def my_subscribers(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    subs = (await db.execute(
        select(Subscription).where(Subscription.owner_id == me.id)
        .order_by(Subscription.created_at.desc())
    )).scalars().all()
    return await _expand(db, subs, me_is_subscriber=False, me=me)


async def _expand(db: AsyncSession, subs: List[Subscription],
                  me_is_subscriber: bool, me: User) -> List[SubscriptionOut]:
    if not subs:
        return []
    other_ids = {s.owner_id if me_is_subscriber else s.subscriber_id for s in subs}
    others = {
        u.id: u for u in (await db.execute(
            select(User).where(User.id.in_(other_ids))
        )).scalars().all()
    }
    tiers = {
        t.id: t for t in (await db.execute(
            select(SubscriptionTier).where(SubscriptionTier.id.in_({s.tier_id for s in subs}))
        )).scalars().all()
    }
    stats = await _charge_stats(db, [s.id for s in subs])
    now = _now()
    out: List[SubscriptionOut] = []
    for s in subs:
        tier = tiers.get(s.tier_id)
        other = others.get(s.owner_id if me_is_subscriber else s.subscriber_id)
        if tier is None or other is None:
            continue
        owner, subscriber = (other, me) if me_is_subscriber else (me, other)
        out.append(_sub_out(s, owner, subscriber, tier, stats, now))
    return out


@router.post("/{sub_id}/cancel", response_model=SubscriptionOut)
async def cancel_subscription(
    sub_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """لغوِ تمدیدِ خودکار. دسترسی تا پایانِ دورهٔ پرداخت‌شده باقی می‌ماند —
    پولِ همان دوره داده شده و برنمی‌گردد."""
    s = await _sub_or_404(db, sub_id)
    if s.subscriber_id != me.id:
        raise HTTPException(404, detail="اشتراک پیدا نشد")
    s.auto_renew = False
    s.status = "cancelled"
    await db.commit()
    await db.refresh(s)

    owner = await db.get(User, s.owner_id)
    tier = await db.get(SubscriptionTier, s.tier_id)
    stats = await _charge_stats(db, [s.id])
    return _sub_out(s, owner, me, tier, stats, _now())


@router.post("/{sub_id}/renew", response_model=SubscriptionOut)
async def renew_subscription(
    sub_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """تمدیدِ دستیِ دورهٔ بعد. دورهٔ تازه از پایانِ دورهٔ فعلی شروع می‌شود (نه از
    «حالا»)، وگرنه تمدیدِ زودهنگام روزهای باقی‌مانده را می‌سوزاند."""
    s = await _sub_or_404(db, sub_id)
    if s.subscriber_id != me.id:
        raise HTTPException(404, detail="اشتراک پیدا نشد")

    tier = await db.get(SubscriptionTier, s.tier_id)
    if tier is None or not tier.is_active:
        raise HTTPException(400, detail="این پلن دیگر فعال نیست")
    owner = await db.get(User, s.owner_id)
    if owner is None:
        raise HTTPException(404, detail="سازنده پیدا نشد")

    now = _now()
    start = s.current_period_end if s.current_period_end > now else now
    period_no = int((await db.execute(
        select(func.count()).select_from(SubscriptionCharge)
        .where(SubscriptionCharge.subscription_id == s.id)
    )).scalar() or 0) + 1

    await _charge_period(db, s, tier, owner, me, period_no, start)
    s.auto_renew = True
    try:
        await db.commit()
    except HTTPException:
        raise
    except Exception:
        # دو تمدیدِ هم‌زمان همان `period_no` را می‌سازند؛ ایندکسِ یکتا بازنده را
        # رد می‌کند و پولش برمی‌گردد.
        await db.rollback()
        raise HTTPException(409, detail="این دوره قبلاً تمدید شده است")

    await db.refresh(s)
    stats = await _charge_stats(db, [s.id])
    return _sub_out(s, owner, me, tier, stats, _now())
