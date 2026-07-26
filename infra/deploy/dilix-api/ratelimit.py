"""سقفِ نرخ برای مسیرهای احراز هویتِ dilix-api.

مقصدِ استقرار: ``/var/www/dilix-api/app/core/ratelimit.py``

چرا لازم است — سه حمله‌ی مشخص که پیش از این هیچ سدی نداشتند:

۱) حدسِ رمز/توکن روی ``/api/v1/auth/login`` و ``/refresh`` — بی‌نهایت تلاش.
۲) بازسازیِ زنجیره‌ایِ چالشِ OTP: ``OTP_MAX_ATTEMPTS`` فقط تلاش‌های *یک* کد را
   می‌شمارد و هر ``/otp/send`` شمارنده را صفر می‌کند؛ با cooldownِ ۳۰ ثانیه‌ای
   یعنی هر نیم‌دقیقه پنج حدسِ تازه، برای همیشه.
۳) بمبارانِ پیامک: cooldownِ فعلی هر شماره را به ۱۲۰ پیامک در ساعت محدود می‌کند —
   هزینه‌ی واقعیِ اپراتور و آزارِ کاربر، بدونِ هیچ سقفِ روزانه.

طراحی: پنجره‌ی ثابت (fixed window) روی Redis با ``INCR``+``TTL``. در بدترین حالت
مرزِ دو پنجره اجازه‌ی دو برابرِ سقف را می‌دهد؛ در برابرِ وضعیتِ فعلی («بی‌نهایت»)
معامله‌ی قابلِ قبولی است و برخلافِ sliding window به حافظه‌ی هر درخواست نیاز ندارد.

اگر Redis از دسترس خارج شود، شمارنده‌ی درون‌پردازه‌ای جای آن را می‌گیرد: سقف روی
هر worker جدا می‌شود (شل‌تر، نه باز)، ولی ورودِ کاربران قطع نمی‌شود.
"""
from __future__ import annotations

import ipaddress
import time
from dataclasses import dataclass

import structlog

log = structlog.get_logger(__name__)


class RateLimited(Exception):
    """عبور از سقف. ``retry_after`` ثانیه‌های ماندهٔ پنجره است."""

    def __init__(self, retry_after: int, message: str | None = None) -> None:
        self.retry_after = max(1, int(retry_after))
        self.message = message or "تلاشِ بیش از حد. لطفاً کمی بعد دوباره امتحان کنید."
        super().__init__(self.message)

    def as_detail(self) -> dict:
        return {
            "error": "rate_limited",
            "retry_after": self.retry_after,
            "message": self.message,
        }


@dataclass(frozen=True)
class Rule:
    """سقفِ ``limit`` درخواست در پنجره‌ی ``window`` ثانیه‌ای."""

    limit: int
    window: int


# مسیرِ دقیق، یا الگوی ستاره‌دار (پیشوند) برای مسیرهای پارامتری.
AUTH_RULES: dict[str, Rule] = {
    "/api/v1/auth/otp/send": Rule(limit=5, window=600),
    "/api/v1/auth/otp/verify": Rule(limit=10, window=600),
    "/api/v1/auth/login": Rule(limit=10, window=300),
    "/api/v1/auth/register": Rule(limit=5, window=3600),
    "/api/v1/auth/oauth/*": Rule(limit=20, window=600),
    "/api/v1/auth/refresh": Rule(limit=60, window=300),
}
# مسیرهای احرازشده‌ی دیگر (ویرایشِ پروفایل، آواتار، KYC) سقفِ سخاوتمندانه دارند؛
# هدف جلوگیری از سوءاستفاده است نه ایجادِ اصطکاک برای کاربرِ عادی.
AUTH_DEFAULT_RULE = Rule(limit=120, window=300)

# سقفِ ارسال به یک مقصدِ مشخص، مستقل از IP: چرخاندنِ IP ارزان است ولی شماره‌ی
# قربانی ثابت می‌مانَد و هر پیامک هزینه‌ی واقعی دارد.
OTP_DESTINATION_RULE = Rule(limit=3, window=600)


def rule_for_path(path: str) -> Rule:
    rule = AUTH_RULES.get(path)
    if rule is not None:
        return rule
    for pattern, candidate in AUTH_RULES.items():
        if pattern.endswith("*") and path.startswith(pattern[:-1]):
            return candidate
    return AUTH_DEFAULT_RULE


# ── شمارنده‌ها ────────────────────────────────────────────────────────────────

class _MemoryStore:
    """جایگزینِ درون‌پردازه‌ای — فقط برای زمانی که Redis در دسترس نیست."""

    def __init__(self) -> None:
        self._hits: dict[str, tuple[int, float]] = {}

    async def incr(self, key: str, window: int) -> tuple[int, int]:
        now = time.monotonic()
        count, expires = self._hits.get(key, (0, 0.0))
        if expires <= now:
            count, expires = 0, now + window
        count += 1
        self._hits[key] = (count, expires)
        if len(self._hits) > 10_000:  # پاک‌سازیِ تنبل تا حافظه بی‌مرز رشد نکند
            self._hits = {k: v for k, v in self._hits.items() if v[1] > now}
        return count, max(1, int(expires - now))

    def reset(self) -> None:
        self._hits.clear()


_memory_fallback = _MemoryStore()


async def _redis_incr(key: str, window: int) -> tuple[int, int]:
    from app.core.redis import get_redis

    redis = await get_redis()
    pipe = redis.pipeline()
    pipe.incr(key)
    pipe.ttl(key)
    count, ttl = await pipe.execute()
    if ttl is None or ttl < 0:  # کلیدِ تازه (یا بی‌انقضا) — پنجره را ست کن
        await redis.expire(key, window)
        ttl = window
    return int(count), int(ttl)


async def hit(scope: str, identity: str, rule: Rule) -> None:
    """یک درخواست را می‌شمارد و در صورتِ عبور از سقف ``RateLimited`` می‌اندازد."""
    key = f"dilix:rl:{scope}:{identity}"
    try:
        count, retry_after = await _redis_incr(key, rule.window)
    except Exception as exc:  # noqa: BLE001 — امنیت به بهای در دسترس نبودنِ ورود نه
        log.warning("ratelimit_redis_unavailable", error=str(exc))
        count, retry_after = await _memory_fallback.incr(key, rule.window)
    if count > rule.limit:
        raise RateLimited(retry_after)


# ── تشخیصِ IP ────────────────────────────────────────────────────────────────

def _is_trusted_peer(host: str) -> bool:
    """آیا اتصال از پروکسیِ خودی آمده؟ (loopback یا شبکه‌ی خصوصی)"""
    try:
        addr = ipaddress.ip_address(host)
    except ValueError:
        return False
    return addr.is_loopback or addr.is_private


def rate_limit_ip(request) -> str:  # noqa: ANN001 — starlette Request
    """هویتِ IP برای شمارش.

    برخلافِ ``netutil.get_client_ip`` (که برای لاگ و ژئو نوشته شده) اینجا سرآیندِ
    ``X-Forwarded-For``/``CF-Connecting-IP`` فقط وقتی پذیرفته می‌شود که اتصال از
    پروکسیِ محلی آمده باشد. پورتِ ۸۰۰۰ مستقیم روی ``0.0.0.0`` باز است، پس هر
    مهاجمی می‌توانست با جعلِ همان سرآیند سقف را بی‌اثر کند.
    """
    peer = request.client.host if request.client else ""
    if peer and _is_trusted_peer(peer):
        for header in ("cf-connecting-ip", "x-forwarded-for", "x-real-ip"):
            value = request.headers.get(header, "")
            first = value.split(",")[0].strip()
            if first:
                return first
    return peer or "unknown"


def reset_for_tests() -> None:
    _memory_fallback.reset()
