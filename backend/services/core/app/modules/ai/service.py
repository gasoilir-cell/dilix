"""سرویس AI — مدیریتِ مکالمه و ارسالِ پیام به agent.

در M3 این ماژول رابطِ بینِ API و موتورِ LangGraph است. LangGraph به‌عنوانِ
سرویسِ مستقل (dilix-ai-service) اجرا می‌شود و از طریقِ HTTP فراخوانده می‌شود.
با تنظیم DILIX_AI_SERVICE_URL اتصال واقعی برقرار می‌شود؛ در غیر این صورت stub.
"""
from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.errors import ForbiddenError, NotFoundError

from app.modules.ai.langgraph_client import invoke_agent
from app.modules.ai.models import ROLE_ASSISTANT, ROLE_USER, AiConversation, AiMessage
from app.modules.ai.schemas import ChatRequest, ConversationCreate


async def create_conversation(
    db: AsyncSession, *, earth_id: uuid.UUID, data: ConversationCreate
) -> AiConversation:
    conv = AiConversation(
        earth_id=earth_id,
        agent_type=data.agent_type,
        title=data.title,
    )
    db.add(conv)
    await db.flush()
    return conv


async def chat(
    db: AsyncSession,
    *,
    conversation_id: uuid.UUID,
    earth_id: uuid.UUID,
    data: ChatRequest,
) -> AiMessage:
    conv = await db.get(AiConversation, conversation_id)
    if conv is None:
        raise NotFoundError("مکالمه یافت نشد.")
    if conv.earth_id != earth_id:
        raise ForbiddenError("دسترسی مجاز نیست.")

    user_msg = AiMessage(
        conversation_id=conversation_id, role=ROLE_USER, content=data.message
    )
    db.add(user_msg)
    await db.flush()

    # بارگذاری تاریخچه (آخرین ۲۰ پیام)
    history_rows = await db.execute(
        select(AiMessage)
        .where(AiMessage.conversation_id == conversation_id)
        .order_by(AiMessage.sent_at.desc())
        .limit(20)
    )
    hist = [
        {"role": m.role, "content": m.content}
        for m in reversed(history_rows.scalars().all())
    ]

    reply_content = await invoke_agent(
        agent_type=conv.agent_type,
        conversation_id=str(conversation_id),
        earth_id=str(earth_id),
        history=hist,
        user_message=data.message,
    )

    assistant_msg = AiMessage(
        conversation_id=conversation_id,
        role=ROLE_ASSISTANT,
        content=reply_content,
    )
    db.add(assistant_msg)
    await db.flush()
    return assistant_msg


async def history(
    db: AsyncSession, conversation_id: uuid.UUID, earth_id: uuid.UUID, limit: int = 50
) -> list[AiMessage]:
    conv = await db.get(AiConversation, conversation_id)
    if conv is None:
        raise NotFoundError("مکالمه یافت نشد.")
    if conv.earth_id != earth_id:
        raise ForbiddenError("دسترسی مجاز نیست.")
    result = await db.execute(
        select(AiMessage)
        .where(AiMessage.conversation_id == conversation_id)
        .order_by(AiMessage.sent_at.asc())
        .limit(limit)
    )
    return list(result.scalars().all())


async def my_conversations(
    db: AsyncSession, earth_id: uuid.UUID
) -> list[AiConversation]:
    result = await db.execute(
        select(AiConversation)
        .where(AiConversation.earth_id == earth_id)
        .order_by(AiConversation.created_at.desc())
    )
    return list(result.scalars().all())
