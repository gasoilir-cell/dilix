"""مدل ORM رفرال — سه‌سطحیِ محدود، گره‌خورده به تراکنشِ واقعی (ADR-08).

Invariant: reward فقط وقتی `reward_event_id` وجود دارد ثبت می‌شود.
این از مدلِ هرمی (پاداشِ صرفِ عضوگیری) جلوگیری می‌کند.
"""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import BigInteger, DateTime, SmallInteger, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

MAX_REFERRAL_LEVELS = 3

STATUS_PENDING = "pending"
STATUS_REWARDED = "rewarded"
STATUS_EXPIRED = "expired"


class Referral(Base):
    __tablename__ = "referral"
    __table_args__ = {"schema": "referral"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    referrer_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    referred_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, unique=True)
    level: Mapped[int] = mapped_column(SmallInteger, nullable=False)  # 1/2/3

    status: Mapped[str] = mapped_column(String(16), default=STATUS_PENDING, nullable=False)

    # شناسهٔ رویدادِ تراکنشی که پاداش را فعال کرد (Invariant ضدِ هرمی)
    reward_event_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    reward_minor: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    currency: Mapped[str] = mapped_column(String(3), default="IRR", nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    rewarded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
