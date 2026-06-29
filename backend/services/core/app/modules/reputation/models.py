"""مدل ORM اعتبار (schema: reputation، سند ۳).

هر کاربر در هر دامنه (logistics, financial, social, trust) امتیاز جداگانه دارد.
امتیاز به تراکنش‌های واقعی گره خورده است — نه تعامل ساده.
"""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

# دامنه‌های امتیاز
DOMAIN_LOGISTICS = "logistics"    # بار و حمل
DOMAIN_FINANCIAL = "financial"   # تراکنش مالی
DOMAIN_SOCIAL = "social"         # تعامل اجتماعی
DOMAIN_TRUST = "trust"           # امتیاز کلی اعتماد


class ReputationScore(Base):
    """امتیاز تجمیعی هر کاربر در هر دامنه (upsert-friendly)."""

    __tablename__ = "reputation_score"
    __table_args__ = (
        CheckConstraint("score >= 0 AND score <= 1000", name="ck_rep_score_range"),
        {"schema": "reputation"},
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    domain: Mapped[str] = mapped_column(String(32), nullable=False)
    # امتیاز ۰–۱۰۰۰ (مقیاس‌بندی درونی؛ به کاربر ÷۱۰ نشان داده می‌شود)
    score: Mapped[int] = mapped_column(Integer, default=500, nullable=False)
    review_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class Review(Base):
    """نظر و امتیاز پس از تراکنش واقعی."""

    __tablename__ = "review"
    __table_args__ = (
        CheckConstraint("rating >= 1 AND rating <= 5", name="ck_review_rating"),
        {"schema": "reputation"},
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    # کاربری که امتیاز گرفته
    reviewee_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    # کاربری که امتیاز داده
    reviewer_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    domain: Mapped[str] = mapped_column(String(32), nullable=False)
    # مرجع تراکنشی که این نظر به آن تعلق دارد (cargo_post_id, payment_order_id, ...)
    transaction_ref: Mapped[str] = mapped_column(String(128), nullable=False)
    rating: Mapped[int] = mapped_column(Integer, nullable=False)
    comment: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
