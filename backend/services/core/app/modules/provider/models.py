"""مدل ORM ارائه‌دهندگان و API آن‌ها (سند ۳، schema: provider).

ستون فقرات Provider Adapter Framework (ADR-02): ثبت‌نام خودکار + KYB + Sandbox.
"""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Provider(Base):
    __tablename__ = "provider"
    __table_args__ = {"schema": "provider"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    legal_name: Mapped[str] = mapped_column(String(255), nullable=False)
    provider_type: Mapped[str] = mapped_column(String(32), nullable=False)  # insurer/carrier/psp/telecom/third_party
    country: Mapped[str] = mapped_column(String(8), nullable=False)
    license_no: Mapped[str | None] = mapped_column(String(128), nullable=True)
    kyb_status: Mapped[str] = mapped_column(String(16), default="pending", nullable=False)  # pending/verified/rejected
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    apis: Mapped[list["ProviderApi"]] = relationship(back_populates="provider")


class ProviderApi(Base):
    """API ای که خودِ ارائه‌دهنده در سیستم register می‌کند."""

    __tablename__ = "provider_api"
    __table_args__ = {"schema": "provider"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    provider_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("provider.provider.id", ondelete="CASCADE"), nullable=False
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    spec_url: Mapped[str | None] = mapped_column(String(512), nullable=True)  # OpenAPI spec
    env: Mapped[str] = mapped_column(String(16), default="sandbox", nullable=False)  # sandbox/prod
    status: Mapped[str] = mapped_column(String(16), default="draft", nullable=False)
    webhook_url: Mapped[str | None] = mapped_column(String(512), nullable=True)

    provider: Mapped[Provider] = relationship(back_populates="apis")
