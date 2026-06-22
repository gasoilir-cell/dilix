"""روتر Messaging — /v1/messaging/..."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import CurrentUser, get_current_user
from app.modules.messaging import service
from app.modules.messaging.schemas import MessageOut, MessageSend, RoomCreate, RoomOut

router = APIRouter(prefix="/v1/messaging", tags=["messaging"])


@router.post("/rooms", response_model=RoomOut, status_code=201)
async def create_room(
    data: RoomCreate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> RoomOut:
    room = await service.create_room(db, creator_earth_id=user.earth_id, data=data)
    return RoomOut.model_validate(room, from_attributes=True)


@router.post("/rooms/{room_id}/messages", response_model=MessageOut, status_code=201)
async def send_message(
    room_id: uuid.UUID,
    data: MessageSend,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> MessageOut:
    msg = await service.send_message(db, room_id=room_id, sender_earth_id=user.earth_id, data=data)
    return MessageOut.model_validate(msg, from_attributes=True)


@router.get("/rooms/{room_id}/messages", response_model=list[MessageOut])
async def list_messages(
    room_id: uuid.UUID,
    limit: int = Query(default=50, le=200),
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[MessageOut]:
    msgs = await service.list_messages(db, room_id, user.earth_id, limit=limit)
    return [MessageOut.model_validate(m, from_attributes=True) for m in msgs]


@router.delete("/messages/{message_id}", response_model=MessageOut)
async def delete_message(
    message_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> MessageOut:
    msg = await service.delete_message(db, message_id, user.earth_id)
    return MessageOut.model_validate(msg, from_attributes=True)
