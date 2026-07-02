"""Dilix — Messages Model"""
import uuid
from datetime import datetime, timezone
from sqlalchemy import (
    Boolean, Column, DateTime, Enum, ForeignKey,
    Integer, String, Text, Index,
)
from sqlalchemy.dialects.postgresql import UUID
from app.core.database import Base


def _now():
    return datetime.now(timezone.utc)


class MessageRoom(Base):
    __tablename__ = "message_rooms"

    id          = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    type        = Column(
        Enum("direct", "group", "system", name="room_type_enum"),
        nullable=False, default="direct"
    )
    name        = Column(String(200), nullable=True)   # for group rooms
    created_at  = Column(DateTime(timezone=True), nullable=False, default=_now)


class RoomMember(Base):
    __tablename__ = "room_members"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    room_id    = Column(UUID(as_uuid=True), ForeignKey("message_rooms.id"), nullable=False, index=True)
    user_id    = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    joined_at  = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("uq_room_member", "room_id", "user_id", unique=True),
    )


class Message(Base):
    __tablename__ = "messages"

    id          = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    room_id     = Column(UUID(as_uuid=True), ForeignKey("message_rooms.id"), nullable=False, index=True)
    sender_id   = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    content     = Column(Text, nullable=False)
    is_deleted  = Column(Boolean, default=False)
    created_at  = Column(DateTime(timezone=True), nullable=False, default=_now)
