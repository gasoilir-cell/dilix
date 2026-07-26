"""
Dilix — سرویس احرازِ هویتِ اجتماعی (Social / OAuth)
تأییدِ امنِ توکنِ ورودِ شبکه‌های اجتماعی در سمتِ سرور:
  • Google / Microsoft / Apple  → id_token (OIDC) با امضایِ JWKS
  • Facebook                    → access_token از طریقِ Graph API
هیچ توکنی بدونِ تأییدِ امضا/مخاطب (audience) پذیرفته نمی‌شود.

نکته: در محیط‌هایی که دسترسی به googleapis.com مسدود است (ایران),
کلیدها از فایل /var/www/dilix-api/google-jwks-cache.json خوانده می‌شوند.
برای به‌روزرسانی فایل، از ماشین محلی (خارج از ایران) اجرا کنید:
  ssh root@SERVER "curl -s https://www.googleapis.com/oauth2/v3/certs > /var/www/dilix-api/google-jwks-cache.json"
"""
from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass

import httpx
import structlog
from jose import jwt

from app.core.config import settings

log = structlog.get_logger(__name__)

GOOGLE = "google"
MICROSOFT = "microsoft"
APPLE = "apple"
FACEBOOK = "facebook"
PROVIDERS = {GOOGLE, MICROSOFT, APPLE, FACEBOOK}

# پیکربندیِ OIDC هر provider: (jwks_uri, local_cache_file, issuers مجاز)
_OIDC = {
    GOOGLE: (
        "https://www.googleapis.com/oauth2/v3/certs",
        "/var/www/dilix-api/google-jwks-cache.json",
        {"https://accounts.google.com", "accounts.google.com"},
    ),
    MICROSOFT: (
        "https://login.microsoftonline.com/common/discovery/v2.0/keys",
        None,
        None,
    ),
    APPLE: (
        "https://appleid.apple.com/auth/keys",
        None,
        {"https://appleid.apple.com"},
    ),
}

# کشِ سادهٔ JWKS در حافظه
_jwks_cache: dict[str, tuple[float, dict]] = {}
_JWKS_TTL = 3600.0


class OAuthError(Exception):
    """خطایِ تأییدِ ورودِ اجتماعی."""


@dataclass
class OAuthClaims:
    provider: str
    subject: str
    email: str | None
    full_name: str | None


def _audience_set(provider: str) -> set[str]:
    raw = {
        GOOGLE: settings.GOOGLE_CLIENT_IDS,
        MICROSOFT: settings.MICROSOFT_CLIENT_IDS,
        APPLE: settings.APPLE_CLIENT_IDS,
    }[provider]
    return {c.strip() for c in raw.split(",") if c.strip()}


def _load_local_jwks(path: str) -> dict | None:
    """بارگذاری JWKS از فایل محلی (اگر وجود داشت)."""
    if not path or not os.path.isfile(path):
        return None
    try:
        with open(path) as f:
            data = json.load(f)
        if data.get("keys"):
            age_hours = (time.time() - os.path.getmtime(path)) / 3600
            if age_hours > 48:
                log.warning("google_jwks_cache_stale", age_hours=round(age_hours, 1))
            else:
                log.info("google_jwks_loaded_from_file", age_hours=round(age_hours, 1))
            return data
    except Exception as e:
        log.error("google_jwks_file_read_error", error=str(e))
    return None


async def _fetch_jwks(uri: str, local_cache_file: str | None = None) -> dict:
    now = time.time()
    cached = _jwks_cache.get(uri)
    if cached and now - cached[0] < _JWKS_TTL:
        return cached[1]

    # ابتدا تلاش برای دریافت از شبکه
    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.get(uri)
            resp.raise_for_status()
            data = resp.json()
        _jwks_cache[uri] = (now, data)
        # ذخیره در فایل محلی برای استفادهٔ بعدی
        if local_cache_file:
            try:
                with open(local_cache_file, "w") as f:
                    json.dump(data, f)
            except Exception:
                pass
        return data
    except Exception as e:
        log.warning("jwks_network_fetch_failed", uri=uri, error=str(e))

    # fallback به فایل محلی
    if local_cache_file:
        local = _load_local_jwks(local_cache_file)
        if local:
            _jwks_cache[uri] = (now, local)
            return local

    raise OAuthError("کلیدهای تأیید هویت در دسترس نیستند. لطفاً دوباره تلاش کنید.")


async def _verify_oidc(provider: str, id_token: str) -> OAuthClaims:
    audiences = _audience_set(provider)
    if not audiences:
        raise OAuthError(f"ورود با {provider} پیکربندی نشده است.")

    jwks_uri, local_cache_file, issuers = _OIDC[provider]
    try:
        header = jwt.get_unverified_header(id_token)
    except Exception:
        raise OAuthError("توکنِ نامعتبر.")

    kid = header.get("kid")
    jwks = await _fetch_jwks(jwks_uri, local_cache_file)
    key = next((k for k in jwks.get("keys", []) if k.get("kid") == kid), None)
    if key is None:
        # شاید کلیدها چرخیده‌اند — کش را پاک و یک‌بار دیگر امتحان کن
        _jwks_cache.pop(jwks_uri, None)
        jwks = await _fetch_jwks(jwks_uri, local_cache_file)
        key = next((k for k in jwks.get("keys", []) if k.get("kid") == kid), None)
    if key is None:
        raise OAuthError("کلیدِ امضایِ توکن یافت نشد — فایل کش نیاز به به‌روزرسانی دارد.")

    last_err: Exception | None = None
    claims = None
    for aud in audiences:
        try:
            claims = jwt.decode(
                id_token,
                key,
                algorithms=[key.get("alg", "RS256")],
                audience=aud,
                options={"verify_at_hash": False},
            )
            break
        except Exception as e:
            last_err = e
            claims = None
    if claims is None:
        raise OAuthError("تأییدِ توکن ناموفق بود.") from last_err

    if issuers and claims.get("iss") not in issuers:
        raise OAuthError("صادرکنندهٔ توکن نامعتبر است.")

    sub = claims.get("sub")
    if not sub:
        raise OAuthError("شناسهٔ کاربر در توکن نیست.")

    name = claims.get("name") or claims.get("given_name")
    return OAuthClaims(provider=provider, subject=sub, email=claims.get("email"), full_name=name)


async def _verify_facebook(access_token: str) -> OAuthClaims:
    app_id = settings.FACEBOOK_APP_ID
    app_secret = settings.FACEBOOK_APP_SECRET
    if not app_id or not app_secret:
        raise OAuthError("ورود با Facebook پیکربندی نشده است.")

    async with httpx.AsyncClient(timeout=10.0) as client:
        debug = await client.get(
            "https://graph.facebook.com/debug_token",
            params={"input_token": access_token, "access_token": f"{app_id}|{app_secret}"},
        )
        debug.raise_for_status()
        info = debug.json().get("data", {})
        if not info.get("is_valid") or str(info.get("app_id")) != str(app_id):
            raise OAuthError("توکنِ Facebook نامعتبر است.")

        me = await client.get(
            "https://graph.facebook.com/me",
            params={"fields": "id,name,email", "access_token": access_token},
        )
        me.raise_for_status()
        data = me.json()

    sub = data.get("id")
    if not sub:
        raise OAuthError("شناسهٔ Facebook دریافت نشد.")
    return OAuthClaims(provider=FACEBOOK, subject=sub, email=data.get("email"), full_name=data.get("name"))


async def verify(provider: str, credential: str) -> OAuthClaims:
    """تأییدِ توکنِ provider و بازگرداندنِ claims. در صورتِ خطا OAuthError."""
    if provider not in PROVIDERS:
        raise OAuthError("provider پشتیبانی نمی‌شود.")
    if not credential:
        raise OAuthError("توکنِ ورود ارسال نشده است.")
    if provider == FACEBOOK:
        return await _verify_facebook(credential)
    return await _verify_oidc(provider, credential)
