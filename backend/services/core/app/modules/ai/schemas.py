from __future__ import annotations
import uuid
from datetime import datetime
from pydantic import BaseModel, Field


class ConversationCreate(BaseModel):
    agent_type: str = Field(
        default="personal",
        pattern="^(personal|freight|insurance|financial)$",
    )
    title: str | None = Field(default=None, max_length=200)


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=8000)


class ConversationOut(BaseModel):
    id: uuid.UUID
    agent_type: str
    title: str | None
    created_at: datetime
    model_config = {"from_attributes": True}


class AiMessageOut(BaseModel):
    id: uuid.UUID
    conversation_id: uuid.UUID
    role: str
    content: str
    tool_calls: list
    sent_at: datetime
    model_config = {"from_attributes": True}
