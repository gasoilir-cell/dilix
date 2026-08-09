"""
Dilix — موتورِ ترجمهٔ حرفه‌ای.

چرا این ماژول جدا از `messages/router.py` است: ترجمه دیگر یک «فراخوانِ ساده» نیست؛
انتخابِ ارائه‌دهنده، حافظهٔ گفتگو، واژه‌نامهٔ تخصصی و دو پروفایلِ تأخیر دارد.

سه لایهٔ ارائه‌دهنده، به ترتیبِ کیفیت:

1. **OpenAI-compatible** (`/chat/completions`) — پیش‌فرضِ عملی. `TRANSLATE_BASE_URL`
   قابل تنظیم است چون از سرورِ ایران `api.anthropic.com` پاسخِ 403 می‌دهد ولی
   `api.openai.com`، `openrouter.ai` و درگاه‌های داخلیِ سازگار (AvalAI/Metis/Liara)
   در دسترس‌اند. همین یک فیلد فرقِ «کار می‌کند» و «کار نمی‌کند» است.
2. **Anthropic** — اگر کلیدش ست شده باشد و شبکه اجازه بدهد.
3. **Google (رایگان)** — فقط تورِ ایمنی. کیفیتش برای چتِ محاوره‌ای «کتابی» است و
   شکایتِ اصلیِ محصول از همین لایه بود؛ هرگز نباید مسیرِ اصلی باشد.

دو پروفایل:
- `quality` — پیامِ چت. حافظهٔ گفتگو + واژه‌نامه + بازنویسیِ اصطلاحی.
- `live`    — زیرنویسِ تماس. بودجهٔ تأخیرِ کوتاه، خروجیِ خام (بدونِ JSON) و
              تحملِ جملهٔ ناتمام. اگر از پروفایلِ `quality` استفاده می‌شد،
              زیرنویس چند ثانیه عقب می‌افتاد و بی‌مصرف می‌شد.
"""
from __future__ import annotations

import asyncio
import hashlib
import json
import re
from dataclasses import dataclass, field
from typing import Optional

import httpx

from app.core.config import settings

# ─────────────────────────── زبان‌ها ───────────────────────────

SUPPORTED_LANGS = {
    "fa", "en", "ar", "tr", "ru", "zh-CN", "fr", "de", "es", "hi", "ur",
    "ps", "ku", "az", "it", "pt", "ja", "ko", "nl", "sv",
}

LANG_ALIASES = {
    "zh": "zh-CN", "cn": "zh-CN", "zh-hans": "zh-CN", "zh_cn": "zh-CN",
    "farsi": "fa", "persian": "fa", "pes": "fa", "fa-ir": "fa",
    "en-us": "en", "en-gb": "en", "pt-br": "pt", "nb": "sv",
}

LANG_NAMES = {
    "fa": "Persian (Farsi)", "en": "English", "ar": "Arabic", "tr": "Turkish",
    "ru": "Russian", "zh-CN": "Simplified Chinese", "fr": "French",
    "de": "German", "es": "Spanish", "hi": "Hindi", "ur": "Urdu",
    "ps": "Pashto", "ku": "Kurdish (Sorani)", "az": "Azerbaijani",
    "it": "Italian", "pt": "Portuguese", "ja": "Japanese", "ko": "Korean",
    "nl": "Dutch", "sv": "Swedish",
}


class UnsupportedLanguage(ValueError):
    """زبانِ مقصد در فهرستِ پشتیبانی‌شده نیست."""


def norm_lang(code: str) -> str:
    c = (code or "").strip()
    low = c.lower()
    if low in LANG_ALIASES:
        return LANG_ALIASES[low]
    if c in SUPPORTED_LANGS:
        return c
    if low in SUPPORTED_LANGS:
        return low
    raise UnsupportedLanguage(c)


# ───────────────────── تشخیصِ ارزانِ زبانِ مبدأ ─────────────────────
# هدف: جلوگیری از فراخوانِ بی‌فایده وقتی متن **از قبل** به زبانِ مقصد است.
# این جای تشخیصِ دقیق را نمی‌گیرد؛ فقط حالتِ بدیهی را کوتاه می‌کند.

_SCRIPT_HINTS = (
    ("fa", re.compile(r"[\u067E\u0686\u0698\u06AF\u06A9\u06CC]")),   # پ چ ژ گ ک ی
    ("ar", re.compile(r"[\u0621-\u064A]")),
    ("ru", re.compile(r"[\u0400-\u04FF]")),
    ("zh-CN", re.compile(r"[\u4E00-\u9FFF]")),
    ("ja", re.compile(r"[\u3040-\u30FF]")),
    ("ko", re.compile(r"[\uAC00-\uD7AF]")),
    ("hi", re.compile(r"[\u0900-\u097F]")),
)
_LATIN = re.compile(r"[A-Za-z]")


def cheap_detect(text: str) -> Optional[str]:
    """حدسِ زبان از روی خط (script). فقط وقتی مطمئن است چیزی برمی‌گرداند."""
    for lang, pat in _SCRIPT_HINTS:
        if pat.search(text):
            return lang
    # لاتین می‌تواند ده‌ها زبان باشد؛ «انگلیسی» حدسِ امنی نیست، پس هیچ.
    return None


def _already_target(text: str, target: str) -> bool:
    guess = cheap_detect(text)
    if guess is None:
        return False
    if guess == target:
        return True
    # فارسی و عربی خطِ مشترک دارند: حدسِ «ar» روی متنی که حروفِ ویژهٔ فارسی
    # ندارد ممکن است فارسیِ ساده باشد؛ پس این جفت را کوتاه نمی‌کنیم.
    return False


# ───────────────────── محافظت از توکن‌های ترجمه‌نشدنی ─────────────────────
# Earth ID، منشن، لینک، کدِ محموله/سفارش و ایموجی نباید «ترجمه» شوند. مدل‌ها
# گاهی آن‌ها را بومی‌سازی می‌کنند (مثلاً عددِ بارنامه را جدا می‌کنند) و همین
# یک خطا کلِ پیامِ تجاری را بی‌اعتبار می‌کند.
_PROTECT = re.compile(
    r"(https?://\S+|www\.\S+|@[\w.\-]+|#[\w\-]+|\b[A-Z]{2,}-\d[\w\-]*\b|\b\d{10,}\b)"
)


def _protected_terms(text: str) -> list[str]:
    seen: list[str] = []
    for m in _PROTECT.findall(text):
        if m not in seen:
            seen.append(m)
    return seen[:12]


# ─────────────────────────── واژه‌نامه ───────────────────────────
# اصطلاحاتی که ترجمهٔ عمومی مرتب خراب می‌کند. کوتاه نگه داشته شده تا در هر
# درخواست کاملاً داخلِ prompt جا شود؛ فهرستِ بلند فقط هزینهٔ توکن است.
_GLOSSARY = {
    "en": [
        "بارنامه = waybill (bill of lading only for sea freight)",
        "حواله = remittance",
        "امانی/اسکرو = escrow",
        "کیف پول = wallet",
        "سنگ نما = facade stone (never 'view stone')",
        "کرایه = freight rate",
        "ترخیص = customs clearance",
        "پیش‌فاکتور = proforma invoice",
        "تناژ = tonnage",
    ],
}


def _glossary_for(target: str) -> str:
    lines = _GLOSSARY.get(target)
    return "\n".join(f"- {t}" for t in lines) if lines else ""


# ─────────────────────────── ورودی/خروجی ───────────────────────────

@dataclass
class TranslationContext:
    """حافظهٔ کوتاهِ گفتگو.

    مهم‌ترین اهرمِ کیفیت است: در چت، جمله‌ها کوتاه و پر از ارجاعِ ضمنی‌اند
    («همونو بفرست»، «چند؟»). بدونِ نوبت‌های قبلی، هر موتوری — حتی LLM — مجبور
    است حدس بزند و خروجی «کتابی» و بی‌ربط می‌شود.
    """

    history: list[str] = field(default_factory=list)   # "Sender: text"
    topic: Optional[str] = None                        # نامِ گروه/موضوع

    def as_prompt(self) -> str:
        if not self.history and not self.topic:
            return ""
        parts = []
        if self.topic:
            parts.append(f"Conversation topic: {self.topic}")
        if self.history:
            parts.append("Preceding messages (context only — DO NOT translate these):")
            parts.extend(self.history[-6:])
        return "\n".join(parts)


@dataclass
class TranslationResult:
    text: str
    detected: Optional[str]
    engine: str          # openai | anthropic | google | echo


# ─────────────────────────── prompt ───────────────────────────

def _system_prompt(target: str, ctx: TranslationContext, protect: list[str],
                   live: bool) -> str:
    tgt = LANG_NAMES.get(target, target)
    rules = [
        "You are a professional human translator and localizer for Dilix — an "
        "international super-app for trade, manufacturing, freight, logistics "
        "and everyday chat between people who share no common language.",
        f"Translate the user's text into {tgt}.",
        "",
        "Non-negotiable rules:",
        "1. Produce what a NATIVE SPEAKER would actually say in that situation. "
        "Never a literal, word-by-word or dictionary rendering.",
        "2. MATCH THE REGISTER. Casual/slangy source becomes casual/slangy target; "
        "formal business source becomes formal business target. Do not upgrade "
        "chat messages into stiff, bookish or academic prose — this is the single "
        "most common failure and it is unacceptable.",
        "3. Localize idioms to the closest natural equivalent instead of "
        "explaining them. Keep humour, sarcasm, politeness level and any "
        "emotional weight intact.",
        "4. Keep emojis, line breaks and message structure exactly as they are.",
        "5. Translate domain terms with real industry vocabulary (trade, "
        "manufacturing, logistics, customs, building/facade stone, textiles, "
        "chemicals, machinery, minerals). Convert nothing: leave numbers, units, "
        "currencies and dates as written.",
        "6. Keep proper nouns, brands and place names accurate; transliterate "
        "only when the target language has no standard form.",
        "7. Never add notes, apologies, quotation marks or explanations. Never "
        "answer the message — only translate it.",
    ]
    gloss = _glossary_for(target)
    if gloss:
        rules += ["", "Required terminology:", gloss]
    if protect:
        rules += [
            "",
            "Copy these tokens through byte-for-byte, unchanged: "
            + ", ".join(protect),
        ]
    ctx_block = ctx.as_prompt()
    if ctx_block:
        rules += ["", ctx_block]

    if live:
        rules += [
            "",
            "This is a LIVE speech caption. It may be an unfinished sentence or "
            "contain speech-recognition noise: translate what is there, do not "
            "complete it, do not correct it, stay short.",
            "Reply with the translation ONLY — plain text, no JSON, no prefix.",
        ]
    else:
        rules += [
            "",
            'Reply with ONE compact JSON object and nothing else: '
            '{"src":"<ISO 639-1 code of the source language>",'
            '"tr":"<the translation>"}',
        ]
    return "\n".join(rules)


def _strip_fence(raw: str) -> str:
    if not raw.startswith("```"):
        return raw
    raw = raw.strip("`")
    nl = raw.find("\n")
    return (raw[nl + 1:] if nl != -1 else raw).strip()


def _parse(raw: str, live: bool) -> tuple[str, Optional[str]]:
    raw = _strip_fence(raw.strip())
    if live:
        return raw, None
    try:
        obj = json.loads(raw)
        return (obj.get("tr") or "").strip(), (obj.get("src") or None)
    except (json.JSONDecodeError, ValueError, AttributeError):
        # مدل JSON نداد؛ متنِ خام بهتر از خطاست.
        return raw, None


# ─────────────────────────── ارائه‌دهنده‌ها ───────────────────────────

def _openai_conf() -> tuple[str, str, str]:
    """(base_url, api_key, model) برای مسیرِ سازگار با OpenAI."""
    base = (getattr(settings, "TRANSLATE_BASE_URL", "") or "").strip()
    key = (getattr(settings, "TRANSLATE_API_KEY", "") or "").strip()
    model = (getattr(settings, "TRANSLATE_MODEL", "") or "").strip()
    if not key:
        key = (getattr(settings, "OPENAI_API_KEY", "") or "").strip()
    return (base.rstrip("/") or "https://api.openai.com/v1", key,
            model or "gpt-4o-mini")


async def _openai_translate(text: str, target: str, ctx: TranslationContext,
                            live: bool) -> TranslationResult:
    base, key, model = _openai_conf()
    body = {
        "model": model,
        "temperature": 0.3,      # کمی آزادی برای طبیعی‌بودن، نه بازآفرینی
        "max_tokens": 400 if live else 2048,
        "messages": [
            {"role": "system",
             "content": _system_prompt(target, ctx, _protected_terms(text), live)},
            {"role": "user", "content": text},
        ],
    }
    timeout = 6.0 if live else 25.0
    async with httpx.AsyncClient(timeout=timeout) as c:
        resp = await c.post(
            f"{base}/chat/completions",
            json=body,
            headers={"Authorization": f"Bearer {key}",
                     "Content-Type": "application/json"},
        )
    resp.raise_for_status()
    data = resp.json()
    raw = ((data.get("choices") or [{}])[0].get("message") or {}).get("content") or ""
    tr, src = _parse(raw, live)
    if not tr:
        raise ValueError("empty translation")
    return TranslationResult(tr, src, "openai")


async def _anthropic_translate(text: str, target: str, ctx: TranslationContext,
                               live: bool) -> TranslationResult:
    key = (settings.ANTHROPIC_API_KEY or "").strip()
    model = (getattr(settings, "TRANSLATE_MODEL_ANTHROPIC", "")
             or "claude-haiku-4-5-20251001")
    body = {
        "model": model,
        "max_tokens": 400 if live else 2048,
        "temperature": 0.3,
        "system": _system_prompt(target, ctx, _protected_terms(text), live),
        "messages": [{"role": "user", "content": text}],
    }
    timeout = 6.0 if live else 25.0
    async with httpx.AsyncClient(timeout=timeout) as c:
        resp = await c.post(
            "https://api.anthropic.com/v1/messages",
            json=body,
            headers={"x-api-key": key,
                     "anthropic-version": "2023-06-01",
                     "content-type": "application/json"},
        )
    resp.raise_for_status()
    data = resp.json()
    raw = "".join(p.get("text", "") for p in (data.get("content") or [])
                  if p.get("type") == "text")
    tr, src = _parse(raw, live)
    if not tr:
        raise ValueError("empty translation")
    return TranslationResult(tr, src, "anthropic")


_GOOGLE_URL = "https://translate.googleapis.com/translate_a/single"


async def _google_translate(text: str, target: str) -> TranslationResult:
    params = {"client": "gtx", "sl": "auto", "tl": target, "dt": "t", "q": text}
    async with httpx.AsyncClient(timeout=12) as c:
        resp = await c.get(_GOOGLE_URL, params=params)
    resp.raise_for_status()
    data = resp.json()
    segments = data[0] or []
    tr = "".join(seg[0] for seg in segments if seg and seg[0])
    detected = data[2] if len(data) > 2 and isinstance(data[2], str) else None
    if not tr:
        raise ValueError("empty translation")
    return TranslationResult(tr, detected, "google")


# ─────────────────────────── کشِ کوتاه ───────────────────────────
# پیامِ چت کشِ پایدارِ دیتابیسی دارد. این کش برای متنِ آزاد و زیرنویسِ تماس است
# که تکرارِ زیاد و عمرِ کوتاه دارند (کاربر یک جمله را چند بار می‌گوید/می‌نویسد).

_CACHE_TTL = 6 * 3600


def _cache_key(text: str, target: str, live: bool) -> str:
    h = hashlib.sha256(f"{target}|{int(live)}|{text}".encode()).hexdigest()[:32]
    return f"tr:v2:{h}"


async def _cache_get(key: str) -> Optional[TranslationResult]:
    try:
        from app.core.redis import get_redis
        r = await get_redis()
        raw = await r.get(key)
    except Exception:
        return None
    if not raw:
        return None
    try:
        o = json.loads(raw)
        return TranslationResult(o["t"], o.get("s"), o.get("e", "cache"))
    except (json.JSONDecodeError, KeyError, TypeError):
        return None


async def _cache_put(key: str, res: TranslationResult) -> None:
    try:
        from app.core.redis import get_redis
        r = await get_redis()
        await r.setex(key, _CACHE_TTL,
                      json.dumps({"t": res.text, "s": res.detected,
                                  "e": res.engine}))
    except Exception:
        pass  # کش اختیاری است؛ خرابی‌اش نباید ترجمه را بشکند


# ─────────────────────────── ورودیِ عمومی ───────────────────────────

def engine_name() -> str:
    """موتوری که *الان* استفاده می‌شود — برای `/health` و پنلِ ادمین."""
    _, key, _ = _openai_conf()
    if key:
        return "openai-compatible"
    if (settings.ANTHROPIC_API_KEY or "").strip():
        return "anthropic"
    return "google-fallback"


async def translate(
    text: str,
    target: str,
    *,
    context: Optional[TranslationContext] = None,
    live: bool = False,
    use_cache: bool = True,
) -> TranslationResult:
    """ترجمهٔ متن به `target`. همیشه نتیجه می‌دهد یا استثنا می‌اندازد.

    ترتیبِ تلاش: OpenAI-compatible → Anthropic → Google. هر شکستی به لایهٔ بعد
    می‌افتد تا یک کلیدِ منقضی کلِ چت را از کار نیندازد.
    """
    text = (text or "").strip()
    if not text:
        raise ValueError("empty text")
    target = norm_lang(target)
    ctx = context or TranslationContext()

    if _already_target(text, target) and not ctx.history:
        return TranslationResult(text, target, "echo")

    key = _cache_key(text, target, live)
    if use_cache:
        hit = await _cache_get(key)
        if hit:
            return hit

    errors: list[str] = []
    _, oa_key, _ = _openai_conf()
    if oa_key:
        try:
            res = await _openai_translate(text, target, ctx, live)
            if use_cache:
                await _cache_put(key, res)
            return res
        except (httpx.HTTPError, ValueError, KeyError, asyncio.TimeoutError) as e:
            errors.append(f"openai:{type(e).__name__}")

    if (settings.ANTHROPIC_API_KEY or "").strip():
        try:
            res = await _anthropic_translate(text, target, ctx, live)
            if use_cache:
                await _cache_put(key, res)
            return res
        except (httpx.HTTPError, ValueError, KeyError, asyncio.TimeoutError) as e:
            errors.append(f"anthropic:{type(e).__name__}")

    res = await _google_translate(text, target)
    if use_cache:
        await _cache_put(key, res)
    return res
