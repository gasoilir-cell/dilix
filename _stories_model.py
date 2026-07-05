"""
Dilix — Stories (داستانِ ۲۴ساعته، مثل اینستاگرام)
هر داستان پس از ۲۴ ساعت منقضی می‌شود (فیلترِ expires_at در کوئری‌ها).
"""
import uuid
from datetime import datetime, timezone, timedelta

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text, Index
from sqlalchemy.dialects.postgresql import UUID

from app.core.database import Base


def _now():
    return datetime.now(timezone.utc)


def _expiry():
    return datetime.now(timezone.utc) + timedelta(hours=24)


class Story(Base):
    """یک داستانِ رسانه‌ای (عکس/ویدیو) با انقضای ۲۴ساعته."""
    __tablename__ = "stories"

    id          = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    author_id   = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    media_url   = Column(Text, nullable=False)
    media_type  = Column(String(12), nullable=False, default="image")  # image | video
    caption     = Column(Text, nullable=True)
    view_count  = Column(Integer, default=0)
    created_at  = Column(DateTime(timezone=True), nullable=False, default=_now, index=True)
    expires_at  = Column(DateTime(timezone=True), nullable=False, default=_expiry, index=True)

    __table_args__ = (
        Index("ix_story_author_exp", "author_id", "expires_at"),
    )


class StoryView(Base):
    """یک ردیف = viewer_id داستانِ story_id را دیده است (یکتا برای هر جفت)."""
    __tablename__ = "story_views"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    story_id   = Column(
        UUID(as_uuid=True),
        ForeignKey("stories.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    viewer_id  = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("uq_story_view", "story_id", "viewer_id", unique=True),
    )
