"""جدول Outbox — انتشار اتمیک رویداد (Transactional Outbox، سند ۴).

رویداد در همان تراکنشِ تغییرِ دامنه در این جدول نوشته می‌شود؛ سپس یک relay
جداگانه (`app/core/relay.py`) آن را به NATS JetStream می‌فرستد. این تضمین می‌کند
که «تغییر state» و «انتشار رویداد» هرگز از هم جدا نمی‌افتند (no dual-write).
"""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import DateTime, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

# وضعیت‌های ردیف outbox
STATUS_PENDING = "pending"
STATUS_PUBLISHED = "published"
STATUS_DEAD = "dead"  # پس از عبور از سقفِ تلاش → DLQ


class OutboxEvent(Base):
    """یک رویدادِ منتظرِ انتشار. در schema جدا تا با دامنه قاطی نشود."""

    __tablename__ = "outbox_event"
    __table_args__ = {"schema": "events"}

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    schema_version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    region: Mapped[str | None] = mapped_column(String(8), nullable=True)
    correlation_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    payload: Mapped[dict] = mapped_column(JSONB, nullable=False)

    status: Mapped[str] = mapped_column(String(16), default=STATUS_PENDING, nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)

    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
