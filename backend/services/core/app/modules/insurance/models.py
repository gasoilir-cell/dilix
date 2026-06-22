"""مدل ORM بیمه — بیمه‌نامه (schema: insurance، سند ۳).

Aggregate Root: InsurancePolicy. ماشینِ حالت:
quoted → issued → claimed
quoted/issued → cancelled
Dilix فقط مرجعِ بیمه‌نامه نزدِ بیمه‌گر (external_ref) را نگه می‌دارد.
"""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import BigInteger, DateTime, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

STATUS_QUOTED = "quoted"
STATUS_ISSUED = "issued"
STATUS_CLAIMED = "claimed"
STATUS_CANCELLED = "cancelled"


class InsurancePolicy(Base):
    __tablename__ = "insurance_policy"
    __table_args__ = {"schema": "insurance"}

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    holder_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    provider_code: Mapped[str] = mapped_column(String(32), nullable=False)
    product_code: Mapped[str] = mapped_column(String(64), nullable=False)

    coverage_minor: Mapped[int] = mapped_column(BigInteger, nullable=False)
    premium_minor: Mapped[int] = mapped_column(BigInteger, nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)

    quote_ref: Mapped[str | None] = mapped_column(String(64), nullable=True)
    external_ref: Mapped[str | None] = mapped_column(String(64), nullable=True)
    status: Mapped[str] = mapped_column(String(16), default=STATUS_QUOTED, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
