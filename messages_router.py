"""
Dilix — Messages Router
GET  /api/v1/messages/rooms            لیست مکالمات
POST /api/v1/messages/rooms            شروع مکالمه جدید (با earth_id)
GET  /api/v1/messages/rooms/{id}       اطلاعات اتاق
GET  /api/v1/messages/rooms/{id}/messages   تاریخچه پیام‌ها
POST /api/v1/messages/rooms/{id}/messages   ارسال پیام
"""
import uuid as _uuid
from datetime import datetime, timezone
from typing import Optional, List

from fastapi import APIRouter, Depends, HTTPException, status, Query
from pydantic import BaseModel, Field
from sqlalchemy import select, and_, or_, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.messages import MessageRoom, RoomMember, Message

router = APIRouter(prefix="/messages", tags=["Messages"])


# ── Schemas ───────────────────────────────────────────────────
class RoomOut(BaseModel):
    id: str
    type: str
    name: Optional[str]
    partner_name: Optional[str]
    partner_earth_id: Optional[str]
    partner_role: Optional[str]
    partner_avatar: Optional[str]
    last_message: Optional[str]
    last_message_at: Optional[datetime]
    unread_count: int
    created_at: datetime


class MessageOut(BaseModel):
    id: str
    sender_id: str
    sender_name: Optional[str]
    sender_earth_id: Optional[str]
    content: str
    is_mine: bool
    created_at: datetime


class StartRoomRequest(BaseModel):
    earth_id: str = Field(..., description="Earth ID طرف مقابل (DLX-XXXXXXXX)")


class SendMessageRequest(BaseModel):
    content: str = Field(..., min_length=1, max_length=4000)


# ── Helpers ───────────────────────────────────────────────────
async def _get_or_create_direct_room(
    db: AsyncSession, user_a_id, user_b_id
) -> MessageRoom:
    """اتاق direct بین دو کاربر را پیدا یا می‌سازد"""
    # find rooms where both are members
    q = (
        select(RoomMember.room_id)
        .where(RoomMember.user_id == user_a_id)
    )
    r = await db.execute(q)
    rooms_a = set(str(row[0]) for row in r.all())

    q2 = (
        select(RoomMember.room_id)
        .where(RoomMember.user_id == user_b_id)
    )
    r2 = await db.execute(q2)
    rooms_b = set(str(row[0]) for row in r2.all())

    common = rooms_a & rooms_b
    if common:
        room_id = _uuid.UUID(next(iter(common)))
        room = await db.get(MessageRoom, room_id)
        if room and room.type == "direct":
            return room

    # create new direct room
    room = MessageRoom(type="direct")
    db.add(room)
    await db.flush()

    db.add(RoomMember(room_id=room.id, user_id=user_a_id))
    db.add(RoomMember(room_id=room.id, user_id=user_b_id))
    await db.commit()
    await db.refresh(room)
    return room


# ── Endpoints ─────────────────────────────────────────────────

@router.get("/rooms", response_model=List[RoomOut])
async def list_rooms(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """لیست تمام اتاق‌های من با آخرین پیام"""
    # get my rooms
    q = select(RoomMember.room_id).where(RoomMember.user_id == me.id)
    r = await db.execute(q)
    room_ids = [row[0] for row in r.all()]

    if not room_ids:
        return []

    rooms_q = select(MessageRoom).where(MessageRoom.id.in_(room_ids))
    rooms_r = await db.execute(rooms_q)
    rooms = rooms_r.scalars().all()

    result = []
    for room in rooms:
        # find partner (for direct rooms)
        partner = None
        partner_name = None
        partner_earth_id = None
        partner_role = None
        partner_avatar = None

        if room.type == "direct":
            members_q = (
                select(User)
                .join(RoomMember, RoomMember.user_id == User.id)
                .where(
                    and_(
                        RoomMember.room_id == room.id,
                        User.id != me.id
                    )
                )
            )
            members_r = await db.execute(members_q)
            partner = members_r.scalar_one_or_none()
            if partner:
                partner_name = partner.full_name or partner.username or partner.earth_id
                partner_earth_id = partner.earth_id
                partner_role = partner.role
                partner_avatar = partner.avatar_url

        # last message
        last_msg_q = (
            select(Message)
            .where(and_(Message.room_id == room.id, Message.is_deleted == False))
            .order_by(Message.created_at.desc())
            .limit(1)
        )
        last_r = await db.execute(last_msg_q)
        last_msg = last_r.scalar_one_or_none()

        # unread count (messages not by me, created after "last seen" — simplified)
        unread_q = (
            select(func.count(Message.id))
            .where(
                and_(
                    Message.room_id == room.id,
                    Message.sender_id != me.id,
                    Message.is_deleted == False,
                )
            )
        )
        unread_r = await db.execute(unread_q)
        unread_count = unread_r.scalar_one_or_none() or 0

        result.append(RoomOut(
            id=str(room.id),
            type=room.type,
            name=room.name,
            partner_name=partner_name,
            partner_earth_id=partner_earth_id,
            partner_role=partner_role,
            partner_avatar=partner_avatar,
            last_message=last_msg.content[:80] if last_msg else None,
            last_message_at=last_msg.created_at if last_msg else None,
            unread_count=unread_count,
            created_at=room.created_at,
        ))

    return sorted(result, key=lambda r: r.last_message_at or r.created_at, reverse=True)


@router.post("/rooms", response_model=RoomOut, status_code=status.HTTP_201_CREATED)
async def start_or_get_room(
    body: StartRoomRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """شروع مکالمه با یک کاربر دیگر (یا بازگشت اتاق موجود)"""
    if body.earth_id == me.earth_id:
        raise HTTPException(status_code=400, detail="نمی‌توانید با خودتان مکالمه داشته باشید")

    user_q = select(User).where(User.earth_id == body.earth_id)
    user_r = await db.execute(user_q)
    partner = user_r.scalar_one_or_none()
    if not partner:
        raise HTTPException(status_code=404, detail="کاربر پیدا نشد")

    room = await _get_or_create_direct_room(db, me.id, partner.id)

    return RoomOut(
        id=str(room.id),
        type=room.type,
        name=room.name,
        partner_name=partner.full_name or partner.username or partner.earth_id,
        partner_earth_id=partner.earth_id,
        partner_role=partner.role,
        partner_avatar=partner.avatar_url,
        last_message=None,
        last_message_at=None,
        unread_count=0,
        created_at=room.created_at,
    )


@router.get("/rooms/{room_id}/messages", response_model=List[MessageOut])
async def get_messages(
    room_id: str,
    limit: int = Query(50, le=100),
    before: Optional[str] = Query(None, description="cursor: message id"),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """تاریخچه پیام‌های یک اتاق"""
    # verify membership
    mem_q = select(RoomMember).where(
        and_(
            RoomMember.room_id == _uuid.UUID(room_id),
            RoomMember.user_id == me.id
        )
    )
    mem_r = await db.execute(mem_q)
    if not mem_r.scalar_one_or_none():
        raise HTTPException(status_code=403, detail="دسترسی ندارید")

    q = (
        select(Message, User.full_name, User.username, User.earth_id)
        .join(User, User.id == Message.sender_id)
        .where(
            and_(
                Message.room_id == _uuid.UUID(room_id),
                Message.is_deleted == False,
            )
        )
        .order_by(Message.created_at.desc())
        .limit(limit)
    )
    if before:
        pivot = await db.get(Message, _uuid.UUID(before))
        if pivot:
            q = q.where(Message.created_at < pivot.created_at)

    r = await db.execute(q)
    rows = r.all()

    msgs = []
    for msg, full_name, username, earth_id in reversed(rows):
        msgs.append(MessageOut(
            id=str(msg.id),
            sender_id=str(msg.sender_id),
            sender_name=full_name or username or earth_id,
            sender_earth_id=earth_id,
            content=msg.content,
            is_mine=msg.sender_id == me.id,
            created_at=msg.created_at,
        ))
    return msgs


@router.post("/rooms/{room_id}/messages", response_model=MessageOut, status_code=status.HTTP_201_CREATED)
async def send_message(
    room_id: str,
    body: SendMessageRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ارسال پیام"""
    mem_q = select(RoomMember).where(
        and_(
            RoomMember.room_id == _uuid.UUID(room_id),
            RoomMember.user_id == me.id
        )
    )
    mem_r = await db.execute(mem_q)
    if not mem_r.scalar_one_or_none():
        raise HTTPException(status_code=403, detail="دسترسی ندارید")

    msg = Message(
        room_id=_uuid.UUID(room_id),
        sender_id=me.id,
        content=body.content,
    )
    db.add(msg)
    await db.commit()
    await db.refresh(msg)

    return MessageOut(
        id=str(msg.id),
        sender_id=str(msg.sender_id),
        sender_name=me.full_name or me.username or me.earth_id,
        sender_earth_id=me.earth_id,
        content=msg.content,
        is_mine=True,
        created_at=msg.created_at,
    )
