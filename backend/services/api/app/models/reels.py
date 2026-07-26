"""
Dilix — Reels (ویدیوهای کوتاهِ عمودی، مثل اینستاگرام Reels / TikTok)
فیدِ عمومیِ کشف؛ لایک/کامنت/بازدید.
"""
import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text, Index
from sqlalchemy.dialects.postgresql import UUID

from app.core.database import Base


def _now():
    return datetime.now(timezone.utc)


class Reel(Base):
    """یک ریلزِ ویدیویی (یا عکس) در فیدِ کشف."""
    __tablename__ = "reels"

    id            = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    author_id     = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    media_url     = Column(Text, nullable=False)
    media_type    = Column(String(12), nullable=False, default="video")  # video | image
    caption       = Column(Text, nullable=True)
    view_count    = Column(Integer, default=0)
    like_count    = Column(Integer, default=0)
    comment_count = Column(Integer, default=0)
    created_at    = Column(DateTime(timezone=True), nullable=False, default=_now, index=True)

    __table_args__ = (
        Index("ix_reel_author_created", "author_id", "created_at"),
    )


class ReelLike(Base):
    """یک ردیف = user_id ریلزِ reel_id را لایک کرده (یکتا برای هر جفت)."""
    __tablename__ = "reel_likes"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    reel_id    = Column(
        UUID(as_uuid=True),
        ForeignKey("reels.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    user_id    = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("uq_reel_like", "reel_id", "user_id", unique=True),
    )


class ReelComment(Base):
    """یک کامنت روی یک ریلز."""
    __tablename__ = "reel_comments"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    reel_id    = Column(
        UUID(as_uuid=True),
        ForeignKey("reels.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    author_id  = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    body       = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now, index=True)
