"""
Dilix — سرمایه‌گذاری: خریدِ واحدِ صندوق (ADR-09)

    GET  /api/v1/investment/funds      کاتالوگِ صندوق‌های مجاز
    GET  /api/v1/investment/nav        آخرین NAVِ یک صندوق
    GET  /api/v1/investment/positions  موقعیت‌های من
    POST /api/v1/investment/buy        خریدِ واحد (از کیفِ پول کسر می‌شود)
    POST /api/v1/investment/sell       فروشِ واحد (به کیفِ پول برمی‌گردد)

سه تصمیمی که ساختار را تعیین کرد:

۱) **خرید پول را واقعاً از کیف کم می‌کند و فروش برمی‌گرداند.** بدونِ آن،
   «موقعیتِ سرمایه‌گذاری» فقط یک عدد در جدول بود که هرکس می‌توانست بی‌نهایتش کند
   و کارتِ «سهم از درآمد» را هم به دروغ فعال نگه دارد.

۲) **هر کاربر برای هر صندوق یک ردیف دارد و واحدها جمع می‌شوند.** خریدِ دوباره
   موقعیتِ تازه نمی‌سازد؛ وگرنه فهرستِ کاربر با هر خرید طولانی‌تر می‌شد و
   محاسبهٔ کلِ واحدها به جمعِ سمتِ کلاینت وابسته می‌ماند.

۳) **NAV قطعی است، نه تصادفی.** از یک قیمتِ پایه به‌علاوهٔ نوسانِ مشتق‌شده از
   (کدِ صندوق + روز) ساخته می‌شود؛ پس در طولِ یک روز ثابت است. با `random`،
   دو فراخوانِ پشتِ‌هم دو قیمت می‌داد و «استعلام» بی‌معنی می‌شد.
"""
import hashlib
import uuid as _uuid
from datetime import date, datetime, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import (
    BigInteger, Column, DateTime, Float, ForeignKey, Index, String, select,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import Base, get_db
from app.models.user import User
from app.models.wallet import Wallet, WalletTransaction
from app.services.wallet_ops import get_or_create_wallet

router = APIRouter(prefix="/investment", tags=["Investment"])

# صندوق‌های مجاز: کد → (نام، نوع، NAVِ پایه به ریال، دامنهٔ نوسانِ روزانه به bps)
FUNDS: dict[str, dict] = {
    "DILIX_GROWTH": {
        "title": "صندوقِ رشدِ دیلیکس", "kind": "سهامی",
        "base_nav": 25_000, "vol_bps": 180,
        "note": "بازدهیِ بلندمدت با ریسکِ بالاتر",
    },
    "DILIX_INCOME": {
        "title": "صندوقِ درآمدِ ثابت", "kind": "درآمدِ ثابت",
        "base_nav": 12_500, "vol_bps": 25,
        "note": "نوسانِ کم، مناسبِ حفظِ ارزش",
    },
    "DILIX_GOLD": {
        "title": "صندوقِ طلای دیلیکس", "kind": "کالایی",
        "base_nav": 41_000, "vol_bps": 140,
        "note": "پوششِ تورم با پشتوانهٔ طلا",
    },
    "DILIX_MIXED": {
        "title": "صندوقِ مختلط", "kind": "مختلط",
        "base_nav": 18_200, "vol_bps": 90,
        "note": "ترکیبِ سهام و اوراق",
    },
}

STATUS_ACTIVE = "active"
STATUS_CLOSED = "closed"

# تعدادِ اعشاری که در پاسخِ API منتشر می‌شود. فروش هم باید با همین دقت سنجیده
# شود، وگرنه کاربری که «همهٔ واحدها» را از روی همان عدد می‌فروشد رد می‌شود:
# مقدارِ منتشرشده می‌تواند تا نصفِ آخرین رقم از مقدارِ ذخیره‌شده بزرگ‌تر باشد.
UNITS_DP = 6
UNITS_EPS = 0.5 * 10 ** -UNITS_DP


def _now() -> datetime:
    return datetime.now(timezone.utc)


def nav_minor(fund_code: str, on: Optional[date] = None) -> int:
    """NAVِ قطعیِ روزِ جاری برای یک صندوق (به ریال).

    نوسان از هشِ (کد، روز) مشتق می‌شود: در طولِ یک روز ثابت است، بینِ روزها
    تغییر می‌کند و بینِ صندوق‌ها متفاوت است — بدونِ نیاز به فیدِ بیرونی.
    """
    cfg = FUNDS[fund_code]
    day = (on or _now().date()).isoformat()
    h = hashlib.sha256(f"{fund_code}:{day}".encode()).hexdigest()
    # عددِ ۰..۹۹۹۹ → نوسانِ متقارن در بازهٔ ±vol_bps
    swing = (int(h[:8], 16) % 10_000) / 10_000.0 * 2 - 1
    factor = 1 + (swing * cfg["vol_bps"] / 10_000.0)
    return max(1, int(round(cfg["base_nav"] * factor)))


# ── مدل ───────────────────────────────────────────────────────────────────────
class InvestmentPosition(Base):
    """موقعیتِ سرمایه‌گذاری — یک ردیف به‌ازای (کاربر، صندوق)."""
    __tablename__ = "investment_positions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                     nullable=False, index=True)
    fund_code = Column(String(32), nullable=False)
    units = Column(Float, nullable=False, default=0.0)
    invested_minor = Column(BigInteger, nullable=False, default=0)
    currency = Column(String(3), nullable=False, default="IRR")
    status = Column(String(16), nullable=False, default=STATUS_ACTIVE)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)

    __table_args__ = (
        Index("uq_investment_position", "user_id", "fund_code", unique=True),
    )


# ── Schemas ───────────────────────────────────────────────────────────────────
class FundOut(BaseModel):
    code:      str
    title:     str
    kind:      str
    nav_minor: int
    note:      str


class NavOut(BaseModel):
    fund_code: str
    nav_minor: int
    as_of:     datetime


class PositionOut(BaseModel):
    id:             str
    fund_code:      str
    fund_title:     str
    units:          float
    invested_minor: int
    value_minor:    int
    currency:       str
    status:         str

    @classmethod
    def of(cls, p: InvestmentPosition) -> "PositionOut":
        cfg = FUNDS.get(p.fund_code, {})
        nav = nav_minor(p.fund_code) if p.fund_code in FUNDS else 0
        return cls(
            id=str(p.id), fund_code=p.fund_code,
            fund_title=cfg.get("title", p.fund_code),
            units=round(float(p.units or 0), UNITS_DP),
            invested_minor=int(p.invested_minor or 0),
            value_minor=int(round(float(p.units or 0) * nav)),
            currency=p.currency or "IRR", status=p.status,
        )


class BuyRequest(BaseModel):
    fund_code:    str
    amount_minor: int = Field(..., gt=0)
    currency:     str = "IRR"
    provider_code: Optional[str] = None   # پذیرفته می‌شود ولی اثری ندارد


class SellRequest(BaseModel):
    fund_code: str
    units:     float = Field(..., gt=0)


# ── Endpoints ─────────────────────────────────────────────────────────────────
@router.get("/funds", response_model=List[FundOut])
async def list_funds(me: User = Depends(get_current_user)):
    return [
        FundOut(code=c, title=f["title"], kind=f["kind"],
                nav_minor=nav_minor(c), note=f["note"])
        for c, f in FUNDS.items()
    ]


@router.get("/nav", response_model=NavOut)
async def get_nav(
    fund_code: str = Query(..., description="کدِ صندوق"),
    me: User = Depends(get_current_user),
):
    code = (fund_code or "").strip().upper()
    if code not in FUNDS:
        raise HTTPException(status_code=404, detail="صندوق یافت نشد")
    return NavOut(fund_code=code, nav_minor=nav_minor(code), as_of=_now())


@router.get("/positions", response_model=List[PositionOut])
async def my_positions(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    rows = (await db.execute(
        select(InvestmentPosition)
        .where(InvestmentPosition.user_id == me.id)
        .order_by(InvestmentPosition.created_at.desc())
    )).scalars().all()
    return [PositionOut.of(p) for p in rows]


@router.post("/buy", response_model=PositionOut)
async def buy(
    body: BuyRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    code = (body.fund_code or "").strip().upper()
    if code not in FUNDS:
        raise HTTPException(status_code=404, detail="صندوق یافت نشد")
    if (body.currency or "IRR").upper() != "IRR":
        raise HTTPException(status_code=400, detail="فعلاً فقط خرید به ریال ممکن است")

    nav = nav_minor(code)
    units = body.amount_minor / nav
    if units <= 0:
        raise HTTPException(status_code=400, detail="مبلغ برای خریدِ حتی یک واحد کافی نیست")

    await get_or_create_wallet(db, me.id)
    w = (await db.execute(
        select(Wallet).where(Wallet.user_id == me.id).with_for_update()
    )).scalar_one()
    if w.is_frozen:
        raise HTTPException(status_code=403, detail="کیف‌پول مسدود است")
    if w.balance_available < body.amount_minor:
        raise HTTPException(status_code=400, detail="موجودیِ کیفِ پول کافی نیست")

    # موقعیت پیش از کسرِ پول قفل می‌شود تا دو خریدِ هم‌زمان واحدها را گم نکنند.
    pos = (await db.execute(
        select(InvestmentPosition)
        .where(InvestmentPosition.user_id == me.id,
               InvestmentPosition.fund_code == code)
        .with_for_update()
    )).scalar_one_or_none()
    if pos is None:
        pos = InvestmentPosition(user_id=me.id, fund_code=code, units=0.0,
                                 invested_minor=0, currency="IRR")
        db.add(pos)
        await db.flush()

    before = w.balance_available
    w.balance_available -= body.amount_minor
    db.add(WalletTransaction(
        wallet_id=w.id, type="transfer_out", status="completed",
        amount=body.amount_minor, balance_before=before,
        balance_after=w.balance_available, reference_id=str(pos.id),
        description=f"خریدِ واحدِ {FUNDS[code]['title']}",
    ))

    pos.units = float(pos.units or 0) + units
    pos.invested_minor = int(pos.invested_minor or 0) + body.amount_minor
    pos.status = STATUS_ACTIVE

    await db.commit()
    await db.refresh(pos)
    return PositionOut.of(pos)


@router.post("/sell", response_model=PositionOut)
async def sell(
    body: SellRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    code = (body.fund_code or "").strip().upper()
    if code not in FUNDS:
        raise HTTPException(status_code=404, detail="صندوق یافت نشد")

    pos = (await db.execute(
        select(InvestmentPosition)
        .where(InvestmentPosition.user_id == me.id,
               InvestmentPosition.fund_code == code)
        .with_for_update()
    )).scalar_one_or_none()
    if pos is None or float(pos.units or 0) <= 0:
        raise HTTPException(status_code=404, detail="موقعیتی برای این صندوق ندارید")
    # رواداری هم‌اندازهٔ گِردکردنِ خودِ پاسخ: کلاینت جز همان عددِ منتشرشده چیزی
    # ندارد، پس «فروشِ همه» نباید به‌خاطرِ رقمِ هفتمِ اعشار رد شود.
    if body.units > float(pos.units) + UNITS_EPS:
        raise HTTPException(status_code=400, detail="واحدِ کافی ندارید")

    sold = min(body.units, float(pos.units))
    proceeds = int(round(sold * nav_minor(code)))

    await get_or_create_wallet(db, me.id)
    w = (await db.execute(
        select(Wallet).where(Wallet.user_id == me.id).with_for_update()
    )).scalar_one()

    before = w.balance_available
    w.balance_available += proceeds
    db.add(WalletTransaction(
        wallet_id=w.id, type="transfer_in", status="completed",
        amount=proceeds, balance_before=before, balance_after=w.balance_available,
        reference_id=str(pos.id),
        description=f"فروشِ واحدِ {FUNDS[code]['title']}",
    ))

    # سرمایهٔ اولیه به نسبتِ واحدهای فروخته‌شده کم می‌شود تا «سود» معنا بدهد.
    prev_units = float(pos.units)
    pos.invested_minor = int(round(
        int(pos.invested_minor or 0) * (1 - sold / prev_units)
    )) if prev_units > 0 else 0
    pos.units = prev_units - sold
    # باقی‌ماندهٔ زیرِ دقتِ منتشرشده «غبار» است: نه نمایش داده می‌شود نه فروختنی،
    # پس موقعیت را باز نگه نمی‌داریم.
    if pos.units <= UNITS_EPS:
        pos.units = 0.0
        pos.invested_minor = 0
        pos.status = STATUS_CLOSED

    await db.commit()
    await db.refresh(pos)
    return PositionOut.of(pos)
