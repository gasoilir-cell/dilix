"""مدل ORM داستانِ ۲۴ساعته (schema: stories).

برگرفته از پیش‌نویسِ `_stories_model.py` و هم‌راستا با قراردادهای Core.
شناسه‌ی کاربر = earth_id (بدونِ FK به جدولِ users). مخاطب‌ها: public و حلقه‌های
دستی (colleagues/family/friends). مخاطبِ followers نیازمندِ گرافِ فالوِ ماژولِ
Social است و در این ماژول پیاده‌سازی نشده.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import DateTime, ForeignKey, Index, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

AUDIENCE_PUBLIC = "public"
CIRCLE_AUDIENCES = ("colleagues", "family", "friends")
AUDIENCES = (AUDIENCE_PUBLIC, *CIRCLE_AUDIENCES)


def _expiry() -> datetime:
    return datetime.now(timezone.utc) + timedelta(hours=24)


class Story(Base):
    """یک داستانِ رسانه‌ای (عکس/ویدیو) با انقضای ۲۴ساعته."""

    __tablename__ = "story"
    __table_args__ = (
        Index("ix_story_author_exp", "author_earth_id", "expires_at"),
        {"schema": "stories"},
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    author_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    media_url: Mapped[str] = mapped_column(Text, nullable=False)
    media_type: Mapped[str] = mapped_column(String(12), default="image", nullable=False)
    caption: Mapped[str | None] = mapped_column(Text, nullable=True)
    audience: Mapped[str] = mapped_column(String(16), default=AUDIENCE_PUBLIC, nullable=False)
    view_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False, index=True
    )
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_expiry, nullable=False, index=True
    )


class ContactCircle(Base):
    """عضویتِ یک مخاطب در یکی از حلقه‌های صاحبِ حساب (همکار/خانواده/دوست)."""

    __tablename__ = "contact_circle"
    __table_args__ = (
        Index("uq_contact_circle", "owner_earth_id", "member_earth_id", "circle", unique=True),
        Index("ix_contact_circle_member", "member_earth_id", "circle"),
        {"schema": "stories"},
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    member_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    circle: Mapped[str] = mapped_column(String(16), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class StoryView(Base):
    """یک ردیف = viewer_earth_id داستانِ story_id را دیده است (یکتا برای هر جفت)."""

    __tablename__ = "story_view"
    __table_args__ = (
        Index("uq_story_view", "story_id", "viewer_earth_id", unique=True),
        {"schema": "stories"},
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    story_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("stories.story.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    viewer_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
