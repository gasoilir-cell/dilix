"""
Dilix — Live (پخشِ زندهٔ ویدیویی ۱-به-چند، مثلِ Instagram/WeChat Live)
میزبان یک نشستِ زنده می‌سازد؛ بینندگان می‌پیوندند و مدیا به‌صورتِ WebRTC (mesh از میزبان)
پخش می‌شود. سیگنالینگ روی همان معماریِ Redis-poll (مثلِ تماس‌ها). چت/قلبِ زنده سبک و ephemeral.
جدولِ live_sessions فقط برای کشف/فهرست و تاریخچه است (نه خودِ مدیا).
"""
import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Index
from sqlalchemy.dialects.postgresql import UUID

from app.core.database import Base


def _now():
    return datetime.now(timezone.utc)


class LiveSession(Base):
    """یک نشستِ پخشِ زنده. status: live | ended."""
    __tablename__ = "live_sessions"

    id            = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    host_id       = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    title         = Column(String(120), nullable=True)
    status        = Column(String(12), nullable=False, default="live")  # live | ended
    peak_viewers  = Column(Integer, default=0)
    total_hearts  = Column(Integer, default=0)
    started_at    = Column(DateTime(timezone=True), nullable=False, default=_now, index=True)
    ended_at      = Column(DateTime(timezone=True), nullable=True)

    __table_args__ = (
        Index("ix_live_status_started", "status", "started_at"),
    )
