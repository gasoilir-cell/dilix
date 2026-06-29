"""اعتبارسنجیِ ورودِ فدراسیون (OAuth2/OIDC): Google, Microsoft, Apple, Facebook.

سرور **هرگز** به رمزِ کاربرِ ارائه‌دهنده دسترسی ندارد؛ فقط توکنی که کلاینت پس از
رضایتِ کاربر گرفته را اعتبارسنجی می‌کند:

* Google / Microsoft / Apple → ``id_token`` (JWT/OIDC) با امضای RS256/ES256 که با
  کلیدهای عمومیِ JWKS ارائه‌دهنده راستی‌آزمایی می‌شود و ``aud`` باید با یکی از
  Client IDهای پیکربندی‌شده برابر باشد.
* Facebook → ``access_token`` که با Graph API (``/debug_token`` + ``/me``) بررسی
  می‌شود.

طراحی‌شده برای تست‌پذیری: تابعِ سطح‌بالای :func:`verify` را می‌توان در تست
monkeypatch کرد؛ منطقِ خالصِ نگاشتِ ادعاها در :func:`_claims_from_payload` است.
"""
from __future__ import annotations

from dataclasses import dataclass

import httpx
import jwt

from dilix_shared.errors import UnauthorizedError, ValidationError

from app.core.config import get_settings
from app.modules.auth.models import (
    PROVIDER_APPLE,
    PROVIDER_FACEBOOK,
    PROVIDER_GOOGLE,
    PROVIDER_MICROSOFT,
)

# نقاطِ پایانِ OIDC هر ارائه‌دهنده
_GOOGLE_ISSUERS = {"https://accounts.google.com", "accounts.google.com"}
_GOOGLE_JWKS = "https://www.googleapis.com/oauth2/v3/certs"
_APPLE_ISSUER = "https://appleid.apple.com"
_APPLE_JWKS = "https://appleid.apple.com/auth/keys"
_MICROSOFT_JWKS = "https://login.microsoftonline.com/common/discovery/v2.0/keys"
_MICROSOFT_ISSUER_PREFIX = "https://login.microsoftonline.com/"

_FB_GRAPH = "https://graph.facebook.com"

_OIDC_ALGS = ["RS256", "ES256"]


@dataclass(slots=True)
class OAuthClaims:
    """ادعاهای نرمال‌شده‌ی هویتِ یک ارائه‌دهنده."""

    provider: str
    subject: str
    email: str | None = None
    email_verified: bool = False
    name: str | None = None


def _claims_from_payload(provider: str, payload: dict) -> OAuthClaims:
    """نگاشتِ خالصِ payloadِ id_token به :class:`OAuthClaims` (واحدتست‌پذیر)."""
    sub = payload.get("sub")
    if not sub:
        raise UnauthorizedError("توکنِ ارائه‌دهنده فاقدِ شناسه (sub) است.")
    ev = payload.get("email_verified")
    if isinstance(ev, str):
        ev = ev.lower() == "true"
    return OAuthClaims(
        provider=provider,
        subject=str(sub),
        email=payload.get("email"),
        email_verified=bool(ev),
        name=payload.get("name"),
    )


def _verify_oidc(
    *,
    provider: str,
    id_token: str,
    jwks_uri: str,
    audiences: set[str],
    issuers: set[str] | None = None,
    issuer_prefix: str | None = None,
) -> OAuthClaims:
    if not audiences:
        raise ValidationError(f"ورود با {provider} پیکربندی نشده است.")
    try:
        signing_key = jwt.PyJWKClient(jwks_uri).get_signing_key_from_jwt(id_token)
        # issuer را وقتی ثابت است خودِ pyjwt بررسی می‌کند؛ برای microsoft (tenantِ متغیر)
        # دستی بررسی می‌کنیم.
        payload = jwt.decode(
            id_token,
            signing_key.key,
            algorithms=_OIDC_ALGS,
            audience=list(audiences),
            issuer=list(issuers) if issuers else None,
            options={"verify_iss": bool(issuers)},
        )
    except jwt.PyJWTError as exc:
        raise UnauthorizedError(f"توکنِ {provider} نامعتبر یا منقضی است.") from exc

    if issuer_prefix is not None:
        iss = str(payload.get("iss", ""))
        if not iss.startswith(issuer_prefix):
            raise UnauthorizedError(f"صادرکننده‌ی توکنِ {provider} نامعتبر است.")

    return _claims_from_payload(provider, payload)


def _verify_facebook(access_token: str) -> OAuthClaims:
    settings = get_settings()
    if not (settings.facebook_app_id and settings.facebook_app_secret):
        raise ValidationError("ورود با Facebook پیکربندی نشده است.")
    app_token = f"{settings.facebook_app_id}|{settings.facebook_app_secret}"
    try:
        with httpx.Client(timeout=10.0) as client:
            debug = client.get(
                f"{_FB_GRAPH}/debug_token",
                params={"input_token": access_token, "access_token": app_token},
            )
            debug.raise_for_status()
            data = debug.json().get("data", {})
            if not data.get("is_valid") or str(data.get("app_id")) != settings.facebook_app_id:
                raise UnauthorizedError("توکنِ Facebook نامعتبر است.")
            me = client.get(
                f"{_FB_GRAPH}/me",
                params={"fields": "id,name,email", "access_token": access_token},
            )
            me.raise_for_status()
            profile = me.json()
    except httpx.HTTPError as exc:
        raise UnauthorizedError("اعتبارسنجیِ توکنِ Facebook ناموفق بود.") from exc

    sub = profile.get("id") or data.get("user_id")
    if not sub:
        raise UnauthorizedError("توکنِ Facebook فاقدِ شناسه‌ی کاربر است.")
    return OAuthClaims(
        provider=PROVIDER_FACEBOOK,
        subject=str(sub),
        email=profile.get("email"),
        email_verified=bool(profile.get("email")),
        name=profile.get("name"),
    )


def verify(provider: str, credential: str) -> OAuthClaims:
    """اعتبارسنجیِ توکنِ ارائه‌دهنده و بازگرداندنِ ادعاهای نرمال‌شده.

    ``credential`` برای Google/Microsoft/Apple همان ``id_token`` و برای Facebook
    همان ``access_token`` است.
    """
    settings = get_settings()
    if provider == PROVIDER_GOOGLE:
        return _verify_oidc(
            provider=provider,
            id_token=credential,
            jwks_uri=_GOOGLE_JWKS,
            audiences=settings.google_client_id_set,
            issuers=_GOOGLE_ISSUERS,
        )
    if provider == PROVIDER_APPLE:
        return _verify_oidc(
            provider=provider,
            id_token=credential,
            jwks_uri=_APPLE_JWKS,
            audiences=settings.apple_client_id_set,
            issuers={_APPLE_ISSUER},
        )
    if provider == PROVIDER_MICROSOFT:
        return _verify_oidc(
            provider=provider,
            id_token=credential,
            jwks_uri=_MICROSOFT_JWKS,
            audiences=settings.microsoft_client_id_set,
            issuer_prefix=_MICROSOFT_ISSUER_PREFIX,
        )
    if provider == PROVIDER_FACEBOOK:
        return _verify_facebook(credential)
    raise ValidationError(f"ارائه‌دهنده‌ی ناشناخته: {provider}")
