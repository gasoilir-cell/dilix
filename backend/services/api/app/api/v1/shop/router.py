"""
Dilix — فروشگاه و پرداختِ امانی (Checkout) درون‌چت — فاز ۴

    GET    /api/v1/shop/products              کاتالوگِ عمومی (جستجو/فیلترِ فروشنده)
    GET    /api/v1/shop/products/mine         کالاهای من (شاملِ غیرفعال‌ها)
    POST   /api/v1/shop/products              افزودنِ کالا
    PATCH  /api/v1/shop/products/{id}         ویرایش
    DELETE /api/v1/shop/products/{id}         غیرفعال‌سازی
    GET    /api/v1/shop/products/{id}         جزئیاتِ یک کالا
    POST   /api/v1/shop/products/{id}/share   فرستادنِ کارتِ کالا داخلِ گفتگو
    GET    /api/v1/shop/products/{id}/reviews نظراتِ خریدارانِ واقعی
    POST   /api/v1/shop/products/{id}/variants افزودنِ گونه (رنگ/سایز و…)
    GET    /api/v1/shop/products/{id}/variants فهرستِ گونه‌ها
    PATCH  /api/v1/shop/products/{id}/variants/{vid}  ویرایشِ گونه
    DELETE /api/v1/shop/products/{id}/variants/{vid}  غیرفعال‌سازیِ گونه

    POST   /api/v1/shop/orders                سفارش + بلوکِ وجه (+ کارتِ درون‌چت)
    POST   /api/v1/shop/cart/checkout         سبدِ چندفروشنده → N سفارشِ امانی در یک تراکنش
    GET    /api/v1/shop/orders/mine           خریدهای من
    GET    /api/v1/shop/orders/sales          فروش‌های من
    GET    /api/v1/shop/orders/{ref}          یک سفارش
    POST   /api/v1/shop/orders/{id}/accept    پذیرشِ فروشنده
    POST   /api/v1/shop/orders/{id}/ship      ارسالِ فروشنده
    POST   /api/v1/shop/orders/{id}/complete  تأییدِ خریدار → آزادسازیِ وجه
    POST   /api/v1/shop/orders/{id}/cancel    لغو → بازگشتِ وجه
    POST   /api/v1/shop/orders/{id}/review    ثبتِ نظر (فقط پس از تکمیل)

    POST   /api/v1/shop/coupons               ساختِ کدِ تخفیف (فروشنده)
    GET    /api/v1/shop/coupons/mine          کدهای من
    PATCH  /api/v1/shop/coupons/{id}          ویرایش
    DELETE /api/v1/shop/coupons/{id}          غیرفعال‌سازی

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

چرا سبدِ چندفروشنده یک جدولِ ردیف‌ (`ShopOrderItem`) جدا می‌خواهد؟
    هر `ShopOrder` قبلاً دقیقاً یک کالا را می‌شناخت. اگر سبد چند کالای یک
    فروشنده را در یک سفارش می‌ریخت ولی جایی برای نگه‌داشتنِ تک‌تکِ آن‌ها
    نبود، بازگشتِ موجودی هنگامِ لغو و ثبتِ نظر برای کالای مشخص ناممکن
    می‌شد. ستون‌های تکی روی خودِ سفارش (`product_id`/`title`/`unit_price`)
    برای سازگاری با دادهٔ قدیمی و نمایشِ خلاصه می‌مانند؛ منبعِ حقیقتِ
    ردیف‌به‌ردیف همیشه `ShopOrderItem` است — حتی برای سفارش‌های تک‌کالاییِ
    مسیرِ قدیمی، که یک ردیف در آن هم درج می‌شود.
"""
import uuid as _uuid
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import (
    JSON, BigInteger, Boolean, Column, DateTime, ForeignKey, Index, Integer,
    String, Text, func, or_, select, update,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.exc import IntegrityError
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
    # تصاویرِ اضافه (گالری). `image_url` همچنان کاورِ اصلی و پیشِ‌فرض است تا
    # جاهایی که قبلاً فقط همین یک فیلد را می‌خواندند (کارتِ چت، مثلاً) نشکنند.
    images = Column(JSON, nullable=True)
    is_active = Column(Boolean, nullable=False, default=True)
    sold_count = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("ix_shop_product_owner", "owner_id", "is_active"),
    )


class ShopProductVariant(Base):
    """گونهٔ یک کالا (رنگ/سایز/…). موجودی و قیمت **مستقلِ** کالای مادر است.

    اگر کالایی گونهٔ فعال داشته باشد، خریدِ بدونِ انتخابِ گونه رد می‌شود —
    وگرنه معلوم نیست کدام موجودی کم شود. `price = NULL` یعنی همان قیمتِ
    کالای مادر را بگیر (اکثرِ گونه‌ها فقط رنگ‌اند، نه قیمتِ متفاوت).
    """
    __tablename__ = "shop_product_variants"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    product_id = Column(UUID(as_uuid=True), ForeignKey("shop_products.id"), nullable=False)
    name = Column(String(80), nullable=False)
    price = Column(BigInteger, nullable=True)
    stock = Column(Integer, nullable=False, default=0)
    image_url = Column(String(500), nullable=True)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("ix_shop_variant_product", "product_id", "is_active"),
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
    discount = Column(BigInteger, nullable=False, default=0)
    coupon_code = Column(String(24), nullable=True)

    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    accepted_at = Column(DateTime(timezone=True), nullable=True)
    shipped_at = Column(DateTime(timezone=True), nullable=True)
    closed_at = Column(DateTime(timezone=True), nullable=True)

    __table_args__ = (
        Index("ix_shop_order_buyer", "buyer_id", "created_at"),
        Index("ix_shop_order_seller", "seller_id", "created_at"),
        Index("ix_shop_order_autorelease", "status", "shipped_at"),
    )


class ShopOrderItem(Base):
    """یک ردیفِ سفارش. **هر** سفارش — حتی تک‌کالاییِ مسیرِ قدیمی — دستِ‌کم یک
    ردیف اینجا دارد؛ ستون‌های خلاصه روی خودِ `ShopOrder` فقط برای نمایشِ سریع
    و سازگاریِ عقب‌رو نگه داشته شده‌اند."""
    __tablename__ = "shop_order_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    order_id = Column(UUID(as_uuid=True), ForeignKey("shop_orders.id"), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("shop_products.id"), nullable=False)
    variant_id = Column(UUID(as_uuid=True), ForeignKey("shop_product_variants.id"), nullable=True)
    title = Column(String(160), nullable=False)
    unit_price = Column(BigInteger, nullable=False)
    qty = Column(Integer, nullable=False)
    subtotal = Column(BigInteger, nullable=False)

    __table_args__ = (
        Index("ix_shop_item_order", "order_id"),
        Index("ix_shop_item_product", "product_id"),
    )


class ShopCoupon(Base):
    """کدِ تخفیفِ یک فروشنده. `product_id = NULL` یعنی روی کلِ کالاهای او.

    ضدِتکرارِ مصرف با `UPDATE ... WHERE used_count < max_uses` انجام می‌شود
    (نه خواندن-سپس-نوشتن)، وگرنه دو خریدِ هم‌زمان می‌توانستند هر دو از آخرین
    ظرفیتِ باقی‌مانده استفاده کنند.
    """
    __tablename__ = "shop_coupons"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    owner_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("shop_products.id"), nullable=True)
    code = Column(String(24), nullable=False, unique=True)
    discount_type = Column(String(10), nullable=False)   # percent | fixed
    discount_value = Column(BigInteger, nullable=False)
    max_uses = Column(Integer, nullable=True)
    used_count = Column(Integer, nullable=False, default=0)
    min_order_total = Column(BigInteger, nullable=False, default=0)
    expires_at = Column(DateTime(timezone=True), nullable=True)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("ix_shop_coupon_owner", "owner_id"),
    )


class ShopReview(Base):
    """نظرِ خریدار روی یک کالا — فقط پس از `completed` شدنِ همان سفارش.

    یکتاییِ `(order_id, product_id)` هم انبارِ‌نظرِ تکراری برای یک خرید را
    می‌بندد و هم اجازه می‌دهد در سفارشِ چندکالایی برای هر کالا جدا نظر داد.
    """
    __tablename__ = "shop_reviews"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    order_id = Column(UUID(as_uuid=True), ForeignKey("shop_orders.id"), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("shop_products.id"), nullable=False)
    reviewer_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    seller_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    rating = Column(Integer, nullable=False)
    comment = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("uq_shop_review_order_product", "order_id", "product_id", unique=True),
        Index("ix_shop_review_product", "product_id"),
    )


# ── طرح‌ها ────────────────────────────────────────────────────────────────────
MAX_IMAGES = 8


class ProductIn(BaseModel):
    title: str = Field(..., min_length=2, max_length=160)
    price: int = Field(..., ge=PRICE_MIN, le=PRICE_MAX)
    description: Optional[str] = Field(None, max_length=4000)
    image_url: Optional[str] = Field(None, max_length=500)
    images: Optional[List[str]] = Field(None, max_length=MAX_IMAGES)
    stock: int = Field(-1, ge=-1, le=1_000_000)


class ProductPatch(BaseModel):
    title: Optional[str] = Field(None, min_length=2, max_length=160)
    price: Optional[int] = Field(None, ge=PRICE_MIN, le=PRICE_MAX)
    description: Optional[str] = Field(None, max_length=4000)
    image_url: Optional[str] = Field(None, max_length=500)
    images: Optional[List[str]] = Field(None, max_length=MAX_IMAGES)
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
    images: List[str] = Field(default_factory=list)
    is_active: bool
    sold_count: int
    created_at: datetime
    rating_avg: Optional[float] = None
    rating_count: int = 0
    has_variants: bool = False


class ShareIn(BaseModel):
    room_id: str


class VariantIn(BaseModel):
    name: str = Field(..., min_length=1, max_length=80)
    price: Optional[int] = Field(None, ge=PRICE_MIN, le=PRICE_MAX)
    stock: int = Field(0, ge=-1, le=1_000_000)
    image_url: Optional[str] = Field(None, max_length=500)


class VariantPatch(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=80)
    price: Optional[int] = Field(None, ge=PRICE_MIN, le=PRICE_MAX)
    stock: Optional[int] = Field(None, ge=-1, le=1_000_000)
    image_url: Optional[str] = Field(None, max_length=500)
    is_active: Optional[bool] = None


class VariantOut(BaseModel):
    id: str
    product_id: str
    name: str
    price: Optional[int] = None
    stock: int
    image_url: Optional[str] = None
    is_active: bool


class OrderIn(BaseModel):
    product_id: str
    variant_id: Optional[str] = None
    qty: int = Field(1, ge=1, le=QTY_MAX)
    room_id: Optional[str] = None
    note: Optional[str] = Field(None, max_length=500)
    address: Optional[str] = Field(None, max_length=300)
    coupon_code: Optional[str] = Field(None, max_length=24)


class CartItemIn(BaseModel):
    product_id: str
    variant_id: Optional[str] = None
    qty: int = Field(1, ge=1, le=QTY_MAX)
    coupon_code: Optional[str] = Field(None, max_length=24)


class CartCheckoutIn(BaseModel):
    items: List[CartItemIn] = Field(..., min_length=1, max_length=20)
    address: Optional[str] = Field(None, max_length=300)


class OrderItemOut(BaseModel):
    product_id: str
    variant_id: Optional[str] = None
    title: str
    unit_price: int
    qty: int
    subtotal: int


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
    discount: int = 0
    coupon_code: Optional[str] = None
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
    items: List[OrderItemOut] = Field(default_factory=list)
    # سرور می‌گوید *این کاربر* اکنون چه می‌تواند بکند تا کلاینت قواعدِ گذار را
    # دوباره پیاده نکند و با سرور اختلاف پیدا نکند.
    can_accept: bool = False
    can_ship: bool = False
    can_complete: bool = False
    can_cancel: bool = False


class CouponIn(BaseModel):
    code: str = Field(..., min_length=3, max_length=24)
    discount_type: str = Field(..., pattern="^(percent|fixed)$")
    discount_value: int = Field(..., gt=0)
    product_id: Optional[str] = None
    max_uses: Optional[int] = Field(None, ge=1, le=100_000)
    min_order_total: int = Field(0, ge=0)
    expires_at: Optional[datetime] = None


class CouponPatch(BaseModel):
    max_uses: Optional[int] = Field(None, ge=1, le=100_000)
    expires_at: Optional[datetime] = None
    is_active: Optional[bool] = None


class CouponOut(BaseModel):
    id: str
    code: str
    discount_type: str
    discount_value: int
    product_id: Optional[str] = None
    max_uses: Optional[int] = None
    used_count: int
    min_order_total: int
    expires_at: Optional[datetime] = None
    is_active: bool
    created_at: datetime


class ReviewIn(BaseModel):
    product_id: str
    rating: int = Field(..., ge=1, le=5)
    comment: Optional[str] = Field(None, max_length=1000)


class ReviewOut(BaseModel):
    id: str
    product_id: str
    order_id: str
    reviewer_earth_id: str
    reviewer_name: Optional[str] = None
    rating: int
    comment: Optional[str] = None
    created_at: datetime


# ── کمکی‌ها ──────────────────────────────────────────────────────────────────
def _new_ref() -> str:
    return "ORD-" + _uuid.uuid4().hex[:10].upper()


def _product_out(p: ShopProduct, u: Optional[User],
                  rating: Optional[tuple] = None,
                  has_variants: bool = False) -> ProductOut:
    avg, cnt = rating if rating else (None, 0)
    return ProductOut(
        id=str(p.id),
        seller_earth_id=(u.earth_id if u else ""),
        seller_name=((u.full_name or u.username or u.earth_id) if u else None),
        title=p.title, description=p.description, price=int(p.price),
        currency=p.currency, stock=int(p.stock), image_url=p.image_url,
        images=list(p.images or []),
        is_active=bool(p.is_active), sold_count=int(p.sold_count),
        created_at=p.created_at,
        rating_avg=(round(avg, 2) if avg is not None else None),
        rating_count=int(cnt or 0), has_variants=has_variants,
    )


async def _rating_map(db: AsyncSession, product_ids) -> dict:
    ids = [i for i in set(product_ids) if i]
    if not ids:
        return {}
    rows = (await db.execute(
        select(ShopReview.product_id, func.avg(ShopReview.rating), func.count(ShopReview.id))
        .where(ShopReview.product_id.in_(ids))
        .group_by(ShopReview.product_id)
    )).all()
    return {pid: (float(avg), int(cnt)) for pid, avg, cnt in rows}


async def _variant_flags(db: AsyncSession, product_ids) -> set:
    """کدام کالاها گونهٔ فعال دارند — برای پرچمِ `has_variants` روی خروجی."""
    ids = [i for i in set(product_ids) if i]
    if not ids:
        return set()
    rows = (await db.execute(
        select(ShopProductVariant.product_id).where(
            ShopProductVariant.product_id.in_(ids),
            ShopProductVariant.is_active.is_(True),
        ).distinct()
    )).scalars().all()
    return set(rows)


async def _order_items(db: AsyncSession, order_ids) -> dict:
    ids = [i for i in set(order_ids) if i]
    if not ids:
        return {}
    rows = (await db.execute(
        select(ShopOrderItem).where(ShopOrderItem.order_id.in_(ids))
    )).scalars().all()
    out: dict = defaultdict(list)
    for r in rows:
        out[r.order_id].append(r)
    return out


def _item_out(it: "ShopOrderItem") -> OrderItemOut:
    return OrderItemOut(
        product_id=str(it.product_id),
        variant_id=(str(it.variant_id) if it.variant_id else None),
        title=it.title, unit_price=int(it.unit_price), qty=int(it.qty),
        subtotal=int(it.subtotal),
    )


def _order_out(o: ShopOrder, seller: Optional[User], buyer: Optional[User],
               me_id, items: Optional[list] = None) -> OrderOut:
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
        total=int(o.total), discount=int(o.discount or 0), coupon_code=o.coupon_code,
        commission=int(o.commission),
        status=o.status, status_label=STATUS_LABEL.get(o.status, o.status),
        escrow_status=o.escrow_status, note=o.note, address=o.address,
        room_id=(str(o.room_id) if o.room_id else None),
        created_at=o.created_at, shipped_at=o.shipped_at, closed_at=o.closed_at,
        items=[_item_out(it) for it in (items or [])],
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


async def _reserve_stock(db: AsyncSession, p: ShopProduct, variant_id: Optional[str],
                          qty: int) -> tuple[Optional[ShopProductVariant], int]:
    """موجودی را اتمیک کم می‌کند و قیمتِ واحدِ صحیح را برمی‌گرداند.

    اگر کالا گونهٔ فعال داشته باشد، خریدِ بدونِ `variant_id` رد می‌شود —
    وگرنه معلوم نیست موجودیِ کدام ردیف باید کم شود.
    """
    if variant_id:
        try:
            vid = _uuid.UUID(variant_id)
        except ValueError:
            raise HTTPException(status_code=404, detail="گونه پیدا نشد")
        v = (await db.execute(
            select(ShopProductVariant).where(
                ShopProductVariant.id == vid, ShopProductVariant.product_id == p.id,
                ShopProductVariant.is_active.is_(True),
            )
        )).scalar_one_or_none()
        if v is None:
            raise HTTPException(status_code=404, detail="گونه پیدا نشد")
        if v.stock != -1:
            res = await db.execute(
                update(ShopProductVariant)
                .where(ShopProductVariant.id == vid, ShopProductVariant.stock >= qty)
                .values(stock=ShopProductVariant.stock - qty)
            )
            if res.rowcount == 0:
                raise HTTPException(status_code=409, detail="موجودیِ این گونه کافی نیست")
        return v, int(v.price if v.price is not None else p.price)

    has_variants = (await db.execute(
        select(func.count()).select_from(ShopProductVariant).where(
            ShopProductVariant.product_id == p.id, ShopProductVariant.is_active.is_(True)
        )
    )).scalar_one()
    if int(has_variants or 0) > 0:
        raise HTTPException(status_code=400, detail="ابتدا گونهٔ کالا را انتخاب کنید")
    if p.stock != -1:
        res = await db.execute(
            update(ShopProduct)
            .where(ShopProduct.id == p.id, ShopProduct.stock >= qty)
            .values(stock=ShopProduct.stock - qty)
        )
        if res.rowcount == 0:
            raise HTTPException(status_code=409, detail="موجودیِ کالا کافی نیست")
    return None, int(p.price)


async def _apply_coupon(db: AsyncSession, code: str, seller_id, only_product_id,
                         subtotal: int) -> tuple:
    """اعتبارسنجی + مصرفِ اتمیکِ یک کدِ تخفیف. برمی‌گردانَد: (تخفیف، کدِ نرمال‌شده)."""
    c = (await db.execute(
        select(ShopCoupon).where(ShopCoupon.code == code.strip().upper())
    )).scalar_one_or_none()
    if c is None or not c.is_active or c.owner_id != seller_id:
        raise HTTPException(status_code=400, detail="کدِ تخفیف نامعتبر است")
    if c.product_id is not None and c.product_id != only_product_id:
        raise HTTPException(
            status_code=400,
            detail="این کدِ تخفیف فقط برای یک کالای مشخص است؛ سبد باید فقط همان کالا را داشته باشد",
        )
    if c.expires_at and c.expires_at <= _now():
        raise HTTPException(status_code=400, detail="کدِ تخفیف منقضی شده")
    if subtotal < int(c.min_order_total or 0):
        raise HTTPException(status_code=400, detail="مبلغِ سفارش کمتر از حداقلِ لازم برای این کد است")

    res = await db.execute(
        update(ShopCoupon)
        .where(
            ShopCoupon.id == c.id, ShopCoupon.is_active.is_(True),
            or_(ShopCoupon.max_uses.is_(None), ShopCoupon.used_count < ShopCoupon.max_uses),
        )
        .values(used_count=ShopCoupon.used_count + 1)
    )
    if res.rowcount == 0:
        raise HTTPException(status_code=409, detail="ظرفیتِ این کدِ تخفیف تمام شده")

    if c.discount_type == "percent":
        discount = subtotal * int(c.discount_value) // 100
    else:
        discount = int(c.discount_value)
    return max(0, min(discount, subtotal)), c.code


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
    rmap = await _rating_map(db, [p.id for p in rows])
    vset = await _variant_flags(db, [p.id for p in rows])
    return [_product_out(p, umap.get(p.owner_id), rmap.get(p.id), p.id in vset) for p in rows]


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
    rmap = await _rating_map(db, [p.id for p in rows])
    vset = await _variant_flags(db, [p.id for p in rows])
    return [_product_out(p, me, rmap.get(p.id), p.id in vset) for p in rows]


@router.post("/products", response_model=ProductOut, status_code=201)
async def create_product(
    body: ProductIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    images = [u.strip() for u in (body.images or []) if u and u.strip()][:MAX_IMAGES]
    p = ShopProduct(
        owner_id=me.id, title=body.title.strip(), price=body.price,
        description=(body.description or "").strip() or None,
        image_url=(body.image_url or "").strip() or None,
        images=(images or None),
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
    if "images" in data:
        imgs = data["images"] or []
        data["images"] = [u.strip() for u in imgs if u and u.strip()][:MAX_IMAGES] or None
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


def _review_out(r: ShopReview, u: Optional[User]) -> ReviewOut:
    return ReviewOut(
        id=str(r.id), product_id=str(r.product_id), order_id=str(r.order_id),
        reviewer_earth_id=(u.earth_id if u else ""),
        reviewer_name=((u.full_name or u.username or u.earth_id) if u else None),
        rating=int(r.rating), comment=r.comment, created_at=r.created_at,
    )


def _coupon_out(c: ShopCoupon) -> CouponOut:
    return CouponOut(
        id=str(c.id), code=c.code, discount_type=c.discount_type,
        discount_value=int(c.discount_value),
        product_id=(str(c.product_id) if c.product_id else None),
        max_uses=c.max_uses, used_count=int(c.used_count),
        min_order_total=int(c.min_order_total or 0), expires_at=c.expires_at,
        is_active=bool(c.is_active), created_at=c.created_at,
    )


def _variant_out(v: ShopProductVariant) -> VariantOut:
    return VariantOut(
        id=str(v.id), product_id=str(v.product_id), name=v.name,
        price=(int(v.price) if v.price is not None else None),
        stock=int(v.stock), image_url=v.image_url, is_active=bool(v.is_active),
    )


async def _my_product(db: AsyncSession, product_id: str, owner_id) -> ShopProduct:
    try:
        pid = _uuid.UUID(product_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="کالا پیدا نشد")
    p = (await db.execute(
        select(ShopProduct).where(ShopProduct.id == pid, ShopProduct.owner_id == owner_id)
    )).scalar_one_or_none()
    if p is None:
        raise HTTPException(status_code=404, detail="کالا پیدا نشد")
    return p


@router.post("/products/{product_id}/variants", response_model=VariantOut, status_code=201)
async def add_variant(
    product_id: str, body: VariantIn,
    db: AsyncSession = Depends(get_db), me: User = Depends(get_current_user),
):
    p = await _my_product(db, product_id, me.id)
    v = ShopProductVariant(
        product_id=p.id, name=body.name.strip(), price=body.price,
        stock=body.stock, image_url=(body.image_url or "").strip() or None,
    )
    db.add(v)
    await db.commit()
    await db.refresh(v)
    return _variant_out(v)


@router.get("/products/{product_id}/variants", response_model=List[VariantOut])
async def list_variants(
    product_id: str,
    db: AsyncSession = Depends(get_db), me: User = Depends(get_current_user),
):
    try:
        pid = _uuid.UUID(product_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="کالا پیدا نشد")
    rows = (await db.execute(
        select(ShopProductVariant).where(
            ShopProductVariant.product_id == pid, ShopProductVariant.is_active.is_(True)
        ).order_by(ShopProductVariant.created_at)
    )).scalars().all()
    return [_variant_out(v) for v in rows]


@router.patch("/products/{product_id}/variants/{variant_id}", response_model=VariantOut)
async def update_variant(
    product_id: str, variant_id: str, body: VariantPatch,
    db: AsyncSession = Depends(get_db), me: User = Depends(get_current_user),
):
    p = await _my_product(db, product_id, me.id)
    try:
        vid = _uuid.UUID(variant_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="گونه پیدا نشد")
    v = (await db.execute(
        select(ShopProductVariant).where(
            ShopProductVariant.id == vid, ShopProductVariant.product_id == p.id
        )
    )).scalar_one_or_none()
    if v is None:
        raise HTTPException(status_code=404, detail="گونه پیدا نشد")
    data = body.model_dump(exclude_unset=True)
    if "name" in data and data["name"] is not None:
        data["name"] = data["name"].strip()
    if "image_url" in data and data["image_url"] is not None:
        data["image_url"] = data["image_url"].strip() or None
    for k, val in data.items():
        setattr(v, k, val)
    await db.commit()
    await db.refresh(v)
    return _variant_out(v)


@router.delete("/products/{product_id}/variants/{variant_id}", status_code=204)
async def deactivate_variant(
    product_id: str, variant_id: str,
    db: AsyncSession = Depends(get_db), me: User = Depends(get_current_user),
):
    p = await _my_product(db, product_id, me.id)
    try:
        vid = _uuid.UUID(variant_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="گونه پیدا نشد")
    v = (await db.execute(
        select(ShopProductVariant).where(
            ShopProductVariant.id == vid, ShopProductVariant.product_id == p.id
        )
    )).scalar_one_or_none()
    if v is None:
        raise HTTPException(status_code=404, detail="گونه پیدا نشد")
    v.is_active = False
    await db.commit()


@router.get("/products/{product_id}/reviews", response_model=List[ReviewOut])
async def list_reviews(
    product_id: str,
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db), me: User = Depends(get_current_user),
):
    try:
        pid = _uuid.UUID(product_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="کالا پیدا نشد")
    rows = (await db.execute(
        select(ShopReview).where(ShopReview.product_id == pid)
        .order_by(ShopReview.created_at.desc()).limit(limit).offset(offset)
    )).scalars().all()
    umap = await _users(db, [r.reviewer_id for r in rows])
    return [_review_out(r, umap.get(r.reviewer_id)) for r in rows]


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
    rmap = await _rating_map(db, [p.id])
    vset = await _variant_flags(db, [p.id])
    return _product_out(p, umap.get(p.owner_id), rmap.get(p.id), p.id in vset)


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

    # کاهشِ موجودی با شرطِ درون همان UPDATE (کالا یا گونه). خواندن و سپس
    # نوشتن، بینِ دو درخواستِ هم‌زمان مسابقه می‌سازد و کالای تمام‌شده را
    # دوباره می‌فروشد.
    variant, unit_price = await _reserve_stock(db, p, body.variant_id, body.qty)
    subtotal = unit_price * body.qty

    discount, coupon_used = 0, None
    if body.coupon_code:
        discount, coupon_used = await _apply_coupon(db, body.coupon_code, p.owner_id, p.id, subtotal)
    total = max(0, subtotal - discount)

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
        room_id=room_uuid, title=p.title, unit_price=unit_price,
        qty=body.qty, total=total, discount=discount, coupon_code=coupon_used,
        status="pending", escrow_status="locked",
        note=(body.note or "").strip() or None,
        address=(body.address or "").strip() or None,
    )
    db.add(o)
    await db.flush()

    db.add(ShopOrderItem(
        order_id=o.id, product_id=p.id, variant_id=(variant.id if variant else None),
        title=p.title, unit_price=unit_price, qty=body.qty, subtotal=subtotal,
    ))

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
    imap = await _order_items(db, [o.id])
    return _order_out(o, umap.get(o.seller_id), umap.get(o.buyer_id), me.id, imap.get(o.id))


@router.post("/cart/checkout", response_model=List[OrderOut], status_code=201)
async def cart_checkout(
    body: CartCheckoutIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """سبدِ چندفروشنده: هر سبد به‌ازای هر فروشنده دقیقاً **یک** سفارشِ امانی
    می‌سازد (نه به‌ازای هر کالا)، و همه در **یک** تراکنش. اگر بلوکِ وجهِ یکی
    از سفارش‌ها به‌خاطرِ کمبودِ موجودی شکست بخورد، کل درخواست برمی‌گردد —
    وگرنه ممکن بود کاربر برای نیمی از سبد پول بدهد و نیمهٔ دیگر گم شود.
    این مسیر کارتِ درون‌چت نمی‌سازد؛ آن قابلیتِ خریدِ تکی از داخلِ گفتگوست.
    """
    pids: dict[str, _uuid.UUID] = {}
    for it in body.items:
        try:
            pids[it.product_id] = _uuid.UUID(it.product_id)
        except ValueError:
            raise HTTPException(status_code=404, detail="کالا پیدا نشد")

    products = {
        str(p.id): p for p in (await db.execute(
            select(ShopProduct).where(ShopProduct.id.in_(pids.values()))
        )).scalars().all()
    }

    groups: dict = defaultdict(list)
    for it in body.items:
        p = products.get(it.product_id)
        if p is None or not p.is_active:
            raise HTTPException(status_code=404, detail="کالا پیدا نشد")
        if p.owner_id == me.id:
            raise HTTPException(status_code=400, detail="خریدِ کالای خودتان ممکن نیست")
        groups[p.owner_id].append((it, p))

    created: List[ShopOrder] = []
    for seller_id, entries in groups.items():
        line_data = []
        coupon_code = None
        for it, p in entries:
            variant, unit_price = await _reserve_stock(db, p, it.variant_id, it.qty)
            line_data.append((p, variant, unit_price, it.qty, unit_price * it.qty))
            if it.coupon_code:
                coupon_code = it.coupon_code

        subtotal = sum(x[4] for x in line_data)
        discount, coupon_used = 0, None
        if coupon_code:
            only_pid = line_data[0][0].id if len(line_data) == 1 else None
            discount, coupon_used = await _apply_coupon(db, coupon_code, seller_id, only_pid, subtotal)
        total = max(0, subtotal - discount)

        ref = _new_ref()
        await lock_escrow(
            db, me.id, total,
            description=f"بلوکِ وجه برای سفارشِ {ref}",
            reference_id=ref,
        )

        first_title = line_data[0][0].title
        summary_title = (
            first_title if len(line_data) == 1
            else f"{first_title} و {len(line_data) - 1} موردِ دیگر"
        )
        o = ShopOrder(
            ref=ref, product_id=line_data[0][0].id, seller_id=seller_id, buyer_id=me.id,
            title=summary_title, unit_price=line_data[0][2],
            qty=sum(x[3] for x in line_data), total=total,
            discount=discount, coupon_code=coupon_used,
            status="pending", escrow_status="locked",
            address=(body.address or "").strip() or None,
        )
        db.add(o)
        await db.flush()
        for p, variant, unit_price, qty, line_subtotal in line_data:
            db.add(ShopOrderItem(
                order_id=o.id, product_id=p.id, variant_id=(variant.id if variant else None),
                title=p.title, unit_price=unit_price, qty=qty, subtotal=line_subtotal,
            ))
        created.append(o)

    await db.commit()
    for o in created:
        await db.refresh(o)
    umap = await _users(db, [o.seller_id for o in created] + [me.id])
    imap = await _order_items(db, [o.id for o in created])
    return [
        _order_out(o, umap.get(o.seller_id), umap.get(me.id), me.id, imap.get(o.id))
        for o in created
    ]


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
    imap = await _order_items(db, [o.id for o in rows])
    return [_order_out(o, umap.get(o.seller_id), umap.get(me.id), me.id, imap.get(o.id)) for o in rows]


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
    imap = await _order_items(db, [o.id for o in rows])
    return [_order_out(o, umap.get(me.id), umap.get(o.buyer_id), me.id, imap.get(o.id)) for o in rows]


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
    imap = await _order_items(db, [o.id])
    return _order_out(o, umap.get(o.seller_id), umap.get(o.buyer_id), me.id, imap.get(o.id))


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
    imap = await _order_items(db, [o.id])
    return _order_out(o, umap.get(o.seller_id), umap.get(o.buyer_id), me.id, imap.get(o.id))


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
    imap = await _order_items(db, [o.id])
    return _order_out(o, umap.get(o.seller_id), umap.get(o.buyer_id), me.id, imap.get(o.id))


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
    imap = await _order_items(db, [o.id])
    return _order_out(o, umap.get(o.seller_id), umap.get(o.buyer_id), me.id, imap.get(o.id))


@router.post("/orders/{order_id}/review", response_model=ReviewOut, status_code=201)
async def review_order(
    order_id: str, body: ReviewIn,
    db: AsyncSession = Depends(get_db), me: User = Depends(get_current_user),
):
    """ثبتِ نظر — فقط پس از `completed` شدنِ سفارش (یعنی وجه واقعاً آزاد شده،
    نه فقط قولِ ارسال). بدونِ این گاردی، هرکس می‌توانست بدونِ خریدِ واقعی
    اعتبارِ فروشنده را با نظرِ جعلی خراب یا تقلبی بسازد.
    """
    o = await _load_order(db, order_id, me.id)
    if o.buyer_id != me.id:
        raise HTTPException(status_code=403, detail="فقط خریدار می‌تواند نظر بدهد")
    if o.status != "completed":
        raise HTTPException(status_code=400, detail="فقط پس از تکمیلِ سفارش می‌توان نظر داد")
    try:
        pid = _uuid.UUID(body.product_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="کالا پیدا نشد")

    in_order = pid == o.product_id
    if not in_order:
        cnt = (await db.execute(
            select(func.count()).select_from(ShopOrderItem).where(
                ShopOrderItem.order_id == o.id, ShopOrderItem.product_id == pid,
            )
        )).scalar_one()
        in_order = bool(cnt)
    if not in_order:
        raise HTTPException(status_code=400, detail="این کالا در این سفارش نبوده")

    r = ShopReview(
        order_id=o.id, product_id=pid, reviewer_id=me.id, seller_id=o.seller_id,
        rating=body.rating, comment=(body.comment or "").strip() or None,
    )
    db.add(r)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=409, detail="برای این کالا در این سفارش قبلاً نظر ثبت شده")
    await db.refresh(r)
    return _review_out(r, me)


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

    # بازگرداندنِ موجودی ردیف‌به‌ردیف (کالا یا گونه)، نه فقط `o.product_id`
    # تکی — سفارشِ سبدی چند ردیف دارد که هرکدام ممکن است گونهٔ متفاوتی باشند.
    # سفارش‌های قدیمیِ پیش از این استقرار هیچ ردیفی در `shop_order_items`
    # ندارند؛ برایشان به همان رفتارِ تک‌کالاییِ قبلی برمی‌گردیم.
    items = (await db.execute(
        select(ShopOrderItem).where(ShopOrderItem.order_id == o.id)
    )).scalars().all()
    if not items:
        p = (await db.execute(
            select(ShopProduct).where(ShopProduct.id == o.product_id).with_for_update()
        )).scalar_one_or_none()
        if p is not None and p.stock != -1:
            p.stock = int(p.stock) + int(o.qty)
    for it in items:
        if it.variant_id:
            v = (await db.execute(
                select(ShopProductVariant).where(ShopProductVariant.id == it.variant_id)
                .with_for_update()
            )).scalar_one_or_none()
            if v is not None and v.stock != -1:
                v.stock = int(v.stock) + int(it.qty)
        else:
            p = (await db.execute(
                select(ShopProduct).where(ShopProduct.id == it.product_id).with_for_update()
            )).scalar_one_or_none()
            if p is not None and p.stock != -1:
                p.stock = int(p.stock) + int(it.qty)

    o.status = "cancelled"
    o.closed_at = _now()
    await db.commit()
    await db.refresh(o)
    umap = await _users(db, [o.seller_id, o.buyer_id])
    return _order_out(o, umap.get(o.seller_id), umap.get(o.buyer_id), me.id, items)


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

    # افزایشِ فروش‌رفته به‌ازای هر کالای واقعی در سفارش — سفارشِ سبدی ممکن
    # است چند کالای متفاوت داشته باشد. سفارش‌های قدیمیِ بدونِ ردیف به همان
    # رفتارِ تک‌کالاییِ قبلی برمی‌گردند.
    items = (await db.execute(
        select(ShopOrderItem).where(ShopOrderItem.order_id == o.id)
    )).scalars().all()
    sold_by_product: dict = defaultdict(int)
    if items:
        for it in items:
            sold_by_product[it.product_id] += int(it.qty)
    else:
        sold_by_product[o.product_id] = int(o.qty)

    products = (await db.execute(
        select(ShopProduct).where(ShopProduct.id.in_(sold_by_product.keys())).with_for_update()
    )).scalars().all()
    for p in products:
        p.sold_count = int(p.sold_count or 0) + sold_by_product[p.id]


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


# ── کدهای تخفیف ──────────────────────────────────────────────────────────────
@router.post("/coupons", response_model=CouponOut, status_code=201)
async def create_coupon(
    body: CouponIn,
    db: AsyncSession = Depends(get_db), me: User = Depends(get_current_user),
):
    if body.discount_type == "percent" and not (1 <= body.discount_value <= 90):
        raise HTTPException(status_code=400, detail="درصدِ تخفیف باید بینِ ۱ تا ۹۰ باشد")
    pid = None
    if body.product_id:
        try:
            pid = _uuid.UUID(body.product_id)
        except ValueError:
            raise HTTPException(status_code=404, detail="کالا پیدا نشد")
        p = (await db.execute(
            select(ShopProduct).where(ShopProduct.id == pid, ShopProduct.owner_id == me.id)
        )).scalar_one_or_none()
        if p is None:
            raise HTTPException(status_code=404, detail="کالا پیدا نشد")

    c = ShopCoupon(
        owner_id=me.id, product_id=pid, code=body.code.strip().upper(),
        discount_type=body.discount_type, discount_value=body.discount_value,
        max_uses=body.max_uses, min_order_total=body.min_order_total,
        expires_at=body.expires_at,
    )
    db.add(c)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=409, detail="این کد قبلاً استفاده شده")
    await db.refresh(c)
    return _coupon_out(c)


@router.get("/coupons/mine", response_model=List[CouponOut])
async def my_coupons(
    db: AsyncSession = Depends(get_db), me: User = Depends(get_current_user),
):
    rows = (await db.execute(
        select(ShopCoupon).where(ShopCoupon.owner_id == me.id)
        .order_by(ShopCoupon.created_at.desc())
    )).scalars().all()
    return [_coupon_out(c) for c in rows]


@router.patch("/coupons/{coupon_id}", response_model=CouponOut)
async def update_coupon(
    coupon_id: str, body: CouponPatch,
    db: AsyncSession = Depends(get_db), me: User = Depends(get_current_user),
):
    try:
        cid = _uuid.UUID(coupon_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="کد پیدا نشد")
    c = (await db.execute(
        select(ShopCoupon).where(ShopCoupon.id == cid, ShopCoupon.owner_id == me.id)
    )).scalar_one_or_none()
    if c is None:
        raise HTTPException(status_code=404, detail="کد پیدا نشد")
    for k, v in body.model_dump(exclude_unset=True).items():
        setattr(c, k, v)
    await db.commit()
    await db.refresh(c)
    return _coupon_out(c)


@router.delete("/coupons/{coupon_id}", status_code=204)
async def deactivate_coupon(
    coupon_id: str,
    db: AsyncSession = Depends(get_db), me: User = Depends(get_current_user),
):
    try:
        cid = _uuid.UUID(coupon_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="کد پیدا نشد")
    c = (await db.execute(
        select(ShopCoupon).where(ShopCoupon.id == cid, ShopCoupon.owner_id == me.id)
    )).scalar_one_or_none()
    if c is None:
        raise HTTPException(status_code=404, detail="کد پیدا نشد")
    c.is_active = False
    await db.commit()
