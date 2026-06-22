"""مدل ORM بار و بیدها (schema: freight، سند ۳).

جریانِ کامل: CargoOwner بار ثبت می‌کند → رانندگان bid می‌دهند → صاحب‌بار bid
قبول می‌کند → escrow بسته می‌شود → بارنامه صادر می‌شود → تحویل → تسویه.
Dilix فقط ارکستریت می‌کند؛ وجه نزدِ بانک و بارنامه نزدِ متصدی است.
"""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import BigInteger, DateTime, Float, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

# وضعیت‌های بارِ کالا
CARGO_OPEN = "open"            # منتشرشده، در انتظارِ bid
CARGO_BIDDING = "bidding"      # حداقل یک bid دریافت‌شده
CARGO_ASSIGNED = "assigned"    # bid قبول‌شده، escrow بسته‌شده
CARGO_IN_TRANSIT = "in_transit"
CARGO_DELIVERED = "delivered"
CARGO_SETTLED = "settled"      # تسویه‌ی کامل
CARGO_CANCELLED = "cancelled"

# وضعیت‌های bid
BID_PENDING = "pending"
BID_ACCEPTED = "accepted"
BID_REJECTED = "rejected"
BID_EXPIRED = "expired"


class CargoPost(Base):
    """بارِ ثبت‌شده توسطِ صاحب‌بار."""

    __tablename__ = "cargo_post"
    __table_args__ = {"schema": "freight"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)

    origin: Mapped[str] = mapped_column(String(120), nullable=False)
    destination: Mapped[str] = mapped_column(String(120), nullable=False)
    weight_grams: Mapped[int] = mapped_column(BigInteger, nullable=False)

    # جزئیاتِ اضافی (ابعاد، نوعِ کالا، خطرناک؟)
    meta: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)

    # پیشنهادِ قیمتِ اولیه (اختیاری)
    budget_minor: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    currency: Mapped[str] = mapped_column(String(3), default="IRR", nullable=False)

    status: Mapped[str] = mapped_column(String(16), default=CARGO_OPEN, nullable=False)

    # پس از assign
    accepted_bid_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    payment_order_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    shipment_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class FreightBid(Base):
    """پیشنهادِ راننده برای حملِ بار."""

    __tablename__ = "freight_bid"
    __table_args__ = {"schema": "freight"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    cargo_post_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    driver_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    price_minor: Mapped[int] = mapped_column(BigInteger, nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    note: Mapped[str | None] = mapped_column(String(500), nullable=True)
    status: Mapped[str] = mapped_column(String(16), default=BID_PENDING, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class FreightLocation(Base):
    """موقعیت GPS راننده در حین حمل — برای tracking realtime (ADR-06)."""

    __tablename__ = "freight_location"
    __table_args__ = {"schema": "freight"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    cargo_post_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("freight.cargo_post.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    driver_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    # دقت GPS (متر)
    accuracy_m: Mapped[float | None] = mapped_column(Float, nullable=True)
    # سرعت (km/h)
    speed_kmh: Mapped[float | None] = mapped_column(Float, nullable=True)
    recorded_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
