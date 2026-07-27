"""
Dilix — بازارگاهِ خدمات: آگهی + سفارشِ امانی (escrow)

    GET  /api/v1/marketplace/listings            فهرست/جستجوی آگهی‌ها
    POST /api/v1/marketplace/listings            ثبتِ آگهی
    GET  /api/v1/marketplace/orders              سفارش‌های من (خریدار یا فروشنده)
    POST /api/v1/marketplace/orders              ثبتِ سفارش (وجه بلوکه می‌شود)
    POST /api/v1/marketplace/orders/{id}/{action}  accept | deliver | complete | cancel

سه تصمیمی که ساختار را تعیین کرد:

۱) **وجه هنگامِ ثبتِ سفارش بلوکه می‌شود، نه هنگامِ تحویل.** اگر پول در پایان
   گرفته می‌شد، فروشنده کار را انجام می‌داد و ممکن بود خریدار موجودی نداشته
   باشد. با بلوکه‌کردن، پول نه دستِ فروشنده است نه در دسترسِ خریدار.

۲) **گذارهای وضعیت با جدولِ مجاز کنترل می‌شوند و نقشِ مجاز هم بررسی می‌شود.**
   بدونِ آن، خریدار می‌توانست سفارش را «تحویل‌شده» کند یا `complete` دوباره
   اجرا شود و `release_escrow` پولِ بلوکه‌نشده را آزاد کند — یعنی خلقِ پول.

۳) **کارمزدِ پلتفرم هنگامِ آزادسازی از مبلغ کم می‌شود** (همان معناشناسیِ
   `release_escrow`)، نه به‌صورتِ تراکنشِ جدا؛ تا جریانِ امانی و جریانِ مستقیم
   دو تعریفِ متفاوت از کارمزد پیدا نکنند.
"""
import uuid as _uuid
from datetime import datetime, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import (
    BigInteger, Column, DateTime, ForeignKey, Integer, String, Text, or_, select,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import Base, get_db
from app.models.user import User
from app.services.wallet_ops import lock_escrow, refund_escrow, release_escrow

router = APIRouter(prefix="/marketplace", tags=["Marketplace"])

COMMISSION_PCT = 5      # کارمزدِ پلتفرم روی هر سفارشِ تکمیل‌شده

CATEGORIES = {
    "logistics":  "حمل‌ونقل",
    "design":     "طراحی",
    "dev":        "برنامه‌نویسی",
    "content":    "تولیدِ محتوا",
    "consulting": "مشاوره",
    "legal":      "حقوقی",
    "other":      "سایر",
}

# گذارهای مجاز: کنش → (وضعیتِ فعلی، وضعیتِ بعدی، نقشِ مجاز)
TRANSITIONS = {
    "accept":   (("pending",), "accepted", "provider"),
    "deliver":  (("accepted", "in_progress"), "delivered", "provider"),
    "complete": (("delivered",), "completed", "buyer"),
    "cancel":   (("pending", "accepted"), "cancelled", "buyer"),
}


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── مدل ───────────────────────────────────────────────────────────────────────
class Listing(Base):
    __tablename__ = "market_listings"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    provider_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                         nullable=False, index=True)
    title = Column(String(200), nullable=False)
    description = Column(Text, nullable=False, default="")
    category = Column(String(32), nullable=False, default="other")
    base_price_minor = Column(BigInteger, nullable=False)
    currency = Column(String(3), nullable=False, default="IRR")
    delivery_days = Column(Integer, nullable=False, default=7)
    status = Column(String(16), nullable=False, default="active")
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)


class Order(Base):
    __tablename__ = "market_orders"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    listing_id = Column(UUID(as_uuid=True), ForeignKey("market_listings.id", ondelete="CASCADE"),
                        nullable=False, index=True)
    buyer_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                      nullable=False, index=True)
    provider_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                         nullable=False, index=True)
    agreed_price_minor = Column(BigInteger, nullable=False)
    currency = Column(String(3), nullable=False, default="IRR")
    requirements = Column(Text, nullable=True)
    status = Column(String(16), nullable=False, default="pending")
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)


# ── Schemas ───────────────────────────────────────────────────────────────────
class ListingOut(BaseModel):
    id:                str
    provider_earth_id: str
    title:             str
    description:       str
    category:          str
    category_label:    str
    base_price_minor:  int
    currency:          str
    delivery_days:     int
    status:            str


class ListingCreate(BaseModel):
    title:            str = Field(..., min_length=3, max_length=200)
    description:      str = Field("", max_length=5000)
    category:         str = "other"
    base_price_minor: int = Field(..., gt=0)
    currency:         str = "IRR"
    delivery_days:    int = Field(7, ge=1, le=365)


class OrderOut(BaseModel):
    id:                 str
    listing_id:         str
    buyer_earth_id:     str
    provider_earth_id:  str
    agreed_price_minor: int
    currency:           str
    status:             str
    created_at:         datetime


class OrderCreate(BaseModel):
    listing_id:         str
    agreed_price_minor: int = Field(..., gt=0)
    currency:           str = "IRR"
    requirements:       Optional[str] = Field(None, max_length=5000)


# ── Helpers ───────────────────────────────────────────────────────────────────
async def _earth_ids(db: AsyncSession, ids) -> dict:
    """نگاشتِ user_id → earth_id در یک کوئری (پرهیز از N+1)."""
    ids = {i for i in ids if i}
    if not ids:
        return {}
    return {
        uid: eid for uid, eid in (await db.execute(
            select(User.id, User.earth_id).where(User.id.in_(ids))
        )).all()
    }


def _listing_out(o: Listing, earth: dict) -> ListingOut:
    return ListingOut(
        id=str(o.id), provider_earth_id=earth.get(o.provider_id, ""),
        title=o.title, description=o.description or "", category=o.category,
        category_label=CATEGORIES.get(o.category, o.category),
        base_price_minor=int(o.base_price_minor), currency=o.currency,
        delivery_days=int(o.delivery_days), status=o.status,
    )


def _order_out(o: Order, earth: dict) -> OrderOut:
    return OrderOut(
        id=str(o.id), listing_id=str(o.listing_id),
        buyer_earth_id=earth.get(o.buyer_id, ""),
        provider_earth_id=earth.get(o.provider_id, ""),
        agreed_price_minor=int(o.agreed_price_minor), currency=o.currency,
        status=o.status, created_at=o.created_at,
    )


def _as_uuid(value: str, what: str) -> _uuid.UUID:
    try:
        return _uuid.UUID(value)
    except (ValueError, AttributeError):
        raise HTTPException(status_code=400, detail=f"شناسهٔ {what} نامعتبر است")


# ── Endpoints ─────────────────────────────────────────────────────────────────
@router.get("/listings", response_model=List[ListingOut])
async def list_listings(
    keyword: Optional[str] = Query(None),
    category: Optional[str] = Query(None),
    limit: int = 50,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    q = select(Listing).where(Listing.status == "active")
    if keyword:
        like = f"%{keyword.strip()}%"
        q = q.where(or_(Listing.title.ilike(like), Listing.description.ilike(like)))
    if category:
        q = q.where(Listing.category == category)
    rows = (await db.execute(
        q.order_by(Listing.created_at.desc()).limit(max(1, min(limit, 200)))
    )).scalars().all()
    earth = await _earth_ids(db, [r.provider_id for r in rows])
    return [_listing_out(r, earth) for r in rows]


@router.post("/listings", response_model=ListingOut, status_code=201)
async def create_listing(
    body: ListingCreate,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    category = body.category if body.category in CATEGORIES else "other"
    o = Listing(
        provider_id=me.id, title=body.title.strip(),
        description=(body.description or "").strip(), category=category,
        base_price_minor=body.base_price_minor,
        currency=(body.currency or "IRR").upper(),
        delivery_days=body.delivery_days, status="active",
    )
    db.add(o)
    await db.commit()
    await db.refresh(o)
    return _listing_out(o, {me.id: me.earth_id})


@router.get("/orders", response_model=List[OrderOut])
async def my_orders(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    rows = (await db.execute(
        select(Order)
        .where(or_(Order.buyer_id == me.id, Order.provider_id == me.id))
        .order_by(Order.created_at.desc())
    )).scalars().all()
    earth = await _earth_ids(db, [r.buyer_id for r in rows] + [r.provider_id for r in rows])
    return [_order_out(r, earth) for r in rows]


@router.post("/orders", response_model=OrderOut, status_code=201)
async def place_order(
    body: OrderCreate,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    listing = await db.get(Listing, _as_uuid(body.listing_id, "آگهی"))
    if listing is None or listing.status != "active":
        raise HTTPException(status_code=404, detail="آگهی یافت نشد")
    if listing.provider_id == me.id:
        raise HTTPException(status_code=400, detail="روی آگهیِ خودتان نمی‌توانید سفارش بدهید")
    if (body.currency or "IRR").upper() != listing.currency:
        raise HTTPException(status_code=400, detail="ارزِ سفارش با آگهی یکی نیست")

    o = Order(
        listing_id=listing.id, buyer_id=me.id, provider_id=listing.provider_id,
        agreed_price_minor=body.agreed_price_minor,
        currency=listing.currency, requirements=body.requirements, status="pending",
    )
    db.add(o)
    await db.flush()

    await lock_escrow(
        db, me.id, body.agreed_price_minor,
        description=f"بلوکهٔ سفارشِ «{listing.title}»", reference_id=str(o.id),
    )
    await db.commit()
    await db.refresh(o)
    earth = await _earth_ids(db, [o.buyer_id, o.provider_id])
    return _order_out(o, earth)


@router.post("/orders/{order_id}/{action}", response_model=OrderOut)
async def order_action(
    order_id: str,
    action: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    if action not in TRANSITIONS:
        raise HTTPException(status_code=400, detail="کنشِ نامعتبر")
    allowed_from, new_status, role = TRANSITIONS[action]

    # قفلِ ردیف: بدونِ آن دو `complete` هم‌زمان هر دو از شرطِ وضعیت رد می‌شدند و
    # `release_escrow` دو بار اجرا می‌شد.
    o = (await db.execute(
        select(Order).where(Order.id == _as_uuid(order_id, "سفارش")).with_for_update()
    )).scalar_one_or_none()
    if o is None:
        raise HTTPException(status_code=404, detail="سفارش یافت نشد")

    actor_id = o.provider_id if role == "provider" else o.buyer_id
    if actor_id != me.id:
        raise HTTPException(status_code=403, detail="این کنش برای شما مجاز نیست")
    if o.status not in allowed_from:
        raise HTTPException(status_code=409, detail=f"سفارش در وضعیتِ «{o.status}» است")

    if action == "complete":
        fee = int(o.agreed_price_minor) * COMMISSION_PCT // 100
        await release_escrow(
            db, o.buyer_id, o.provider_id, int(o.agreed_price_minor),
            out_desc="آزادسازیِ وجهِ سفارش", in_desc="دریافتِ وجهِ سفارش",
            fee=fee, fee_desc="کارمزدِ بازارگاه", reference_id=str(o.id),
        )
    elif action == "cancel":
        await refund_escrow(
            db, o.buyer_id, int(o.agreed_price_minor),
            description="بازگشتِ وجهِ سفارشِ لغوشده", reference_id=str(o.id),
        )

    o.status = new_status
    await db.commit()
    await db.refresh(o)
    earth = await _earth_ids(db, [o.buyer_id, o.provider_id])
    return _order_out(o, earth)
