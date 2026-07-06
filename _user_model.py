"""
Dilix — مدل کاربر (User)
Earth ID — هویت یکپارچه جهانی
"""
import uuid
from datetime import datetime, timezone
from sqlalchemy import (
    Boolean, Column, DateTime, Enum, ForeignKey, Integer,
    String, Text, JSON, Index, func,
)
from sqlalchemy.dialects.postgresql import UUID

from app.core.database import Base


class User(Base):
    __tablename__ = "users"

    # ─── شناسه‌ها ─────────────────────────────────────────────
    id          = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    earth_id    = Column(String(20), unique=True, nullable=False, index=True)
    # فرمت: DLX-XXXXXXXX

    # ─── اطلاعات پایه ─────────────────────────────────────────
    phone       = Column(String(20), unique=True, nullable=True, index=True)
    email       = Column(String(255), unique=True, nullable=True, index=True)
    full_name   = Column(String(200), nullable=True)
    username    = Column(String(50), unique=True, nullable=True, index=True)
    avatar_url  = Column(Text, nullable=True)
    bio         = Column(Text, nullable=True)

    # ─── هویت / KYC ───────────────────────────────────────────
    kyc_level   = Column(Integer, default=0)
    # 0=unverified, 1=phone_verified, 2=kyc_basic, 3=kyc_full, 4=pro, 5=elite
    kyc_status  = Column(
        Enum("pending", "approved", "rejected", "expired", name="kyc_status_enum"),
        default="pending",
    )
    national_id = Column(String(255), nullable=True)  # encrypted
    date_of_birth = Column(DateTime(timezone=True), nullable=True)

    # ─── نقش و وضعیت ──────────────────────────────────────────
    role        = Column(
        Enum(
            "user", "driver", "cargo_owner", "freight_broker",
            "insurance_agent", "banker", "creator", "admin", "super_admin",
            name="user_role_enum",
        ),
        default="user",
    )
    tier        = Column(
        Enum("free", "silver", "gold", "platinum", name="user_tier_enum"),
        default="free",
    )
    status      = Column(
        Enum("active", "inactive", "blocked", "pending_verification", name="user_status_enum"),
        default="pending_verification",
    )
    blocked_reason = Column(Text, nullable=True)

    # ─── ملی / منطقه ──────────────────────────────────────────
    country_code  = Column(String(3), nullable=True)   # ISO 3166-1 alpha-3
    locale        = Column(String(10), default="fa")   # fa, en, ar, tr, ru
    timezone_name = Column(String(50), default="Asia/Tehran")

    # ─── امنیت ────────────────────────────────────────────────
    password_hash = Column(String(255), nullable=True)
    mfa_enabled   = Column(Boolean, default=False)
    mfa_secret    = Column(String(255), nullable=True)  # encrypted TOTP secret
    last_login_at = Column(DateTime(timezone=True), nullable=True)
    last_login_ip = Column(String(45), nullable=True)
    last_seen_at  = Column(DateTime(timezone=True), nullable=True)  # حضور: آخرین فعالیت

    # ─── پروفایل راننده ────────────────────────────────────────
    is_driver           = Column(Boolean, default=False)
    driver_license_no   = Column(String(50), nullable=True)
    driver_license_type = Column(String(10), nullable=True)  # A, B, C, C1, C2, D
    driver_license_expiry = Column(DateTime(timezone=True), nullable=True)
    trust_score         = Column(Integer, default=0)  # 0-1000

    # ─── آمار ─────────────────────────────────────────────────
    avg_rating    = Column(Integer, default=0)   # 0-500 (×100 برای دقت)
    total_ratings = Column(Integer, default=0)
    total_trips   = Column(Integer, default=0)
    completion_rate = Column(Integer, default=100)  # percentage

    # ─── حریم خصوصی ───────────────────────────────────────────
    privacy_on_map = Column(Boolean, default=False)
    # False = مخفی روی نقشه (پیشنهادی), True = دیده‌شدنی

    # ─── رفرال ────────────────────────────────────────────────
    referred_by   = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)

    # ─── متادیتا ──────────────────────────────────────────────
    metadata_     = Column("metadata", JSON, default=dict)
    created_at    = Column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
    updated_at    = Column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    __table_args__ = (
        Index("ix_users_phone_status", "phone", "status"),
        Index("ix_users_role_status", "role", "status"),
        Index("ix_users_country_locale", "country_code", "locale"),
    )

    def __repr__(self) -> str:
        return f"<User {self.earth_id} | {self.phone}>"

    @property
    def is_active(self) -> bool:
        return self.status == "active"

    @property
    def is_phone_verified(self) -> bool:
        return self.kyc_level >= 1

    @property
    def display_name(self) -> str:
        return self.full_name or self.username or self.earth_id
