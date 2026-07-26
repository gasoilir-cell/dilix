"""
Dilix — امنیت: JWT، OTP، رمزنگاری
"""
import random
import string
from datetime import datetime, timedelta, timezone
from typing import Any

import bcrypt
from jose import jwt

from app.core.config import settings

# ─── Password ─────────────────────────────────────────────────

def hash_password(password: str) -> str:
    # bcrypt محدودیتِ ۷۲ بایت دارد؛ ورودی به‌صورتِ استاندارد کوتاه می‌شود.
    pw = password.encode("utf-8")[:72]
    return bcrypt.hashpw(pw, bcrypt.gensalt()).decode("utf-8")


def verify_password(plain: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(plain.encode("utf-8")[:72], hashed.encode("utf-8"))
    except (ValueError, TypeError):
        return False


# ─── JWT ──────────────────────────────────────────────────────

def create_access_token(data: dict[str, Any]) -> str:
    payload = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES
    )
    payload.update({"exp": expire, "type": "access"})
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)


def create_refresh_token(data: dict[str, Any]) -> str:
    payload = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(
        days=settings.REFRESH_TOKEN_EXPIRE_DAYS
    )
    payload.update({"exp": expire, "type": "refresh"})
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)


def decode_token(token: str) -> dict[str, Any]:
    """
    raises JWTError اگر نامعتبر یا منقضی شده باشد
    """
    return jwt.decode(token, settings.JWT_SECRET, algorithms=[settings.JWT_ALGORITHM])


# ─── OTP ──────────────────────────────────────────────────────

def generate_otp(length: int = None) -> str:
    """تولید OTP عددی"""
    length = length or settings.OTP_LENGTH
    return "".join(random.choices(string.digits, k=length))


def generate_earth_id() -> str:
    """
    Earth ID — شناسه منحصربه‌فرد جهانی کاربر Dilix
    فرمت: DLX-XXXXXX (حروف + اعداد بزرگ)
    """
    chars = string.ascii_uppercase + string.digits
    suffix = "".join(random.choices(chars, k=8))
    return f"DLX-{suffix}"
