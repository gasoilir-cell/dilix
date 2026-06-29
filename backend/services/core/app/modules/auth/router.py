"""روتر Auth (سند ۵: /v1/auth/...).

Endpoints:
  POST /register          — ثبت‌نام
  POST /login             — ورود (اگر MFA فعال: mfa_required=True)
  POST /oauth/{provider}  — ورود با Google/Microsoft/Apple/Facebook
  POST /otp/request       — ارسالِ کد به موبایل (پیامک) یا Facebook
  POST /otp/verify        — تأییدِ کد و ورود/ثبت‌نام
  POST /mfa/setup         — دریافت TOTP secret + QR
  POST /mfa/enable        — فعال‌سازی با کد تأیید
  POST /mfa/verify        — تأیید کد پس از ورود (صدور توکن کامل)
  DELETE /mfa             — غیرفعال‌سازی
  POST /device-keys       — ثبت کلید عمومی دستگاه (E2EE)
  GET  /device-keys/{eid} — دریافت bundle کلیدهای یک کاربر
  POST /token/refresh     — تجدید access token
"""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.security import create_access_token, decode_token
from app.modules.auth import mfa_service, oauth, service
from app.modules.auth.deps import get_current_earth_id
from app.modules.auth.models import DeviceKey
from app.modules.auth.schemas import (
    DeviceKeyRegister,
    DeviceKeyResponse,
    LoginRequest,
    MfaCodeRequest,
    MfaEnableResponse,
    MfaSetupResponse,
    MfaVerifyRequest,
    OAuthLoginRequest,
    OAuthLoginResponse,
    OtpRequest,
    OtpRequestResponse,
    OtpVerifyRequest,
    RegisterRequest,
    RegisterResponse,
    TokenPair,
)

router = APIRouter(prefix="/v1/auth", tags=["auth"])


# ─────────────────────── ثبت‌نام / ورود ───────────────────────

@router.post("/register", response_model=RegisterResponse, status_code=201)
async def register(
    data: RegisterRequest, db: AsyncSession = Depends(get_session)
) -> RegisterResponse:
    earth_id, tokens = await service.register(db, data)
    return RegisterResponse(earth_id=earth_id, tokens=tokens)


@router.post("/login", response_model=TokenPair)
async def login(data: LoginRequest, db: AsyncSession = Depends(get_session)) -> TokenPair:
    return await service.login(db, data)


# ─────────────────── ورودِ فدراسیون (Google/Microsoft/Apple/Facebook) ───────────────────

@router.post("/oauth/{provider}", response_model=OAuthLoginResponse)
async def oauth_login(
    provider: str,
    data: OAuthLoginRequest,
    db: AsyncSession = Depends(get_session),
) -> OAuthLoginResponse:
    """ورود/ثبت‌نام با حسابِ Google، Microsoft، Apple یا Facebook.

    کلاینت پس از رضایتِ کاربر، ``id_token`` (یا برای فیسبوک ``access_token``) را
    می‌فرستد؛ سرور آن را اعتبارسنجی و در صورتِ نیاز حسابِ Earth ID می‌سازد.
    """
    claims = oauth.verify(provider, data.credential)
    earth_id, tokens = await service.login_or_register_oauth(
        db, claims, home_region=data.home_region
    )
    return OAuthLoginResponse(earth_id=earth_id, tokens=tokens)


# ─────────────────── کدِ یک‌بارمصرف (SMS / Facebook) ───────────────────

@router.post("/otp/request", response_model=OtpRequestResponse, status_code=201)
async def otp_request(
    data: OtpRequest, db: AsyncSession = Depends(get_session)
) -> OtpRequestResponse:
    """ارسالِ کدِ تأیید به موبایل (پیامک) یا شبکه‌ی اجتماعی (Facebook Messenger)."""
    challenge = await service.request_otp(db, data)
    return OtpRequestResponse(
        challenge_id=challenge.id,
        channel=challenge.channel,
        expires_at=challenge.expires_at,
    )


@router.post("/otp/verify", response_model=OAuthLoginResponse)
async def otp_verify(
    data: OtpVerifyRequest, db: AsyncSession = Depends(get_session)
) -> OAuthLoginResponse:
    """تأییدِ کد و ورود/ثبت‌نامِ خودکار."""
    earth_id, tokens = await service.verify_otp(db, data.challenge_id, data.code)
    return OAuthLoginResponse(earth_id=earth_id, tokens=tokens)


# ─────────────────────── Token Refresh ────────────────────────

@router.post("/token/refresh", response_model=TokenPair)
async def refresh_token(body: dict) -> TokenPair:
    """تجدید access token با refresh token معتبر."""
    payload = decode_token(body.get("refresh_token", ""))
    if payload.get("type") != "refresh":
        from dilix_shared.errors import ForbiddenError
        raise ForbiddenError("توکن تجدید نامعتبر است.")
    earth_id = payload["sub"]
    return TokenPair(
        access_token=create_access_token(earth_id),
        refresh_token=body["refresh_token"],  # refresh token جدید در rotation کامل صادر می‌شود
    )


# ─────────────────────── MFA ─────────────────────────────────

@router.post("/mfa/setup", response_model=MfaSetupResponse)
async def mfa_setup(
    db: AsyncSession = Depends(get_session),
    earth_id: uuid.UUID = Depends(get_current_earth_id),
) -> MfaSetupResponse:
    """مرحله ۱: تولید TOTP secret و QR code."""
    from sqlalchemy import select as sa_select
    from app.modules.auth.models import Credential
    row = await db.execute(sa_select(Credential).where(Credential.earth_id == earth_id))
    cred = row.scalar_one_or_none()
    email = cred.email if cred else None
    result = await mfa_service.setup_mfa(db, earth_id, email)
    return MfaSetupResponse(**result)


@router.post("/mfa/enable", response_model=MfaEnableResponse)
async def mfa_enable(
    data: MfaCodeRequest,
    db: AsyncSession = Depends(get_session),
    earth_id: uuid.UUID = Depends(get_current_earth_id),
) -> MfaEnableResponse:
    """مرحله ۲: فعال‌سازی با کد TOTP."""
    backup_codes = await mfa_service.enable_mfa(db, earth_id, data.code)
    return MfaEnableResponse(backup_codes=backup_codes)


@router.post("/mfa/verify", response_model=TokenPair)
async def mfa_verify(
    data: MfaVerifyRequest, db: AsyncSession = Depends(get_session)
) -> TokenPair:
    """تأیید MFA پس از ورود موفق. توکن کامل صادر می‌شود."""
    return await mfa_service.verify_mfa(db, data.earth_id, data.code)


@router.delete("/mfa", status_code=204)
async def mfa_disable(
    data: MfaCodeRequest,
    db: AsyncSession = Depends(get_session),
    earth_id: uuid.UUID = Depends(get_current_earth_id),
) -> None:
    """غیرفعال‌سازی MFA با تأیید کد فعلی."""
    await mfa_service.disable_mfa(db, earth_id, data.code)


# ─────────────────────── Device Keys (E2EE) ──────────────────

@router.post("/device-keys", response_model=DeviceKeyResponse, status_code=201)
async def register_device_key(
    data: DeviceKeyRegister,
    db: AsyncSession = Depends(get_session),
    earth_id: uuid.UUID = Depends(get_current_earth_id),
) -> DeviceKeyResponse:
    """ثبت کلید عمومی دستگاه. کلید خصوصی هرگز به سرور نمی‌آید."""
    key = DeviceKey(
        earth_id=earth_id,
        device_id=data.device_id,
        public_key=data.public_key,
        prekey_bundle=data.prekey_bundle,
    )
    db.add(key)
    await db.flush()
    return DeviceKeyResponse(
        id=key.id,
        device_id=key.device_id,
        public_key=key.public_key,
        prekey_bundle=key.prekey_bundle,
    )


@router.get("/device-keys/{target_earth_id}", response_model=list[DeviceKeyResponse])
async def get_device_keys(
    target_earth_id: uuid.UUID,
    db: AsyncSession = Depends(get_session),
    _: uuid.UUID = Depends(get_current_earth_id),  # احراز هویت لازم است
) -> list[DeviceKeyResponse]:
    """دریافت کلیدهای عمومی یک کاربر برای شروع جلسه‌ی E2EE."""
    rows = await db.execute(
        select(DeviceKey).where(DeviceKey.earth_id == target_earth_id)
    )
    keys = rows.scalars().all()
    return [
        DeviceKeyResponse(
            id=k.id,
            device_id=k.device_id,
            public_key=k.public_key,
            prekey_bundle=k.prekey_bundle,
        )
        for k in keys
    ]
