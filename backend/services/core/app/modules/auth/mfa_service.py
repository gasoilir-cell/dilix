"""سرویس MFA — TOTP (RFC 6238) برای احراز هویت دو‌مرحله‌ای (سند ۶).

جریان:
  ۱. POST /v1/auth/mfa/setup   → secret + QR URI برمی‌گرداند (هنوز فعال نیست)
  ۲. POST /v1/auth/mfa/enable  → کد TOTP تأیید + فعال‌سازی
  ۳. POST /v1/auth/mfa/verify  → تأیید کد پس از ورود (وقتی mfa_required=True)
  ۴. DELETE /v1/auth/mfa       → غیرفعال‌سازی با کد TOTP

سیاست امنیتی: secret فقط یک‌بار در setup بازگشت داده می‌شود و سپس در DB رمزنگاری‌شده
نگه داشته می‌شود (در پیاده‌سازی کامل با KMS؛ اینجا ساده‌سازی‌شده).
"""
from __future__ import annotations

import base64
import io
import secrets
import uuid

import pyotp
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.errors import ConflictError, ForbiddenError, NotFoundError

from app.core.security import create_access_token, create_refresh_token
from app.modules.auth.models import Credential
from app.modules.auth.schemas import TokenPair

ISSUER = "Dilix"
TOTP_WINDOW = 1  # ±30 ثانیه تلرانس


async def _get_cred(db: AsyncSession, earth_id: uuid.UUID) -> Credential:
    row = await db.execute(select(Credential).where(Credential.earth_id == earth_id))
    cred = row.scalar_one_or_none()
    if cred is None:
        raise NotFoundError("اعتبارنامه یافت نشد.")
    return cred


# ─────────────────────────── Setup ────────────────────────────

async def setup_mfa(db: AsyncSession, earth_id: uuid.UUID, email: str | None) -> dict:
    """مرحله‌ی اول: تولید secret و بازگرداندن QR URI."""
    cred = await _get_cred(db, earth_id)
    if cred.mfa_enabled:
        raise ConflictError("MFA قبلاً فعال شده است.")

    secret = pyotp.random_base32()
    # ذخیره‌ی موقت (هنوز فعال نیست تا تأیید)
    cred.mfa_secret = secret
    await db.flush()

    label = email or str(earth_id)
    totp = pyotp.TOTP(secret)
    uri = totp.provisioning_uri(name=label, issuer_name=ISSUER)

    # تولید QR code به‌صورت data URL (اگر qrcode نصب باشد)
    qr_data_url: str | None = None
    try:
        import qrcode  # type: ignore
        img = qrcode.make(uri)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        b64 = base64.b64encode(buf.getvalue()).decode()
        qr_data_url = f"data:image/png;base64,{b64}"
    except ImportError:
        pass

    return {
        "secret": secret,
        "otpauth_uri": uri,
        "qr_data_url": qr_data_url,
    }


# ─────────────────────────── Enable ───────────────────────────

async def enable_mfa(db: AsyncSession, earth_id: uuid.UUID, code: str) -> list[str]:
    """مرحله‌ی دوم: تأیید کد و فعال‌سازی. لیست backup codes برمی‌گردد."""
    cred = await _get_cred(db, earth_id)
    if cred.mfa_enabled:
        raise ConflictError("MFA قبلاً فعال شده است.")
    if not cred.mfa_secret:
        raise ForbiddenError("ابتدا setup را انجام دهید.")

    totp = pyotp.TOTP(cred.mfa_secret)
    if not totp.verify(code, valid_window=TOTP_WINDOW):
        raise ForbiddenError("کد MFA نادرست است.")

    cred.mfa_enabled = True
    await db.flush()

    # تولید ۸ کد پشتیبان (هر کدام یک‌بارمصرف — در پیاده‌سازی کامل در DB هش‌شده ذخیره شوند)
    backup_codes = [secrets.token_hex(4).upper() for _ in range(8)]
    return backup_codes


# ─────────────────────────── Verify ───────────────────────────

async def verify_mfa(db: AsyncSession, earth_id: uuid.UUID, code: str) -> TokenPair:
    """تأیید کد پس از ورود اولیه. توکن کامل صادر می‌شود."""
    cred = await _get_cred(db, earth_id)
    if not cred.mfa_enabled or not cred.mfa_secret:
        raise ForbiddenError("MFA فعال نیست.")

    totp = pyotp.TOTP(cred.mfa_secret)
    if not totp.verify(code, valid_window=TOTP_WINDOW):
        raise ForbiddenError("کد MFA نادرست یا منقضی است.")

    return TokenPair(
        access_token=create_access_token(str(earth_id)),
        refresh_token=create_refresh_token(str(earth_id)),
    )


# ─────────────────────────── Disable ──────────────────────────

async def disable_mfa(db: AsyncSession, earth_id: uuid.UUID, code: str) -> None:
    """غیرفعال‌سازی MFA با تأیید کد فعلی."""
    cred = await _get_cred(db, earth_id)
    if not cred.mfa_enabled or not cred.mfa_secret:
        raise ForbiddenError("MFA فعال نیست.")

    totp = pyotp.TOTP(cred.mfa_secret)
    if not totp.verify(code, valid_window=TOTP_WINDOW):
        raise ForbiddenError("کد MFA نادرست است.")

    cred.mfa_enabled = False
    cred.mfa_secret = None
    await db.flush()
