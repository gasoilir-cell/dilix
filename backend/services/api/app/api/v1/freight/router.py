"""
Dilix — Freight Router
POST   /api/v1/freight/posts        ثبت بار جدید (صاحب بار / کارگزار)
GET    /api/v1/freight/posts        لیست بارهای موجود (راننده: open / صاحب بار: خودش)
GET    /api/v1/freight/posts/{id}   جزئیات یک بار
POST   /api/v1/freight/posts/{id}/take   راننده بار را می‌پذیرد
DELETE /api/v1/freight/posts/{id}   لغو (فقط صاحب بار، وقتی open است)

POST   /api/v1/freight/posts/{id}/offers   راننده پیشنهادِ قیمت می‌دهد (bidding)
GET    /api/v1/freight/posts/{id}/offers   پیشنهادها (صاحب بار: همه/ارزان‌ترین اول؛ راننده: خودش)
POST   /api/v1/freight/offers/{id}/accept  صاحب بار یک پیشنهاد را می‌پذیرد
POST   /api/v1/freight/offers/{id}/withdraw  راننده پیشنهادش را پس می‌گیرد

چرخهٔ عمرِ حمل (multi-party lifecycle):
POST   /api/v1/freight/posts/{id}/pickup     راننده تحویل‌گیریِ بار در مبدأ را با کدِ مبدأ تأیید می‌کند
POST   /api/v1/freight/posts/{id}/location   راننده موقعیتِ فعلی را ثبت می‌کند (رهگیریِ مسیر)
POST   /api/v1/freight/posts/{id}/deliver    راننده تحویلِ بار در مقصد را ثبت می‌کند (+عکسِ اثباتِ تحویل)
POST   /api/v1/freight/posts/{id}/receive    صاحب/گیرنده دریافتِ نهایی را با کدِ مقصد تأیید می‌کند
GET    /api/v1/freight/posts/{id}/tracking   خطِ زمانیِ رهگیری
GET    /api/v1/freight/vehicle-types         کاتالوگِ انواعِ باربری
"""
import uuid as _uuid
import random
from datetime import datetime, timezone
from typing import Optional, List

from fastapi import APIRouter, Depends, HTTPException, status, Query
from pydantic import BaseModel, Field
from sqlalchemy import (
    select, func, Column, BigInteger, Integer, Float, Boolean, String,
    DateTime, Enum, ForeignKey, Text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db, Base
from app.api.deps import get_current_user
from app.models.user import User
from app.models.freight import CargoPost
from app.models.wallet import Wallet, WalletTransaction

router = APIRouter(prefix="/freight", tags=["Freight"])

# کارمزدِ دیلیکس روی هر حملِ تسویه‌شده (درصد)
FREIGHT_COMMISSION_PCT = 10


def _now():
    return datetime.now(timezone.utc)


def _gen_code() -> str:
    """کدِ تأییدِ ۴رقمی برای گره‌های تحویل."""
    return f"{random.randint(1000, 9999)}"


async def _wallet_of(db: AsyncSession, user_id, create: bool = False) -> Optional[Wallet]:
    """کیفِ پولِ یک کاربر (در صورتِ نبود و create=True با موجودی صفر می‌سازد)."""
    r = await db.execute(select(Wallet).where(Wallet.user_id == user_id))
    w = r.scalar_one_or_none()
    if w is None and create:
        w = Wallet(user_id=user_id, currency="IRR")
        db.add(w)
        await db.flush()
    return w


async def _lock_escrow(db: AsyncSession, post: CargoPost, amount: int):
    """وجهِ توافقی را از موجودیِ در دسترسِ صاحبِ بار بلوکه (escrow) می‌کند.

    اگر موجودی کافی نباشد یا کیف مسدود باشد، خطای شفاف برمی‌گرداند.
    idempotent: اگر قبلاً قفل شده باشد دوباره قفل نمی‌کند.
    """
    if post.escrow_status == "locked":
        return
    w = await _wallet_of(db, post.owner_id)
    if w is None or w.is_frozen:
        raise HTTPException(status_code=400, detail="کیفِ پولِ صاحبِ بار در دسترس نیست؛ ابتدا شارژ کنید")
    if int(w.balance_available or 0) < amount:
        raise HTTPException(status_code=400, detail="موجودیِ کیفِ صاحبِ بار برای بلوکِ وجه کافی نیست")

    before = int(w.balance_available or 0)
    w.balance_available = before - amount
    w.balance_escrow = int(w.balance_escrow or 0) + amount
    db.add(WalletTransaction(
        wallet_id=w.id, type="escrow_lock", status="completed", amount=amount,
        balance_before=before, balance_after=w.balance_available,
        reference_id=post.ref, description=f"بلوکِ وجه برای حملِ {post.ref}",
    ))
    post.escrow_amount = amount
    post.escrow_status = "locked"


async def _release_escrow(db: AsyncSession, post: CargoPost):
    """آزادسازیِ escrow: راننده «مبلغ − کارمزد» می‌گیرد، کارمزدِ دیلیکس ثبت می‌شود.

    idempotent: فقط وقتی escrow_status == 'locked' اجرا می‌شود.
    """
    if post.escrow_status != "locked" or not post.escrow_amount:
        return
    amount = int(post.escrow_amount)
    commission = amount * FREIGHT_COMMISSION_PCT // 100

    # صاحبِ بار: خروجِ وجه از escrow
    ow = await _wallet_of(db, post.owner_id)
    if ow is not None:
        ow.balance_escrow = max(0, int(ow.balance_escrow or 0) - amount)
        db.add(WalletTransaction(
            wallet_id=ow.id, type="escrow_release", status="completed", amount=amount,
            balance_before=int(ow.balance_available or 0), balance_after=int(ow.balance_available or 0),
            reference_id=post.ref, description=f"تسویهٔ حملِ {post.ref} (پرداخت به راننده)",
        ))

    # راننده: دریافتِ خالص + ثبتِ کارمزد
    if post.driver_id:
        dw = await _wallet_of(db, post.driver_id, create=True)
        d_before = int(dw.balance_available or 0)
        dw.balance_available = d_before + amount
        db.add(WalletTransaction(
            wallet_id=dw.id, type="escrow_release", status="completed", amount=amount,
            balance_before=d_before, balance_after=dw.balance_available,
            reference_id=post.ref, description=f"دریافتِ کرایهٔ حملِ {post.ref}",
        ))
        if commission > 0:
            f_before = int(dw.balance_available or 0)
            dw.balance_available = f_before - commission
            db.add(WalletTransaction(
                wallet_id=dw.id, type="fee", status="completed", amount=commission,
                balance_before=f_before, balance_after=dw.balance_available,
                reference_id=post.ref, description=f"کارمزدِ دیلیکس ({FREIGHT_COMMISSION_PCT}٪) — حملِ {post.ref}",
            ))

    post.commission_amount = commission
    post.escrow_status = "released"


async def _refund_escrow(db: AsyncSession, post: CargoPost):
    """بازگشتِ escrow به صاحبِ بار هنگامِ لغو (پیش از تحویل). بدونِ کارمزد.

    idempotent: فقط وقتی escrow_status == 'locked' اجرا می‌شود.
    """
    if post.escrow_status != "locked" or not post.escrow_amount:
        return
    amount = int(post.escrow_amount)
    ow = await _wallet_of(db, post.owner_id)
    if ow is not None:
        before = int(ow.balance_available or 0)
        ow.balance_available = before + amount
        ow.balance_escrow = max(0, int(ow.balance_escrow or 0) - amount)
        db.add(WalletTransaction(
            wallet_id=ow.id, type="refund", status="completed", amount=amount,
            balance_before=before, balance_after=ow.balance_available,
            reference_id=post.ref, description=f"بازگشتِ وجهِ امانی — لغوِ حملِ {post.ref}",
        ))
    post.escrow_status = "refunded"


# ── Model: پیشنهادِ قیمتِ راننده روی یک بار (bidding) ─────────────
class FreightOffer(Base):
    """پیشنهادِ قیمتِ یک راننده روی یک بارِ open. صاحبِ بار مقایسه و یکی را می‌پذیرد."""
    __tablename__ = "freight_offers"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    post_id    = Column(UUID(as_uuid=True), ForeignKey("cargo_posts.id"), nullable=False, index=True)
    driver_id  = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    price      = Column(BigInteger, nullable=False)              # پیشنهادِ راننده (ریال)
    eta_days   = Column(Integer, nullable=True)                  # زمانِ تخمینیِ تحویل (روز)
    message    = Column(Text, nullable=True)
    status     = Column(
        Enum("pending", "accepted", "rejected", "withdrawn", name="freight_offer_status_enum"),
        nullable=False, default="pending", index=True,
    )
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)


# ── Model: رویدادِ رهگیری (timeline) ──────────────────────────────
class FreightTrackingEvent(Base):
    """هر تغییرِ حالت یا آپدیتِ موقعیت روی یک بار، برای نمایشِ خطِ زمانی."""
    __tablename__ = "freight_tracking_events"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    post_id    = Column(UUID(as_uuid=True), ForeignKey("cargo_posts.id"), nullable=False, index=True)
    actor_id   = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    event_type = Column(String(30), nullable=False)   # created/accepted/picked_up/location/delivered/received/cancelled
    status     = Column(String(30), nullable=True)     # حالتِ بار پس از رویداد
    lat        = Column(Float, nullable=True)
    lng        = Column(Float, nullable=True)
    note       = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)


# ── Model: کاتالوگِ انواعِ باربری ─────────────────────────────────
class FreightVehicleType(Base):
    """انواعِ خودرو/سرویسِ باربری (وانت، خاور، کامیون، تریلی، ...)."""
    __tablename__ = "freight_vehicle_types"

    id            = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    code          = Column(String(50), nullable=False, unique=True)
    name_fa       = Column(String(100), nullable=False)
    category      = Column(String(30), nullable=False, default="intercity")  # intracity/intercity/international
    max_weight_kg = Column(Float, nullable=True)
    icon          = Column(String(50), nullable=True)
    sort_order    = Column(Integer, nullable=False, default=0)
    active        = Column(Boolean, nullable=False, default=True)


# ── Model: امتیازدهیِ متقابل پس از تحویلِ نهایی ───────────────────
class FreightRating(Base):
    """امتیازِ یک طرف به طرفِ دیگر پس از `received`. هر طرف یک‌بار می‌تواند امتیاز دهد."""
    __tablename__ = "freight_ratings"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    post_id    = Column(UUID(as_uuid=True), ForeignKey("cargo_posts.id"), nullable=False, index=True)
    rater_id   = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    ratee_id   = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    role       = Column(String(24), nullable=False)   # owner_rates_driver / driver_rates_owner
    score      = Column(Integer, nullable=False)       # 1..5
    comment    = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)


# ── ورودی‌های چرخهٔ عمر (باید پیش از endpointها تعریف شوند) ──────
class CodeIn(BaseModel):
    code: str = Field(..., min_length=1, max_length=8)


class LocationIn(BaseModel):
    lat:  float
    lng:  float
    note: Optional[str] = Field(None, max_length=200)


class DeliverIn(BaseModel):
    pod_photo_url: Optional[str] = Field(None, max_length=1000)


# ── Schemas ───────────────────────────────────────────────────
class CargoPostCreate(BaseModel):
    origin:      str       = Field(..., min_length=2, max_length=500)
    destination: str       = Field(..., min_length=2, max_length=500)
    origin_lat:  Optional[float] = None
    origin_lng:  Optional[float] = None
    dest_lat:    Optional[float] = None
    dest_lng:    Optional[float] = None
    cargo_type:  str       = Field(..., min_length=2, max_length=100)
    vehicle_type: Optional[str] = Field(None, max_length=50)
    weight_kg:   float     = Field(..., gt=0)
    price:       int       = Field(..., gt=0)
    description: Optional[str] = None
    pickup_date: Optional[datetime] = None
    consignee_name:  Optional[str] = Field(None, max_length=200)
    consignee_phone: Optional[str] = Field(None, max_length=30)


class CargoPostOut(BaseModel):
    id:          str
    ref:         str
    owner_id:    str
    origin:      str
    destination: str
    origin_lat:  Optional[float]
    origin_lng:  Optional[float]
    dest_lat:    Optional[float]
    dest_lng:    Optional[float]
    cargo_type:  str
    vehicle_type: Optional[str] = None
    weight_kg:   float
    price:       int
    description: Optional[str]
    status:      str
    driver_id:   Optional[str]
    pickup_date: Optional[datetime]
    offers_count: int = 0
    consignee_name:  Optional[str] = None
    consignee_phone: Optional[str] = None
    pod_photo_url:   Optional[str] = None
    picked_up_at:    Optional[datetime] = None
    delivered_at:    Optional[datetime] = None
    received_at:     Optional[datetime] = None
    last_lat:        Optional[float] = None
    last_lng:        Optional[float] = None
    last_location_at: Optional[datetime] = None
    escrow_amount:     Optional[int] = None
    escrow_status:     Optional[str] = None
    commission_amount: Optional[int] = None
    rated_by_me:       bool = False
    # کدهای تأیید فقط برای صاحبِ بار دیده می‌شوند
    pickup_code:   Optional[str] = None
    delivery_code: Optional[str] = None
    created_at:  datetime

    class Config:
        from_attributes = True

    @classmethod
    def from_orm(cls, obj: CargoPost, me_id=None) -> "CargoPostOut":
        is_owner = me_id is not None and obj.owner_id == me_id
        return cls(
            id          = str(obj.id),
            ref         = obj.ref,
            owner_id    = str(obj.owner_id),
            origin      = obj.origin,
            destination = obj.destination,
            origin_lat  = obj.origin_lat,
            origin_lng  = obj.origin_lng,
            dest_lat    = obj.dest_lat,
            dest_lng    = obj.dest_lng,
            cargo_type  = obj.cargo_type,
            vehicle_type = getattr(obj, "vehicle_type", None),
            weight_kg   = obj.weight_kg,
            price       = obj.price,
            description = obj.description,
            status      = obj.status,
            driver_id   = str(obj.driver_id) if obj.driver_id else None,
            pickup_date = obj.pickup_date,
            consignee_name  = getattr(obj, "consignee_name", None),
            consignee_phone = getattr(obj, "consignee_phone", None),
            pod_photo_url   = getattr(obj, "pod_photo_url", None),
            picked_up_at    = getattr(obj, "picked_up_at", None),
            delivered_at    = getattr(obj, "delivered_at", None),
            received_at     = getattr(obj, "received_at", None),
            last_lat        = getattr(obj, "last_lat", None),
            last_lng        = getattr(obj, "last_lng", None),
            last_location_at = getattr(obj, "last_location_at", None),
            escrow_amount     = getattr(obj, "escrow_amount", None),
            escrow_status     = getattr(obj, "escrow_status", None),
            commission_amount = getattr(obj, "commission_amount", None),
            pickup_code   = (getattr(obj, "pickup_code", None) if is_owner else None),
            delivery_code = (getattr(obj, "delivery_code", None) if is_owner else None),
            created_at  = obj.created_at,
        )


def _gen_ref() -> str:
    """FRT-XXXXXXXX"""
    return "FRT-" + _uuid.uuid4().hex[:8].upper()


def _track(db: AsyncSession, post: CargoPost, actor_id, event_type: str,
           lat: Optional[float] = None, lng: Optional[float] = None,
           note: Optional[str] = None):
    """یک رویدادِ رهگیری به خطِ زمانی اضافه می‌کند (commit توسطِ فراخوان)."""
    db.add(FreightTrackingEvent(
        post_id=post.id, actor_id=actor_id, event_type=event_type,
        status=post.status, lat=lat, lng=lng, note=note,
    ))


# ── Vehicle Types ─────────────────────────────────────────────
class VehicleTypeOut(BaseModel):
    code:          str
    name_fa:       str
    category:      str
    max_weight_kg: Optional[float] = None
    icon:          Optional[str] = None

    class Config:
        from_attributes = True


@router.get("/vehicle-types", response_model=List[VehicleTypeOut])
async def list_vehicle_types(
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    """کاتالوگِ انواعِ باربری (وانت، خاور، کامیون، تریلی، ...)."""
    r = await db.execute(
        select(FreightVehicleType)
        .where(FreightVehicleType.active == True)  # noqa: E712
        .order_by(FreightVehicleType.sort_order.asc())
    )
    return [VehicleTypeOut.model_validate(v) for v in r.scalars().all()]


# ── Endpoints ─────────────────────────────────────────────────

@router.post("/posts", response_model=CargoPostOut, status_code=status.HTTP_201_CREATED)
async def create_cargo_post(
    body: CargoPostCreate,
    db:   AsyncSession = Depends(get_db),
    me:   User         = Depends(get_current_user),
):
    """ثبت بار جدید — برای همه کاربران احرازهویت‌شده"""
    post = CargoPost(
        ref         = _gen_ref(),
        owner_id    = me.id,
        origin      = body.origin,
        destination = body.destination,
        origin_lat  = body.origin_lat,
        origin_lng  = body.origin_lng,
        dest_lat    = body.dest_lat,
        dest_lng    = body.dest_lng,
        cargo_type  = body.cargo_type,
        vehicle_type = body.vehicle_type,
        weight_kg   = body.weight_kg,
        price       = body.price,
        description = body.description,
        pickup_date = body.pickup_date,
        consignee_name  = body.consignee_name,
        consignee_phone = body.consignee_phone,
        status      = "open",
    )
    db.add(post)
    await db.flush()
    _track(db, post, me.id, "created", note="بار ثبت شد")
    await db.commit()
    await db.refresh(post)
    return CargoPostOut.from_orm(post, me.id)


@router.get("/posts", response_model=List[CargoPostOut])
async def list_cargo_posts(
    mine:  bool = Query(False, description="فقط بارهای خودم"),
    limit: int  = Query(50, le=200),
    db:    AsyncSession = Depends(get_db),
    me:    User         = Depends(get_current_user),
):
    """
    لیست بارها.
    - mine=false (پیش‌فرض): بارهای open برای رانندگان
    - mine=true: بارهای صاحب بار لاگین‌شده
    """
    if mine:
        q = select(CargoPost).where(CargoPost.owner_id == me.id)
    else:
        q = select(CargoPost).where(CargoPost.status == "open")

    q = q.order_by(CargoPost.created_at.desc()).limit(limit)
    result = await db.execute(q)
    posts  = result.scalars().all()
    out = [CargoPostOut.from_orm(p, me.id) for p in posts]

    # شمارِ پیشنهادهای در انتظار برای بارهای خودِ صاحبِ بار
    if mine and posts:
        cnt = await db.execute(
            select(FreightOffer.post_id, func.count(FreightOffer.id))
            .where(
                FreightOffer.post_id.in_([p.id for p in posts]),
                FreightOffer.status == "pending",
            )
            .group_by(FreightOffer.post_id)
        )
        counts = {str(pid): int(c) for pid, c in cnt.all()}
        for o in out:
            o.offers_count = counts.get(o.id, 0)

    # علامتِ «قبلاً امتیاز داده‌ام» برای بارهای تحویل‌شده (batched)
    received_ids = [p.id for p in posts if p.status == "received"]
    if received_ids:
        rr = await db.execute(
            select(FreightRating.post_id).where(
                FreightRating.post_id.in_(received_ids),
                FreightRating.rater_id == me.id,
            )
        )
        rated_set = {str(pid) for (pid,) in rr.all()}
        for o in out:
            if o.id in rated_set:
                o.rated_by_me = True
    return out


@router.get("/posts/{post_id}", response_model=CargoPostOut)
async def get_cargo_post(
    post_id: str,
    db:  AsyncSession = Depends(get_db),
    me:  User         = Depends(get_current_user),
):
    post = await db.get(CargoPost, _uuid.UUID(post_id))
    if not post:
        raise HTTPException(status_code=404, detail="بار پیدا نشد")
    out = CargoPostOut.from_orm(post, me.id)
    if post.status == "received":
        rated = await db.execute(
            select(FreightRating.id).where(
                FreightRating.post_id == post.id,
                FreightRating.rater_id == me.id,
            ).limit(1)
        )
        out.rated_by_me = rated.scalars().first() is not None
    return out


@router.post("/posts/{post_id}/take", response_model=CargoPostOut)
async def take_cargo(
    post_id: str,
    db:  AsyncSession = Depends(get_db),
    me:  User         = Depends(get_current_user),
):
    """راننده بار را می‌پذیرد (پذیرشِ مستقیم با قیمتِ فعلی)."""
    post = await db.get(CargoPost, _uuid.UUID(post_id))
    if not post:
        raise HTTPException(status_code=404, detail="بار پیدا نشد")
    if post.status != "open":
        raise HTTPException(status_code=400, detail="این بار دیگر در دسترس نیست")
    if post.owner_id == me.id:
        raise HTTPException(status_code=400, detail="نمی‌توانید بار خود را بپذیرید")

    # بلوکِ وجهِ صاحبِ بار (escrow) پیش از تخصیص
    await _lock_escrow(db, post, int(post.price))

    post.driver_id     = me.id
    post.status        = "in_progress"
    post.pickup_code   = _gen_code()
    post.delivery_code = _gen_code()
    _track(db, post, me.id, "accepted", note="راننده بار را پذیرفت")
    await db.commit()
    await db.refresh(post)
    return CargoPostOut.from_orm(post, me.id)


@router.post("/posts/{post_id}/pickup", response_model=CargoPostOut)
async def pickup_cargo(
    post_id: str,
    body: CodeIn,
    db:  AsyncSession = Depends(get_db),
    me:  User         = Depends(get_current_user),
):
    """راننده تحویل‌گیریِ بار در مبدأ را با کدِ مبدأ (که صاحبِ بار در محل می‌دهد) تأیید می‌کند."""
    post = await db.get(CargoPost, _uuid.UUID(post_id))
    if not post:
        raise HTTPException(status_code=404, detail="بار پیدا نشد")
    if post.driver_id != me.id:
        raise HTTPException(status_code=403, detail="فقط رانندهٔ تخصیص‌یافته می‌تواند تحویل بگیرد")
    if post.status != "in_progress":
        raise HTTPException(status_code=400, detail="این بار در مرحلهٔ تحویل‌گیری نیست")
    if not post.pickup_code or body.code.strip() != post.pickup_code:
        raise HTTPException(status_code=400, detail="کدِ مبدأ نادرست است")

    post.status       = "picked_up"
    post.picked_up_at = _now()
    _track(db, post, me.id, "picked_up",
           lat=post.origin_lat, lng=post.origin_lng, note="بار در مبدأ تحویل گرفته شد")
    await db.commit()
    await db.refresh(post)
    return CargoPostOut.from_orm(post, me.id)


@router.post("/posts/{post_id}/location", response_model=CargoPostOut)
async def update_location(
    post_id: str,
    body: LocationIn,
    db:  AsyncSession = Depends(get_db),
    me:  User         = Depends(get_current_user),
):
    """راننده موقعیتِ فعلی را ثبت می‌کند (رهگیریِ مسیرِ مبدأ تا مقصد)."""
    post = await db.get(CargoPost, _uuid.UUID(post_id))
    if not post:
        raise HTTPException(status_code=404, detail="بار پیدا نشد")
    if post.driver_id != me.id:
        raise HTTPException(status_code=403, detail="فقط رانندهٔ تخصیص‌یافته می‌تواند موقعیت بفرستد")
    if post.status not in ("picked_up", "in_transit"):
        raise HTTPException(status_code=400, detail="این بار در مرحلهٔ حمل نیست")

    post.last_lat = body.lat
    post.last_lng = body.lng
    post.last_location_at = _now()
    if post.status == "picked_up":
        post.status = "in_transit"
    _track(db, post, me.id, "location", lat=body.lat, lng=body.lng, note=body.note)
    await db.commit()
    await db.refresh(post)
    return CargoPostOut.from_orm(post, me.id)


@router.post("/posts/{post_id}/deliver", response_model=CargoPostOut)
async def deliver_cargo(
    post_id: str,
    body: DeliverIn,
    db:  AsyncSession = Depends(get_db),
    me:  User         = Depends(get_current_user),
):
    """راننده تحویلِ بار در مقصد را ثبت می‌کند (+ عکسِ اثباتِ تحویل)."""
    post = await db.get(CargoPost, _uuid.UUID(post_id))
    if not post:
        raise HTTPException(status_code=404, detail="بار پیدا نشد")
    if post.driver_id != me.id:
        raise HTTPException(status_code=403, detail="فقط رانندهٔ تخصیص‌یافته می‌تواند تحویل دهد")
    if post.status not in ("picked_up", "in_transit"):
        raise HTTPException(status_code=400, detail="این بار در مرحلهٔ تحویل در مقصد نیست")

    post.status        = "delivered"
    post.delivered_at  = _now()
    post.pod_photo_url = body.pod_photo_url
    _track(db, post, me.id, "delivered",
           lat=post.dest_lat, lng=post.dest_lng, note="بار در مقصد تحویل داده شد")
    await db.commit()
    await db.refresh(post)
    return CargoPostOut.from_orm(post, me.id)


@router.post("/posts/{post_id}/receive", response_model=CargoPostOut)
async def receive_cargo(
    post_id: str,
    body: CodeIn,
    db:  AsyncSession = Depends(get_db),
    me:  User         = Depends(get_current_user),
):
    """صاحبِ بار (به‌نمایندگیِ گیرنده) دریافتِ نهایی را با کدِ مقصد تأیید می‌کند."""
    post = await db.get(CargoPost, _uuid.UUID(post_id))
    if not post:
        raise HTTPException(status_code=404, detail="بار پیدا نشد")
    if post.owner_id != me.id:
        raise HTTPException(status_code=403, detail="فقط صاحبِ بار می‌تواند دریافت را تأیید کند")
    if post.status != "delivered":
        raise HTTPException(status_code=400, detail="این بار هنوز در مقصد تحویل داده نشده است")
    if not post.delivery_code or body.code.strip() != post.delivery_code:
        raise HTTPException(status_code=400, detail="کدِ مقصد نادرست است")

    post.status      = "received"
    post.received_at = _now()
    # تسویه: آزادسازیِ escrow به راننده منهایِ کارمزدِ دیلیکس
    await _release_escrow(db, post)
    # شمارِ سفرهای موفقِ راننده +۱ (اعتبارِ حملِ کامل‌شده)
    if post.driver_id:
        drv = await db.get(User, post.driver_id)
        if drv is not None:
            drv.total_trips = int(drv.total_trips or 0) + 1
    _track(db, post, me.id, "received",
           note=f"گیرندهٔ نهایی تحویل گرفت — تسویه انجام شد (کارمزد {FREIGHT_COMMISSION_PCT}٪)")
    await db.commit()
    await db.refresh(post)
    return CargoPostOut.from_orm(post, me.id)


class TrackingEventOut(BaseModel):
    id:         str
    event_type: str
    status:     Optional[str] = None
    lat:        Optional[float] = None
    lng:        Optional[float] = None
    note:       Optional[str] = None
    created_at: datetime


@router.get("/posts/{post_id}/tracking", response_model=List[TrackingEventOut])
async def get_tracking(
    post_id: str,
    db:  AsyncSession = Depends(get_db),
    me:  User         = Depends(get_current_user),
):
    """خطِ زمانیِ رهگیری (صاحبِ بار یا رانندهٔ تخصیص‌یافته)."""
    post = await db.get(CargoPost, _uuid.UUID(post_id))
    if not post:
        raise HTTPException(status_code=404, detail="بار پیدا نشد")
    if me.id not in (post.owner_id, post.driver_id):
        raise HTTPException(status_code=403, detail="دسترسی ندارید")

    r = await db.execute(
        select(FreightTrackingEvent)
        .where(FreightTrackingEvent.post_id == post.id)
        .order_by(FreightTrackingEvent.created_at.asc())
    )
    return [
        TrackingEventOut(
            id=str(e.id), event_type=e.event_type, status=e.status,
            lat=e.lat, lng=e.lng, note=e.note, created_at=e.created_at,
        )
        for e in r.scalars().all()
    ]


@router.delete("/posts/{post_id}", status_code=status.HTTP_204_NO_CONTENT)
async def cancel_post(
    post_id: str,
    db:  AsyncSession = Depends(get_db),
    me:  User         = Depends(get_current_user),
):
    """لغو بار توسطِ صاحبِ بار.

    - `open`: لغوِ ساده (هنوز escrow قفل نشده)؛ پیشنهادهای در انتظار رد می‌شوند.
    - `in_progress` (پذیرفته‌شده ولی هنوز تحویل‌گیری نشده): لغو مجاز است و وجهِ
      امانی کاملاً به صاحبِ بار **بازگردانده** می‌شود (بدونِ کارمزد).
    - پس از `picked_up` (بار در مسیر): لغوِ خودکار ممکن نیست (نیازِ داوری).
    """
    post = await db.get(CargoPost, _uuid.UUID(post_id))
    if not post:
        raise HTTPException(status_code=404, detail="بار پیدا نشد")
    if post.owner_id != me.id:
        raise HTTPException(status_code=403, detail="فقط صاحب بار می‌تواند لغو کند")
    if post.status not in ("open", "in_progress"):
        raise HTTPException(status_code=400, detail="در این مرحله امکانِ لغو نیست؛ بار در مسیر است")

    # بازگشتِ وجهِ امانی اگر قفل شده باشد (وضعیتِ in_progress)
    await _refund_escrow(db, post)

    # ردِ پیشنهادهای در انتظار/پذیرفته‌شده
    pend = await db.execute(
        select(FreightOffer).where(
            FreightOffer.post_id == post.id,
            FreightOffer.status.in_(("pending", "accepted")),
        )
    )
    for o in pend.scalars().all():
        o.status = "rejected"

    refunded = post.escrow_status == "refunded"
    post.status = "cancelled"
    _track(db, post, me.id, "cancelled",
           note=("بار لغو شد و وجهِ امانی بازگردانده شد" if refunded else "بار لغو شد"))
    await db.commit()


# ── پیشنهادِ قیمت (bidding) ────────────────────────────────────
class OfferCreate(BaseModel):
    price:    int           = Field(..., gt=0)          # پیشنهادِ راننده (ریال)
    eta_days: Optional[int] = Field(None, ge=0, le=365)
    message:  Optional[str] = Field(None, max_length=500)


class OfferOut(BaseModel):
    id:            str
    post_id:       str
    driver_id:     str
    driver_name:   Optional[str] = None
    driver_avatar: Optional[str] = None
    driver_rating: float = 0.0
    driver_trips:  int   = 0
    price:         int
    eta_days:      Optional[int] = None
    message:       Optional[str] = None
    status:        str
    is_mine:       bool = False
    best:          bool = False
    created_at:    datetime


def _offer_out(o: "FreightOffer", u: Optional[User], me_id) -> OfferOut:
    return OfferOut(
        id=str(o.id), post_id=str(o.post_id), driver_id=str(o.driver_id),
        driver_name=(u.full_name if u else None),
        driver_avatar=(u.avatar_url if u else None),
        driver_rating=(round((u.avg_rating or 0) / 100, 1) if u else 0.0),
        driver_trips=(int(u.total_trips or 0) if u else 0),
        price=int(o.price or 0), eta_days=o.eta_days, message=o.message,
        status=o.status, is_mine=(o.driver_id == me_id),
        created_at=o.created_at,
    )


@router.post("/posts/{post_id}/offers", response_model=OfferOut, status_code=status.HTTP_201_CREATED)
async def make_offer(
    post_id: str,
    body: OfferCreate,
    db:  AsyncSession = Depends(get_db),
    me:  User         = Depends(get_current_user),
):
    """راننده روی یک بارِ open پیشنهادِ قیمت می‌دهد.

    اگر قبلاً پیشنهادِ در انتظار داشته باشد، همان به‌روزرسانی می‌شود (نه ردیفِ تکراری).
    """
    post = await db.get(CargoPost, _uuid.UUID(post_id))
    if not post:
        raise HTTPException(status_code=404, detail="بار پیدا نشد")
    if post.status != "open":
        raise HTTPException(status_code=400, detail="این بار دیگر پذیرای پیشنهاد نیست")
    if post.owner_id == me.id:
        raise HTTPException(status_code=400, detail="روی بارِ خودتان نمی‌توانید پیشنهاد بدهید")

    existing = await db.execute(
        select(FreightOffer).where(
            FreightOffer.post_id == post.id,
            FreightOffer.driver_id == me.id,
            FreightOffer.status == "pending",
        ).limit(1)
    )
    offer = existing.scalars().first()
    if offer:
        offer.price = body.price
        offer.eta_days = body.eta_days
        offer.message = body.message
    else:
        offer = FreightOffer(
            post_id=post.id, driver_id=me.id, price=body.price,
            eta_days=body.eta_days, message=body.message, status="pending",
        )
        db.add(offer)
    await db.commit()
    await db.refresh(offer)
    return _offer_out(offer, me, me.id)


@router.get("/posts/{post_id}/offers", response_model=List[OfferOut])
async def list_offers(
    post_id: str,
    db:  AsyncSession = Depends(get_db),
    me:  User         = Depends(get_current_user),
):
    """پیشنهادهای یک بار.

    - صاحبِ بار: همهٔ پیشنهادهای در انتظار (ارزان‌ترین اول، با علامتِ `best`).
    - راننده: فقط پیشنهادِ خودش.
    """
    post = await db.get(CargoPost, _uuid.UUID(post_id))
    if not post:
        raise HTTPException(status_code=404, detail="بار پیدا نشد")

    is_owner = post.owner_id == me.id
    q = select(FreightOffer, User).join(User, User.id == FreightOffer.driver_id).where(
        FreightOffer.post_id == post.id,
        FreightOffer.status == "pending",
    )
    if not is_owner:
        q = q.where(FreightOffer.driver_id == me.id)
    q = q.order_by(FreightOffer.price.asc())
    r = await db.execute(q)
    rows = r.all()
    out = [_offer_out(o, u, me.id) for o, u in rows]
    if is_owner and out:
        out[0].best = True
    return out


@router.post("/offers/{offer_id}/accept", response_model=CargoPostOut)
async def accept_offer(
    offer_id: str,
    db:  AsyncSession = Depends(get_db),
    me:  User         = Depends(get_current_user),
):
    """صاحبِ بار یک پیشنهاد را می‌پذیرد: راننده تخصیص، قیمتِ توافقی ثبت،
    بار به `in_progress` و بقیهٔ پیشنهادها `rejected` می‌شوند.
    """
    offer = await db.get(FreightOffer, _uuid.UUID(offer_id))
    if not offer:
        raise HTTPException(status_code=404, detail="پیشنهاد پیدا نشد")
    post = await db.get(CargoPost, offer.post_id)
    if not post:
        raise HTTPException(status_code=404, detail="بار پیدا نشد")
    if post.owner_id != me.id:
        raise HTTPException(status_code=403, detail="فقط صاحب بار می‌تواند بپذیرد")
    if post.status != "open":
        raise HTTPException(status_code=400, detail="این بار دیگر open نیست")
    if offer.status != "pending":
        raise HTTPException(status_code=400, detail="این پیشنهاد در دسترس نیست")

    # بلوکِ وجهِ صاحبِ بار (escrow) با قیمتِ توافقی پیش از تخصیص
    await _lock_escrow(db, post, int(offer.price))

    post.driver_id     = offer.driver_id
    post.price         = offer.price
    post.status        = "in_progress"
    post.pickup_code   = _gen_code()
    post.delivery_code = _gen_code()
    offer.status       = "accepted"

    others = await db.execute(
        select(FreightOffer).where(
            FreightOffer.post_id == post.id,
            FreightOffer.id != offer.id,
            FreightOffer.status == "pending",
        )
    )
    for o in others.scalars().all():
        o.status = "rejected"

    _track(db, post, me.id, "accepted", note="پیشنهادِ راننده پذیرفته شد")
    await db.commit()
    await db.refresh(post)
    return CargoPostOut.from_orm(post, me.id)


@router.post("/offers/{offer_id}/withdraw", status_code=status.HTTP_204_NO_CONTENT)
async def withdraw_offer(
    offer_id: str,
    db:  AsyncSession = Depends(get_db),
    me:  User         = Depends(get_current_user),
):
    """راننده پیشنهادِ در انتظارِ خودش را پس می‌گیرد."""
    offer = await db.get(FreightOffer, _uuid.UUID(offer_id))
    if not offer:
        raise HTTPException(status_code=404, detail="پیشنهاد پیدا نشد")
    if offer.driver_id != me.id:
        raise HTTPException(status_code=403, detail="فقط خودِ راننده می‌تواند پس بگیرد")
    if offer.status != "pending":
        raise HTTPException(status_code=400, detail="این پیشنهاد قابل‌لغو نیست")
    offer.status = "withdrawn"
    await db.commit()


# ── امتیازدهیِ متقابل (پس از تحویلِ نهایی) ──────────────────────
class RatingCreate(BaseModel):
    score:   int           = Field(..., ge=1, le=5)   # ۱ تا ۵ ستاره
    comment: Optional[str] = Field(None, max_length=500)


class RatingOut(BaseModel):
    id:         str
    post_id:    str
    rater_id:   str
    ratee_id:   str
    role:       str
    score:      int
    comment:    Optional[str] = None
    created_at: datetime


@router.post("/posts/{post_id}/rate", response_model=RatingOut, status_code=status.HTTP_201_CREATED)
async def rate_counterparty(
    post_id: str,
    body: RatingCreate,
    db:  AsyncSession = Depends(get_db),
    me:  User         = Depends(get_current_user),
):
    """پس از تحویلِ نهایی (`received`)، هر طرف یک‌بار به طرفِ دیگر امتیاز (۱–۵) می‌دهد.

    صاحبِ بار → راننده و راننده → صاحبِ بار. امتیاز میانگینِ کاربرِ مقابل را به‌روز می‌کند.
    """
    post = await db.get(CargoPost, _uuid.UUID(post_id))
    if not post:
        raise HTTPException(status_code=404, detail="بار پیدا نشد")
    if post.status != "received":
        raise HTTPException(status_code=400, detail="امتیازدهی فقط پس از تحویلِ نهایی ممکن است")

    if me.id == post.owner_id:
        if not post.driver_id:
            raise HTTPException(status_code=400, detail="راننده‌ای برای امتیازدهی وجود ندارد")
        ratee_id = post.driver_id
        role = "owner_rates_driver"
    elif me.id == post.driver_id:
        ratee_id = post.owner_id
        role = "driver_rates_owner"
    else:
        raise HTTPException(status_code=403, detail="فقط طرفینِ این حمل می‌توانند امتیاز دهند")

    # جلوگیری از امتیازِ تکراری (UNIQUE post_id+rater_id)
    dup = await db.execute(
        select(FreightRating).where(
            FreightRating.post_id == post.id,
            FreightRating.rater_id == me.id,
        ).limit(1)
    )
    if dup.scalars().first():
        raise HTTPException(status_code=400, detail="قبلاً برای این حمل امتیاز ثبت کرده‌اید")

    rating = FreightRating(
        post_id=post.id, rater_id=me.id, ratee_id=ratee_id,
        role=role, score=body.score, comment=body.comment,
    )
    db.add(rating)

    # به‌روزرسانیِ میانگینِ امتیازِ کاربرِ مقابل (avg_rating ×۱۰۰ برای دقت)
    ratee = await db.get(User, ratee_id)
    if ratee is not None:
        old_count = int(ratee.total_ratings or 0)
        old_avg   = int(ratee.avg_rating or 0)   # 0..500
        new_avg   = round((old_avg * old_count + body.score * 100) / (old_count + 1))
        ratee.total_ratings = old_count + 1
        ratee.avg_rating    = new_avg

    await db.commit()
    await db.refresh(rating)
    return RatingOut(
        id=str(rating.id), post_id=str(rating.post_id),
        rater_id=str(rating.rater_id), ratee_id=str(rating.ratee_id),
        role=rating.role, score=rating.score, comment=rating.comment,
        created_at=rating.created_at,
    )
