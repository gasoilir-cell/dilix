"""
Dilix — عضویت (Membership): طرحِ رایگان / استاندارد / ویژه

    GET  /api/v1/membership          عضویتِ جاریِ من
    GET  /api/v1/membership/plans    کاتالوگِ طرح‌ها و قیمتِ ماهانه
    POST /api/v1/membership/upgrade  ارتقا/تمدید (از کیفِ پول کسر می‌شود)
    POST /api/v1/membership/cancel   لغو → بازگشت به طرحِ رایگان

سه تصمیمی که ساختار را تعیین کرد:

۱) **ارتقا واقعاً پول کم می‌کند.** اگر فقط ستونِ `plan` را عوض می‌کردیم، «طرحِ
   ویژه» یک برچسبِ تزئینی می‌شد که هرکس می‌توانست رایگان بگیرد. هزینه از
   `balance_available` کسر و یک ردیفِ `WalletTransaction` ثبت می‌شود تا در
   تاریخچهٔ کیف هم دیده شود.

۲) **تمدید تاریخ را از بیشینهٔ «حالا» و «انقضای فعلی» جلو می‌برد.** اگر همیشه از
   «حالا» حساب می‌شد، کاربری که یک ماه مانده تمدید می‌کرد روزهای باقی‌مانده‌اش را
   می‌سوزاند.

۳) **انقضا هنگامِ خواندن اعمال می‌شود، نه با کرانِ شبانه.** یک عضویتِ سررسیدشده
   همان لحظه که خوانده شود به `expired` و کش‌بکِ صفر برمی‌گردد؛ پس نبودِ job
   زمان‌بندی‌شده نمی‌تواند به کسی مزیتِ رایگان بدهد.
"""
import uuid as _uuid
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import (
    BigInteger, Column, DateTime, ForeignKey, Integer, String, select,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import Base, get_db
from app.models.user import User
from app.models.wallet import Wallet, WalletTransaction
from app.services.wallet_ops import get_or_create_wallet

router = APIRouter(prefix="/membership", tags=["Membership"])

PLAN_FREE = "free"
PLAN_STANDARD = "standard"
PLAN_PREMIUM = "premium"

STATUS_ACTIVE = "active"
STATUS_EXPIRED = "expired"
STATUS_CANCELLED = "cancelled"

# کش‌بکِ هر طرح برحسبِ basis point (۱۰۰ bps = ۱٪) و قیمتِ ماهانه به ریال.
PLANS: dict[str, dict] = {
    PLAN_FREE:     {"cashback_bps": 0,   "price_irr": 0,          "title": "رایگان"},
    PLAN_STANDARD: {"cashback_bps": 100, "price_irr": 1_900_000,  "title": "استاندارد"},
    PLAN_PREMIUM:  {"cashback_bps": 250, "price_irr": 4_900_000,  "title": "ویژه"},
}

PLAN_PERKS: dict[str, List[str]] = {
    PLAN_FREE: [
        "کیفِ پول و انتقالِ درون‌شبکه‌ای",
        "پیام‌رسانِ رمزنگاری‌شده",
        "کره و کشفِ افراد",
    ],
    PLAN_STANDARD: [
        "۱٪ کش‌بک روی خرید و پرداختِ قبض",
        "سهم از درآمدِ کارمزدِ پلتفرم",
        "پشتیبانیِ اولویت‌دار",
    ],
    PLAN_PREMIUM: [
        "۲.۵٪ کش‌بک روی خرید و پرداختِ قبض",
        "بیشترین سهم از درآمدِ کارمزدِ پلتفرم",
        "کارمزدِ کمترِ تبدیلِ ارز",
        "نشانِ ویژه در نمایه",
    ],
}


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _aware(dt: Optional[datetime]) -> Optional[datetime]:
    """تاریخ‌های خوانده‌شده از DB ممکن است naive باشند؛ مقایسه با UTC می‌شکند."""
    if dt is not None and dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt


# ── مدل ───────────────────────────────────────────────────────────────────────
class Membership(Base):
    """عضویتِ هر کاربر — یک ردیف به‌ازای هر کاربر."""
    __tablename__ = "memberships"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                     nullable=False, unique=True)
    plan = Column(String(16), nullable=False, default=PLAN_FREE)
    status = Column(String(16), nullable=False, default=STATUS_ACTIVE)
    cashback_bps = Column(Integer, nullable=False, default=0)
    paid_total = Column(BigInteger, nullable=False, default=0)
    started_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    expires_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)


# ── Schemas ───────────────────────────────────────────────────────────────────
class MembershipOut(BaseModel):
    id:           str
    earth_id:     str
    plan:         str
    plan_title:   str
    status:       str
    cashback_bps: int
    expires_at:   Optional[datetime]

    @classmethod
    def of(cls, m: Membership, user: User) -> "MembershipOut":
        return cls(
            id=str(m.id), earth_id=user.earth_id, plan=m.plan,
            plan_title=PLANS.get(m.plan, {}).get("title", m.plan),
            status=m.status, cashback_bps=int(m.cashback_bps or 0),
            expires_at=_aware(m.expires_at),
        )


class PlanOut(BaseModel):
    id:           str
    title:        str
    price_irr:    int
    cashback_bps: int
    perks:        List[str]


class UpgradeRequest(BaseModel):
    plan:   str = Field(..., pattern="^(free|standard|premium)$")
    months: int = Field(1, ge=1, le=12)


# ── Helpers ───────────────────────────────────────────────────────────────────
async def _get_or_create(db: AsyncSession, user: User) -> Membership:
    m = (await db.execute(
        select(Membership).where(Membership.user_id == user.id)
    )).scalar_one_or_none()
    if m is None:
        m = Membership(user_id=user.id, plan=PLAN_FREE, status=STATUS_ACTIVE, cashback_bps=0)
        db.add(m)
        try:
            await db.flush()
        except IntegrityError:
            # دو درخواستِ هم‌زمانِ اولِ همان کاربر؛ ردیفِ رقیب برنده است.
            await db.rollback()
            m = (await db.execute(
                select(Membership).where(Membership.user_id == user.id)
            )).scalar_one()
    return m


def _apply_expiry(m: Membership) -> Membership:
    """طرحِ سررسیدشده را همین‌جا به رایگان برمی‌گرداند (بدونِ کرانِ شبانه)."""
    exp = _aware(m.expires_at)
    if m.plan != PLAN_FREE and exp is not None and exp <= _now():
        m.plan = PLAN_FREE
        m.status = STATUS_EXPIRED
        m.cashback_bps = 0
    return m


# ── Endpoints ─────────────────────────────────────────────────────────────────
@router.get("", response_model=MembershipOut, include_in_schema=False)
@router.get("/", response_model=MembershipOut)
async def my_membership(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    m = _apply_expiry(await _get_or_create(db, me))
    await db.commit()
    await db.refresh(m)
    return MembershipOut.of(m, me)


@router.get("/plans", response_model=List[PlanOut])
async def list_plans(me: User = Depends(get_current_user)):
    return [
        PlanOut(
            id=code, title=cfg["title"], price_irr=cfg["price_irr"],
            cashback_bps=cfg["cashback_bps"], perks=PLAN_PERKS.get(code, []),
        )
        for code, cfg in PLANS.items()
    ]


@router.post("/upgrade", response_model=MembershipOut)
async def upgrade(
    body: UpgradeRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ارتقا یا تمدیدِ طرح. هزینه همان لحظه از کیفِ پول کسر می‌شود."""
    cfg = PLANS[body.plan]
    m = _apply_expiry(await _get_or_create(db, me))

    if body.plan == PLAN_FREE:
        m.plan = PLAN_FREE
        m.status = STATUS_ACTIVE
        m.cashback_bps = 0
        m.expires_at = None
        await db.commit()
        await db.refresh(m)
        return MembershipOut.of(m, me)

    cost = int(cfg["price_irr"]) * body.months
    await get_or_create_wallet(db, me.id)
    w = (await db.execute(
        select(Wallet).where(Wallet.user_id == me.id).with_for_update()
    )).scalar_one()
    if w.is_frozen:
        raise HTTPException(status_code=403, detail="کیف‌پول مسدود است")
    if w.balance_available < cost:
        raise HTTPException(status_code=400, detail="موجودیِ کیفِ پول کافی نیست")

    before = w.balance_available
    w.balance_available -= cost
    db.add(WalletTransaction(
        wallet_id=w.id, type="fee", status="completed",
        amount=cost, balance_before=before, balance_after=w.balance_available,
        reference_id=str(m.id),
        description=f"عضویتِ {cfg['title']} — {body.months} ماه",
    ))

    # تمدید از دیرترِ «حالا» و «انقضای فعلی» تا روزهای باقی‌مانده نسوزد.
    base = _now()
    exp = _aware(m.expires_at)
    if m.plan == body.plan and exp is not None and exp > base:
        base = exp
    m.plan = body.plan
    m.status = STATUS_ACTIVE
    m.cashback_bps = int(cfg["cashback_bps"])
    m.expires_at = base + timedelta(days=30 * body.months)
    m.paid_total = int(m.paid_total or 0) + cost

    await db.commit()
    await db.refresh(m)
    return MembershipOut.of(m, me)


@router.post("/cancel", response_model=MembershipOut)
async def cancel(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """لغوِ عضویت: طرح بی‌درنگ به رایگان برمی‌گردد (بدونِ بازپرداختِ باقی‌مانده)."""
    m = await _get_or_create(db, me)
    m.plan = PLAN_FREE
    m.status = STATUS_CANCELLED
    m.cashback_bps = 0
    m.expires_at = None
    await db.commit()
    await db.refresh(m)
    return MembershipOut.of(m, me)
