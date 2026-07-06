"""Dilix — Messages Model"""
import uuid
from datetime import datetime, timezone
from sqlalchemy import (
    Boolean, Column, DateTime, Enum, Float, ForeignKey,
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
    avatar_url  = Column(String(500), nullable=True)   # group avatar
    created_by  = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)  # group owner/admin
    created_at  = Column(DateTime(timezone=True), nullable=False, default=_now)


class RoomMember(Base):
    __tablename__ = "room_members"

    id           = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    room_id      = Column(UUID(as_uuid=True), ForeignKey("message_rooms.id"), nullable=False, index=True)
    user_id      = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    joined_at    = Column(DateTime(timezone=True), nullable=False, default=_now)
    last_read_at = Column(DateTime(timezone=True), nullable=True)   # read-receipt cursor
    muted_until  = Column(DateTime(timezone=True), nullable=True)   # بی‌صداییِ اعلان تا این زمان (null = فعال)
    cleared_at   = Column(DateTime(timezone=True), nullable=True)   # پاک‌سازیِ گفتگو: پیام‌های قبل از این برایِ من پنهان

    __table_args__ = (
        Index("uq_room_member", "room_id", "user_id", unique=True),
    )


class Message(Base):
    __tablename__ = "messages"

    id          = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    room_id     = Column(UUID(as_uuid=True), ForeignKey("message_rooms.id"), nullable=False, index=True)
    sender_id   = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    content     = Column(Text, nullable=False)
    reply_to_id = Column(UUID(as_uuid=True), ForeignKey("messages.id", ondelete="SET NULL"), nullable=True)
    is_deleted  = Column(Boolean, default=False)
    edited_at   = Column(DateTime(timezone=True), nullable=True)
    media_url   = Column(String(500), nullable=True)   # image/voice/file URL
    media_type  = Column(String(32), nullable=True)    # image | voice | file | location | live_location
    media_name  = Column(String(300), nullable=True)   # original filename (files)
    media_meta  = Column(String(200), nullable=True)   # size / duration hint
    sticker_id  = Column(UUID(as_uuid=True), nullable=True)   # link to sticker library
    loc_lat     = Column(Float, nullable=True)         # location latitude
    loc_lng     = Column(Float, nullable=True)         # location longitude
    loc_label   = Column(String(200), nullable=True)   # optional place label
    live_expires_at = Column(DateTime(timezone=True), nullable=True)  # live-location end time
    live_updated_at = Column(DateTime(timezone=True), nullable=True)  # last position update
    is_forwarded   = Column(Boolean, default=False)   # forwarded message (attributed)
    forwarded_from = Column(String(120), nullable=True)  # original sender display name (None = anonymous)
    pinned_at   = Column(DateTime(timezone=True), nullable=True)  # سنجاق: زمانِ سنجاق (null = بدونِ سنجاق)
    pinned_by   = Column(UUID(as_uuid=True), nullable=True)       # سنجاق: کاربرِ سنجاق‌کننده
    created_at  = Column(DateTime(timezone=True), nullable=False, default=_now)


class MessageReaction(Base):
    __tablename__ = "message_reactions"

    id          = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    message_id  = Column(UUID(as_uuid=True), ForeignKey("messages.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id     = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    emoji       = Column(String(16), nullable=False)
    created_at  = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        # one reaction (emoji) per user per message — tap again to toggle a different emoji
        Index("uq_reaction", "message_id", "user_id", unique=True),
    )


class MessageTranslation(Base):
    """کشِ ترجمهٔ پیام‌ها به هر زبانِ مقصد (یک ردیف به‌ازای message+target_lang)."""
    __tablename__ = "message_translations"

    id              = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    message_id      = Column(UUID(as_uuid=True), ForeignKey("messages.id", ondelete="CASCADE"), nullable=False, index=True)
    target_lang     = Column(String(8), nullable=False)
    translated_text = Column(Text, nullable=False)
    detected_lang   = Column(String(8), nullable=True)
    created_at      = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("uq_msg_translation", "message_id", "target_lang", unique=True),
    )


class MessagePoll(Base):
    """نظرسنجی پیوست‌شده به یک پیام (media_type='poll'). گزینه‌ها JSON آرایه‌ای از رشته‌ها."""
    __tablename__ = "message_polls"

    id          = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    message_id  = Column(UUID(as_uuid=True), ForeignKey("messages.id", ondelete="CASCADE"), nullable=False, index=True)
    question    = Column(String(300), nullable=False)
    options     = Column(Text, nullable=False)                 # JSON: ["گزینه ۱", ...]
    multiple    = Column(Boolean, default=False)               # اجازهٔ چند‌انتخابی
    created_at  = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("uq_poll_message", "message_id", unique=True),
    )


class PollVote(Base):
    """رأیِ یک کاربر به یک گزینه از نظرسنجی (یک ردیف به‌ازای poll+user+option)."""
    __tablename__ = "poll_votes"

    id           = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    poll_id      = Column(UUID(as_uuid=True), ForeignKey("message_polls.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id      = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    option_index = Column(Integer, nullable=False)
    created_at   = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("uq_poll_vote", "poll_id", "user_id", "option_index", unique=True),
    )


class UserBlock(Base):
    """مسدودسازیِ کاربر: blocker کاربرِ blocked را مسدود کرده (یک‌طرفه، یکتا)."""
    __tablename__ = "user_blocks"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    blocker_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    blocked_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("uq_user_block", "blocker_id", "blocked_id", unique=True),
    )
