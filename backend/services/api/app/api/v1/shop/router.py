"""
Dilix — فروشگاه و پرداختِ امانی (Checkout) درون‌چت — فاز ۴

    GET    /api/v1/shop/products              کاتالوگِ عمومی (جستجو/فیلترِ فروشنده)
    GET    /api/v1/shop/products/mine         کالاهای من (شاملِ غیرفعال‌ها)
    POST   /api/v1/shop/products              افزودنِ کالا
    PATCH  /api/v1/shop/products/{id}         ویرایش
    DELETE /api/v1/shop/products/{id}         غیرفعال‌سازی
    GET    /api/v1/shop/products/{id}         جزئیاتِ یک کالا
    POST   /api/v1/shop/products/{id}/share   فرستادنِ کارتِ کالا داخلِ گفتگو

    POST   /api/v1/shop/orders                سفارش + بلوکِ وجه (+ کارتِ درون‌چت)
    GET    /api/v1/shop/orders/mine           خریدهای من
    GET    /api/v1/shop/orders/sales          فروش‌های من
    GET    /api/v1/shop/orders/{ref}          یک سفارش
    POST   /api/v1/shop/orders/{id}/accept    پذیرشِ فروشنده
    POST   /api/v1/shop/orders/{id}/ship      ارسالِ فروشنده
    POST   /api/v1/shop/orders/{id}/complete  تأییدِ خریدار → آزادسازیِ وجه
    POST   /api/v1/shop/orders/{id}/cancel    لغو → بازگشتِ وجه

چرا escrow و نه انتقالِ ساده؟
    اگر پول همان لحظه به فروشنده می‌رفت، خریدار هیچ اهرمی برای دریافتِ کالا
    نداشت؛ و اگر پول اصلاً بلوکه نمی‌شد، خریدار می‌توانست پس از ثبتِ سفارش
    همان پول را جای دیگری خرج کند و فروشنده کالای فروخته‌شده را بی‌پول
    تحویل دهد. پس وجه در همان کیفِ خریدار **بلوکه** می‌شود: نه در دسترسِ او،
    نه هنوز مالِ فروشنده.

چرا آزادسازیِ خودکار؟
    اگر تنها راهِ آزادسازی، تأییدِ خریدار بود، خریدارِ بی‌تفاوت (یا بدنیت)
    می‌توانست پولِ فروشنده را تا ابد گروگان بگیرد. پس پس از
    `AUTO_RELEASE_DAYS` روز از «ارسال»، وجه خودکار آزاد می‌شود.
"""
import uuid as _uuid
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import (
    BigInteger, Boolean, Column, DateTime, ForeignKey, Index, Integer,
    String, Text, func, select, update,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import Base, get_db
from app.models.messages import Message, RoomMember
from app.models.user import User
from app.services.mlm import SHOP_LEVEL_RATES_BPS, distribute_commission
from app.services.wallet_ops import lock_escrow, refund_escrow, release_escrow

router = APIRouter(prefix="/shop", tags=["Shop"])

# کارمزدِ پلتفرم روی هر معاملهٔ موفق (درصد). فقط هنگامِ آزادسازی گرفته می‌شود؛
# سفارشِ لغوشده کارمزد ندارد.
COMMISSION_PCT = 2
AUTO_RELEASE_DAYS = 7

PRICE_MIN = 1_000                # ۱۰۰ تومان
PRICE_MAX = 5_000_000_000        # ۵۰۰٬۰۰۰٬۰۰۰ تومان
QTY_MAX = 100

# چرخهٔ وضعیت. هر گذار فقط از وضعیتِ مجاز ممکن است؛ جدول تنها مرجعِ آن است تا
# منطقِ گذار در چند نقطه پراکنده نشود.
ALLOWED: dict[str, set[str]] = {
    "pending": {"accepted", "cancelled"},
    "accepted": {"shipped", "cancelled"},
    "shipped": {"completed"},
    "completed": set(),
    "cancelled": set(),
}

STATUS_LABEL = {
    "pending": "در انتظارِ پذیرش",
    "accepted": "پذیرفته‌شده",
    "shipped": "ارسال‌شده",
    "completed": "تکمیل‌شده",
    "cancelled": "لغوشده",
}


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── مدل‌ها ────────────────────────────────────────────────────────────────────
class ShopProduct(Base):
    """کالا/خدمتِ یک فروشنده.

    `stock = -1` یعنی موجودیِ نامحدود (خدمتِ دیجیتال). عددِ صفر یعنی تمام‌شده.
    """
    __tablename__ = "shop_products"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    owner_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    title = Column(String(160), nullable=False)
    description = Column(Text, nullable=True)
    price = Column(BigInteger, nullable=False)         # ریال
    currency = Column(String(3), nullable=False, default="IRR")
    stock = Column(Integer, nullable=False, default=-1)
    image_url = Column(String(500), nullable=True)
    is_active = Column(Boolean, nullable=False, default=True)
    sold_count = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("ix_shop_product_owner", "owner_id", "is_active"),
    )


class ShopOrder(Base):
    """یک سفارش. `ref` شناسهٔ کوتاهِ خواندنی برای کاربر و رسیدهاست.

    `escrow_status` جدا از `status` نگه داشته می‌شود چون پرسشِ «آیا پول هنوز
    بلوکه است؟» با پرسشِ «سفارش کجای چرخه است؟» یکی نیست؛ یکی‌کردنشان
    آزادسازی را غیرِ idempotent می‌کرد.
    """
    __tablename__ = "shop_orders"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    ref = Column(String(24), nullable=False, unique=True)
    product_id = Column(UUID(as_uuid=True), ForeignKey("shop_products.id"), nullable=False)
    seller_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    buyer_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    room_id = Column(UUID(as_uuid=True), nullable=True)
    message_id = Column(UUID(as_uuid=True), nullable=True)

    title = Column(String(160), nullable=False)        # snapshot: عنوان ممکن است بعداً عوض شود
    unit_price = Column(BigInteger, nullable=False)    # snapshot: قیمت ممکن است بعداً عوض شود
    qty = Column(Integer, nullable=False, default=1)
    total = Column(BigInteger, nullable=False)
    commission = Column(BigInteger, nullable=False, default=0)

    status = Column(String(16), nullable=False, default="pending")
    escrow_status = Column(String(16), nullable=False, default="locked")
    note = Column(Text, nullable=True)
    address = Column(String(300), nullable=True)

    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    accepted_at = Column(DateTime(timezone=True), nullable=True)
    shipped_at = Column(DateTime(timezone=True), nullable=True)
    closed_at = Column(DateTime(timezone=True), nullable=True)

    __table_args__ = (
        Index("ix_shop_order_buyer", "buyer_id", "created_at"),
        Index("ix_shop_order_seller", "seller_id", "created_at"),
        Index("ix_shop_order_autorelease", "status", "shipped_at"),
    )


# ── طرح‌ها ────────────────────────────────────────────────────────────────────
class ProductIn(BaseModel):
    title: str = Field(..., min_length=2, max_length=160)
    price: int = Field(..., ge=PRICE_MIN, le=PRICE_MAX)
    description: Optional[str] = Field(None, max_length=4000)
    image_url: Optional[str] = Field(None, max_length=500)
    stock: int = Field(-1, ge=-1, le=1_000_000)


class ProductPatch(BaseModel):
    title: Optional[str] = Field(None, min_length=2, max_length=160)
    price: Optional[int] = Field(None, ge=PRICE_MIN, le=PRICE_MAX)
    description: Optional[str] = Field(None, max_length=4000)
    image_url: Optional[str] = Field(None, max_length=500)
    stock: Optional[int] = Field(None, ge=-1, le=1_000_000)
    is_active: Optional[bool] = None


class ProductOut(BaseModel):
    id: str
    seller_earth_id: str
    seller_name: Optional[str] = None
    title: str
    description: Optional[str] = None
    price: int
    currency: str
    stock: int
    image_url: Optional[str] = None
    is_active: bool
    sold_count: int
    created_at: datetime


class ShareIn(BaseModel):
    room_id: str


class OrderIn(BaseModel):
    product_id: str
    qty: int = Field(1, ge=1, le=QTY_MAX)
    room_id: Optional[str] = None
    note: Optional[str] = Field(None, max_length=500)
    address: Optional[str] = Field(None, max_length=300)


class OrderOut(BaseModel):
    id: str
    ref: str
    product_id: str
    seller_earth_id: str
    seller_name: Optional[str] = None
    buyer_earth_id: str
    buyer_name: Optional[str] = None
    title: str
    unit_price: int
    qty: int
    total: int
    commission: int
    status: str
    status_label: str
    escrow_status: str
    note: Optional[str] = None
    address: Optional[str] = None
    room_id: Optional[str] = None
    created_at: datetime
    shipped_at: Optional[datetime] = None
    closed_at: Optional[datetime] = None
    # سرور می‌گوید *این کاربر* اکنون چه می‌تواند بکند تا کلاینت قواعدِ گذار را
    # دوباره پیاده نکند و با سرور اختلاف پیدا نکند.
    can_accept: bool = False
    can_ship: bool = False
    can_complete: bool = False
    can_cancel: bool = False


# ── کمکی‌ها ──────────────────────────────────────────────────────────────────
def _new_ref() -> str:
    return "ORD-" + _uuid.uuid4().hex[:10].upper()


def _product_out(p: ShopProduct, u: Optional[User]) -> ProductOut:
    return ProductOut(
        id=str(p.id),
        seller_earth_id=(u.earth_id if u else ""),
        seller_name=((u.full_name or u.username or u.earth_id) if u else None),
        title=p.title, description=p.description, price=int(p.price),
        currency=p.currency, stock=int(p.stock), image_url=p.image_url,
        is_active=bool(p.is_active), sold_count=int(p.sold_count),
        created_at=p.created_at,
    )


def _order_out(o: ShopOrder, seller: Optional[User], buyer: Optional[User],
               me_id) -> OrderOut:
    is_seller = o.seller_id == me_id
    is_buyer = o.buyer_id == me_id
    return OrderOut(
        id=str(o.id), ref=o.ref, product_id=str(o.product_id),
        seller_earth_id=(seller.earth_id if seller else ""),
        seller_name=((seller.full_name or seller.username or seller.earth_id)
                     if seller else None),
        buyer_earth_id=(buyer.earth_id if buyer else ""),
        buyer_name=((buyer.full_name or buyer.username or buyer.earth_id)
                    if buyer else None),
        title=o.title, unit_price=int(o.unit_price), qty=int(o.qty),
        total=int(o.total), commission=int(o.commission),
        status=o.status, status_label=STATUS_LABEL.get(o.status, o.status),
        escrow_status=o.escrow_status, note=o.note, address=o.address,
        room_id=(str(o.room_id) if o.room_id else None),
        created_at=o.created_at, shipped_at=o.shipped_at, closed_at=o.closed_at,
        can_accept=is_seller and o.status == "pending",
        can_ship=is_seller and o.status == "accepted",
        can_complete=is_buyer and o.status == "shipped",
        # خریدار فقط تا پیش از پذیرش، فروشنده تا پیش از ارسال.
        can_cancel=(
            (is_buyer and o.status == "pending")
            or (is_seller and o.status in ("pending", "accepted"))
        ),
    )


async def _users(db: AsyncSession, ids) -> dict:
    ids = [i for i in set(ids) if i]
    if not ids:
        return {}
    rows = (await db.execute(select(User).where(User.id.in_(ids)))).scalars().all()
    return {u.id: u for u in rows}


async def _load_order(db: AsyncSession, order_id: str, me_id) -> ShopOrder:
    try:
        oid = _uuid.UUID(order_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="سفارش پیدا نشد")
    o = (await db.execute(
        select(ShopOrder).where(ShopOrder.id == oid).with_for_update()
    )).scalar_one_or_none()
    if o is None:
        raise HTTPException(status_code=404, detail="سفارش پیدا نشد")
    if me_id not in (o.buyer_id, o.seller_id):
        raise HTTPException(status_code=404, detail="سفارش پیدا نشد")
    return o


def _guard(o: ShopOrder, target: str) -> None:
    if target not in ALLOWED.get(o.status, set()):
        raise HTTPException(
            status_code=400,
            detail=f"از وضعیتِ «{STATUS_LABEL.get(o.status, o.status)}» این تغییر ممکن نیست",
        )


# ── کالاها ───────────────────────────────────────────────────────────────────
@router.get("/products", response_model=List[ProductOut])
async def list_products(
    q: Optional[str] = Query(None, max_length=100),
    seller: Optional[str] = Query(None, description="Earth ID فروشنده"),
    limit: int = Query(30, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """کاتالوگِ عمومی. فقط کالای فعال و فقط با موجودی (یا نامحدود)."""
    stmt = select(ShopProduct).where(
        ShopProduct.is_active.is_(True),
        (ShopProduct.stock != 0),
    )
    if seller:
        u = (await db.execute(
            select(User).where(User.earth_id == seller)
        )).scalar_one_or_none()
        if u is None:
            return []
        stmt = stmt.where(ShopProduct.owner_id == u.id)
    if q:
        like = f"%{q.strip()}%"
        stmt = stmt.where(ShopProduct.title.ilike(like))
    rows = (await db.execute(
        stmt.order_by(ShopProduct.created_at.desc()).limit(limit).offset(offset)
    )).scalars().all()
    umap = await _users(db, [p.owner_id for p in rows])
    return [_product_out(p, umap.get(p.owner_id)) for p in rows]


@router.get("/products/mine", response_model=List[ProductOut])
async def my_products(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    rows = (await db.execute(
        select(ShopProduct)
        .where(ShopProduct.owner_id == me.id)
        .order_by(ShopProduct.created_at.desc())
    )).scalars().all()
    return [_product_out(p, me) for p in rows]


@router.post("/products", response_model=ProductOut, status_code=201)
async def create_product(
    body: ProductIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    p = ShopProduct(
        owner_id=me.id, title=body.title.strip(), price=body.price,
        description=(body.description or "").strip() or None,
        image_url=(body.image_url or "").strip() or None,
        stock=body.stock,
    )
    db.add(p)
    await db.commit()
    await db.refresh(p)
    return _product_out(p, me)


@router.patch("/products/{product_id}", response_model=ProductOut)
async def update_product(
    product_id: str,
    body: ProductPatch,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    try:
        pid = _uuid.UUID(product_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="کالا پیدا نشد")
    p = (await db.execute(
        select(ShopProduct).where(
            ShopProduct.id == pid, ShopProduct.owner_id == me.id
        )
    )).scalar_one_or_none()
    if p is None:
        raise HTTPException(status_code=404, detail="کالا پیدا نشد")

    data = body.model_dump(exclude_unset=True)
    for k in ("title", "description", "image_url"):
        if k in data and data[k] is not None:
            data[k] = str(data[k]).strip() or None
    for k, v in data.items():
        setattr(p, k, v)
    await db.commit()
    await db.refresh(p)
    return _product_out(p, me)


@router.delete("/products/{product_id}", status_code=204)
async def deactivate_product(
    product_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """غیرفعال‌سازی، نه حذف — سفارش‌های قبلی به این ردیف اشاره دارند."""
    try:
        pid = _uuid.UUID(product_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="کالا پیدا نشد")
    p = (await db.execute(
        select(ShopProduct).where(
            ShopProduct.id == pid, ShopProduct.owner_id == me.id
        )
    )).scalar_one_or_none()
    if p is None:
        raise HTTPException(status_code=404, detail="کالا پیدا نشد")
    p.is_active = False
    await db.commit()


@router.post("/products/{product_id}/share", status_code=201)
async def share_product(
    product_id: str,
    body: ShareIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """فرستادنِ کارتِ کالا داخلِ گفتگو.

    تا امروز مسیرِ فروش یک‌طرفه بود: خریدار باید خودش کالا را در فروشگاه پیدا
    می‌کرد و سفارش می‌داد. فروشنده هیچ راهی نداشت کالا را در همان گفتگویی که
    دارد چانه می‌زند نشان بدهد جز چسباندنِ لینک — و لینک از اپ بیرون می‌بَرد.
    این مسیر همان کارتِ زندهٔ کالا را داخلِ چت می‌گذارد.

    برخلافِ کارتِ **سفارش** (که فقط در اتاقِ خریدار-فروشنده ساخته می‌شود)، اینجا
    فقط عضویتِ **فرستنده** لازم است: اشتراکِ کالا مثلِ فرستادنِ یک لینک است و
    کالای فعال عمومی است. تنها چیزی که حتماً باید بسته بماند تزریقِ پیام به
    اتاقی است که فرستنده عضوش نیست.

    پیام فقط `id`ِ کالا را حمل می‌کند، نه قیمت را؛ قیمت و موجودی بعداً عوض
    می‌شوند و کارت باید همان چیزی را نشان دهد که در لحظهٔ خرید واقعی است.
    """
    try:
        pid = _uuid.UUID(product_id)
        rid = _uuid.UUID(body.room_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="کالا پیدا نشد")

    p = (await db.execute(
        select(ShopProduct).where(ShopProduct.id == pid, ShopProduct.is_active.is_(True))
    )).scalar_one_or_none()
    if p is None:
        raise HTTPException(status_code=404, detail="کالا پیدا نشد")

    mine = (await db.execute(
        select(func.count()).select_from(RoomMember).where(
            RoomMember.room_id == rid, RoomMember.user_id == me.id
        )
    )).scalar_one()
    if not int(mine or 0):
        raise HTTPException(status_code=403, detail="عضوِ این گفتگو نیستید")

    msg = Message(
        room_id=rid, sender_id=me.id,
        content=f"🏷️ {p.title}",
        media_type="product", media_name=str(p.id),
    )
    db.add(msg)
    await db.commit()
    await db.refresh(msg)
    return {"message_id": str(msg.id), "product_id": str(p.id)}


@router.get("/products/{product_id}", response_model=ProductOut)
async def get_product(
    product_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    try:
        pid = _uuid.UUID(product_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="کالا پیدا نشد")
    p = (await db.execute(
        select(ShopProduct).where(ShopProduct.id == pid)
    )).scalar_one_or_none()
    if p is None:
        raise HTTPException(status_code=404, detail="کالا پیدا نشد")
    umap = await _users(db, [p.owner_id])
    return _product_out(p, umap.get(p.owner_id))


# ── سفارش‌ها ─────────────────────────────────────────────────────────────────
@router.post("/orders", response_model=OrderOut, status_code=201)
async def create_order(
    body: OrderIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ثبتِ سفارش: کاهشِ اتمیکِ موجودی + بلوکِ وجه + کارتِ درون‌چت."""
    try:
        pid = _uuid.UUID(body.product_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="کالا پیدا نشد")

    p = (await db.execute(
        select(ShopProduct).where(ShopProduct.id == pid)
    )).scalar_one_or_none()
    if p is None or not p.is_active:
        raise HTTPException(status_code=404, detail="کالا پیدا نشد")
    if p.owner_id == me.id:
        raise HTTPException(status_code=400, detail="خریدِ کالای خودتان ممکن نیست")

    total = int(p.price) * body.qty

    # کاهشِ موجودی با شرطِ درون همان UPDATE. خواندن و سپس نوشتن، بینِ دو
    # درخواستِ هم‌زمان مسابقه می‌سازد و کالای تمام‌شده را دوباره می‌فروشد.
    if p.stock != -1:
        res = await db.execute(
            update(ShopProduct)
            .where(ShopProduct.id == pid, ShopProduct.stock >= body.qty)
            .values(stock=ShopProduct.stock - body.qty)
        )
        if res.rowcount == 0:
            raise HTTPException(status_code=409, detail="موجودیِ کالا کافی نیست")

    # بلوکِ وجه پس از رزروِ موجودی: اگر پول کم باشد، استثنا کلِ تراکنش را —
    # از جمله کاهشِ موجودی — برمی‌گرداند.
    ref = _new_ref()
    await lock_escrow(
        db, me.id, total,
        description=f"بلوکِ وجه برای سفارشِ {ref} ({p.title})",
        reference_id=ref,
    )

    room_uuid = None
    if body.room_id:
        try:
            rid = _uuid.UUID(body.room_id)
        except ValueError:
            raise HTTPException(status_code=404, detail="گفتگو پیدا نشد")
        # کارتِ سفارش فقط در اتاقی ساخته می‌شود که **هر دو طرف** عضوش باشند،
        # وگرنه رسیدِ خرید به گفتگوی بی‌ربط تزریق می‌شد.
        cnt = (await db.execute(
            select(func.count()).select_from(RoomMember).where(
                RoomMember.room_id == rid,
                RoomMember.user_id.in_([me.id, p.owner_id]),
            )
        )).scalar_one()
        if int(cnt or 0) < 2:
            raise HTTPException(status_code=403, detail="این گفتگو بینِ خریدار و فروشنده نیست")
        room_uuid = rid

    o = ShopOrder(
        ref=ref, product_id=p.id, seller_id=p.owner_id, buyer_id=me.id,
        room_id=room_uuid, title=p.title, unit_price=int(p.price),
        qty=body.qty, total=total, status="pending", escrow_status="locked",
        note=(body.note or "").strip() or None,
        address=(body.address or "").strip() or None,
    )
    db.add(o)
    await db.flush()

    if room_uuid is not None:
        msg = Message(
            room_id=room_uuid, sender_id=me.id,
            content=f"🛒 سفارشِ «{p.title}» ثبت شد",
            media_type="order", media_name=ref,
        )
        db.add(msg)
        await db.flush()
        o.message_id = msg.id

    await db.commit()
    await db.refresh(o)
    umap = await _users(db, [o.seller_id, o.buyer_id])
    return _order_out(o, umap.get(o.seller_id), umap.get(o.buyer_id), me.id)


@router.get("/orders/mine", response_model=List[OrderOut])
async def my_orders(
    limit: int = Query(30, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    rows = (await db.execute(
        select(ShopOrder).where(ShopOrder.buyer_id == me.id)
        .order_by(ShopOrder.created_at.desc()).limit(limit).offset(offset)
    )).scalars().all()
    umap = await _users(db, [o.seller_id for o in rows] + [me.id])
    return [_order_out(o, umap.get(o.seller_id), umap.get(me.id), me.id) for o in rows]


@router.get("/orders/sales", response_model=List[OrderOut])
async def my_sales(
    limit: int = Query(30, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    rows = (await db.execute(
        select(ShopOrder).where(ShopOrder.seller_id == me.id)
        .order_by(ShopOrder.created_at.desc()).limit(limit).offset(offset)
    )).scalars().all()
    umap = await _users(db, [o.buyer_id for o in rows] + [me.id])
    return [_order_out(o, umap.get(me.id), umap.get(o.buyer_id), me.id) for o in rows]


@router.get("/orders/{ref}", response_model=OrderOut)
async def get_order(
    ref: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """با `ref` یا `id`. ترتیبِ این روت پس از `/orders/mine` و `/orders/sales`
    عمدی است؛ وگرنه `mine` به‌عنوانِ `ref` تفسیر می‌شد."""
    stmt = select(ShopOrder).where(ShopOrder.ref == ref)
    o = (await db.execute(stmt)).scalar_one_or_none()
    if o is None:
        try:
            oid = _uuid.UUID(ref)
        except ValueError:
            raise HTTPException(status_code=404, detail="سفارش پیدا نشد")
        o = (await db.execute(
            select(ShopOrder).where(ShopOrder.id == oid)
        )).scalar_one_or_none()
    if o is None or me.id not in (o.buyer_id, o.seller_id):
        raise HTTPException(status_code=404, detail="سفارش پیدا نشد")
    umap = await _users(db, [o.seller_id, o.buyer_id])
    return _order_out(o, umap.get(o.seller_id), umap.get(o.buyer_id), me.id)


@router.post("/orders/{order_id}/accept", response_model=OrderOut)
async def accept_order(
    order_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    o = await _load_order(db, order_id, me.id)
    if o.seller_id != me.id:
        raise HTTPException(status_code=403, detail="فقط فروشنده می‌تواند سفارش را بپذیرد")
    _guard(o, "accepted")
    o.status = "accepted"
    o.accepted_at = _now()
    await db.commit()
    await db.refresh(o)
    umap = await _users(db, [o.seller_id, o.buyer_id])
    return _order_out(o, umap.get(o.seller_id), umap.get(o.buyer_id), me.id)


@router.post("/orders/{order_id}/ship", response_model=OrderOut)
async def ship_order(
    order_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    o = await _load_order(db, order_id, me.id)
    if o.seller_id != me.id:
        raise HTTPException(status_code=403, detail="فقط فروشنده می‌تواند ارسال را ثبت کند")
    _guard(o, "shipped")
    o.status = "shipped"
    o.shipped_at = _now()
    await db.commit()
    await db.refresh(o)
    umap = await _users(db, [o.seller_id, o.buyer_id])
    return _order_out(o, umap.get(o.seller_id), umap.get(o.buyer_id), me.id)


@router.post("/orders/{order_id}/complete", response_model=OrderOut)
async def complete_order(
    order_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """تأییدِ دریافت → آزادسازیِ وجه به فروشنده منهای کارمزد."""
    o = await _load_order(db, order_id, me.id)
    if o.buyer_id != me.id:
        raise HTTPException(status_code=403, detail="فقط خریدار می‌تواند دریافت را تأیید کند")
    _guard(o, "completed")
    await _settle(db, o)
    await db.commit()
    await db.refresh(o)
    umap = await _users(db, [o.seller_id, o.buyer_id])
    return _order_out(o, umap.get(o.seller_id), umap.get(o.buyer_id), me.id)


@router.post("/orders/{order_id}/cancel", response_model=OrderOut)
async def cancel_order(
    order_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """لغو + بازگشتِ کاملِ وجه و برگرداندنِ موجودیِ کالا."""
    o = await _load_order(db, order_id, me.id)
    _guard(o, "cancelled")
    # خریدار فقط تا پیش از پذیرش؛ پس از آن فروشنده تصمیم می‌گیرد.
    if o.buyer_id == me.id and o.status != "pending":
        raise HTTPException(status_code=403, detail="پس از پذیرشِ فروشنده، لغو با اوست")

    if o.escrow_status == "locked":
        await refund_escrow(
            db, o.buyer_id, int(o.total),
            description=f"بازگشتِ وجهِ سفارشِ لغوشدهٔ {o.ref}",
            reference_id=o.ref,
        )
        o.escrow_status = "refunded"

    p = (await db.execute(
        select(ShopProduct).where(ShopProduct.id == o.product_id).with_for_update()
    )).scalar_one_or_none()
    if p is not None and p.stock != -1:
        p.stock = int(p.stock) + int(o.qty)

    o.status = "cancelled"
    o.closed_at = _now()
    await db.commit()
    await db.refresh(o)
    umap = await _users(db, [o.seller_id, o.buyer_id])
    return _order_out(o, umap.get(o.seller_id), umap.get(o.buyer_id), me.id)


async def _settle(db: AsyncSession, o: ShopOrder) -> None:
    """تسویهٔ نهایی. **فقط** وقتی وجه هنوز بلوکه است اجرا می‌شود؛ این شرط تنها
    چیزی است که آزادسازیِ دوباره (و ساختنِ پول از هیچ) را ناممکن می‌کند."""
    if o.escrow_status != "locked":
        return
    total = int(o.total)
    commission = total * COMMISSION_PCT // 100
    await release_escrow(
        db, o.buyer_id, o.seller_id, total,
        out_desc=f"تسویهٔ سفارشِ {o.ref} ({o.title})",
        in_desc=f"دریافتِ وجهِ سفارشِ {o.ref} ({o.title})",
        fee=commission,
        fee_desc=f"کارمزدِ دیلیکس ({COMMISSION_PCT}٪) — سفارشِ {o.ref}",
        reference_id=o.ref,
    )
    o.commission = commission
    o.escrow_status = "released"
    o.status = "completed"
    o.closed_at = _now()

    # پاداشِ رفرال روی **فروش**، نه فقط شارژِ کیف. تا پیش از این تنها
    # `paygate/verify` کمیسیون توزیع می‌کرد، یعنی معرف از خریدِ زیرمجموعه‌اش
    # هیچ درآمدی نداشت و کلِ زنجیرهٔ ارزشِ تجاری از سیستمِ بازاریابی جدا بود.
    # نرخِ فروش عمداً از دلِ همین کارمزدِ ۲٪ برداشته می‌شود (نگاه کن به
    # `SHOP_LEVEL_RATES_BPS`)، پس هر سفارشِ معرف‌دار همچنان برای پلتفرم
    # سودده می‌مانَد. اینجا امن است چون گاردِ `escrow_status != "locked"`
    # بالای همین تابع تضمین می‌کند تسویه فقط یک‌بار اجرا شود.
    await distribute_commission(
        db, o.buyer_id, total, "IRR",
        source_type="shop", reference_id=o.ref,
        rates=SHOP_LEVEL_RATES_BPS,
    )

    p = (await db.execute(
        select(ShopProduct).where(ShopProduct.id == o.product_id).with_for_update()
    )).scalar_one_or_none()
    if p is not None:
        p.sold_count = int(p.sold_count or 0) + int(o.qty)


async def auto_release_due(db: AsyncSession) -> int:
    """آزادسازیِ خودکارِ سفارش‌هایی که خریدار تأییدشان را فراموش کرده.

    بدونِ این، پولِ فروشنده تا ابد گروگانِ بی‌تفاوتیِ خریدار می‌ماند.
    """
    deadline = _now() - timedelta(days=AUTO_RELEASE_DAYS)
    rows = (await db.execute(
        select(ShopOrder).where(
            ShopOrder.status == "shipped",
            ShopOrder.escrow_status == "locked",
            ShopOrder.shipped_at.is_not(None),
            ShopOrder.shipped_at <= deadline,
        ).limit(200)
    )).scalars().all()
    done = 0
    for o in rows:
        try:
            await _settle(db, o)
            await db.commit()
            done += 1
        except Exception:
            await db.rollback()
    return done
