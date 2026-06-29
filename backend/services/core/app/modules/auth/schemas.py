"""Schemaهای Auth (سند ۵: /v1/auth/...)."""
from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, EmailStr, Field, model_validator

from dilix_shared.earth_id import EntityType


class RegisterRequest(BaseModel):
    display_name: str = Field(min_length=2, max_length=120)
    entity_type: EntityType = EntityType.INDIVIDUAL
    home_region: str = Field(default="IR", max_length=8)
    email: EmailStr | None = None
    phone: str | None = Field(default=None, max_length=32)
    password: str = Field(min_length=8, max_length=128)

    @model_validator(mode="after")
    def _need_identifier(self) -> "RegisterRequest":
        if not self.email and not self.phone:
            raise ValueError("ایمیل یا شماره تلفن الزامی است.")
        return self


class LoginRequest(BaseModel):
    identifier: str  # email یا phone
    password: str


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    mfa_required: bool = False


class RegisterResponse(BaseModel):
    earth_id: uuid.UUID
    tokens: TokenPair


# ─────────────────── ورودِ فدراسیون (OAuth/OIDC) ───────────────────
class OAuthLoginRequest(BaseModel):
    """ورود/ثبت‌نام با ارائه‌دهنده‌ی بیرونی.

    ``credential`` برای google/microsoft/apple همان ``id_token`` و برای facebook
    همان ``access_token`` است.
    """

    credential: str = Field(min_length=8, description="id_token یا access_token از کلاینت")
    home_region: str = Field(default="IR", max_length=8)


class OAuthLoginResponse(BaseModel):
    earth_id: uuid.UUID
    tokens: TokenPair


# ─────────────────── کدِ یک‌بارمصرف (OTP) ───────────────────
class OtpRequest(BaseModel):
    channel: str = Field(pattern="^(sms|facebook)$", description="کانالِ تحویل")
    destination: str = Field(min_length=3, max_length=255, description="شماره‌ی موبایل یا PSID")
    purpose: str = Field(default="login", pattern="^(login|register)$")


class OtpRequestResponse(BaseModel):
    challenge_id: uuid.UUID
    channel: str
    expires_at: datetime


class OtpVerifyRequest(BaseModel):
    challenge_id: uuid.UUID
    code: str = Field(min_length=4, max_length=8)


# ─────────────────────── MFA ───────────────────────
class MfaSetupResponse(BaseModel):
    secret: str
    otpauth_uri: str
    qr_data_url: str | None = None


class MfaCodeRequest(BaseModel):
    code: str = Field(min_length=6, max_length=8)


class MfaEnableResponse(BaseModel):
    backup_codes: list[str]


class MfaVerifyRequest(BaseModel):
    earth_id: uuid.UUID
    code: str = Field(min_length=6, max_length=8)


# ─────────────────────── Device Keys (E2EE) ────────
class DeviceKeyRegister(BaseModel):
    device_id: str = Field(max_length=128)
    public_key: str = Field(max_length=2048, description="Base64-encoded X25519 public key")
    prekey_bundle: dict | None = None  # signed prekeys برای Signal Protocol


class DeviceKeyResponse(BaseModel):
    id: uuid.UUID
    device_id: str
    public_key: str
    prekey_bundle: dict | None = None
