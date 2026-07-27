"""
Dilix — Provider Onboarding Router
پرتال ثبت‌نامِ خدمات‌دهنده (شرکت بیمه / بانک / کارگزار / PSP).

دیلیکس بستری «برای خدمات‌دهندگان» است: خودِ شرکت بیمه/بانک با کد بیمه‌ای/
کارگزاری خودش ثبت‌نام می‌کند، توافق‌نامهٔ کارمزد را می‌پذیرد، و API خود را
معرفی می‌کند. مجوز و مسئولیتِ صدور روی دوشِ همان provider است (نه دیلیکس).

POST /api/v1/providers/register            ثبت مرکز
GET  /api/v1/providers/me                  مراکزِ من
GET  /api/v1/providers/types               کاتالوگ انواع مرکز
GET  /api/v1/providers/{id}                جزئیات مرکز
POST /api/v1/providers/{id}/apis           معرفی API
GET  /api/v1/providers/{id}/apis           لیست APIها
POST /api/v1/providers/{id}/apis/{api_id}/sandbox-test   تست اتصال sandbox
"""
import uuid as _uuid
import base64
import hashlib
import hmac
import secrets as _secrets
from datetime import datetime, timezone
from typing import Optional, List

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy import (
    Column, DateTime, Enum, Float, ForeignKey, String, Boolean, Text, select,
)
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db, Base
from app.core.config import settings
from app.api.deps import get_current_user
from app.models.user import User

router = APIRouter(prefix="/providers", tags=["Provider"])

ADMIN_ROLES = ("admin", "super_admin")


def _now():
    return datetime.now(timezone.utc)


# ── Crypto (Fernet key از JWT_SECRET مشتق می‌شود) ────────────────
def _fernet():
    """کلید Fernet را از JWT_SECRET پروژه مشتق می‌کند (بدون افزودن راز جدید)."""
    from cryptography.fernet import Fernet
    raw = (settings.JWT_SECRET or "dilix").encode("utf-8")
    key = base64.urlsafe_b64encode(hashlib.sha256(raw).digest())
    return Fernet(key)


def _encrypt(plain: str) -> str:
    return _fernet().encrypt(plain.encode("utf-8")).decode("utf-8")


def _decrypt(token: str) -> str:
    return _fernet().decrypt(token.encode("utf-8")).decode("utf-8")


# ── Models (inline; create_all می‌سازد) ─────────────────────────
class Provider(Base):
    __tablename__ = "providers"

    id                    = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    owner_id              = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    legal_name            = Column(String(200), nullable=False)          # نام حقوقی
    provider_type         = Column(
        Enum("insurer", "bank", "broker", "psp", "other", name="provider_type_enum"),
        nullable=False, default="insurer",
    )
    license_no            = Column(String(100), nullable=False)          # کد بیمه‌ای/کارگزاری/مجوز
    economic_code         = Column(String(50), nullable=True)           # شناسه/کد اقتصادی
    contact_name          = Column(String(150), nullable=True)
    contact_phone         = Column(String(30), nullable=True)
    contact_email         = Column(String(150), nullable=True)
    commission_rate       = Column(Float, nullable=False, default=15.0)  # کارمزد توافقی (٪)
    products              = Column(JSONB, nullable=True)                 # کدهای بیمهٔ پوشش‌داده‌شده؛ null/[] = همه
    country               = Column(String(2), nullable=False, default="IR")   # کشورِ ثبت (ISO-3166 alpha-2)
    currency              = Column(String(3), nullable=False, default="IRR")  # ارزِ تسویه (ISO-4217)
    regulator             = Column(String(120), nullable=True)          # نهادِ ناظر/رگولاتور (مثلاً بیمهٔ مرکزی، BaFin)
    agreement_accepted    = Column(Boolean, nullable=False, default=False)
    agreement_accepted_at = Column(DateTime(timezone=True), nullable=True)
    kyb_status            = Column(
        Enum("pending", "verified", "rejected", name="kyb_status_enum"),
        nullable=False, default="pending",
    )
    created_at            = Column(DateTime(timezone=True), nullable=False, default=_now)


class ProviderAPI(Base):
    __tablename__ = "provider_apis"

    id             = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    provider_id    = Column(UUID(as_uuid=True), ForeignKey("providers.id"), nullable=False, index=True)
    name           = Column(String(150), nullable=False)
    base_url       = Column(String(400), nullable=False)
    spec_url       = Column(String(400), nullable=True)                  # OpenAPI/Swagger
    env            = Column(
        Enum("sandbox", "production", name="provider_api_env_enum"),
        nullable=False, default="sandbox",
    )
    status         = Column(
        Enum("registered", "tested", "failed", name="provider_api_status_enum"),
        nullable=False, default="registered",
    )
    last_tested_at = Column(DateTime(timezone=True), nullable=True)
    created_at     = Column(DateTime(timezone=True), nullable=False, default=_now)


class ProviderCredential(Base):
    """رازِ برون‌مرزی برای فراخوانی API خدمات‌دهنده (Dilix→Provider).

    مقدارِ خام رمزنگاری‌شده (Fernet) ذخیره می‌شود و فقط هنگام فراخوانی
    توسط موتور رمزگشایی می‌گردد؛ در پاسخِ API هرگز خام برنمی‌گردد.
    """
    __tablename__ = "provider_credentials"

    id          = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    provider_id = Column(UUID(as_uuid=True), ForeignKey("providers.id"), nullable=False, index=True)
    label       = Column(String(150), nullable=False)              # نام قابل‌شناسایی
    auth_type   = Column(
        Enum("api_key", "bearer", "basic", name="provider_cred_auth_enum"),
        nullable=False, default="api_key",
    )
    env         = Column(
        Enum("sandbox", "production", name="provider_cred_env_enum"),
        nullable=False, default="sandbox",
    )
    secret_enc  = Column(Text, nullable=False)                     # Fernet(token)
    key_prefix  = Column(String(12), nullable=True)               # چند کاراکترِ اولِ راز (نمایش)
    status      = Column(
        Enum("active", "revoked", name="provider_cred_status_enum"),
        nullable=False, default="active",
    )
    created_at  = Column(DateTime(timezone=True), nullable=False, default=_now)


class ProviderWebhook(Base):
    """وب‌هوکِ ورودی (Provider→Dilix). رازِ HMAC فقط یک‌بار هنگام ساخت برمی‌گردد.

    `secret_hash` برای نمایش/راستی‌آزماییِ سریع است؛ `secret_enc` (Fernet)
    برای بازتولیدِ امضای HMAC هنگامِ دریافتِ رویداد استفاده می‌شود.
    """
    __tablename__ = "provider_webhooks"

    id           = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    provider_id  = Column(UUID(as_uuid=True), ForeignKey("providers.id"), nullable=False, index=True)
    url          = Column(String(500), nullable=False)
    event_types  = Column(JSONB, nullable=True)                    # ["policy.issued", ...]
    secret_hash  = Column(String(128), nullable=False)            # sha256(secret)
    secret_enc   = Column(Text, nullable=True)                    # Fernet(secret) برای HMAC
    status       = Column(
        Enum("active", "disabled", name="provider_webhook_status_enum"),
        nullable=False, default="active",
    )
    created_at   = Column(DateTime(timezone=True), nullable=False, default=_now)


class ProviderWebhookEvent(Base):
    """لاگِ رویدادهای دریافتیِ تأییدشده از خدمات‌دهنده (Provider→Dilix)."""
    __tablename__ = "provider_webhook_events"

    id          = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    provider_id = Column(UUID(as_uuid=True), ForeignKey("providers.id"), nullable=False, index=True)
    webhook_id  = Column(UUID(as_uuid=True), ForeignKey("provider_webhooks.id"), nullable=False, index=True)
    event_type  = Column(String(100), nullable=False, default="unknown")
    payload     = Column(JSONB, nullable=True)
    received_at = Column(DateTime(timezone=True), nullable=False, default=_now)


# ── Catalog ─────────────────────────────────────────────────────
PROVIDER_TYPES = {
    "insurer": {"label": "شرکت بیمه",          "emoji": "🛡️"},
    "bank":    {"label": "بانک",                "emoji": "🏦"},
    "broker":  {"label": "کارگزاری",            "emoji": "🤝"},
    "psp":     {"label": "شرکت پرداخت (PSP)",   "emoji": "💳"},
    "other":   {"label": "سایر خدمات‌دهنده",     "emoji": "🏢"},
}
KYB_LABEL = {
    "pending":  "در انتظار احراز",
    "verified": "احراز شده",
    "rejected": "رد شده",
}

# کدهای بیمهٔ قابلِ پوشش توسط هر مرکز (باید با PRODUCTS در insurance/router.py هم‌راستا بماند)
INSURANCE_PRODUCTS = {
    "cargo":       "بیمه باربری",
    "third_party": "بیمه شخص ثالث",
    "auto_body":   "بیمه بدنه خودرو",
    "life":        "بیمه عمر",
    "fire":        "بیمه آتش‌سوزی",
    "liability":   "بیمه مسئولیت",
    "health":      "بیمه درمان",
    "travel":      "بیمه مسافرتی",
    "engineering": "بیمه مهندسی",
}

# سرویس‌های قابلِ ارائه به‌تفکیکِ نوعِ مرکز. پیش‌تر کاتالوگ **همیشه** بیمه بود، پس
# یک بانک در پورتالِ خودش فهرستِ «بیمهٔ باربری/شخصِ ثالث/…» می‌دید و هیچ سرویسِ
# بانکی‌ای برای انتخاب نداشت. کاتالوگ باید تابعِ نوعِ مرکز باشد، نه ثابت.
BANK_PRODUCTS = {
    "deposit":       "افتتاح و مدیریتِ سپرده",
    "card_issue":    "صدورِ کارتِ بانکی",
    "loan":          "تسهیلات و وام",
    "guarantee":     "ضمانت‌نامهٔ بانکی",
    "lc":            "اعتبارِ اسنادی (LC)",
    "fx_transfer":   "حوالهٔ ارزی",
    "settlement":    "تسویه و پایاپای",
    "account_info":  "خدماتِ اطلاعاتِ حساب (Open Banking)",
}
PSP_PRODUCTS = {
    "ipg":           "درگاهِ پرداختِ اینترنتی (IPG)",
    "direct_debit":  "پرداختِ مستقیم و برداشتِ خودکار",
    "payout":        "واریزِ گروهی (تسویه با فروشندگان)",
    "pos":           "کارت‌خوانِ فروشگاهی",
    "wallet_topup":  "شارژِ کیفِ پول",
    "bill_payment":  "پرداختِ قبض",
    "tokenization":  "توکن‌سازیِ کارت",
}
BROKER_PRODUCTS = {
    "fund_units":    "خرید و فروشِ واحدِ صندوق",
    "equity":        "معاملهٔ سهام",
    "fixed_income":  "اوراقِ با درآمدِ ثابت",
    "portfolio":     "سبدگردانیِ اختصاصی",
    "advisory":      "مشاورهٔ سرمایه‌گذاری",
    "custody":       "امانت‌داریِ دارایی",
}
OTHER_PRODUCTS = {
    "logistics":     "خدماتِ حمل‌ونقل",
    "telecom":       "خدماتِ ارتباطی",
    "identity":      "احرازِ هویت",
    "data":          "سرویسِ داده",
    "other":         "سایرِ خدمات",
}

PRODUCT_CATALOGS: dict[str, dict] = {
    "insurer": INSURANCE_PRODUCTS,
    "bank":    BANK_PRODUCTS,
    "psp":     PSP_PRODUCTS,
    "broker":  BROKER_PRODUCTS,
    "other":   OTHER_PRODUCTS,
}

# برچسبِ همهٔ کدها در یک نگاشت، برای نمایشِ محصولاتِ ذخیره‌شده بدونِ دانستنِ نوع.
ALL_PRODUCT_LABELS: dict[str, str] = {
    code: label for cat in PRODUCT_CATALOGS.values() for code, label in cat.items()
}


# ── توافق‌نامهٔ همکاری ───────────────────────────────────────────
# نسخه را با هر تغییرِ معناییِ متن بالا ببرید.
AGREEMENT_VERSION = "1.0"

AGREEMENT_SECTIONS: list[tuple[str, str]] = [
    (
        "۱) جایگاهِ طرفین",
        "دیلیکس یک بسترِ واسط (Marketplace/Orchestrator) است و خود ارائه‌دهندهٔ "
        "خدماتِ بانکی، بیمه‌ای، پرداختی یا سرمایه‌گذاری نیست. مسئولیتِ صدور، "
        "اجرا و پاسخ‌گوییِ خدمات بر عهدهٔ ارائه‌دهنده است و ارائه‌دهنده تأیید "
        "می‌کند که مجوزهای لازم از نهادِ ناظرِ مربوطه را دارد و آن‌ها را معتبر "
        "نگه می‌دارد.",
    ),
    (
        "۲) احرازِ هویتِ کسب‌وکار (KYB)",
        "ثبت‌نام پس از ارسالِ مدارک در وضعیتِ «در انتظارِ احراز» قرار می‌گیرد. تا "
        "پیش از تأییدِ KYB، سرویس‌های ارائه‌دهنده فقط در محیطِ آزمایشی (sandbox) "
        "قابلِ فراخوانی‌اند و به کاربرِ نهایی عرضه نمی‌شوند. ارائه‌دهنده متعهد "
        "است هر تغییر در وضعیتِ مجوز یا مالکیت را بی‌درنگ اعلام کند.",
    ),
    (
        "۳) سطحِ خدمت و کیفیت",
        "ارائه‌دهنده متعهد به پاسخ‌گوییِ APIهای ثبت‌شده با دسترس‌پذیریِ حداقل ۹۹٪ "
        "ماهانه و زمانِ پاسخِ متعارف است. قطعیِ برنامه‌ریزی‌شده باید دستِ‌کم ۴۸ "
        "ساعت پیش‌تر اعلام شود. دیلیکس می‌تواند سرویسی را که پیوسته خطا می‌دهد "
        "به‌طورِ موقت از موتورِ مقایسه خارج کند.",
    ),
    (
        "۴) کارمزد و تسویه",
        "نرخِ کارمزدِ پلتفرم هنگامِ ثبت‌نام تعیین و در صورت‌حسابِ ماهانه اعمال "
        "می‌شود. تسویه بر پایهٔ تراکنش‌های موفقِ ثبت‌شده در سامانه انجام می‌گیرد و "
        "مبنای محاسبه، دفترِ تراکنشِ دیلیکس است. اعتراض به صورت‌حساب حداکثر تا "
        "۳۰ روز پس از صدور پذیرفته می‌شود.",
    ),
    (
        "۵) دادهٔ کاربر و محرمانگی",
        "ارائه‌دهنده فقط به حداقلِ دادهٔ لازم برای انجامِ همان خدمت دسترسی دارد و "
        "حق ندارد آن را برای مقصودِ دیگر، بازاریابی یا انتقال به شخصِ ثالث "
        "استفاده کند. دادهٔ کاربرانِ ایران در ریجنِ داخلی نگه‌داری می‌شود و "
        "رعایتِ قوانینِ حفاظت از داده بر عهدهٔ هر دو طرف است.",
    ),
    (
        "۶) امنیت و کلیدها",
        "کلیدهای صادرشده محرمانه‌اند و مسئولیتِ هر فراخوانی که با آن‌ها انجام "
        "شود بر عهدهٔ ارائه‌دهنده است. در صورتِ نشتِ کلید، ارائه‌دهنده موظف است "
        "بی‌درنگ آن را ابطال و حادثه را گزارش کند. امضای webhookها باید در سمتِ "
        "ارائه‌دهنده راستی‌آزمایی شود.",
    ),
    (
        "۷) تعلیق و خاتمه",
        "هر طرف می‌تواند با اعلامِ کتبیِ ۳۰ روزه همکاری را خاتمه دهد. دیلیکس "
        "می‌تواند در صورتِ تخلفِ آشکار، نقضِ امنیت یا ابطالِ مجوز، دسترسی را "
        "فوراً تعلیق کند. تعهداتِ مربوط به تراکنش‌های انجام‌شده و محرمانگیِ داده "
        "پس از خاتمه نیز پابرجاست.",
    ),
    (
        "۸) قانونِ حاکم",
        "این توافق‌نامه تابعِ قوانینِ جمهوری اسلامی ایران است. اختلافات ابتدا از "
        "راهِ مذاکره و در صورتِ عدمِ حصولِ نتیجه از طریقِ مراجعِ صالحِ قضایی حل "
        "می‌شود.",
    ),
]


def catalog_for(provider_type: str | None) -> dict:
    """کاتالوگِ سرویسِ متناسب با نوعِ مرکز (پیش‌فرض: بیمه، برای سازگاری با گذشته)."""
    return PRODUCT_CATALOGS.get((provider_type or "").strip(), INSURANCE_PRODUCTS)


def _clean_products(products, provider_type: str | None = None) -> Optional[list]:
    """اعتبارسنجیِ لیستِ کدهای محصول؛ None/[] یعنی «همهٔ محصولات».

    کدها باید در کاتالوگِ **همان نوعِ مرکز** باشند؛ وگرنه یک بانک می‌توانست
    کدِ بیمه‌ای ذخیره کند و در موتورِ مقایسه به‌عنوانِ بیمه‌گر فراخوانده شود.
    """
    if not products:
        return None
    allowed = catalog_for(provider_type)
    seen, out = set(), []
    for code in products:
        c = str(code).strip()
        if c in allowed and c not in seen:
            seen.add(c)
            out.append(c)
    return out or None


def type_label(t: str) -> str:
    return PROVIDER_TYPES.get(t, {}).get("label", t)


def _flag(country: str) -> str:
    """پرچمِ اموجی از کدِ کشورِ ISO alpha-2 (regional-indicatorها)."""
    c = (country or "").strip().upper()
    if len(c) != 2 or not c.isalpha():
        return ""
    return "".join(chr(0x1F1E6 + (ord(ch) - ord("A"))) for ch in c)


# ── Schemas ─────────────────────────────────────────────────────
class ProviderRegister(BaseModel):
    legal_name:         str = Field(..., min_length=2, max_length=200)
    provider_type:      str = "insurer"
    license_no:         str = Field(..., min_length=2, max_length=100)
    economic_code:      Optional[str] = None
    contact_name:       Optional[str] = None
    contact_phone:      Optional[str] = None
    contact_email:      Optional[str] = None
    commission_rate:    float = Field(15.0, ge=0, le=90)
    products:           Optional[List[str]] = None   # کدهای بیمهٔ پوشش‌داده‌شده
    country:            str = Field("IR", min_length=2, max_length=2)   # ISO alpha-2
    currency:           str = Field("IRR", min_length=3, max_length=3)  # ISO-4217
    regulator:          Optional[str] = Field(None, max_length=120)
    agreement_accepted: bool = False


class ProviderOut(BaseModel):
    id:                 str
    legal_name:         str
    provider_type:      str
    provider_type_label: str
    license_no:         str
    economic_code:      Optional[str]
    contact_name:       Optional[str]
    contact_phone:      Optional[str]
    contact_email:      Optional[str]
    commission_rate:    float
    products:           List[str] = []
    products_labels:    List[str] = []
    country:            str = "IR"
    country_flag:       str = ""
    currency:           str = "IRR"
    regulator:          Optional[str] = None
    agreement_accepted: bool
    kyb_status:         str
    kyb_status_label:   str
    created_at:         datetime

    @classmethod
    def of(cls, o) -> "ProviderOut":
        prods = list(getattr(o, "products", None) or [])
        country = (getattr(o, "country", None) or "IR").upper()
        return cls(
            id=str(o.id), legal_name=o.legal_name,
            provider_type=o.provider_type, provider_type_label=type_label(o.provider_type),
            license_no=o.license_no, economic_code=o.economic_code,
            contact_name=o.contact_name, contact_phone=o.contact_phone,
            contact_email=o.contact_email, commission_rate=o.commission_rate,
            products=prods,
            products_labels=[ALL_PRODUCT_LABELS.get(c, c) for c in prods],
            country=country, country_flag=_flag(country),
            currency=(getattr(o, "currency", None) or "IRR").upper(),
            regulator=getattr(o, "regulator", None),
            agreement_accepted=o.agreement_accepted,
            kyb_status=o.kyb_status, kyb_status_label=KYB_LABEL.get(o.kyb_status, o.kyb_status),
            created_at=o.created_at,
        )


class ProductsUpdate(BaseModel):
    products: List[str] = []          # کدهای بیمهٔ پوشش‌داده‌شده؛ خالی = همه


class ProductCatalogOut(BaseModel):
    id:    str
    label: str


class AgreementSection(BaseModel):
    title: str
    body:  str


class AgreementOut(BaseModel):
    version:  str
    title:    str
    sections: List[AgreementSection]


class APICreate(BaseModel):
    name:     str = Field(..., min_length=2, max_length=150)
    base_url: str = Field(..., min_length=4, max_length=400)
    spec_url: Optional[str] = None
    env:      str = "sandbox"


class APIOut(BaseModel):
    id:             str
    name:           str
    base_url:       str
    spec_url:       Optional[str]
    env:            str
    status:         str
    last_tested_at: Optional[datetime]
    created_at:     datetime

    @classmethod
    def of(cls, o) -> "APIOut":
        return cls(
            id=str(o.id), name=o.name, base_url=o.base_url, spec_url=o.spec_url,
            env=o.env, status=o.status, last_tested_at=o.last_tested_at, created_at=o.created_at,
        )


class TypeOut(BaseModel):
    id:    str
    label: str
    emoji: str


class KYBDecision(BaseModel):
    status: str                              # verified | rejected | pending
    note:   Optional[str] = None


class CredentialCreate(BaseModel):
    label:     str = Field(..., min_length=2, max_length=150)
    auth_type: str = "api_key"
    env:       str = "sandbox"
    secret:    str = Field(..., min_length=4, max_length=2000)


class CredentialOut(BaseModel):
    id:         str
    label:      str
    auth_type:  str
    env:        str
    key_prefix: Optional[str]
    status:     str
    created_at: datetime

    @classmethod
    def of(cls, o) -> "CredentialOut":
        return cls(
            id=str(o.id), label=o.label, auth_type=o.auth_type, env=o.env,
            key_prefix=o.key_prefix, status=o.status, created_at=o.created_at,
        )


class WebhookCreate(BaseModel):
    url:         str = Field(..., min_length=8, max_length=500)
    event_types: Optional[List[str]] = None


class WebhookOut(BaseModel):
    id:          str
    url:         str
    event_types: Optional[List[str]]
    status:      str
    created_at:  datetime
    secret:      Optional[str] = None        # فقط هنگام ساخت پر می‌شود

    @classmethod
    def of(cls, o, secret: Optional[str] = None) -> "WebhookOut":
        return cls(
            id=str(o.id), url=o.url, event_types=o.event_types,
            status=o.status, created_at=o.created_at, secret=secret,
        )


class EventOut(BaseModel):
    id:          str
    event_type:  str
    payload:     Optional[dict]
    received_at: datetime

    @classmethod
    def of(cls, o) -> "EventOut":
        return cls(
            id=str(o.id), event_type=o.event_type,
            payload=o.payload, received_at=o.received_at,
        )


# ── Helpers ─────────────────────────────────────────────────────
async def _owned_provider(db: AsyncSession, provider_id: str, me: User) -> Provider:
    try:
        pid = _uuid.UUID(provider_id)
    except ValueError:
        raise HTTPException(400, "شناسه نامعتبر است")
    p = await db.get(Provider, pid)
    if not p:
        raise HTTPException(404, "مرکز پیدا نشد")
    if p.owner_id != me.id:
        raise HTTPException(403, "دسترسی ندارید")
    return p


def _require_admin(me: User) -> None:
    if me.role not in ADMIN_ROLES:
        raise HTTPException(403, "این عملیات فقط برای مدیران مجاز است")


async def _provider_admin(db: AsyncSession, provider_id: str) -> Provider:
    try:
        pid = _uuid.UUID(provider_id)
    except ValueError:
        raise HTTPException(400, "شناسه نامعتبر است")
    p = await db.get(Provider, pid)
    if not p:
        raise HTTPException(404, "مرکز پیدا نشد")
    return p


# ── Endpoints ───────────────────────────────────────────────────
@router.get("/types", response_model=List[TypeOut])
async def list_types(me: User = Depends(get_current_user)):
    return [TypeOut(id=k, label=v["label"], emoji=v["emoji"]) for k, v in PROVIDER_TYPES.items()]


@router.post("/register", response_model=ProviderOut, status_code=201)
async def register_provider(
    body: ProviderRegister,
    db:   AsyncSession = Depends(get_db),
    me:   User         = Depends(get_current_user),
):
    if body.provider_type not in PROVIDER_TYPES:
        raise HTTPException(400, "نوع مرکز معتبر نیست")
    if not body.agreement_accepted:
        raise HTTPException(400, "برای ثبت‌نام باید توافق‌نامهٔ همکاری را بپذیرید")
    p = Provider(
        owner_id           = me.id,
        legal_name         = body.legal_name.strip(),
        provider_type      = body.provider_type,
        license_no         = body.license_no.strip(),
        economic_code      = (body.economic_code or None),
        contact_name       = (body.contact_name or None),
        contact_phone      = (body.contact_phone or None),
        contact_email      = (body.contact_email or None),
        commission_rate    = body.commission_rate,
        products           = _clean_products(body.products, body.provider_type),
        country            = (body.country or "IR").strip().upper(),
        currency           = (body.currency or "IRR").strip().upper(),
        regulator          = ((body.regulator or "").strip() or None),
        agreement_accepted = True,
        agreement_accepted_at = _now(),
        kyb_status         = "pending",
    )
    db.add(p)
    await db.commit()
    await db.refresh(p)
    return ProviderOut.of(p)


@router.get("/catalog/products", response_model=List[ProductCatalogOut])
async def list_product_catalog(
    provider_type: Optional[str] = Query(None, description="نوعِ مرکز؛ خالی = بیمه"),
    me: User = Depends(get_current_user),
):
    """کاتالوگِ سرویس‌هایی که یک مرکز از **نوعِ داده‌شده** می‌تواند ارائه دهد."""
    return [ProductCatalogOut(id=k, label=v) for k, v in catalog_for(provider_type).items()]


@router.get("/agreement", response_model=AgreementOut)
async def get_agreement(me: User = Depends(get_current_user)):
    """متنِ توافق‌نامهٔ همکاری که مرکز هنگامِ ثبت‌نام می‌پذیرد.

    متن از سرور می‌آید تا نسخهٔ پذیرفته‌شده یکتا و قابلِ استناد بماند؛ اگر در
    کلاینت سخت‌کد می‌شد، هر نسخهٔ اپ می‌توانست متنِ متفاوتی نشان دهد در حالی که
    همان تیکِ «می‌پذیرم» را به سرور می‌فرستاد.
    """
    return AgreementOut(
        version=AGREEMENT_VERSION,
        title="توافق‌نامهٔ همکاریِ ارائه‌دهنده",
        sections=[AgreementSection(title=t, body=b) for t, b in AGREEMENT_SECTIONS],
    )


@router.put("/{provider_id}/products", response_model=ProviderOut)
async def set_provider_products(
    provider_id: str,
    body: ProductsUpdate,
    db:   AsyncSession = Depends(get_db),
    me:   User         = Depends(get_current_user),
):
    """تعیینِ سرویس‌های تحتِ پوششِ مرکز، از کاتالوگِ نوعِ همان مرکز (فقط مالک).

    لیستِ خالی یعنی «همهٔ محصولات». در موتورِ مقایسه فقط مراکزی که
    محصولِ درخواستی را پوشش می‌دهند فراخوانی می‌شوند.
    """
    p = await _owned_provider(db, provider_id, me)
    p.products = _clean_products(body.products, p.provider_type)
    await db.commit()
    await db.refresh(p)
    return ProviderOut.of(p)


@router.get("/me", response_model=List[ProviderOut])
async def my_providers(
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    r = await db.execute(
        select(Provider).where(Provider.owner_id == me.id).order_by(Provider.created_at.desc())
    )
    return [ProviderOut.of(x) for x in r.scalars().all()]


@router.get("/{provider_id}", response_model=ProviderOut)
async def get_provider(
    provider_id: str,
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    return ProviderOut.of(await _owned_provider(db, provider_id, me))


@router.post("/{provider_id}/apis", response_model=APIOut, status_code=201)
async def add_api(
    provider_id: str,
    body: APICreate,
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    p = await _owned_provider(db, provider_id, me)
    if p.kyb_status == "rejected":
        raise HTTPException(400, "احراز مرکز رد شده است؛ امکان ثبت API نیست")
    if body.env not in ("sandbox", "production"):
        raise HTTPException(400, "محیط نامعتبر است")
    if body.env == "production" and p.kyb_status != "verified":
        raise HTTPException(400, "برای محیط production ابتدا باید احراز (KYB) کامل شود")
    api = ProviderAPI(
        provider_id = p.id,
        name        = body.name.strip(),
        base_url    = body.base_url.strip(),
        spec_url    = (body.spec_url or None),
        env         = body.env,
        status      = "registered",
    )
    db.add(api)
    await db.commit()
    await db.refresh(api)
    return APIOut.of(api)


@router.get("/{provider_id}/apis", response_model=List[APIOut])
async def list_apis(
    provider_id: str,
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    p = await _owned_provider(db, provider_id, me)
    r = await db.execute(
        select(ProviderAPI).where(ProviderAPI.provider_id == p.id).order_by(ProviderAPI.created_at.desc())
    )
    return [APIOut.of(x) for x in r.scalars().all()]


@router.post("/{provider_id}/apis/{api_id}/sandbox-test", response_model=APIOut)
async def sandbox_test(
    provider_id: str,
    api_id: str,
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    """یک درخواست GET به spec_url (یا base_url) می‌زند و وضعیت را tested/failed می‌کند."""
    p = await _owned_provider(db, provider_id, me)
    try:
        aid = _uuid.UUID(api_id)
    except ValueError:
        raise HTTPException(400, "شناسهٔ API نامعتبر است")
    api = await db.get(ProviderAPI, aid)
    if not api or api.provider_id != p.id:
        raise HTTPException(404, "API پیدا نشد")

    target = api.spec_url or api.base_url
    ok = False
    try:
        import httpx
        async with httpx.AsyncClient(timeout=8.0, follow_redirects=True) as client:
            resp = await client.get(target)
            ok = resp.status_code < 500
    except Exception:
        ok = False

    api.status = "tested" if ok else "failed"
    api.last_tested_at = _now()
    await db.commit()
    await db.refresh(api)
    return APIOut.of(api)


# ── Admin: KYB verify/reject ────────────────────────────────────
@router.get("/admin/all", response_model=List[ProviderOut])
async def admin_list_all(
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    """همهٔ مراکز (برای پنل مدیر) — به‌ترتیب: در انتظار احراز، سپس بقیه."""
    _require_admin(me)
    r = await db.execute(select(Provider).order_by(Provider.created_at.desc()))
    items = list(r.scalars().all())
    items.sort(key=lambda p: 0 if p.kyb_status == "pending" else 1)
    return [ProviderOut.of(x) for x in items]


@router.post("/{provider_id}/kyb", response_model=ProviderOut)
async def admin_set_kyb(
    provider_id: str,
    body: KYBDecision,
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    """مدیر وضعیت احراز (KYB) مرکز را تعیین می‌کند."""
    _require_admin(me)
    if body.status not in ("pending", "verified", "rejected"):
        raise HTTPException(400, "وضعیت نامعتبر است")
    p = await _provider_admin(db, provider_id)
    p.kyb_status = body.status
    await db.commit()
    await db.refresh(p)
    return ProviderOut.of(p)


# ── Credentials (Dilix→Provider، رازِ رمزنگاری‌شده) ──────────────
@router.post("/{provider_id}/credentials", response_model=CredentialOut, status_code=201)
async def add_credential(
    provider_id: str,
    body: CredentialCreate,
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    p = await _owned_provider(db, provider_id, me)
    if body.auth_type not in ("api_key", "bearer", "basic"):
        raise HTTPException(400, "نوع احراز نامعتبر است")
    if body.env not in ("sandbox", "production"):
        raise HTTPException(400, "محیط نامعتبر است")
    if body.env == "production" and p.kyb_status != "verified":
        raise HTTPException(400, "برای کلیدِ production ابتدا باید احراز (KYB) کامل شود")
    secret = body.secret.strip()
    cred = ProviderCredential(
        provider_id = p.id,
        label       = body.label.strip(),
        auth_type   = body.auth_type,
        env         = body.env,
        secret_enc  = _encrypt(secret),
        key_prefix  = secret[:6],
        status      = "active",
    )
    db.add(cred)
    await db.commit()
    await db.refresh(cred)
    return CredentialOut.of(cred)


@router.get("/{provider_id}/credentials", response_model=List[CredentialOut])
async def list_credentials(
    provider_id: str,
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    p = await _owned_provider(db, provider_id, me)
    r = await db.execute(
        select(ProviderCredential)
        .where(ProviderCredential.provider_id == p.id)
        .order_by(ProviderCredential.created_at.desc())
    )
    return [CredentialOut.of(x) for x in r.scalars().all()]


@router.post("/{provider_id}/credentials/{cred_id}/revoke", response_model=CredentialOut)
async def revoke_credential(
    provider_id: str,
    cred_id: str,
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    p = await _owned_provider(db, provider_id, me)
    try:
        cid = _uuid.UUID(cred_id)
    except ValueError:
        raise HTTPException(400, "شناسهٔ کلید نامعتبر است")
    cred = await db.get(ProviderCredential, cid)
    if not cred or cred.provider_id != p.id:
        raise HTTPException(404, "کلید پیدا نشد")
    cred.status = "revoked"
    await db.commit()
    await db.refresh(cred)
    return CredentialOut.of(cred)


# ── Webhooks (Provider→Dilix، رازِ HMAC یک‌بار برمی‌گردد) ─────────
@router.post("/{provider_id}/webhooks", response_model=WebhookOut, status_code=201)
async def add_webhook(
    provider_id: str,
    body: WebhookCreate,
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    p = await _owned_provider(db, provider_id, me)
    if not (body.url.startswith("http://") or body.url.startswith("https://")):
        raise HTTPException(400, "آدرس وب‌هوک باید با http(s) شروع شود")
    raw_secret = "whsec_" + _secrets.token_urlsafe(32)
    wh = ProviderWebhook(
        provider_id = p.id,
        url         = body.url.strip(),
        event_types = body.event_types or None,
        secret_hash = hashlib.sha256(raw_secret.encode("utf-8")).hexdigest(),
        secret_enc  = _encrypt(raw_secret),
        status      = "active",
    )
    db.add(wh)
    await db.commit()
    await db.refresh(wh)
    # رازِ خام فقط همین‌جا (یک‌بار) برمی‌گردد
    return WebhookOut.of(wh, secret=raw_secret)


@router.get("/{provider_id}/webhooks", response_model=List[WebhookOut])
async def list_webhooks(
    provider_id: str,
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    p = await _owned_provider(db, provider_id, me)
    r = await db.execute(
        select(ProviderWebhook)
        .where(ProviderWebhook.provider_id == p.id)
        .order_by(ProviderWebhook.created_at.desc())
    )
    return [WebhookOut.of(x) for x in r.scalars().all()]


@router.get("/{provider_id}/webhooks/events", response_model=List[EventOut])
async def list_webhook_events(
    provider_id: str,
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    """آخرین رویدادهای تأییدشدهٔ دریافتی از مرکز (برای مالکِ مرکز)."""
    p = await _owned_provider(db, provider_id, me)
    r = await db.execute(
        select(ProviderWebhookEvent)
        .where(ProviderWebhookEvent.provider_id == p.id)
        .order_by(ProviderWebhookEvent.received_at.desc())
        .limit(50)
    )
    return [EventOut.of(x) for x in r.scalars().all()]


# ── Inbound receiver (Provider→Dilix، بدون احراز کاربر، با تأییدِ HMAC) ──
@router.post("/webhooks/incoming/{webhook_id}")
async def receive_webhook(
    webhook_id: str,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """گیرندهٔ رویدادِ خدمات‌دهنده. امضای `X-Dilix-Signature: sha256=…` را با
    HMAC-SHA256(secret, raw_body) می‌سنجد؛ در صورت تأیید، رویداد ثبت می‌شود.
    این endpoint عمومی است (خودِ خدمات‌دهنده صدا می‌زند) و JWT نمی‌خواهد.
    """
    try:
        wid = _uuid.UUID(webhook_id)
    except ValueError:
        raise HTTPException(400, "شناسه نامعتبر است")
    wh = await db.get(ProviderWebhook, wid)
    if not wh or wh.status != "active":
        raise HTTPException(404, "وب‌هوک فعال پیدا نشد")
    if not wh.secret_enc:
        raise HTTPException(400, "این وب‌هوک رازِ امضا ندارد؛ دوباره ثبت شود")

    raw = await request.body()
    provided = request.headers.get("X-Dilix-Signature", "")
    secret = _decrypt(wh.secret_enc)
    expected = "sha256=" + hmac.new(secret.encode("utf-8"), raw, hashlib.sha256).hexdigest()
    if not provided or not hmac.compare_digest(provided, expected):
        raise HTTPException(401, "امضای نامعتبر است")

    import json as _json
    try:
        payload = _json.loads(raw.decode("utf-8")) if raw else {}
    except Exception:
        payload = {}
    if not isinstance(payload, dict):
        payload = {"_raw": str(payload)[:2000]}
    event_type = str(payload.get("event") or payload.get("type") or "unknown")[:100]

    ev = ProviderWebhookEvent(
        provider_id = wh.provider_id,
        webhook_id  = wh.id,
        event_type  = event_type,
        payload     = payload or None,
    )
    db.add(ev)
    await db.commit()
    return {"ok": True, "received": True, "event": event_type}
