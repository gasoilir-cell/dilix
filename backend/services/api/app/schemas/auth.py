"""
Dilix — Schemas برای Auth API
"""
from pydantic import BaseModel, Field, field_validator
import phonenumbers
import re


# نقش‌هایی که کاربر می‌تواند خودش انتخاب/تغییر دهد (onboarding + سوییچرِ نقش).
# نقش‌های ممتاز (admin/super_admin) هرگز از این مسیر قابلِ خوداعطا نیستند —
# جلوگیری از privilege escalation.
SELF_SERVICE_ROLES = frozenset(
    {
        "user",
        "driver",
        "cargo_owner",
        "freight_broker",
        "insurance_agent",
        "banker",
        "creator",
    }
)


class SendOTPRequest(BaseModel):
    phone: str = Field(..., description="شماره موبایل با کد کشور", example="+989121234567")
    purpose: str = Field(default="login", description="login | register | reset")

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        try:
            parsed = phonenumbers.parse(v)
            if not phonenumbers.is_valid_number(parsed):
                raise ValueError("شماره موبایل نامعتبر است")
            return phonenumbers.format_number(parsed, phonenumbers.PhoneNumberFormat.E164)
        except phonenumbers.NumberParseException:
            raise ValueError("فرمت شماره موبایل اشتباه است (مثال: +989121234567)")


class VerifyOTPRequest(BaseModel):
    phone: str = Field(..., example="+989121234567")
    otp: str = Field(..., min_length=4, max_length=8, example="123456")

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        try:
            parsed = phonenumbers.parse(v)
            if not phonenumbers.is_valid_number(parsed):
                raise ValueError("شماره موبایل نامعتبر است")
            return phonenumbers.format_number(parsed, phonenumbers.PhoneNumberFormat.E164)
        except phonenumbers.NumberParseException:
            raise ValueError("فرمت شماره موبایل اشتباه است")


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    earth_id: str
    is_new_user: bool = False


class RefreshTokenRequest(BaseModel):
    refresh_token: str


class UpdateProfileRequest(BaseModel):
    full_name: str | None = Field(None, max_length=200)
    username: str | None = Field(None, min_length=3, max_length=50)
    bio: str | None = Field(None, max_length=500)
    locale: str | None = Field(None, pattern="^(fa|en|ar|tr|ru)$")
    privacy_on_map: bool | None = None
    role: str | None = None

    @field_validator("username")
    @classmethod
    def validate_username(cls, v: str | None) -> str | None:
        if v is None:
            return v
        if not re.match(r"^[a-z0-9_\.]+$", v):
            raise ValueError("نام کاربری فقط شامل حروف کوچک، اعداد، _ و . می‌شود")
        return v

    @field_validator("role")
    @classmethod
    def validate_role(cls, v: str | None) -> str | None:
        # فقط نقش‌های خودسرویس مجازند؛ نقش‌های ممتاز خوداعطا نمی‌شوند.
        if v is None:
            return v
        if v not in SELF_SERVICE_ROLES:
            raise ValueError("این نقش قابلِ انتخاب نیست")
        return v


class UserResponse(BaseModel):
    id: str
    earth_id: str
    phone: str | None
    email: str | None
    full_name: str | None
    username: str | None
    avatar_url: str | None
    bio: str | None
    role: str
    tier: str
    status: str
    kyc_level: int
    kyc_status: str = "pending"
    national_id_set: bool = False
    locale: str
    country_code: str | None = None
    is_driver: bool
    trust_score: int
    avg_rating: float | None = None
    total_trips: int
    privacy_on_map: bool = False
    created_at: str

    model_config = {"from_attributes": True}


# ─── ورودِ اجتماعی و ایمیل/گذرواژه ─────────────────────────────
class OAuthLoginRequest(BaseModel):
    credential: str = Field(..., description="id_token (Google/Microsoft/Apple) یا access_token (Facebook)")


class EmailRegisterRequest(BaseModel):
    identifier: str = Field(..., description="ایمیل یا شماره موبایل", min_length=3, max_length=255)
    password: str = Field(..., min_length=8, max_length=128)
    full_name: str = Field(..., min_length=2, max_length=200)

    @field_validator("identifier")
    @classmethod
    def normalize_identifier(cls, v: str) -> str:
        v = v.strip()
        if "@" in v:
            return v.lower()
        # شماره موبایل — نرمال‌سازی به E164
        try:
            parsed = phonenumbers.parse(v, "IR")
            if not phonenumbers.is_valid_number(parsed):
                raise ValueError("ایمیل یا شماره موبایل نامعتبر است")
            return phonenumbers.format_number(parsed, phonenumbers.PhoneNumberFormat.E164)
        except phonenumbers.NumberParseException:
            raise ValueError("ایمیل یا شماره موبایل نامعتبر است")


class EmailLoginRequest(BaseModel):
    identifier: str = Field(..., description="ایمیل یا شماره موبایل", min_length=3, max_length=255)
    password: str = Field(..., min_length=1, max_length=128)

    @field_validator("identifier")
    @classmethod
    def normalize_identifier(cls, v: str) -> str:
        v = v.strip()
        if "@" in v:
            return v.lower()
        try:
            parsed = phonenumbers.parse(v, "IR")
            if phonenumbers.is_valid_number(parsed):
                return phonenumbers.format_number(parsed, phonenumbers.PhoneNumberFormat.E164)
        except phonenumbers.NumberParseException:
            pass
        return v
