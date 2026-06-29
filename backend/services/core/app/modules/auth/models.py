"""مدل ORM احراز هویت (سند ۳، schema: auth). جدا از identity برای مرز Context."""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

# ارائه‌دهندگانِ ورودِ فدراسیون (OAuth2/OIDC)
PROVIDER_GOOGLE = "google"
PROVIDER_MICROSOFT = "microsoft"
PROVIDER_APPLE = "apple"
PROVIDER_FACEBOOK = "facebook"

# کانال‌های تحویلِ کدِ یک‌بارمصرف (OTP)
OTP_CHANNEL_SMS = "sms"
OTP_CHANNEL_FACEBOOK = "facebook"

# هدفِ کدِ یک‌بارمصرف
OTP_PURPOSE_LOGIN = "login"
OTP_PURPOSE_REGISTER = "register"


class Credential(Base):
    """اعتبارنامه‌ی ورود، گره‌خورده به Earth ID.

    ``password_hash`` می‌تواند ``None`` باشد برای حساب‌هایی که فقط با
    ورودِ فدراسیون (Google/Microsoft/Apple) یا کدِ یک‌بارمصرف ساخته شده‌اند.
    """

    __tablename__ = "credential"
    __table_args__ = {"schema": "auth"}

    earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    email: Mapped[str | None] = mapped_column(String(255), unique=True, nullable=True)
    phone: Mapped[str | None] = mapped_column(String(32), unique=True, nullable=True)
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    mfa_enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    mfa_secret: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class FederatedIdentity(Base):
    """پیوندِ یک حسابِ بیرونی (OAuth/OIDC) به Earth ID.

    یک کاربر می‌تواند چند ارائه‌دهنده داشته باشد؛ هر (provider, subject) یکتاست.
    """

    __tablename__ = "federated_identity"
    __table_args__ = (
        UniqueConstraint("provider", "subject", name="uq_federated_provider_subject"),
        {"schema": "auth"},
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    provider: Mapped[str] = mapped_column(String(32), nullable=False)  # google|microsoft|apple|facebook
    subject: Mapped[str] = mapped_column(String(255), nullable=False)  # ادعای `sub` نزدِ ارائه‌دهنده
    email: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class OtpChallenge(Base):
    """چالشِ کدِ یک‌بارمصرف برای ورود/ثبت‌نام بدونِ رمز.

    کد هرگز به‌صورتِ متن ذخیره نمی‌شود؛ فقط هشِ آن نگه داشته می‌شود.
    """

    __tablename__ = "otp_challenge"
    __table_args__ = {"schema": "auth"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    channel: Mapped[str] = mapped_column(String(16), nullable=False)  # sms|facebook
    destination: Mapped[str] = mapped_column(String(255), nullable=False, index=True)  # phone یا psid
    code_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    purpose: Mapped[str] = mapped_column(String(16), nullable=False, default=OTP_PURPOSE_LOGIN)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    consumed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class DeviceKey(Base):
    """کلید عمومی دستگاه برای E2EE (سند ۶). کلید خصوصی هرگز به سرور نمی‌آید."""

    __tablename__ = "device_key"
    __table_args__ = {"schema": "auth"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    device_id: Mapped[str] = mapped_column(String(128), nullable=False)
    public_key: Mapped[str] = mapped_column(String(2048), nullable=False)
    # prekey bundle — signed prekeys برای Signal Protocol (اختیاری)
    prekey_bundle: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
