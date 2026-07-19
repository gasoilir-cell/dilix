"""منطق احراز هویت: ثبت‌نام (با ساخت Earth ID)، ورود، توکن، OAuth و OTP."""
from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.earth_id import EntityType
from dilix_shared.errors import ConflictError, ForbiddenError, UnauthorizedError

from app.core.config import get_settings
from app.core.security import (
    create_access_token,
    create_refresh_token,
    hash_password,
    verify_password,
)
from app.modules.auth import otp as otp_lib
from app.modules.auth.models import (
    OTP_CHANNEL_FACEBOOK,
    OTP_CHANNEL_SMS,
    PROVIDER_FACEBOOK,
    Credential,
    FederatedIdentity,
    OtpChallenge,
)
from app.modules.auth.oauth import OAuthClaims
from app.modules.auth.schemas import LoginRequest, OtpRequest, RegisterRequest, TokenPair
from app.modules.identity import service as identity_service


async def register(db: AsyncSession, data: RegisterRequest) -> tuple[str, TokenPair]:
    # فقط شناسه‌های ارائه‌شده را بررسی کن؛ در غیر این صورت `field == None` توسط
    # SQLAlchemy به `IS NULL` ترجمه می‌شود و با هر ردیفِ فاقدِ آن فیلد تطبیق
    # می‌خورد (باگِ «همیشه ۴۰۹»).
    identifier_filters = []
    if data.email:
        identifier_filters.append(Credential.email == data.email)
    if data.phone:
        identifier_filters.append(Credential.phone == data.phone)
    if identifier_filters:
        existing = await db.execute(
            select(Credential).where(or_(*identifier_filters))
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
    # حساب‌های فقط-فدراسیون/OTP رمز ندارند → ورود با رمز برایشان مجاز نیست.
    if cred is None or not cred.password_hash or not verify_password(
        data.password, cred.password_hash
    ):
        raise ForbiddenError("نام کاربری یا رمز عبور نادرست است.")

    return _tokens_for(cred)


def _issue_tokens(earth_id: str) -> TokenPair:
    return TokenPair(
        access_token=create_access_token(earth_id),
        refresh_token=create_refresh_token(earth_id),
    )


def _tokens_for(cred: Credential) -> TokenPair:
    """صدورِ توکن با احترام به MFA؛ اگر MFA فعال باشد ``mfa_required`` برمی‌گردد."""
    # MFA (سند ۶): اگر فعال باشد، توکن کامل صادر نمی‌شود تا تأیید MFA.
    if cred.mfa_enabled:
        return TokenPair(access_token="", refresh_token="", mfa_required=True)
    return _issue_tokens(str(cred.earth_id))


# ─────────────────── ورودِ فدراسیون (OAuth2/OIDC) ───────────────────

async def login_or_register_oauth(
    db: AsyncSession, claims: OAuthClaims, *, home_region: str | None = None
) -> tuple[str, TokenPair]:
    """ورود یا ثبت‌نامِ خودکار با ادعاهای یک ارائه‌دهنده.

    ترتیبِ تطبیق: (۱) پیوندِ فدراسیونِ موجود → (۲) ایمیلِ تأییدشده‌ی موجود →
    (۳) ساختِ حسابِ تازه (بدونِ رمز).
    """
    # ۱) پیوندِ فدراسیونِ موجود
    fed = await db.execute(
        select(FederatedIdentity).where(
            FederatedIdentity.provider == claims.provider,
            FederatedIdentity.subject == claims.subject,
        )
    )
    link = fed.scalar_one_or_none()
    if link is not None:
        cred = await _get_credential(db, link.earth_id)
        return str(link.earth_id), _tokens_for(cred)

    # ۲) تطبیق با ایمیلِ تأییدشده‌ی موجود (link حسابِ موجود)
    earth_id: uuid.UUID | None = None
    if claims.email and claims.email_verified:
        existing = await db.execute(
            select(Credential).where(Credential.email == claims.email)
        )
        cred = existing.scalar_one_or_none()
        if cred is not None:
            earth_id = cred.earth_id

    # ۳) ساختِ حسابِ تازه
    if earth_id is None:
        identity = await identity_service.create_identity(
            db,
            entity_type=EntityType.INDIVIDUAL,
            display_name=claims.name or (claims.email or "کاربرِ دیلیکس"),
            home_region=home_region or get_settings().region,
        )
        earth_id = identity.earth_id
        db.add(
            Credential(
                earth_id=earth_id,
                email=claims.email if claims.email_verified else None,
                password_hash=None,
            )
        )

    db.add(
        FederatedIdentity(
            earth_id=earth_id,
            provider=claims.provider,
            subject=claims.subject,
            email=claims.email,
        )
    )
    await db.flush()
    cred = await _get_credential(db, earth_id)
    return str(earth_id), _tokens_for(cred)


# ─────────────────── کدِ یک‌بارمصرف (OTP) ───────────────────

async def request_otp(db: AsyncSession, data: OtpRequest) -> OtpChallenge:
    """ساختِ چالشِ OTP و تحویلِ کد از طریقِ کانالِ خواسته‌شده."""
    otp_lib.validate_channel(data.channel)
    settings = get_settings()
    code = otp_lib.generate_code()
    challenge = OtpChallenge(
        channel=data.channel,
        destination=data.destination,
        code_hash=otp_lib.hash_code(code),
        purpose=data.purpose,
        expires_at=datetime.now(timezone.utc) + timedelta(seconds=settings.otp_ttl_seconds),
    )
    db.add(challenge)
    await db.flush()
    otp_lib.deliver(data.channel, data.destination, code)
    return challenge


async def verify_otp(db: AsyncSession, challenge_id: uuid.UUID, code: str) -> tuple[str, TokenPair]:
    """تأییدِ کد و ورود/ثبت‌نامِ خودکارِ کاربر بر اساسِ کانال."""
    row = await db.execute(select(OtpChallenge).where(OtpChallenge.id == challenge_id))
    challenge = row.scalar_one_or_none()
    if challenge is None or challenge.consumed:
        raise UnauthorizedError("چالشِ کد نامعتبر است.")
    if datetime.now(timezone.utc) >= _aware(challenge.expires_at):
        raise UnauthorizedError("کد منقضی شده است.")
    if challenge.attempts >= get_settings().otp_max_attempts:
        raise UnauthorizedError("تعدادِ تلاش بیش از حد است.")
    if not otp_lib.verify_code(code, challenge.code_hash):
        challenge.attempts += 1
        await db.flush()
        raise UnauthorizedError("کد نادرست است.")

    challenge.consumed = True
    await db.flush()

    if challenge.channel == OTP_CHANNEL_SMS:
        cred = await _resolve_by_phone(db, challenge.destination)
    elif challenge.channel == OTP_CHANNEL_FACEBOOK:
        cred = await _resolve_by_federated(db, PROVIDER_FACEBOOK, challenge.destination)
    else:  # pragma: no cover — validate_channel در request جلوگیری کرده
        raise UnauthorizedError("کانالِ نامعتبر.")

    return str(cred.earth_id), _tokens_for(cred)


# ─────────────────── کمکی‌ها ───────────────────

def _aware(dt: datetime) -> datetime:
    """تضمینِ timezone-aware (SQLite گاهی naive برمی‌گرداند)."""
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)


async def _get_credential(db: AsyncSession, earth_id: uuid.UUID) -> Credential:
    row = await db.execute(select(Credential).where(Credential.earth_id == earth_id))
    cred = row.scalar_one_or_none()
    if cred is None:
        raise UnauthorizedError("اعتبارنامه یافت نشد.")
    return cred


async def _resolve_by_phone(db: AsyncSession, phone: str) -> Credential:
    row = await db.execute(select(Credential).where(Credential.phone == phone))
    cred = row.scalar_one_or_none()
    if cred is not None:
        return cred
    identity = await identity_service.create_identity(
        db,
        entity_type=EntityType.INDIVIDUAL,
        display_name=phone,
        home_region=get_settings().region,
    )
    cred = Credential(earth_id=identity.earth_id, phone=phone, password_hash=None)
    db.add(cred)
    await db.flush()
    return cred


async def _resolve_by_federated(db: AsyncSession, provider: str, subject: str) -> Credential:
    fed = await db.execute(
        select(FederatedIdentity).where(
            FederatedIdentity.provider == provider,
            FederatedIdentity.subject == subject,
        )
    )
    link = fed.scalar_one_or_none()
    if link is not None:
        return await _get_credential(db, link.earth_id)
    identity = await identity_service.create_identity(
        db,
        entity_type=EntityType.INDIVIDUAL,
        display_name="کاربرِ دیلیکس",
        home_region=get_settings().region,
    )
    cred = Credential(earth_id=identity.earth_id, password_hash=None)
    db.add(cred)
    db.add(FederatedIdentity(earth_id=identity.earth_id, provider=provider, subject=subject))
    await db.flush()
    return cred
