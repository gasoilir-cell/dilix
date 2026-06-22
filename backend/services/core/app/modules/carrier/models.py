"""مدل ORM حمل‌ونقل — محموله (schema: carrier، سند ۳).

Aggregate Root: Shipment. ماشینِ حالت:
created → dispatched → in_transit → delivered
created/dispatched/in_transit → cancelled
Dilix فقط شماره‌ی بارنامه نزدِ متصدی (waybill_no) را نگه می‌دارد.
"""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import BigInteger, DateTime, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

STATUS_CREATED = "created"
STATUS_DISPATCHED = "dispatched"
STATUS_IN_TRANSIT = "in_transit"
STATUS_DELIVERED = "delivered"
STATUS_CANCELLED = "cancelled"


class Shipment(Base):
    __tablename__ = "shipment"
    __table_args__ = {"schema": "carrier"}

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    shipper_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    provider_code: Mapped[str] = mapped_column(String(32), nullable=False)

    origin: Mapped[str] = mapped_column(String(120), nullable=False)
    destination: Mapped[str] = mapped_column(String(120), nullable=False)
    weight_grams: Mapped[int] = mapped_column(BigInteger, nullable=False)

    waybill_no: Mapped[str | None] = mapped_column(String(64), nullable=True)
    status: Mapped[str] = mapped_column(String(16), default=STATUS_CREATED, nullable=False)
    last_location: Mapped[str | None] = mapped_column(String(120), nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
