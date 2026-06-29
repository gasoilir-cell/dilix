"""MCP Tool Layer — اجرایِ ابزارهایِ دامنه با فراخوانیِ برگشتی به dilix-core (سند ۸).

هر ابزار به یک endpointِ امنِ Core نگاشت می‌شود. agent فقط ابزارهایِ مجازِ خود را
می‌بیند (`tools_for_agent`). کنترلِ دسترسیِ نهایی در خودِ Core اعمال می‌شود؛ این لایه
صرفاً واسطه‌ی امن است و توکنِ سرویس‌به‌سرویس و earth_idِ کاربر را حمل می‌کند.
"""
from __future__ import annotations

import logging

import httpx

from app.agents import MCP_TOOLS, tools_for_agent
from app.config import get_settings

logger = logging.getLogger("dilix.ai.mcp")

_client: httpx.AsyncClient | None = None


def _get_client() -> httpx.AsyncClient:
    global _client
    if _client is None:
        settings = get_settings()
        _client = httpx.AsyncClient(
            base_url=settings.core_base_url,
            timeout=httpx.Timeout(settings.mcp_timeout_seconds, connect=5.0),
            headers={"X-Service": "dilix-ai"},
        )
    return _client


class MCPError(RuntimeError):
    """خطایِ اجرایِ ابزارِ MCP."""


def _authorize(agent_type: str, tool_name: str) -> dict:
    spec = MCP_TOOLS.get(tool_name)
    if spec is None:
        raise MCPError(f"ابزارِ ناشناخته: {tool_name}")
    if tool_name not in tools_for_agent(agent_type):
        raise MCPError(f"agentِ «{agent_type}» اجازه‌ی ابزارِ «{tool_name}» را ندارد")
    return spec


async def call_tool(
    *,
    agent_type: str,
    earth_id: str,
    tool_name: str,
    arguments: dict | None = None,
) -> dict:
    """یک ابزارِ MCP را پس از مجوزسنجی روی dilix-core اجرا می‌کند.

    خروجی: بدنه‌ی پاسخِ Core به‌صورتِ dict.
    """
    arguments = arguments or {}
    spec = _authorize(agent_type, tool_name)

    settings = get_settings()
    if not settings.mcp_enabled:
        raise MCPError("MCP غیرفعال است — DILIX_AI_CORE_BASE_URL تنظیم نشده")

    # جایگذاریِ پارامترهایِ مسیر مثلِ {earth_id}
    path = spec["path"].format(earth_id=earth_id, **arguments)
    method = spec["method"].upper()

    headers = {
        "X-Earth-Id": earth_id,
        "X-Service-Token": settings.core_service_token,
    }
    try:
        if method == "GET":
            resp = await _get_client().get(path, params=arguments, headers=headers)
        else:
            resp = await _get_client().request(method, path, json=arguments, headers=headers)
        resp.raise_for_status()
        return resp.json()
    except httpx.HTTPStatusError as exc:
        logger.error("MCP %s %s → %s", method, path, exc.response.status_code)
        raise MCPError(f"خطای Core {exc.response.status_code} برای {tool_name}") from exc
    except httpx.RequestError as exc:
        logger.error("MCP connection error %s %s: %s", method, path, exc)
        raise MCPError(f"اتصال به Core برای {tool_name} ناموفق بود") from exc
