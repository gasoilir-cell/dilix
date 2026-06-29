"""لایه‌ی LLM — کلاینتِ سازگار با OpenAI Chat Completions + fallbackِ قطعی.

اگر `DILIX_AI_LLM_API_KEY` تنظیم نشده باشد، سرویس بدونِ تماسِ خارجی با پاسخِ
rule-based کار می‌کند تا در محیطِ بدونِ کلید هم قابلِ اجرا و تست باشد.
"""
from __future__ import annotations

import logging

import httpx

from app.config import get_settings

logger = logging.getLogger("dilix.ai.llm")

_client: httpx.AsyncClient | None = None


def _get_client() -> httpx.AsyncClient:
    global _client
    if _client is None:
        settings = get_settings()
        _client = httpx.AsyncClient(
            base_url=settings.llm_base_url,
            timeout=httpx.Timeout(settings.llm_timeout_seconds, connect=5.0),
            headers={"Authorization": f"Bearer {settings.llm_api_key}"},
        )
    return _client


async def complete(*, system_prompt: str, messages: list[dict[str, str]]) -> tuple[str, dict]:
    """یک turnِ گفتگو را کامل می‌کند.

    خروجی: (متنِ پاسخ، metadata).
    """
    settings = get_settings()
    if not settings.llm_enabled:
        return _fallback(system_prompt, messages), {"engine": "fallback", "model": None}

    payload = {
        "model": settings.llm_model,
        "temperature": settings.llm_temperature,
        "max_tokens": settings.llm_max_tokens,
        "messages": [{"role": "system", "content": system_prompt}, *messages],
    }
    try:
        resp = await _get_client().post("/chat/completions", json=payload)
        resp.raise_for_status()
        data = resp.json()
        reply = data["choices"][0]["message"]["content"]
        usage = data.get("usage", {})
        return reply, {"engine": "llm", "model": settings.llm_model, "usage": usage}
    except httpx.HTTPStatusError as exc:
        logger.error("LLM HTTP error %s: %s", exc.response.status_code, exc.response.text[:300])
    except httpx.RequestError as exc:
        logger.error("LLM connection error: %s", exc)
    except (KeyError, IndexError) as exc:
        logger.error("LLM unexpected response shape: %s", exc)
    # هر خطایی → fallback تا گفتگو قطع نشود
    return _fallback(system_prompt, messages), {"engine": "fallback", "model": None, "degraded": True}


def _fallback(system_prompt: str, messages: list[dict[str, str]]) -> str:
    """پاسخِ قطعیِ بدونِ مدل — برای محیطِ بدونِ کلید یا هنگامِ خطا.

    خلاصه‌ای از نقشِ agent (از system_prompt) به‌علاوه‌ی بازتابِ پیامِ کاربر.
    """
    last_user = ""
    for m in reversed(messages):
        if m.get("role") == "user":
            last_user = m.get("content", "")
            break
    role_line = system_prompt.strip().split("\n", 1)[0] if system_prompt else "دستیار Dilix هستم."
    return (
        f"{role_line}\n"
        f"دریافت شد: «{last_user[:160]}»\n"
        "برای پاسخِ هوشمندِ کامل، اتصالِ مدلِ زبانی (DILIX_AI_LLM_API_KEY) لازم است."
    )
