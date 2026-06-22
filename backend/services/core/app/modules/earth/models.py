"""مدل ORM Earth/Location — نقشهٔ ۳D، opt-in، fuzzing (schema: earth، ADR-06).

Privacy-by-design:
- موقعیتِ دقیق هرگز ذخیره نمی‌شود مگر با opt-in صریح.
- geo_precision: exact | district | city | region (پیش‌فرض: region).
- بزرگ‌نماییِ دقیق را VisibilitySettings (identity) کنترل می‌کند.
"""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, Float, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

PRECISION_EXACT = "exact"
PRECISION_DISTRICT = "district"
PRECISION_CITY = "city"
PRECISION_REGION = "region"


class LocationPin(Base):
    """آخرینِ موقعیتِ کاربر روی نقشه — بر اساسِ opt-in و precision."""

    __tablename__ = "location_pin"
    __table_args__ = {"schema": "earth"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, unique=True)

    # مختصاتِ fuzzedشده (نه دقیق) بر اساسِ geo_precision
    lat: Mapped[float] = mapped_column(Float, nullable=False)
    lon: Mapped[float] = mapped_column(Float, nullable=False)
    geo_precision: Mapped[str] = mapped_column(String(16), default=PRECISION_REGION, nullable=False)

    is_visible: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    country_code: Mapped[str | None] = mapped_column(String(4), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class PointOfInterest(Base):
    """نقطهٔ علاقه روی نقشه (کسب‌وکار، مخزنِ بار، ایستگاه)."""

    __tablename__ = "point_of_interest"
    __table_args__ = {"schema": "earth"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    category: Mapped[str] = mapped_column(String(64), nullable=False)  # warehouse|depot|office|...
    lat: Mapped[float] = mapped_column(Float, nullable=False)
    lon: Mapped[float] = mapped_column(Float, nullable=False)
    country_code: Mapped[str] = mapped_column(String(4), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
