"""Dilix — Sticker / Emoji Library Model

کتابخانه‌ی استیکر و ایموجیِ اختصاصی:
  • StickerPack   — یک کتابخانه (بسته) که مالک دارد؛ می‌تواند عمومی/خصوصی باشد.
  • Sticker       — یک استیکر/ایموجی داخلِ یک بسته (تصویر | ویدیو | صوت).
  • StarredSticker— استیکرهای ستاره‌دارِ کاربر برای دسترسیِ سریع.
  • InstalledPack — بسته‌هایی که کاربر از کتابخانه‌ی عمومی نصب کرده است.
"""
import uuid
from datetime import datetime, timezone
from sqlalchemy import (
    Boolean, Column, DateTime, ForeignKey, Integer, String, Text, Index,
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
