"""نقطه‌ی ورودِ dilix-ai-service — LangGraph Supervisor runtime (سند ۸).

این سرویس قراردادِ `POST /v1/invoke` را که dilix-core انتظار دارد پیاده می‌کند:
  درخواست:  {agent_type, conversation_id, earth_id, system_prompt, history, message}
  پاسخ:    {reply, tool_calls, metadata}
"""
from __future__ import annotations

import logging

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.agents import ALL_AGENTS, AGENT_SYSTEM_PROMPTS, MCP_TOOLS, system_prompt_for, tools_for_agent
from app.config import get_settings
from app.llm import complete
from app.schemas import InvokeRequest, InvokeResponse
from app.supervisor import resolve_agent

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("dilix.ai")
settings = get_settings()

app = FastAPI(
    title="Dilix AI Service",
    version="0.1.0",
    description=(
        "LangGraph Supervisor + specialist agents + MCP Tool Layer. "
        "رابطِ هوشِ مصنوعیِ Dilix که توسطِ سرویسِ Core فراخوانی می‌شود."
    ),
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)


@app.exception_handler(Exception)
async def unhandled_error_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.exception("Unhandled error: %s", exc)
    return JSONResponse(
        status_code=500,
        content={
            "type": "https://dilix.app/errors/ai_internal_error",
            "title": "AI Service Error",
            "status": 500,
            "detail": "خطای داخلیِ سرویسِ هوشِ مصنوعی.",
            "instance": str(request.url.path),
        },
    )


@app.get("/health", tags=["system"])
async def health() -> dict:
    return {
        "status": "ok",
        "service": settings.service_name,
        "version": "0.1.0",
        "environment": settings.environment,
        "llm_enabled": settings.llm_enabled,
        "mcp_enabled": settings.mcp_enabled,
    }


@app.get("/v1/agents", tags=["ai"])
async def list_agents() -> dict:
    """کاتالوگِ agentها و ابزارهایِ MCPِ مجازِ هرکدام."""
    return {
        "agents": [
            {
                "type": agent,
                "system_prompt": AGENT_SYSTEM_PROMPTS[agent],
                "tools": tools_for_agent(agent),
            }
            for agent in ALL_AGENTS
        ],
        "tools": {name: {k: v for k, v in spec.items() if k != "agents"} for name, spec in MCP_TOOLS.items()},
    }


@app.post("/v1/invoke", response_model=InvokeResponse, tags=["ai"])
async def invoke(req: InvokeRequest) -> InvokeResponse:
    """یک turnِ گفتگو را برای agentِ مناسب اجرا می‌کند.

    Supervisor در صورتِ نیاز پیام را به متخصصِ دقیق‌تر هدایت می‌کند، سپس LLM (یا
    fallbackِ قطعی) پاسخ تولید می‌کند. ابزارهایِ MCP از طریقِ لایه‌ی `mcp` در دسترسِ
    agent هستند (اجرا در Core، با کنترلِ دسترسیِ نهایی همان‌جا).
    """
    agent = resolve_agent(req.agent_type, req.message)
    system_prompt = req.system_prompt or system_prompt_for(agent)

    messages = [{"role": m.role, "content": m.content} for m in req.history]
    messages.append({"role": "user", "content": req.message})

    reply, meta = await complete(system_prompt=system_prompt, messages=messages)

    meta = {
        **meta,
        "agent_type": agent,
        "requested_agent": req.agent_type,
        "conversation_id": req.conversation_id,
        "available_tools": tools_for_agent(agent),
    }
    return InvokeResponse(reply=reply, tool_calls=[], metadata=meta)
