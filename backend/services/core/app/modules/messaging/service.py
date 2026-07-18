"""سرویس پیام‌رسان. WebSocket/WebRTC realtime در لایه‌ی Gateway جداگانه است."""
from __future__ import annotations

import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.errors import ForbiddenError, NotFoundError
from dilix_shared.events import DomainEvent

from app.core.events import publisher
from app.modules.messaging.models import (
    ROOM_AI, Message, MessageRoom, RoomMember,
)
from app.modules.messaging.schemas import MessageSend, RoomCreate


async def create_room(
    db: AsyncSession, *, creator_earth_id: uuid.UUID, data: RoomCreate
) -> MessageRoom:
    is_e2ee = data.room_type != ROOM_AI
    room = MessageRoom(
        room_type=data.room_type,
        title=data.title,
        is_e2ee=is_e2ee,
        created_by=creator_earth_id,
    )
    db.add(room)
    await db.flush()

    # افزودنِ سازنده و سایرِ اعضا
    all_members = list({creator_earth_id} | set(data.member_ids))
    for mid in all_members:
        db.add(RoomMember(room_id=room.id, member_earth_id=mid))
    await db.flush()
    return room


async def list_rooms(
    db: AsyncSession, actor_earth_id: uuid.UUID, limit: int = 100
) -> list[MessageRoom]:
    """اتاق‌هایی که کاربر عضوِ آن‌هاست، مرتب‌شده بر اساسِ جدیدترین فعالیت
    (آخرین پیام؛ در نبودِ پیام، زمانِ ساختِ اتاق)."""
    last_msg = (
        select(
            Message.room_id.label("room_id"),
            func.max(Message.sent_at).label("last_at"),
        )
        .group_by(Message.room_id)
        .subquery()
    )
    result = await db.execute(
        select(MessageRoom)
        .join(RoomMember, RoomMember.room_id == MessageRoom.id)
        .outerjoin(last_msg, last_msg.c.room_id == MessageRoom.id)
        .where(RoomMember.member_earth_id == actor_earth_id)
        .order_by(func.coalesce(last_msg.c.last_at, MessageRoom.created_at).desc())
        .limit(limit)
    )
    return list(result.scalars().all())


async def _assert_member(db: AsyncSession, room_id: uuid.UUID, earth_id: uuid.UUID) -> None:
    res = await db.execute(
        select(RoomMember).where(
            RoomMember.room_id == room_id,
            RoomMember.member_earth_id == earth_id,
        )
    )
    if res.scalars().first() is None:
        raise ForbiddenError("شما عضوِ این اتاق نیستید.")


async def send_message(
    db: AsyncSession,
    *,
    room_id: uuid.UUID,
    sender_earth_id: uuid.UUID,
    data: MessageSend,
) -> Message:
    room = await db.get(MessageRoom, room_id)
    if room is None:
        raise NotFoundError("اتاق یافت نشد.")
    await _assert_member(db, room_id, sender_earth_id)

    msg = Message(
        room_id=room_id,
        sender_earth_id=sender_earth_id,
        msg_type=data.msg_type,
        content=data.content,
        file_ref=data.file_ref,
        is_e2ee=room.is_e2ee,
    )
    db.add(msg)
    await db.flush()
    await publisher.publish(
        db,
        DomainEvent(
            name="messaging.MessageSent",
            payload={"message_id": str(msg.id), "room_id": str(room_id)},
        ),
    )
    return msg


async def list_messages(
    db: AsyncSession, room_id: uuid.UUID, actor_earth_id: uuid.UUID, limit: int = 50
) -> list[Message]:
    await _assert_member(db, room_id, actor_earth_id)
    result = await db.execute(
        select(Message)
        .where(Message.room_id == room_id, Message.deleted.is_(False))
        .order_by(Message.sent_at.desc())
        .limit(limit)
    )
    return list(result.scalars().all())


async def delete_message(
    db: AsyncSession, message_id: uuid.UUID, actor_earth_id: uuid.UUID
) -> Message:
    msg = await db.get(Message, message_id)
    if msg is None:
        raise NotFoundError("پیام یافت نشد.")
    if msg.sender_earth_id != actor_earth_id:
        raise ForbiddenError("فقط فرستنده می‌تواند پیامِ خود را حذف کند.")
    msg.deleted = True
    await db.flush()
    return msg
