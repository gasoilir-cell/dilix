"""مدل ORM پیام‌رسان (schema: messaging، ADR-05).

E2EE: پیام‌های کاربر↔کاربر رمزنگاری‌شده‌اند (MLS/Signal-style)؛ سرور فقط
ciphertext نگه می‌دارد. کانالِ AI جدا و بدونِ E2EE است (ذخیره‌ی plaintext برای RAG).
"""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

ROOM_DIRECT = "direct"    # 1:1
ROOM_GROUP = "group"
ROOM_AI = "ai_chat"      # کانالِ AI — بدونِ E2EE

MSG_TEXT = "text"
MSG_FILE = "file"
MSG_VOICE = "voice"
MSG_SYSTEM = "system"


class MessageRoom(Base):
    __tablename__ = "message_room"
    __table_args__ = {"schema": "messaging"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    room_type: Mapped[str] = mapped_column(String(16), nullable=False)
    title: Mapped[str | None] = mapped_column(String(120), nullable=True)
    is_e2ee: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_by: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class RoomMember(Base):
    __tablename__ = "room_member"
    __table_args__ = {"schema": "messaging"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    room_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("messaging.message_room.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    member_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    joined_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class Message(Base):
    """پیام. برای E2EE: content = ciphertext (base64). برای AI: cleartext."""

    __tablename__ = "message"
    __table_args__ = {"schema": "messaging"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    room_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("messaging.message_room.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    sender_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    msg_type: Mapped[str] = mapped_column(String(16), default=MSG_TEXT, nullable=False)

    # برای E2EE → ciphertext؛ برای AI → cleartext
    content: Mapped[str] = mapped_column(Text, nullable=False)
    # مرجعِ فایل در MinIO (اختیاری)
    file_ref: Mapped[str | None] = mapped_column(String(512), nullable=True)

    is_e2ee: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    sent_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    edited_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
