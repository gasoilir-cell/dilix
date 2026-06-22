"""ابزارهای امنیتی پایه: هش رمز عبور و JWT (سند ۶).

نکته: این لایه فقط احراز هویت پایه را پوشش می‌دهد. MFA، چرخش refresh،
و E2EE در ماژول‌های اختصاصی پیاده می‌شوند.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
from passlib.context import CryptContext

from app.core.config import get_settings

_settings = get_settings()
_pwd = CryptContext(schemes=["argon2"], deprecated="auto")


def hash_password(raw: str) -> str:
    return _pwd.hash(raw)


def verify_password(raw: str, hashed: str) -> bool:
    return _pwd.verify(raw, hashed)


def _create_token(subject: str, ttl_seconds: int, token_type: str, **claims: Any) -> str:
    now = datetime.now(timezone.utc)
    payload: dict[str, Any] = {
        "sub": subject,
        "type": token_type,
        "iat": now,
        "exp": now + timedelta(seconds=ttl_seconds),
        "jti": str(uuid.uuid4()),
        "region": _settings.region,
        **claims,
    }
    return jwt.encode(payload, _settings.jwt_secret, algorithm=_settings.jwt_algorithm)


def create_access_token(earth_id: str, **claims: Any) -> str:
    return _create_token(earth_id, _settings.access_token_ttl_seconds, "access", **claims)


def create_refresh_token(earth_id: str) -> str:
    return _create_token(earth_id, _settings.refresh_token_ttl_seconds, "refresh")


def decode_token(token: str) -> dict[str, Any]:
    return jwt.decode(token, _settings.jwt_secret, algorithms=[_settings.jwt_algorithm])
