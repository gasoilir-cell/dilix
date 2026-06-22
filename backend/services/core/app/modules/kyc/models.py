"""مدل ORM KYC — درخواست احرازِ هویت (schema: kyc، سند ۶).

KYC از سطح ۰ تا ۳ است:
  ۰ = ثبت‌نام ابتدایی (ایمیل/شماره تأییدشده)
  ۱ = هویتِ پایه (نام + ملی)
  ۲ = مدرکِ هویت (کارتِ ملی / پاسپورت)
  ۳ = تأییدِ بیومتریک یا حضوری

تغییر `kyc_level` روی EarthIdentity فقط از طریقِ تأییدِ KycRequest
توسطِ admin/moderator مجاز است.
"""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import DateTime, SmallInteger, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

STATUS_PENDING = "pending"
STATUS_IN_REVIEW = "in_review"
STATUS_APPROVED = "approved"
STATUS_REJECTED = "rejected"


class KycRequest(Base):
    __tablename__ = "kyc_request"
    __table_args__ = {"schema": "kyc"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    subject_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    requested_level: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    status: Mapped[str] = mapped_column(String(16), default=STATUS_PENDING, nullable=False)

    # مدارک: [{type: "national_id", file_ref: "...", ...}]
    documents: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)

    # تأییدکننده (regional_admin یا global_admin)
    reviewer_earth_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
