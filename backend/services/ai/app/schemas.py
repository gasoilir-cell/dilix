"""قراردادِ HTTP بینِ dilix-core و dilix-ai-service.

این قرارداد دقیقاً با `app/modules/ai/langgraph_client.py` در سرویسِ Core هم‌خوان است.
"""
from __future__ import annotations

from pydantic import BaseModel, Field

from app.agents import ALL_AGENTS

_AGENT_PATTERN = "^(" + "|".join(ALL_AGENTS) + ")$"


class ChatMessage(BaseModel):
    role: str = Field(pattern="^(user|assistant|system|tool)$")
    content: str


class InvokeRequest(BaseModel):
    agent_type: str = Field(default="personal", pattern=_AGENT_PATTERN)
    conversation_id: str
    earth_id: str
    system_prompt: str = ""
    history: list[ChatMessage] = Field(default_factory=list)
    message: str = Field(min_length=1, max_length=8000)


class ToolCall(BaseModel):
    name: str
    arguments: dict = Field(default_factory=dict)
    result: dict | None = None


class InvokeResponse(BaseModel):
    reply: str
    tool_calls: list[ToolCall] = Field(default_factory=list)
    metadata: dict = Field(default_factory=dict)
