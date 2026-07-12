"""مدل ORM کتابخانه‌ی استیکر/ایموجی (schema: stickers).

برگرفته از پیش‌نویسِ `_stickers_model.py` و هم‌راستا با قراردادهای Core
(SQLAlchemy 2.0، شناسه‌ی کاربر به‌صورتِ earth_id بدونِ JOINِ بین‌Contextی).
"""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, Integer, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

MEDIA_IMAGE = "image"
MEDIA_VIDEO = "video"
MEDIA_VOICE = "voice"


class StickerPack(Base):
    """یک بسته (کتابخانه) استیکر که مالک دارد؛ می‌تواند عمومی/خصوصی باشد."""

    __tablename__ = "sticker_pack"
    __table_args__ = {"schema": "stickers"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(120), nullable=False)
    description: Mapped[str | None] = mapped_column(String(300), nullable=True)
    cover_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    is_public: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, index=True)
    is_animated: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    install_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    sticker_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class Sticker(Base):
    """یک استیکر/ایموجی داخلِ یک بسته (تصویر | ویدیو | صوت)."""

    __tablename__ = "sticker"
    __table_args__ = {"schema": "stickers"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    pack_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("stickers.sticker_pack.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    owner_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    media_url: Mapped[str] = mapped_column(String(500), nullable=False)
    media_type: Mapped[str] = mapped_column(String(32), default=MEDIA_IMAGE, nullable=False)
    emoji_tag: Mapped[str | None] = mapped_column(String(32), nullable=True)
    title: Mapped[str | None] = mapped_column(String(120), nullable=True)
    use_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class StarredSticker(Base):
    """استیکرهای ستاره‌دارِ کاربر برای دسترسیِ سریع."""

    __tablename__ = "starred_sticker"
    __table_args__ = (
        Index("uq_starred_sticker", "user_earth_id", "sticker_id", unique=True),
        {"schema": "stickers"},
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    sticker_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("stickers.sticker.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class InstalledPack(Base):
    """بسته‌هایی که کاربر از کتابخانه‌ی عمومی نصب کرده است."""

    __tablename__ = "installed_pack"
    __table_args__ = (
        Index("uq_installed_pack", "user_earth_id", "pack_id", unique=True),
        {"schema": "stickers"},
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    pack_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("stickers.sticker_pack.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
