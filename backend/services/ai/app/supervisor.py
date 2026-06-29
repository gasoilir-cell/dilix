"""Supervisor — مسیریابیِ پیامِ کاربر به specialist agentِ مناسب (سند ۸).

Coreِ Dilix معمولاً agent_type را از پیش انتخاب می‌کند؛ اما اگر «personal» (پیش‌فرض)
فرستاده شود، Supervisor تلاش می‌کند پیام را به متخصصِ مناسب‌تر هدایت کند.
"""
from __future__ import annotations

from app.agents import (
    AGENT_BUSINESS,
    AGENT_FINANCIAL,
    AGENT_FREIGHT,
    AGENT_INSURANCE,
    AGENT_MATCHMAKING,
    AGENT_PERSONAL,
    AGENT_TRAVEL,
)

# نگاشتِ کلیدواژه → agent (هم‌خوان با _ROUTING_KEYWORDS در Core).
_ROUTING_KEYWORDS: dict[str, tuple[str, ...]] = {
    AGENT_FREIGHT: ("بار", "راننده", "حمل", "محموله", "بارنامه", "کامیون"),
    AGENT_INSURANCE: ("بیمه", "خسارت", "بیمه‌نامه", "پوشش"),
    AGENT_FINANCIAL: ("پرداخت", "سرمایه", "صندوق", "تراکنش", "کیف پول", "سود"),
    AGENT_MATCHMAKING: ("دوست", "آشنا", "هم‌علاقه", "کشف", "نزدیک", "اطراف", "هم‌زبان"),
    AGENT_TRAVEL: ("سفر", "هم‌سفر", "مسیر", "اقامت", "هتل", "گردش"),
    AGENT_BUSINESS: ("شریک", "تأمین", "بازارگاه", "کسب‌وکار", "همکار", "سرمایه‌گذار"),
}


def route(user_message: str) -> str:
    """انتخابِ specialist agent بر اساسِ پیامِ کاربر؛ پیش‌فرض personal."""
    text = user_message.lower()
    for agent, keywords in _ROUTING_KEYWORDS.items():
        if any(kw in text for kw in keywords):
            return agent
    return AGENT_PERSONAL


def resolve_agent(requested: str, user_message: str) -> str:
    """اگر agentِ مشخصی (غیر personal) خواسته شده همان را نگه می‌دارد؛
    در غیرِ این صورت Supervisor بر اساسِ پیام مسیریابی می‌کند."""
    if requested and requested != AGENT_PERSONAL:
        return requested
    return route(user_message)
