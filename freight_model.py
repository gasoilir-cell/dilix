"""
Dilix — مدل حمل بار (CargoPost)
"""
import uuid
from datetime import datetime, timezone
from sqlalchemy import (
    BigInteger, Boolean, Column, DateTime, Enum,
    Float, ForeignKey, Integer, String, Text,
)
from sqlalchemy.dialects.postgresql import UUID

from app.core.database import Base


def _now():
    return datetime.now(timezone.utc)


class CargoPost(Base):
    __tablename__ = "cargo_posts"

    id          = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    ref         = Column(String(20), unique=True, nullable=False, index=True)
    # FRT-XXXXXXXX

    # صاحب بار
    owner_id    = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)

    # اطلاعات مبدأ / مقصد
    origin       = Column(String(500), nullable=False)
    origin_lat   = Column(Float, nullable=True)
    origin_lng   = Column(Float, nullable=True)
    destination  = Column(String(500), nullable=False)
    dest_lat     = Column(Float, nullable=True)
    dest_lng     = Column(Float, nullable=True)

    # جزئیات بار
    cargo_type   = Column(String(100), nullable=False)
    weight_kg    = Column(Float, nullable=False)
    description  = Column(Text, nullable=True)
    price        = Column(BigInteger, nullable=False)   # ریال

    # وضعیت
    status       = Column(
        Enum("open", "in_progress", "delivered", "cancelled", name="cargo_status_enum"),
        default="open", nullable=False, index=True,
    )

    # راننده پذیرفته‌شده
    driver_id    = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)

    pickup_date  = Column(DateTime(timezone=True), nullable=True)
    created_at   = Column(DateTime(timezone=True), default=_now, nullable=False)
    updated_at   = Column(DateTime(timezone=True), default=_now, onupdate=_now, nullable=False)
