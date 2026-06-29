"""کدِ یک‌بارمصرف (OTP): تولید، هش، و تحویل از طریقِ کانال‌ها.

کانال‌ها:
* ``sms``      → ارسالِ پیامک به شماره‌ی موبایل از طریقِ درگاهِ پیامک.
* ``facebook`` → ارسالِ پیام به کاربر در Messenger با Send API (با PSID).

کد هرگز به‌صورتِ متن ذخیره نمی‌شود؛ فقط HMAC-SHA256 آن نگه داشته می‌شود. در محیطِ
توسعه اگر کانالی پیکربندی نشده باشد، تحویل no-op است (کد لو نمی‌رود)؛ در production
نبودِ پیکربندی خطا می‌دهد.
"""
from __future__ import annotations

import hashlib
import hmac
import secrets

import httpx

from dilix_shared.errors import ProviderError, ValidationError

from app.core.config import get_settings
from app.modules.auth.models import OTP_CHANNEL_FACEBOOK, OTP_CHANNEL_SMS

_VALID_CHANNELS = {OTP_CHANNEL_SMS, OTP_CHANNEL_FACEBOOK}


def generate_code(length: int | None = None) -> str:
    """تولیدِ کدِ عددیِ تصادفیِ امن."""
    n = length or get_settings().otp_length
    return "".join(secrets.choice("0123456789") for _ in range(n))


def hash_code(code: str) -> str:
    """هشِ HMAC-SHA256 کد با کلیدِ سرور (مقایسه‌ی پایدار در برابرِ timing)."""
    secret = get_settings().jwt_secret.encode()
    return hmac.new(secret, code.encode(), hashlib.sha256).hexdigest()


def verify_code(code: str, code_hash: str) -> bool:
    return hmac.compare_digest(hash_code(code), code_hash)


def _message(code: str) -> str:
    return f"کدِ تأییدِ دیلیکس: {code}"


def _send_sms(destination: str, code: str) -> None:
    settings = get_settings()
    if not settings.sms_enabled:
        if settings.is_production:
            raise ProviderError("درگاهِ پیامک پیکربندی نشده است.")
        return  # توسعه: no-op
    try:
        with httpx.Client(timeout=10.0) as client:
            resp = client.post(
                settings.sms_base_url,
                headers={"Authorization": f"Bearer {settings.sms_api_key}"},
                json={"to": destination, "from": settings.sms_sender, "text": _message(code)},
            )
            resp.raise_for_status()
    except httpx.HTTPError as exc:
        raise ProviderError("ارسالِ پیامک ناموفق بود.") from exc


def _send_facebook(destination: str, code: str) -> None:
    """ارسالِ کد به کاربر در Messenger؛ ``destination`` همان PSID است."""
    settings = get_settings()
    if not settings.facebook_otp_enabled:
        if settings.is_production:
            raise ProviderError("کانالِ Facebook پیکربندی نشده است.")
        return  # توسعه: no-op
    try:
        with httpx.Client(timeout=10.0) as client:
            resp = client.post(
                "https://graph.facebook.com/v19.0/me/messages",
                params={"access_token": settings.facebook_page_token},
                json={
                    "recipient": {"id": destination},
                    "messaging_type": "MESSAGE_TAG",
                    "tag": "ACCOUNT_UPDATE",
                    "message": {"text": _message(code)},
                },
            )
            resp.raise_for_status()
    except httpx.HTTPError as exc:
        raise ProviderError("ارسالِ پیامِ Facebook ناموفق بود.") from exc


def deliver(channel: str, destination: str, code: str) -> None:
    """تحویلِ کد از طریقِ کانالِ مشخص‌شده."""
    if channel == OTP_CHANNEL_SMS:
        _send_sms(destination, code)
    elif channel == OTP_CHANNEL_FACEBOOK:
        _send_facebook(destination, code)
    else:
        raise ValidationError(f"کانالِ نامعتبر: {channel}")


def validate_channel(channel: str) -> None:
    if channel not in _VALID_CHANNELS:
        raise ValidationError(f"کانالِ نامعتبر: {channel}")
