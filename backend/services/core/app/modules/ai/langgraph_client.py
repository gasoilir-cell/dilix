"""کلاینت LangGraph — رابط بین Core Service و dilix-ai-service.

معماری (سند ۸):
  dilix-core (این سرویس)
       ↓ HTTP/gRPC
  dilix-ai-service (LangGraph Supervisor)
       ├── PersonalAssistant Agent
       ├── FreightAgent
       ├── InsuranceAgent
       ├── FinancialAgent
       ├── MatchmakingAgent   (کشفِ افراد روی کره — Discovery)
       ├── TravelAgent
       └── BusinessAgent
  + MCP Tool Layer: ابزارهای امنِ دامنه که هر agent می‌تواند صدا بزند.

در این فایل قرارداد API با dilix-ai-service تعریف شده است.
با فعال‌سازی env var DILIX_AI_SERVICE_URL اتصال واقعی برقرار می‌شود؛
در غیر این صورت stub محلی استفاده می‌شود.
"""
from __future__ import annotations

import logging

import httpx

from app.core.config import get_settings

logger = logging.getLogger("dilix.ai")

_client: httpx.AsyncClient | None = None


def get_client() -> httpx.AsyncClient:
    global _client
    if _client is None:
        settings = get_settings()
        base_url = settings.ai_service_url or "http://localhost:8001"
        _client = httpx.AsyncClient(
            base_url=base_url,
            timeout=httpx.Timeout(30.0, connect=5.0),
            headers={"X-Service": "dilix-core"},
        )
    return _client


# ─────────────────────── Agent Types ──────────────────────────

AGENT_PERSONAL = "personal"
AGENT_FREIGHT = "freight"
AGENT_INSURANCE = "insurance"
AGENT_FINANCIAL = "financial"
AGENT_MATCHMAKING = "matchmaking"
AGENT_TRAVEL = "travel"
AGENT_BUSINESS = "business"

ALL_AGENTS = (
    AGENT_PERSONAL,
    AGENT_FREIGHT,
    AGENT_INSURANCE,
    AGENT_FINANCIAL,
    AGENT_MATCHMAKING,
    AGENT_TRAVEL,
    AGENT_BUSINESS,
)

# پیام سیستمی هر agent — در dilix-ai-service به LangGraph تزریق می‌شود
AGENT_SYSTEM_PROMPTS: dict[str, str] = {
    AGENT_PERSONAL: (
        "تو دستیار شخصی Dilix هستی. به کاربر در مدیریت سفارش‌ها، پیام‌ها، "
        "وضعیت سرویس‌ها و راهنمایی کلی کمک کن. فارسی بنویس."
    ),
    AGENT_FREIGHT: (
        "تو متخصص لجستیک و حمل‌ونقل Dilix هستی. در ثبت بار، پیدا کردن راننده، "
        "ردیابی محموله و رفع اختلافات کمک کن. فارسی بنویس."
    ),
    AGENT_INSURANCE: (
        "تو مشاور بیمه Dilix هستی. در استعلام، انتخاب و مقایسه‌ی بیمه‌نامه‌ها "
        "و فرآیند خسارت راهنمایی کن. فارسی بنویس."
    ),
    AGENT_FINANCIAL: (
        "تو مشاور مالی Dilix هستی. در انتخاب روش پرداخت، سرمایه‌گذاری از طریق "
        "صندوق‌های مجاز و مدیریت تراکنش‌ها کمک کن. فارسی بنویس."
    ),
    AGENT_MATCHMAKING: (
        "تو دستیار کشفِ افراد و کسب‌وکار روی کره‌ی Dilix هستی. با احترامِ کامل به "
        "حریمِ خصوصی (فقط کاربرانِ opt-in، بدونِ مختصاتِ دقیق) به کاربر کمک کن افرادِ "
        "هم‌علاقه، هم‌زبان یا شریکِ کاری پیدا کند. فارسی بنویس."
    ),
    AGENT_TRAVEL: (
        "تو مشاور سفر Dilix هستی. در برنامه‌ریزی مسیر، یافتنِ هم‌سفر، اقامتگاه و "
        "خدماتِ محلی کمک کن. فارسی بنویس."
    ),
    AGENT_BUSINESS: (
        "تو مشاور کسب‌وکار Dilix هستی. در یافتنِ شریک، تأمین‌کننده، خدماتِ بازارگاه و "
        "رشدِ قانونی کمک کن. فارسی بنویس."
    ),
}

# ─────────────────────── MCP Tool Layer (سند ۸) ──────────────────────────
# کاتالوگِ ابزارهایِ امنِ دامنه که Supervisor/agentها از طریقِ MCP صدا می‌زنند.
# هر ابزار به یک endpointِ داخلیِ Dilix نگاشت می‌شود (کنترلِ دسترسی در همان لایه).
MCP_TOOLS: dict[str, dict] = {
    "freight.search": {"method": "GET", "path": "/v1/freight/cargo", "agents": [AGENT_FREIGHT]},
    "insurance.quote": {"method": "POST", "path": "/v1/insurance/quotes", "agents": [AGENT_INSURANCE]},
    "payment.create_order": {"method": "POST", "path": "/v1/payments/escrow", "agents": [AGENT_FINANCIAL]},
    "discovery.find_people": {"method": "GET", "path": "/v1/discovery/nearby", "agents": [AGENT_MATCHMAKING, AGENT_TRAVEL]},
    "reputation.get": {"method": "GET", "path": "/v1/reputation/scores/{earth_id}", "agents": list(ALL_AGENTS)},
    "profile.get": {"method": "GET", "path": "/v1/identity/me", "agents": list(ALL_AGENTS)},
}


def tools_for_agent(agent_type: str) -> list[str]:
    """نامِ ابزارهایِ MCP مجاز برای یک agent."""
    return [name for name, spec in MCP_TOOLS.items() if agent_type in spec["agents"]]


# ─────────────────────── Supervisor Routing ──────────────────────────
# نگاشتِ کلیدواژه → agent برای مسیریابیِ پیامِ کاربر وقتی agent مشخص نشده.
_ROUTING_KEYWORDS: dict[str, tuple[str, ...]] = {
    AGENT_FREIGHT: ("بار", "راننده", "حمل", "محموله", "بارنامه", "کامیون"),
    AGENT_INSURANCE: ("بیمه", "خسارت", "بیمه‌نامه", "پوشش"),
    AGENT_FINANCIAL: ("پرداخت", "سرمایه", "صندوق", "تراکنش", "کیف پول", "سود"),
    AGENT_MATCHMAKING: ("دوست", "آشنا", "هم‌علاقه", "کشف", "نزدیک", "اطراف", "هم‌زبان"),
    AGENT_TRAVEL: ("سفر", "هم‌سفر", "مسیر", "اقامت", "هتل", "گردش"),
    AGENT_BUSINESS: ("شریک", "تأمین", "بازارگاه", "کسب‌وکار", "همکار", "سرمایه‌گذار"),
}


def route_to_agent(user_message: str) -> str:
    """Supervisor: انتخابِ specialist agent بر اساسِ پیامِ کاربر؛ پیش‌فرض personal."""
    text = user_message.lower()
    for agent, keywords in _ROUTING_KEYWORDS.items():
        if any(kw in text for kw in keywords):
            return agent
    return AGENT_PERSONAL


# ─────────────────────── API Contract ──────────────────────────

async def invoke_agent(
    *,
    agent_type: str,
    conversation_id: str,
    earth_id: str,
    history: list[dict[str, str]],
    user_message: str,
) -> str:
    """
    فراخوانی agent در dilix-ai-service.

    Request body:
      {
        "agent_type": "personal",
        "conversation_id": "uuid",
        "earth_id": "uuid",
        "system_prompt": "...",
        "history": [{"role": "user", "content": "..."}, ...],
        "message": "پیام جدید کاربر"
      }

    Response:
      {"reply": "پاسخ agent", "tool_calls": [...], "metadata": {...}}
    """
    settings = get_settings()
    if not settings.ai_service_url:
        return _local_stub(agent_type, user_message)

    try:
        client = get_client()
        response = await client.post(
            "/v1/invoke",
            json={
                "agent_type": agent_type,
                "conversation_id": conversation_id,
                "earth_id": earth_id,
                "system_prompt": AGENT_SYSTEM_PROMPTS.get(agent_type, ""),
                "history": history,
                "message": user_message,
            },
        )
        response.raise_for_status()
        data = response.json()
        return data.get("reply", "پاسخی دریافت نشد.")

    except httpx.HTTPStatusError as exc:
        logger.error("AI service HTTP error %s: %s", exc.response.status_code, exc.response.text)
        return _local_stub(agent_type, user_message)
    except httpx.RequestError as exc:
        logger.error("AI service connection error: %s", exc)
        return _local_stub(agent_type, user_message)


def _local_stub(agent_type: str, user_msg: str) -> str:
    """پاسخ محلی تا اتصال dilix-ai-service."""
    prompts = {
        AGENT_PERSONAL: "به شما در مدیریت حساب و سرویس‌ها کمک می‌کنم.",
        AGENT_FREIGHT: "می‌توانم بار، راننده و بارنامه را پیگیری کنم.",
        AGENT_INSURANCE: "استعلام و انتخاب بیمه‌نامه در اختیار شماست.",
        AGENT_FINANCIAL: "راهنمایی پرداخت و سرمایه‌گذاری مجاز انجام می‌دهم.",
        AGENT_MATCHMAKING: "افرادِ هم‌علاقه و کسب‌وکارها را روی کره پیدا می‌کنم.",
        AGENT_TRAVEL: "در برنامه‌ریزی سفر و یافتنِ هم‌سفر کمک می‌کنم.",
        AGENT_BUSINESS: "شریک، تأمین‌کننده و فرصتِ کاری پیشنهاد می‌دهم.",
    }
    intro = prompts.get(agent_type, "دستیار Dilix هستم.")
    return (
        f"[{agent_type.upper()} AGENT] {intro}\n"
        f"پیام شما: «{user_msg[:100]}»\n"
        "⚠️ dilix-ai-service هنوز متصل نشده — تنظیم DILIX_AI_SERVICE_URL لازم است."
    )
