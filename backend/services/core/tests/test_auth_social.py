"""تست‌های واحدِ ورودِ اجتماعی: OAuth (Google/Microsoft/Apple/Facebook) + OTP."""
from __future__ import annotations

import pytest

from dilix_shared.errors import UnauthorizedError, ValidationError


# ── OAuth — نگاشتِ خالصِ ادعاها ────────────────────────────────────────────────

def test_oauth_claims_from_payload_basic() -> None:
    from app.modules.auth.oauth import _claims_from_payload
    claims = _claims_from_payload(
        "google",
        {"sub": "123", "email": "a@b.com", "email_verified": True, "name": "علی"},
    )
    assert claims.provider == "google"
    assert claims.subject == "123"
    assert claims.email == "a@b.com"
    assert claims.email_verified is True
    assert claims.name == "علی"


def test_oauth_claims_email_verified_string_true() -> None:
    """اپل گاهی email_verified را به‌صورتِ رشته‌ی "true" می‌فرستد."""
    from app.modules.auth.oauth import _claims_from_payload
    claims = _claims_from_payload("apple", {"sub": "x", "email_verified": "true"})
    assert claims.email_verified is True


def test_oauth_claims_requires_subject() -> None:
    from app.modules.auth.oauth import _claims_from_payload
    with pytest.raises(UnauthorizedError):
        _claims_from_payload("google", {"email": "a@b.com"})


# ── OAuth — گیتِ پیکربندی و ارائه‌دهنده‌ی ناشناخته ─────────────────────────────

def test_oauth_verify_unknown_provider() -> None:
    from app.modules.auth.oauth import verify
    with pytest.raises(ValidationError):
        verify("twitter", "some-token")


def test_oauth_verify_unconfigured_google_raises() -> None:
    """وقتی Client ID پیکربندی نشده، ورودِ google باید خطای پیکربندی بدهد."""
    from app.modules.auth.oauth import verify
    with pytest.raises(ValidationError):
        verify("google", "header.payload.sig")


def test_oauth_verify_unconfigured_facebook_raises() -> None:
    from app.modules.auth.oauth import verify
    with pytest.raises(ValidationError):
        verify("facebook", "fb-access-token")


def test_oauth_provider_constants() -> None:
    from app.modules.auth.models import (
        PROVIDER_APPLE,
        PROVIDER_FACEBOOK,
        PROVIDER_GOOGLE,
        PROVIDER_MICROSOFT,
    )
    assert {PROVIDER_GOOGLE, PROVIDER_MICROSOFT, PROVIDER_APPLE, PROVIDER_FACEBOOK} == {
        "google", "microsoft", "apple", "facebook",
    }


# ── OTP — تولید، هش، اعتبارِ کانال ───────────────────────────────────────────

def test_otp_generate_code_length_and_digits() -> None:
    from app.modules.auth import otp
    code = otp.generate_code()
    assert len(code) == 6
    assert code.isdigit()
    assert len(otp.generate_code(8)) == 8


def test_otp_hash_roundtrip() -> None:
    from app.modules.auth import otp
    code = "482913"
    h = otp.hash_code(code)
    assert h != code  # هرگز متنِ خام
    assert otp.verify_code(code, h) is True
    assert otp.verify_code("000000", h) is False


def test_otp_validate_channel() -> None:
    from app.modules.auth import otp
    otp.validate_channel("sms")
    otp.validate_channel("facebook")
    with pytest.raises(ValidationError):
        otp.validate_channel("telegram")


def test_otp_deliver_noop_in_dev_when_unconfigured() -> None:
    """در توسعه و بدونِ پیکربندیِ کانال، تحویل بدونِ خطا no-op است (کد لو نمی‌رود)."""
    from app.modules.auth import otp
    otp.deliver("sms", "+989120000000", "123456")
    otp.deliver("facebook", "PSID123", "123456")


def test_otp_deliver_invalid_channel() -> None:
    from app.modules.auth import otp
    with pytest.raises(ValidationError):
        otp.deliver("email", "x@y.com", "123456")


# ── Config — تجزیه‌ی CSV و گیت‌ها ─────────────────────────────────────────────

def test_settings_csv_client_ids() -> None:
    from app.core.config import Settings
    s = Settings(google_client_ids="aaa.apps.googleusercontent.com, bbb ,")
    assert s.google_client_id_set == {"aaa.apps.googleusercontent.com", "bbb"}


def test_settings_channel_enabled_flags() -> None:
    from app.core.config import Settings
    off = Settings()
    assert off.sms_enabled is False
    assert off.facebook_otp_enabled is False
    on = Settings(
        sms_base_url="https://sms.example", sms_api_key="k", facebook_page_token="t"
    )
    assert on.sms_enabled is True
    assert on.facebook_otp_enabled is True


# ── Schemas — اعتبارسنجیِ ورودی ───────────────────────────────────────────────

def test_otp_request_schema_rejects_bad_channel() -> None:
    from pydantic import ValidationError as PydErr
    from app.modules.auth.schemas import OtpRequest
    OtpRequest(channel="sms", destination="+989120000000")
    with pytest.raises(PydErr):
        OtpRequest(channel="telegram", destination="x")


def test_error_status_codes() -> None:
    assert UnauthorizedError("x").status_code == 401
    assert ValidationError("x").status_code == 400
