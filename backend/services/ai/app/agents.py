"""تعریفِ agentهای متخصص، promptهای سیستمی و کاتالوگِ ابزارهایِ MCP (سند ۸).

این ماژول منبعِ حقیقتِ سمتِ ai-service است و باید با
`dilix-core/app/modules/ai/langgraph_client.py` هم‌خوان بماند.
"""
from __future__ import annotations

# ─────────────────────── Agent Types ──────────────────────────

AGENT_PERSONAL = "personal"
AGENT_FREIGHT = "freight"
AGENT_INSURANCE = "insurance"
AGENT_FINANCIAL = "financial"
AGENT_MATCHMAKING = "matchmaking"
AGENT_TRAVEL = "travel"
AGENT_BUSINESS = "business"

ALL_AGENTS: tuple[str, ...] = (
    AGENT_PERSONAL,
    AGENT_FREIGHT,
    AGENT_INSURANCE,
    AGENT_FINANCIAL,
    AGENT_MATCHMAKING,
    AGENT_TRAVEL,
    AGENT_BUSINESS,
)

# promptِ سیستمیِ هر agent. وقتی Core در درخواست system_prompt بفرستد، همان اولویت دارد؛
# این‌ها fallback و مرجع هستند.
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
# هر ابزار به یک endpointِ امنِ dilix-core نگاشت می‌شود. کنترلِ دسترسی همان‌جا اعمال می‌شود.
MCP_TOOLS: dict[str, dict] = {
    "freight.search": {
        "method": "GET",
        "path": "/v1/freight/cargo",
        "agents": [AGENT_FREIGHT],
        "description": "جستجوی بارهای ثبت‌شده برای راننده/صاحبِ بار.",
    },
    "insurance.quote": {
        "method": "POST",
        "path": "/v1/insurance/quotes",
        "agents": [AGENT_INSURANCE],
        "description": "استعلامِ قیمتِ بیمه‌نامه.",
    },
    "payment.create_order": {
        "method": "POST",
        "path": "/v1/payments/escrow",
        "agents": [AGENT_FINANCIAL],
        "description": "ایجادِ سفارشِ امانی (escrow).",
    },
    "discovery.find_people": {
        "method": "GET",
        "path": "/v1/discovery/nearby",
        "agents": [AGENT_MATCHMAKING, AGENT_TRAVEL],
        "description": "کشفِ افرادِ هم‌علاقه/هم‌زبان روی کره (privacy-by-design).",
    },
    "reputation.get": {
        "method": "GET",
        "path": "/v1/reputation/scores/{earth_id}",
        "agents": list(ALL_AGENTS),
        "description": "امتیازِ اعتبارِ یک کاربر.",
    },
    "profile.get": {
        "method": "GET",
        "path": "/v1/identity/me",
        "agents": list(ALL_AGENTS),
        "description": "پروفایلِ کاربرِ جاری.",
    },
}


def tools_for_agent(agent_type: str) -> list[str]:
    """نامِ ابزارهایِ MCP مجاز برای یک agent."""
    return [name for name, spec in MCP_TOOLS.items() if agent_type in spec["agents"]]


def system_prompt_for(agent_type: str) -> str:
    return AGENT_SYSTEM_PROMPTS.get(agent_type, AGENT_SYSTEM_PROMPTS[AGENT_PERSONAL])
