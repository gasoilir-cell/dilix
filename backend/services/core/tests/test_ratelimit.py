"""تست‌های سقفِ نرخِ مسیرهای احراز هویت.

آنچه اینجا سنجیده می‌شود سه ادعای امنیتی است: حدسِ رمز، ساختِ زنجیره‌ایِ چالشِ
OTP، و بمبارانِ پیامکِ یک شماره — هر سه باید به ۴۲۹ برسند.
"""

from __future__ import annotations

import pytest

from dilix_shared.errors import RateLimitedError


@pytest.fixture(autouse=True)
def _reset():
    from app.core.ratelimit import reset_for_tests

    reset_for_tests()
    yield
    reset_for_tests()


# ── هسته‌ی شمارنده ────────────────────────────────────────────────────────────


async def test_hit_raises_after_limit() -> None:
    from app.core.ratelimit import Rule, hit

    rule = Rule(limit=3, window=60)
    for _ in range(3):
        await hit("t", "ip-1", rule)
    with pytest.raises(RateLimitedError) as err:
        await hit("t", "ip-1", rule)
    assert err.value.status_code == 429
    assert err.value.retry_after > 0


async def test_hit_is_isolated_per_identity() -> None:
    """سقفِ یک کاربر نباید کاربرِ دیگر را قفل کند."""
    from app.core.ratelimit import Rule, hit

    rule = Rule(limit=1, window=60)
    await hit("t", "ip-1", rule)
    await hit("t", "ip-2", rule)  # نباید خطا بدهد
    with pytest.raises(RateLimitedError):
        await hit("t", "ip-1", rule)


async def test_hit_is_isolated_per_scope() -> None:
    from app.core.ratelimit import Rule, hit

    rule = Rule(limit=1, window=60)
    await hit("login", "ip-1", rule)
    await hit("otp", "ip-1", rule)


def test_rule_for_path_exact_and_prefix() -> None:
    from app.core.ratelimit import AUTH_DEFAULT_RULE, rule_for_path

    assert rule_for_path("/v1/auth/login").limit == 10
    assert rule_for_path("/v1/auth/otp/request").limit == 5
    # الگوی ستاره‌دار: هر ارائه‌دهنده‌ای زیرِ همان سقف است
    assert rule_for_path("/v1/auth/oauth/google").limit == 20
    assert rule_for_path("/v1/auth/device-keys") == AUTH_DEFAULT_RULE


# ── تشخیصِ IP ─────────────────────────────────────────────────────────────────


class _Req:
    def __init__(self, peer: str | None, forwarded: str | None = None) -> None:
        self.client = type("C", (), {"host": peer})() if peer else None
        self.headers = {"x-forwarded-for": forwarded} if forwarded else {}


def test_client_ip_trusts_forwarded_only_from_local_proxy() -> None:
    from app.core.ratelimit import client_ip

    # از پروکسیِ محلی → سرآیند معتبر است
    assert client_ip(_Req("127.0.0.1", "203.0.113.9")) == "203.0.113.9"
    # اتصالِ مستقیم از اینترنت → سرآیندِ جعلی نادیده گرفته می‌شود
    assert client_ip(_Req("203.0.113.5", "1.2.3.4")) == "203.0.113.5"
    assert client_ip(_Req(None)) == "unknown"


# ── سرتاسری: میان‌افزار روی مسیرِ واقعی ───────────────────────────────────────


async def test_auth_endpoint_returns_429_after_limit(integration) -> None:
    """مسیرِ `token/refresh` انتخاب شده چون به دیتابیس دست نمی‌زند؛ آنچه سنجیده
    می‌شود خودِ میان‌افزار است، نه منطقِ آن روت."""
    from app.core.ratelimit import AUTH_RULES

    path = "/v1/auth/token/refresh"
    limit = AUTH_RULES[path].limit
    body = {"refresh_token": "not-a-real-token"}
    for _ in range(limit):
        resp = await integration.client.post(path, json=body)
        assert resp.status_code != 429  # هنوز داخلِ سقف

    resp = await integration.client.post(path, json=body)
    assert resp.status_code == 429
    assert resp.headers["retry-after"].isdigit()
    assert resp.json()["type"].endswith("/rate_limited")


async def test_non_auth_paths_are_not_limited(integration) -> None:
    """سقف فقط روی `/v1/auth/*` است؛ مسیرهای دیگر نباید خفه شوند."""
    for _ in range(80):
        resp = await integration.client.get("/health")
        assert resp.status_code == 200


async def test_otp_destination_limit_blocks_sms_bombing() -> None:
    """چرخاندنِ IP نباید بگذارد یک شماره بی‌نهایت پیامک بگیرد."""
    from app.core.ratelimit import OTP_DESTINATION_RULE, hit

    victim = "+989120000000"
    for _ in range(OTP_DESTINATION_RULE.limit):
        await hit("otp:sms", victim, OTP_DESTINATION_RULE)
    with pytest.raises(RateLimitedError):
        await hit("otp:sms", victim, OTP_DESTINATION_RULE)
