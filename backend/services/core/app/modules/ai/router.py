"""روتر AI — /v1/ai/..."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import CurrentUser, get_current_user
from app.modules.ai import service
from app.modules.ai.schemas import (
    AiMessageOut, ChatRequest, ConversationCreate, ConversationOut,
)

router = APIRouter(prefix="/v1/ai", tags=["ai"])


@router.post("/conversations", response_model=ConversationOut, status_code=201)
async def create_conversation(
    data: ConversationCreate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> ConversationOut:
    conv = await service.create_conversation(db, earth_id=user.earth_id, data=data)
    return ConversationOut.model_validate(conv, from_attributes=True)


@router.get("/conversations", response_model=list[ConversationOut])
async def my_conversations(
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[ConversationOut]:
    convs = await service.my_conversations(db, user.earth_id)
    return [ConversationOut.model_validate(c, from_attributes=True) for c in convs]


@router.post("/conversations/{conversation_id}/chat", response_model=AiMessageOut)
async def chat(
    conversation_id: uuid.UUID,
    data: ChatRequest,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> AiMessageOut:
    msg = await service.chat(db, conversation_id=conversation_id, earth_id=user.earth_id, data=data)
    return AiMessageOut.model_validate(msg, from_attributes=True)


@router.get("/conversations/{conversation_id}/history", response_model=list[AiMessageOut])
async def history(
    conversation_id: uuid.UUID,
    limit: int = Query(default=50, le=200),
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[AiMessageOut]:
    msgs = await service.history(db, conversation_id, user.earth_id, limit=limit)
    return [AiMessageOut.model_validate(m, from_attributes=True) for m in msgs]
