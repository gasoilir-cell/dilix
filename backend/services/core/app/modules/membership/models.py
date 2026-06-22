"""مدل ORM عضویت — Membership (Walmart+ style، سند ۰ ADR-08 / سند ۱).

طرح‌های عضویت: free, standard, premium. هر طرح cashback_bps (basis points) دارد.
"""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import DateTime, SmallInteger, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

PLAN_FREE = "free"
PLAN_STANDARD = "standard"
PLAN_PREMIUM = "premium"

STATUS_ACTIVE = "active"
STATUS_EXPIRED = "expired"
STATUS_CANCELLED = "cancelled"

PLAN_CASHBACK_BPS: dict[str, int] = {
    PLAN_FREE: 0,
    PLAN_STANDARD: 100,   # ۱٪ cashback
    PLAN_PREMIUM: 250,    # ۲.۵٪ cashback
}


class MembershipSubscription(Base):
    __tablename__ = "membership_subscription"
    __table_args__ = {"schema": "membership"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, unique=True)
    plan: Mapped[str] = mapped_column(String(16), default=PLAN_FREE, nullable=False)
    status: Mapped[str] = mapped_column(String(16), default=STATUS_ACTIVE, nullable=False)
    cashback_bps: Mapped[int] = mapped_column(SmallInteger, default=0, nullable=False)
    started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
