"""منطق احراز هویت: ثبت‌نام (با ساخت Earth ID)، ورود، توکن."""
from __future__ import annotations

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.errors import ConflictError, ForbiddenError

from app.core.security import (
    create_access_token,
    create_refresh_token,
    hash_password,
    verify_password,
)
from app.modules.auth.models import Credential
from app.modules.auth.schemas import LoginRequest, RegisterRequest, TokenPair
from app.modules.identity import service as identity_service


async def register(db: AsyncSession, data: RegisterRequest) -> tuple[str, TokenPair]:
    existing = await db.execute(
        select(Credential).where(
            or_(Credential.email == data.email, Credential.phone == data.phone)
        )
    )
    if existing.scalar_one_or_none() is not None:
        raise ConflictError("کاربری با این ایمیل/تلفن وجود دارد.")

    identity = await identity_service.create_identity(
        db,
        entity_type=data.entity_type,
        display_name=data.display_name,
        home_region=data.home_region,
    )
    db.add(
        Credential(
            earth_id=identity.earth_id,
            email=data.email,
            phone=data.phone,
            password_hash=hash_password(data.password),
        )
    )
    await db.flush()
    return str(identity.earth_id), _issue_tokens(str(identity.earth_id))


async def login(db: AsyncSession, data: LoginRequest) -> TokenPair:
    result = await db.execute(
        select(Credential).where(
            or_(Credential.email == data.identifier, Credential.phone == data.identifier)
        )
    )
    cred = result.scalar_one_or_none()
    if cred is None or not verify_password(data.password, cred.password_hash):
        raise ForbiddenError("نام کاربری یا رمز عبور نادرست است.")

    # MFA (سند ۶): اگر فعال باشد، توکن کامل صادر نمی‌شود تا تأیید MFA.
    if cred.mfa_enabled:
        return TokenPair(access_token="", refresh_token="", mfa_required=True)
    return _issue_tokens(str(cred.earth_id))


def _issue_tokens(earth_id: str) -> TokenPair:
    return TokenPair(
        access_token=create_access_token(earth_id),
        refresh_token=create_refresh_token(earth_id),
    )
