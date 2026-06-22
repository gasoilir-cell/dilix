"""مدل ORM بازارگاه خدمات (schema: marketplace، سند ۳ — Milestone 3).

Dilix بستر است؛ فریلنسر/ارائه‌دهنده خدمت را ثبت می‌کند و مشتری سفارش می‌دهد.
کارمزد Dilix از escrow کسر می‌شود؛ پول نزد بانک است.
"""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import BigInteger, Boolean, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

# وضعیت سرویس
SERVICE_ACTIVE = "active"
SERVICE_PAUSED = "paused"
SERVICE_DELETED = "deleted"

# وضعیت سفارش
ORDER_PENDING = "pending"
ORDER_ACCEPTED = "accepted"
ORDER_IN_PROGRESS = "in_progress"
ORDER_DELIVERED = "delivered"
ORDER_DISPUTED = "disputed"
ORDER_COMPLETED = "completed"
ORDER_CANCELLED = "cancelled"

# دسته‌بندی‌های اصلی (قابل گسترش)
CATEGORY_TECH = "tech"
CATEGORY_DESIGN = "design"
CATEGORY_LEGAL = "legal"
CATEGORY_HEALTH = "health"
CATEGORY_EDUCATION = "education"
CATEGORY_TRANSPORT = "transport"
CATEGORY_OTHER = "other"


class ServiceListing(Base):
    """خدمتی که فریلنسر یا شرکت در بازارگاه ارائه می‌دهد."""

    __tablename__ = "service_listing"
    __table_args__ = {"schema": "marketplace"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    provider_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    category: Mapped[str] = mapped_column(String(32), nullable=False)
    # قیمت پایه (ریال/minor unit)
    base_price_minor: Mapped[int] = mapped_column(BigInteger, nullable=False)
    currency: Mapped[str] = mapped_column(String(3), default="IRR", nullable=False)
    # مدت تحویل (روز)
    delivery_days: Mapped[int] = mapped_column(Integer, nullable=False, default=7)
    # تگ‌ها برای جستجو
    tags: Mapped[list] = mapped_column(JSONB, default=list, nullable=False)
    # رسانه‌ها (MinIO refs)
    media_refs: Mapped[list] = mapped_column(JSONB, default=list, nullable=False)
    status: Mapped[str] = mapped_column(String(16), default=SERVICE_ACTIVE, nullable=False)
    is_featured: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class ServiceOrder(Base):
    """سفارش خدمت از بازارگاه."""

    __tablename__ = "service_order"
    __table_args__ = {"schema": "marketplace"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    listing_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("marketplace.service_listing.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    buyer_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    provider_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    # نیاز خریدار
    requirements: Mapped[str | None] = mapped_column(Text, nullable=True)
    agreed_price_minor: Mapped[int] = mapped_column(BigInteger, nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    # escrow (گره به payment module)
    payment_order_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    status: Mapped[str] = mapped_column(String(16), default=ORDER_PENDING, nullable=False)
    # کارمزد پلتفورم (bps — ۱/۱۰۰ درصد)
    platform_fee_bps: Mapped[int] = mapped_column(Integer, default=500, nullable=False)  # 5%
    deadline_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
