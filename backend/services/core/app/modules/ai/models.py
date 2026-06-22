"""مدل ORM دستیارِ هوشِ مصنوعی — مکالمه و حافظهٔ RAG (schema: ai، ADR-05).

کانالِ AI جدا از پیام‌رسانِ E2EE است (ADR-05). محتوای cleartext در این جدول
ذخیره می‌شود تا RAG و fine-tuning امکان‌پذیر باشد.
"""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import DateTime, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

ROLE_USER = "user"
ROLE_ASSISTANT = "assistant"
ROLE_SYSTEM = "system"

AGENT_PERSONAL = "personal"       # دستیارِ شخصی
AGENT_FREIGHT = "freight"         # دستیارِ لجستیک
AGENT_INSURANCE = "insurance"     # دستیارِ بیمه
AGENT_FINANCIAL = "financial"     # دستیارِ مالی


class AiConversation(Base):
    """مکالمه‌ی AI با یک کاربر (یک session)."""

    __tablename__ = "ai_conversation"
    __table_args__ = {"schema": "ai"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    agent_type: Mapped[str] = mapped_column(String(32), default=AGENT_PERSONAL, nullable=False)
    title: Mapped[str | None] = mapped_column(String(200), nullable=True)
    meta: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class AiMessage(Base):
    """یک پیام در مکالمهٔ AI (cleartext برای RAG)."""

    __tablename__ = "ai_message"
    __table_args__ = {"schema": "ai"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    conversation_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    role: Mapped[str] = mapped_column(String(16), nullable=False)   # user | assistant | system
    content: Mapped[str] = mapped_column(Text, nullable=False)
    # ابزارهایی که agent فراخواند (MCP tool calls)
    tool_calls: Mapped[dict] = mapped_column(JSONB, default=list, nullable=False)
    tokens_used: Mapped[int | None] = mapped_column(nullable=True)
    sent_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
