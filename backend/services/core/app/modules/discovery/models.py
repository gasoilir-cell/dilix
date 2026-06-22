"""مدل ORM Discovery — درخواستِ تماس بینِ افرادِ کشف‌شده (schema: discovery)."""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import DateTime, String, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

CONTACT_PENDING = "pending"
CONTACT_ACCEPTED = "accepted"
CONTACT_DECLINED = "declined"


class ContactRequest(Base):
    """درخواستِ شروعِ گفتگو با فردی که از طریقِ Discovery پیدا شده."""

    __tablename__ = "contact_request"
    __table_args__ = (
        # هر فرستنده فقط یک درخواستِ فعال به هر گیرنده
        UniqueConstraint("requester_earth_id", "target_earth_id", name="uq_contact_pair"),
        {"schema": "discovery"},
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    requester_earth_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), nullable=False, index=True
    )
    target_earth_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), nullable=False, index=True
    )
    message: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(String(16), default=CONTACT_PENDING, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    responded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
