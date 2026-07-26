"""محدودسازیِ نرخ برای مسیرهای حساسِ احراز هویت (سند ۶).

بدونِ این لایه، `/v1/auth/*` سه حمله‌ی ارزان را می‌پذیرد: حدسِ نامحدودِ رمز روی
`/login`، حدسِ کدِ عددیِ OTP با ساختِ چالشِ تازه به‌ازای هر تلاش (سقفِ
``otp_max_attempts`` فقط *درونِ یک چالش* است)، و بمبارانِ پیامکِ یک قربانی از راهِ
`/otp/request` که برای پلتفرم هزینه‌ی واقعی دارد.

پنجره‌ی ثابت (fixed window) است نه sliding: برای گلوگاهِ سوءاستفاده کافی است و
یک `INCR` بیشتر نمی‌خواهد. بدترین حالتش پذیرشِ ۲برابرِ سقف در مرزِ دو پنجره است
که در برابرِ «بی‌نهایت»ِ فعلی بی‌اهمیت است.

پشتِ سر Redis می‌نشیند چون سرویس با چند worker اجرا می‌شود و شمارنده باید مشترک
باشد. اگر Redis نبود یا از دسترس خارج شد، به شمارنده‌ی درون‌پردازه‌ای برمی‌گردیم:
سقف عملاً در تعدادِ workerها ضرب می‌شود ولی همچنان کران‌دار است — و مهم‌تر اینکه
قطعیِ Redis نباید ورودِ کاربران را قطع کند.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass

from dilix_shared.errors import RateLimitedError

from app.core.config import get_settings

log = logging.getLogger("dilix.ratelimit")


@dataclass(frozen=True)
class Rule:
    """سقفِ ``limit`` درخواست در پنجره‌ی ``window`` ثانیه‌ای."""

    limit: int
    window: int


# ── سقف‌های مسیرهای احراز هویت (کلید = مسیرِ دقیق؛ ``*`` = پیشوند) ──
# اعداد برای «کاربرِ واقعیِ گیر افتاده» دست‌ودل‌بازند و برای اسکریپت خفه‌کننده.
AUTH_RULES: dict[str, Rule] = {
    "/v1/auth/otp/request": Rule(limit=5, window=600),
    "/v1/auth/otp/verify": Rule(limit=10, window=600),
    "/v1/auth/login": Rule(limit=10, window=300),
    "/v1/auth/register": Rule(limit=5, window=3600),
    "/v1/auth/oauth/*": Rule(limit=20, window=600),
    "/v1/auth/token/refresh": Rule(limit=60, window=300),
}
AUTH_DEFAULT_RULE = Rule(limit=60, window=300)

# سقفِ ارسالِ پیامک به یک مقصدِ مشخص — مستقل از IP، چون چرخاندنِ IP ارزان است
# ولی شماره‌ی قربانی ثابت می‌مانَد.
OTP_DESTINATION_RULE = Rule(limit=3, window=600)


def rule_for_path(path: str) -> Rule:
    """قاعده‌ی متناظرِ یک مسیر؛ تطبیقِ دقیق و سپس پیشوندی."""
    exact = AUTH_RULES.get(path)
    if exact is not None:
        return exact
    for pattern, rule in AUTH_RULES.items():
        if pattern.endswith("*") and path.startswith(pattern[:-1]):
            return rule
    return AUTH_DEFAULT_RULE


# ─────────────────────── انبارهٔ شمارنده ───────────────────────


class _MemoryStore:
    """شمارنده‌ی درون‌پردازه‌ای — برای آزمون و حالتِ نبودِ Redis."""

    def __init__(self) -> None:
        self._hits: dict[str, tuple[int, float]] = {}

    async def incr(self, key: str, window: int) -> tuple[int, int]:
        now = time.monotonic()
        count, started = self._hits.get(key, (0, now))
        if now - started >= window:
            count, started = 0, now
        count += 1
        self._hits[key] = (count, started)
        # تمیزکاریِ تنبل: کلیدهای منقضی را وقتی جدول بزرگ شد دور می‌ریزیم تا
        # حافظه با IPهای یک‌بارمصرف بی‌کران رشد نکند.
        if len(self._hits) > 10_000:
            self._hits = {k: v for k, v in self._hits.items() if now - v[1] < window}
        return count, max(1, int(window - (now - started)))

    async def reset(self) -> None:
        self._hits.clear()


class _RedisStore:
    """شمارنده‌ی مشترک بینِ workerها."""

    def __init__(self, url: str) -> None:
        import redis.asyncio as aioredis  # وارداتِ تنبل: وابستگیِ اختیاری

        self._redis = aioredis.from_url(url, encoding="utf-8", decode_responses=True)

    async def incr(self, key: str, window: int) -> tuple[int, int]:
        pipe = self._redis.pipeline()
        pipe.incr(key)
        pipe.ttl(key)
        count, ttl = await pipe.execute()
        if ttl < 0:  # کلیدِ تازه (یا بی‌انقضا) → پنجره را همین‌جا می‌بندیم
            await self._redis.expire(key, window)
            ttl = window
        return int(count), max(1, int(ttl))

    async def reset(self) -> None:
        await self._redis.flushdb()


_store: _MemoryStore | _RedisStore | None = None
_memory_fallback = _MemoryStore()


def _get_store() -> _MemoryStore | _RedisStore:
    global _store
    if _store is None:
        url = get_settings().redis_url
        try:
            _store = _RedisStore(url)
        except Exception as exc:  # ماژولِ redis نصب نیست یا URL بی‌معناست
            log.warning("محدودسازیِ نرخ به حافظه‌ی محلی برگشت: %s", exc)
            _store = _memory_fallback
    return _store


async def hit(scope: str, identity: str, rule: Rule) -> None:
    """یک تلاش را می‌شمارد و در صورتِ عبور از سقف [RateLimitedError] می‌دهد."""
    key = f"dilix:rl:{scope}:{identity}"
    store = _get_store()
    try:
        count, retry_after = await store.incr(key, rule.window)
    except Exception as exc:
        # Redis خوابیده — امنیت نباید به بهای در دسترس نبودنِ ورود تمام شود.
        log.warning("شمارنده‌ی Redis در دسترس نیست، حافظه‌ی محلی: %s", exc)
        count, retry_after = await _memory_fallback.incr(key, rule.window)
    if count > rule.limit:
        raise RateLimitedError(
            "تلاشِ بیش از حد. لطفاً کمی بعد دوباره امتحان کنید.",
            retry_after=retry_after,
        )


_LOCAL_PREFIXES = ("127.", "10.", "192.168.", "172.16.", "172.17.", "172.18.")


def client_ip(request) -> str:
    """IPِ واقعیِ کلاینت.

    سرویس هم مستقیم روی اینترنت شنیده می‌شود و هم از پشتِ پروکسیِ محلی. سرآیندِ
    ``X-Forwarded-For`` فقط وقتی معتبر است که اتصال از خودِ ماشین/شبکه‌ی خصوصی
    آمده باشد؛ وگرنه هر کلاینتی می‌توانست با جعلِ آن سقف را دور بزند.
    """
    peer = request.client.host if request.client else "unknown"
    if peer == "::1" or peer.startswith(_LOCAL_PREFIXES):
        forwarded = request.headers.get("x-forwarded-for", "")
        first = forwarded.split(",")[0].strip()
        if first:
            return first
    return peer


def reset_for_tests() -> None:
    """پاک‌سازیِ شمارنده‌ی محلی بینِ آزمون‌ها."""
    global _store
    _store = _memory_fallback
    _memory_fallback._hits.clear()
