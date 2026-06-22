"""مدل ORM هویت — Earth ID و پروفایل‌ها (سند ۳، schema: identity).

Aggregate Root: EarthIdentity. Invariant: تغییر kyc_level فقط با مدرک تأییدشده
(در لایه‌ی service اعمال می‌شود).
"""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, SmallInteger, String, func
from sqlalchemy.dialects.postgresql import ARRAY, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class EarthIdentity(Base):
    __tablename__ = "earth_identity"
    __table_args__ = {"schema": "identity"}

    earth_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    entity_type: Mapped[str] = mapped_column(String(32), nullable=False)
    status: Mapped[str] = mapped_column(String(16), default="active", nullable=False)
    kyc_level: Mapped[int] = mapped_column(SmallInteger, default=0, nullable=False)
    home_region: Mapped[str] = mapped_column(String(8), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    profile: Mapped["Profile"] = relationship(back_populates="identity", uselist=False)
    visibility: Mapped["VisibilitySettings"] = relationship(
        back_populates="identity", uselist=False
    )


class Profile(Base):
    __tablename__ = "profile"
    __table_args__ = {"schema": "identity"}

    earth_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("identity.earth_identity.earth_id", ondelete="CASCADE"),
        primary_key=True,
    )
    display_name: Mapped[str] = mapped_column(String(120), nullable=False)
    gender: Mapped[str | None] = mapped_column(String(16), nullable=True)
    birth_date: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    marital_status: Mapped[str | None] = mapped_column(String(16), nullable=True)
    # شغل (افراد) یا دسته‌ی کسب‌وکار (سازمان‌ها) — برای فیلترِ Discovery
    profession: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    languages: Mapped[list[str]] = mapped_column(ARRAY(String), default=list)
    interests: Mapped[list[str]] = mapped_column(ARRAY(String), default=list)
    bio: Mapped[str | None] = mapped_column(String(500), nullable=True)
    avatar_url: Mapped[str | None] = mapped_column(String(512), nullable=True)

    identity: Mapped[EarthIdentity] = relationship(back_populates="profile")


class VisibilitySettings(Base):
    """تنظیمات دیده‌شدن روی نقشه (ADR-06: opt-in + fuzzing). پیش‌فرض: خاموش."""

    __tablename__ = "visibility_settings"
    __table_args__ = {"schema": "identity"}

    earth_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("identity.earth_identity.earth_id", ondelete="CASCADE"),
        primary_key=True,
    )
    discoverable: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    audience: Mapped[str] = mapped_column(String(16), default="connections", nullable=False)
    geo_precision: Mapped[str] = mapped_column(String(8), default="region", nullable=False)
    visible_fields: Mapped[list[str]] = mapped_column(ARRAY(String), default=list)

    identity: Mapped[EarthIdentity] = relationship(back_populates="visibility")
