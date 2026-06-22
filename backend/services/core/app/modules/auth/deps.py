"""Dependencyهای احراز هویت برای روترها (استخراج کاربر جاری از JWT)."""
from __future__ import annotations

import uuid
from dataclasses import dataclass

import jwt
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from dilix_shared.errors import ForbiddenError

from app.core.security import decode_token

_bearer = HTTPBearer(auto_error=True)


@dataclass(slots=True)
class CurrentUser:
    earth_id: uuid.UUID
    region: str


async def get_current_user(
    creds: HTTPAuthorizationCredentials = Depends(_bearer),
) -> CurrentUser:
    try:
        payload = decode_token(creds.credentials)
    except jwt.PyJWTError as exc:  # امضا/انقضای نامعتبر
        raise ForbiddenError("توکن نامعتبر یا منقضی است.") from exc
    if payload.get("type") != "access":
        raise ForbiddenError("نوع توکن نامعتبر است.")
    return CurrentUser(
        earth_id=uuid.UUID(payload["sub"]),
        region=payload.get("region", "IR"),
    )


async def get_current_earth_id(
    user: CurrentUser = Depends(get_current_user),
) -> uuid.UUID:
    """شناسهٔ Earth کاربر جاری (میان‌بر برای روترهایی که فقط earth_id لازم دارند)."""
    return user.earth_id
