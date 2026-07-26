"""
Dilix — Social Graph (Follow) Model
گرافِ اجتماعی: رابطهٔ دنبال‌کردن (یک‌طرفه، مثل اینستاگرام)
"""
import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, DateTime, ForeignKey, Index
from sqlalchemy.dialects.postgresql import UUID

from app.core.database import Base


def _now():
    return datetime.now(timezone.utc)


class Follow(Base):
    """یک ردیف = follower_id کاربرِ following_id را دنبال می‌کند."""
    __tablename__ = "follows"

    id           = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    follower_id  = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    following_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    created_at   = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        # هر جفت فقط یک‌بار (جلوگیری از دنبال‌کردنِ تکراری)
        Index("uq_follow_pair", "follower_id", "following_id", unique=True),
        # جستجوی سریعِ «چه‌کسانی X را دنبال می‌کنند»
        Index("ix_follow_following", "following_id", "follower_id"),
    )
