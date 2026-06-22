from __future__ import annotations
import uuid
from datetime import datetime
from pydantic import BaseModel, Field


class RoomCreate(BaseModel):
    room_type: str = Field(default="direct", pattern="^(direct|group|ai_chat)$")
    title: str | None = Field(default=None, max_length=120)
    member_ids: list[uuid.UUID] = Field(default_factory=list)


class MessageSend(BaseModel):
    content: str = Field(min_length=1)
    msg_type: str = Field(default="text", pattern="^(text|file|voice|system)$")
    file_ref: str | None = None


class RoomOut(BaseModel):
    id: uuid.UUID
    room_type: str
    title: str | None
    is_e2ee: bool
    created_by: uuid.UUID
    model_config = {"from_attributes": True}


class MessageOut(BaseModel):
    id: uuid.UUID
    room_id: uuid.UUID
    sender_earth_id: uuid.UUID
    msg_type: str
    content: str
    file_ref: str | None
    is_e2ee: bool
    sent_at: datetime
    deleted: bool
    model_config = {"from_attributes": True}
