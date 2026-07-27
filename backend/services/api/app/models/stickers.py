"""Dilix — Sticker / Emoji Library Model

کتابخانه‌ی استیکر و ایموجیِ اختصاصی:
  • StickerPack   — یک کتابخانه (بسته) که مالک دارد؛ می‌تواند عمومی/خصوصی باشد.
  • Sticker       — یک استیکر/ایموجی داخلِ یک بسته (تصویر | ویدیو | صوت).
  • StarredSticker— استیکرهای ستاره‌دارِ کاربر برای دسترسیِ سریع.
  • InstalledPack — بسته‌هایی که کاربر از کتابخانه‌ی عمومی نصب کرده است.
  • StickerPurchase — خریدِ یک بستهٔ پولی (بازارِ استیکر، فاز ۵).
"""
import uuid
from datetime import datetime, timezone
from sqlalchemy import (
    BigInteger, Boolean, Column, DateTime, ForeignKey, Integer, String, Index,
)
from sqlalchemy.dialects.postgresql import UUID
from app.core.database import Base


def _now():
    return datetime.now(timezone.utc)


class StickerPack(Base):
    __tablename__ = "sticker_packs"

    id            = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_id      = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    title         = Column(String(120), nullable=False)
    description   = Column(String(300), nullable=True)
    cover_url     = Column(String(500), nullable=True)     # آیکنِ بسته (اولین استیکر معمولاً)
    is_public     = Column(Boolean, nullable=False, default=False, index=True)
    is_animated   = Column(Boolean, nullable=False, default=False)  # شاملِ ویدیو/متحرک؟
    install_count = Column(Integer, nullable=False, default=0)      # چند نفر نصب کرده‌اند
    sticker_count = Column(Integer, nullable=False, default=0)      # تعدادِ استیکرها (denormalized)
    # بازارِ استیکر (فاز ۵): قیمتِ صفر یعنی رایگان — همان رفتارِ قبلی.
    price         = Column(BigInteger, nullable=False, default=0)   # ریال
    sales_count   = Column(Integer, nullable=False, default=0)
    revenue_total = Column(BigInteger, nullable=False, default=0)   # درآمدِ خالصِ سازنده
    created_at    = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at    = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)


class Sticker(Base):
    __tablename__ = "stickers"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    pack_id    = Column(UUID(as_uuid=True), ForeignKey("sticker_packs.id", ondelete="CASCADE"),
                        nullable=False, index=True)
    owner_id   = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    media_url  = Column(String(500), nullable=False)
    media_type = Column(String(32), nullable=False, default="image")  # image | video | voice
    emoji_tag  = Column(String(32), nullable=True)      # ایموجیِ متناظر برای جست‌وجو (مثلاً 😂)
    title      = Column(String(120), nullable=True)     # برچسبِ اختیاری
    use_count  = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)


class StarredSticker(Base):
    __tablename__ = "starred_stickers"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id    = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    sticker_id = Column(UUID(as_uuid=True), ForeignKey("stickers.id", ondelete="CASCADE"),
                        nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("uq_starred_sticker", "user_id", "sticker_id", unique=True),
    )


class InstalledPack(Base):
    __tablename__ = "installed_packs"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id    = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    pack_id    = Column(UUID(as_uuid=True), ForeignKey("sticker_packs.id", ondelete="CASCADE"),
                        nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("uq_installed_pack", "user_id", "pack_id", unique=True),
    )


class StickerPurchase(Base):
    """خریدِ یک بستهٔ پولی — یک ردیف به‌ازای هر (بسته، خریدار).

    قیمت و کارمزد **snapshot** می‌شوند: سازنده می‌تواند فردا قیمت را عوض کند
    ولی رسیدِ خرید نباید با آن تغییر کند. یکتاییِ `(pack_id, buyer_id)` تنها
    محافظِ خریدِ دوباره است؛ اگر با `if`ِ پایتونی بررسی می‌شد، دو درخواستِ
    هم‌زمان هر دو پول را کم می‌کردند.
    """
    __tablename__ = "sticker_purchases"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    pack_id    = Column(UUID(as_uuid=True), ForeignKey("sticker_packs.id", ondelete="CASCADE"),
                        nullable=False, index=True)
    buyer_id   = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                        nullable=False, index=True)
    seller_id  = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                        nullable=False, index=True)
    price      = Column(BigInteger, nullable=False)
    fee        = Column(BigInteger, nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("uq_sticker_purchase", "pack_id", "buyer_id", unique=True),
    )
