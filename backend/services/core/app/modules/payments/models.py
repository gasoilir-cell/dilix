"""مدل ORM پرداخت — سفارشِ امانی (schema: payments، سند ۳).

Aggregate Root: PaymentOrder. ماشینِ حالت:
created → escrowed → captured  (مسیرِ موفق)
                  ↘ refunded   (لغو/اختلاف)
created/escrowed → failed
Dilix فقط مرجعِ امانتِ بانک (external_ref) را نگه می‌دارد؛ هرگز خودِ وجه را.
"""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import BigInteger, DateTime, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

# حالت‌های مجاز
STATUS_CREATED = "created"
STATUS_ESCROWED = "escrowed"
STATUS_CAPTURED = "captured"
STATUS_REFUNDED = "refunded"
STATUS_FAILED = "failed"


class PaymentOrder(Base):
    __tablename__ = "payment_order"
    __table_args__ = {"schema": "payments"}

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    payer_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    payee_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    amount_minor: Mapped[int] = mapped_column(BigInteger, nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)

    provider_code: Mapped[str] = mapped_column(String(32), nullable=False)
    external_ref: Mapped[str | None] = mapped_column(String(64), nullable=True)
    status: Mapped[str] = mapped_column(String(16), default=STATUS_CREATED, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
