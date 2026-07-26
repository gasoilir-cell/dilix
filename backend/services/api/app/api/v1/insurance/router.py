"""
Dilix — Insurance Router (Multi-product)
POST /api/v1/insurance/quote        محاسبه حق بیمه
POST /api/v1/insurance/requests     ثبت درخواست/صدور بیمه‌نامه
GET  /api/v1/insurance/requests     لیست درخواست‌های من
GET  /api/v1/insurance/requests/{id} جزئیات
GET  /api/v1/insurance/products     کاتالوگ انواع بیمه‌نامه

انواع بیمه‌نامه پشتیبانی‌شده: باربری، شخص ثالث، بدنه خودرو، عمر،
آتش‌سوزی، مسئولیت، درمان، مسافرتی، مهندسی.
"""
import uuid as _uuid
from datetime import datetime, timezone
from typing import Optional, List

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import Column, DateTime, Enum, Float, ForeignKey, String, Text, BigInteger
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy import select, func, case
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db, Base
from app.api.deps import get_current_user
from app.models.user import User
from app.services.fx import convert_minor, get_rate_map, minor_scale

router = APIRouter(prefix="/insurance", tags=["Insurance"])

# نگاشتِ محصولاتِ دیلیکس به کدِ خطِ بیمه‌ایِ استانداردِ خدمات‌دهنده
PROVIDER_LINE_MAP = {
    "cargo": "cargo", "third_party": "motor_tpl", "auto_body": "motor_own",
    "life": "life", "fire": "fire", "liability": "liability",
    "health": "health", "travel": "travel", "engineering": "engineering",
}

# ── Inline model (avoid separate file for simplicity) ─────────
def _now():
    return datetime.now(timezone.utc)


class InsuranceRequest(Base):
    __tablename__ = "insurance_requests"

    id            = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    ref           = Column(String(20), unique=True, nullable=False)
    owner_id      = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    product       = Column(String(40), nullable=False, default="cargo")   # نوع بیمه‌نامه
    subject       = Column(String(300), nullable=True)                     # موضوع بیمه (خودرو/ملک/بیمه‌شده)
    cargo_type    = Column(String(100), nullable=True)                     # فقط باربری
    cargo_value   = Column(BigInteger, nullable=False)                     # ارزش/سرمایه بیمه‌ای (تومان)
    origin        = Column(String(300), nullable=True)                     # فقط باربری/مسافرتی
    destination   = Column(String(300), nullable=True)                     # فقط باربری/مسافرتی
    coverage_type = Column(
        Enum("basic", "comprehensive", "all_risk", name="coverage_type_enum"),
        nullable=False, default="basic"
    )
    premium       = Column(BigInteger, nullable=False)       # تومان
    form_data     = Column(JSONB, nullable=True)             # فیلدهای پویای هر محصول
    notes         = Column(Text, nullable=True)
    source        = Column(String(20), nullable=False, default="internal")  # internal | provider
    provider_name = Column(String(200), nullable=True)      # نامِ خدمات‌دهندهٔ صادرکننده
    provider_ref  = Column(String(100), nullable=True)      # شمارهٔ بیمه‌نامهٔ صادرشدهٔ خدمات‌دهنده
    status        = Column(
        Enum("pending", "reviewed", "approved", "rejected", name="insurance_status_enum"),
        nullable=False, default="pending"
    )
    created_at    = Column(DateTime(timezone=True), nullable=False, default=_now)


class InsuranceCommission(Base):
    """دفترِ کارمزدِ دیلیکس روی بیمه‌نامه‌های صادرشده نزدِ خدمات‌دهنده (source=provider).

    هنگامِ صدورِ زندهٔ هر بیمه‌نامه یک ردیفِ accrued ثبت می‌شود؛ ادمین آن را
    per-provider جمع و در پایانِ دوره تسویه (settled) می‌کند.
    """
    __tablename__ = "insurance_commissions"

    id                = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    request_id        = Column(UUID(as_uuid=True), ForeignKey("insurance_requests.id"), nullable=False, index=True)
    request_ref       = Column(String(20), nullable=True)                  # نمایشِ سریع
    provider_id       = Column(UUID(as_uuid=True), nullable=True, index=True)  # مرکزِ صادرکننده
    provider_name     = Column(String(200), nullable=True)
    product           = Column(String(40), nullable=True)
    premium           = Column(BigInteger, nullable=False, default=0)      # حق‌بیمهٔ صادرشده (تومان)
    commission_rate   = Column(Float, nullable=False, default=0.0)         # ٪ توافقی
    commission_amount = Column(BigInteger, nullable=False, default=0)      # کارمزدِ دیلیکس (تومان)
    status            = Column(
        Enum("accrued", "settled", name="commission_status_enum"),
        nullable=False, default="accrued", index=True,
    )
    settled_at        = Column(DateTime(timezone=True), nullable=True)
    note              = Column(String(300), nullable=True)
    created_at        = Column(DateTime(timezone=True), nullable=False, default=_now)


# ── Product catalog ─────────────────────────────────────────────
# rate = نرخ پایه سالانه به‌صورت کسری از سرمایه بیمه‌ای.
# باربری نرخ خود را از CARGO_RATES بر اساس نوع کالا می‌گیرد (rate=None).
PRODUCTS = {
    "cargo":       {"label": "بیمه باربری",      "emoji": "📦", "rate": None,   "needs_route": True,  "needs_cargo_type": True,  "value_label": "ارزش کالا"},
    "third_party": {"label": "بیمه شخص ثالث",    "emoji": "🚗", "rate": 0.0120, "needs_route": False, "needs_cargo_type": False, "value_label": "سرمایه تعهدی"},
    "auto_body":   {"label": "بیمه بدنه خودرو",  "emoji": "🚙", "rate": 0.0250, "needs_route": False, "needs_cargo_type": False, "value_label": "ارزش خودرو"},
    "life":        {"label": "بیمه عمر",          "emoji": "❤️", "rate": 0.0180, "needs_route": False, "needs_cargo_type": False, "value_label": "سرمایه بیمه عمر"},
    "fire":        {"label": "بیمه آتش‌سوزی",     "emoji": "🔥", "rate": 0.0015, "needs_route": False, "needs_cargo_type": False, "value_label": "ارزش ملک/دارایی"},
    "liability":   {"label": "بیمه مسئولیت",      "emoji": "⚖️", "rate": 0.0090, "needs_route": False, "needs_cargo_type": False, "value_label": "سقف تعهدات"},
    "health":      {"label": "بیمه درمان",        "emoji": "🩺", "rate": 0.0350, "needs_route": False, "needs_cargo_type": False, "value_label": "سقف پوشش درمان"},
    "travel":      {"label": "بیمه مسافرتی",      "emoji": "✈️", "rate": 0.0060, "needs_route": True,  "needs_cargo_type": False, "value_label": "سقف پوشش"},
    "engineering": {"label": "بیمه مهندسی",       "emoji": "🏗️", "rate": 0.0070, "needs_route": False, "needs_cargo_type": False, "value_label": "ارزش پروژه"},
}


# ── Cargo sub-rate table (فقط باربری) ───────────────────────────
CARGO_RATES = {
    "electronics":    0.0080,
    "perishables":    0.0065,
    "machinery":      0.0055,
    "textiles":       0.0040,
    "raw_materials":  0.0035,
    "chemicals":      0.0090,
    "artwork":        0.0100,
    "vehicles":       0.0060,
    "general":        0.0045,
}
COVERAGE_MULTIPLIER = {
    "basic":         1.0,
    "comprehensive": 1.55,
    "all_risk":      2.10,
}
CARGO_LABEL = {
    "electronics": "الکترونیک",    "perishables":   "مواد فاسدشدنی",
    "machinery":   "ماشین‌آلات",   "textiles":      "منسوجات و پارچه",
    "raw_materials":"مواد اولیه",  "chemicals":     "مواد شیمیایی",
    "artwork":     "آثار هنری",    "vehicles":      "خودرو",
    "general":     "عمومی",
}
COVERAGE_LABEL = {
    "basic":         "پایه",
    "comprehensive": "جامع",
    "all_risk":      "همه‌خطر (all risk)",
}


def product_label(product: str) -> str:
    return PRODUCTS.get(product, {}).get("label", product)


def base_rate_for(product: str, cargo_type: Optional[str]) -> float:
    if product == "cargo":
        return CARGO_RATES.get(cargo_type or "general", 0.0045)
    rate = PRODUCTS.get(product, {}).get("rate")
    return rate if rate is not None else 0.0045


def calc_premium(product: str, cargo_value: int, coverage_type: str, cargo_type: Optional[str] = None) -> int:
    base_rate = base_rate_for(product, cargo_type)
    mult      = COVERAGE_MULTIPLIER.get(coverage_type, 1.0)
    premium   = int(cargo_value * base_rate * mult)
    return max(premium, 50_000)   # حداقل ۵۰ هزار تومان


def gen_ref() -> str:
    return "INS-" + _uuid.uuid4().hex[:8].upper()


def _validate_product(product: str, cargo_type: Optional[str],
                      origin: Optional[str], destination: Optional[str]) -> None:
    meta = PRODUCTS.get(product)
    if meta is None:
        raise HTTPException(400, detail=f"نوع بیمه‌نامه معتبر نیست. گزینه‌ها: {list(PRODUCTS)}")
    if meta["needs_cargo_type"] and (not cargo_type or cargo_type not in CARGO_RATES):
        raise HTTPException(400, detail="برای بیمه باربری، نوع کالا الزامی است")
    if meta["needs_route"] and (not origin or not destination):
        raise HTTPException(400, detail="مبدأ و مقصد الزامی است")


# ── Schemas ─────────────────────────────────────────────────────
class QuoteRequest(BaseModel):
    product:       str   = Field("cargo", description="نوع بیمه‌نامه")
    subject:       Optional[str] = Field(None, description="موضوع بیمه")
    cargo_type:    Optional[str] = Field(None, description="نوع کالا (فقط باربری)")
    cargo_value:   int   = Field(..., gt=0, description="سرمایه/ارزش بیمه‌ای (تومان)")
    coverage_type: str   = Field("basic", description="نوع پوشش")
    origin:        Optional[str] = None
    destination:   Optional[str] = None


class QuoteResponse(BaseModel):
    product:          str
    product_label:    str
    cargo_type:       Optional[str]
    cargo_type_label: Optional[str]
    cargo_value:      int
    coverage_type:    str
    coverage_label:   str
    base_rate_pct:    float
    premium:          int
    source:           str = "internal"          # internal | provider
    provider_name:    Optional[str] = None      # نامِ خدمات‌دهندهٔ صادرکننده نرخ


class QuoteOption(BaseModel):
    source:          str                        # provider | internal
    provider_id:     Optional[str] = None
    provider_name:   Optional[str] = None
    premium:         int
    currency:        str = "IRR"                # ارزِ تسویهٔ همان مرکز (بین‌المللی)
    premium_usd:     Optional[int] = None       # حق‌بیمهٔ نرمال‌شده به سنتِ دلار (برای مقایسهٔ بین‌ارزی)
    commission_rate: Optional[float] = None
    best:            bool = False                # ارزان‌ترین گزینه (پس از نرمال‌سازیِ ارز)


class CompareResponse(BaseModel):
    product:        str
    product_label:  str
    cargo_value:    int
    coverage_type:  str
    coverage_label: str
    options:        List[QuoteOption]
    provider_count: int                         # تعدادِ مراکزِ پاسخ‌داده


class RequestCreate(BaseModel):
    product:       str   = "cargo"
    subject:       Optional[str] = None
    cargo_type:    Optional[str] = None
    cargo_value:   int   = Field(..., gt=0)
    coverage_type: str   = "basic"
    origin:        Optional[str] = None
    destination:   Optional[str] = None
    form_data:     Optional[dict] = None   # فیلدهای پویای هر محصول
    notes:         Optional[str] = None
    provider_id:   Optional[str] = None    # مرکزِ انتخابیِ کاربر از صفحهٔ مقایسه


class RequestOut(BaseModel):
    id:            str
    ref:           str
    product:       str
    product_label: str
    subject:       Optional[str]
    cargo_type:    Optional[str]
    cargo_value:   int
    origin:        Optional[str]
    destination:   Optional[str]
    coverage_type: str
    premium:       int
    form_data:     Optional[dict]
    notes:         Optional[str]
    status:        str
    source:        str = "internal"
    provider_name: Optional[str] = None
    provider_ref:  Optional[str] = None
    created_at:    datetime

    class Config:
        from_attributes = True

    @classmethod
    def from_orm(cls, obj) -> "RequestOut":
        return cls(
            id=str(obj.id), ref=obj.ref,
            product=obj.product or "cargo", product_label=product_label(obj.product or "cargo"),
            subject=obj.subject,
            cargo_type=obj.cargo_type, cargo_value=obj.cargo_value,
            origin=obj.origin, destination=obj.destination,
            coverage_type=obj.coverage_type, premium=obj.premium,
            form_data=obj.form_data, notes=obj.notes,
            status=obj.status,
            source=getattr(obj, "source", None) or "internal",
            provider_name=getattr(obj, "provider_name", None),
            provider_ref=getattr(obj, "provider_ref", None),
            created_at=obj.created_at,
        )


class ProductOut(BaseModel):
    id:          str
    label:       str
    emoji:       str
    needs_route: bool
    needs_cargo_type: bool
    value_label: str
    base_rate_pct: Optional[float]


class InquiryRequest(BaseModel):
    product:     str = Field("third_party", description="نوع بیمه‌نامه")
    plate:       Optional[str] = Field(None, description="پلاک خودرو")
    national_id: Optional[str] = Field(None, description="کد ملی بیمه‌گذار")
    vin:         Optional[str] = Field(None, description="شماره شاسی/VIN")


class InquiryResponse(BaseModel):
    found:       bool
    source:      str                  # sanhab | mock
    message:     str
    prefill:     dict                 # فیلدهای آماده برای form_data
    bonus_malus: Optional[int] = None  # سطح تخفیف عدم‌خسارت (۰..۱۰)


# ── Live provider adapter (Dilix→Provider) ──────────────────────
async def _provider_ctxs(db: AsyncSession, limit: int = 8, prefer_provider_id=None, product=None):
    """همهٔ مراکزِ احرازشده با APIِ production تست‌شده و کلیدِ production فعال.

    خروجی: لیستی از (base_url, headers, provider_name, provider_id, commission_rate).
    اگر `prefer_provider_id` داده شود، فقط همان مرکز برمی‌گردد (برای صدورِ انتخابی).
    اگر `product` داده شود، فقط مراکزی که آن محصول را پوشش می‌دهند
    (`products` تهی/خالی = پوششِ همه) برمی‌گردند.
    این یک seam است تا آداپترِ اختصاصیِ هر شرکت بعداً جایگزینِ قراردادِ عمومی شود.
    """
    try:
        from app.api.v1.provider.router import (
            Provider, ProviderAPI, ProviderCredential, _decrypt,
        )
    except Exception:
        return []
    ctxs = []
    try:
        q = (
            select(ProviderAPI, Provider)
            .join(Provider, Provider.id == ProviderAPI.provider_id)
            .where(
                Provider.kyb_status == "verified",
                ProviderAPI.env == "production",
                ProviderAPI.status == "tested",
            )
        )
        if prefer_provider_id:
            try:
                pid = prefer_provider_id if isinstance(prefer_provider_id, _uuid.UUID) else _uuid.UUID(str(prefer_provider_id))
                q = q.where(Provider.id == pid)
            except ValueError:
                return []
        q = q.limit(limit)
        r = await db.execute(q)
        for api, provider in r.all():
            if product:
                covered = getattr(provider, "products", None) or []
                if covered and product not in covered:
                    continue
            rc = await db.execute(
                select(ProviderCredential)
                .where(
                    ProviderCredential.provider_id == provider.id,
                    ProviderCredential.env == "production",
                    ProviderCredential.status == "active",
                )
                .limit(1)
            )
            cred = rc.scalars().first()
            if not cred:
                continue
            secret = _decrypt(cred.secret_enc)
            headers = {}
            if cred.auth_type == "bearer":
                headers["Authorization"] = f"Bearer {secret}"
            elif cred.auth_type == "basic":
                headers["Authorization"] = f"Basic {secret}"
            else:
                headers["X-API-Key"] = secret
            ctxs.append((
                api.base_url.rstrip("/"), headers, provider.legal_name,
                provider.id, float(provider.commission_rate or 0.0),
                (getattr(provider, "currency", None) or "IRR").upper(),
            ))
    except Exception:
        return ctxs
    return ctxs


async def _live_provider(db: AsyncSession, prefer_provider_id=None, product=None):
    """یک مرکزِ واجدِ شرایط (اولین، یا مرکزِ انتخابی) یا None."""
    ctxs = await _provider_ctxs(db, limit=1, prefer_provider_id=prefer_provider_id, product=product)
    return ctxs[0] if ctxs else None


async def _quote_from_ctx(ctx, product, cargo_value, coverage_type, cargo_type):
    """نرخ‌گیریِ یک مرکز از روی contextِ آماده. در هر خطا None."""
    base_url, headers, provider_name, provider_id, commission_rate, provider_currency = ctx
    try:
        import httpx
        payload = _provider_payload(product, cargo_value, coverage_type, cargo_type)
        async with httpx.AsyncClient(timeout=8.0, follow_redirects=True) as client:
            resp = await client.post(base_url + "/quote", json=payload, headers=headers)
        if resp.status_code >= 400:
            return None
        data = resp.json()
        premium = data.get("premium") or data.get("premium_amount")
        if not isinstance(premium, (int, float)) or premium <= 0:
            return None
        return {
            "provider_id": str(provider_id),
            "provider_name": provider_name,
            "premium": int(premium),
            "commission_rate": commission_rate,
            "currency": provider_currency,
        }
    except Exception:
        return None


def _provider_payload(product, cargo_value, coverage_type, cargo_type, extra=None):
    payload = {
        "line":          PROVIDER_LINE_MAP.get(product, product),
        "product":       product,
        "sum_insured":   cargo_value,
        "coverage_type": coverage_type,
        "cargo_type":    cargo_type,
    }
    if extra:
        payload.update(extra)
    return payload


async def _try_provider_quote(
    db: AsyncSession, product: str, cargo_value: int,
    coverage_type: str, cargo_type: Optional[str],
):
    """نرخِ زندهٔ محاسبه (بدون صدور) از خدمات‌دهنده. در هر خطا None (fallback داخلی).
    قرارداد: POST {base_url}/quote → JSON شاملِ `premium`.
    """
    ctx = await _live_provider(db, product=product)
    if not ctx:
        return None
    res = await _quote_from_ctx(ctx, product, cargo_value, coverage_type, cargo_type)
    if not res:
        return None
    return {"premium": res["premium"], "provider_name": res["provider_name"]}


async def _try_provider_issue(
    db: AsyncSession, product: str, cargo_value: int, coverage_type: str,
    cargo_type: Optional[str], form_data: Optional[dict], ref: str,
    prefer_provider_id=None,
):
    """صدورِ زندهٔ بیمه‌نامه نزدِ خدمات‌دهنده. در هر خطا None (fallback: ثبتِ داخلی).
    اگر `prefer_provider_id` داده شود، نزدِ همان مرکزِ انتخابیِ کاربر صادر می‌شود.
    قرارداد: POST {base_url}/issue → JSON شاملِ `premium` و شمارهٔ بیمه‌نامه
    (`policy_no`/`policy_number`).
    """
    ctx = await _live_provider(db, prefer_provider_id=prefer_provider_id, product=product)
    if not ctx:
        return None
    base_url, headers, provider_name, provider_id, commission_rate, provider_currency = ctx
    try:
        import httpx
        payload = _provider_payload(
            product, cargo_value, coverage_type, cargo_type,
            extra={"dilix_ref": ref, "form_data": form_data or {}},
        )
        async with httpx.AsyncClient(timeout=12.0, follow_redirects=True) as client:
            resp = await client.post(base_url + "/issue", json=payload, headers=headers)
        if resp.status_code >= 400:
            return None
        data = resp.json()
        premium = data.get("premium") or data.get("premium_amount")
        policy_no = data.get("policy_no") or data.get("policy_number") or data.get("policy")
        if not isinstance(premium, (int, float)) or premium <= 0:
            return None
        return {
            "premium": int(premium),
            "provider_name": provider_name,
            "provider_ref": str(policy_no)[:100] if policy_no else None,
            "provider_id": provider_id,
            "commission_rate": commission_rate,
        }
    except Exception:
        return None


# ── Endpoints ───────────────────────────────────────────────────

@router.get("/products", response_model=List[ProductOut])
async def list_products(me: User = Depends(get_current_user)):
    """کاتالوگ انواع بیمه‌نامه قابل صدور"""
    return [
        ProductOut(
            id=pid, label=meta["label"], emoji=meta["emoji"],
            needs_route=meta["needs_route"], needs_cargo_type=meta["needs_cargo_type"],
            value_label=meta["value_label"],
            base_rate_pct=round(meta["rate"] * 100, 3) if meta["rate"] is not None else None,
        )
        for pid, meta in PRODUCTS.items()
    ]


@router.post("/quote", response_model=QuoteResponse)
async def get_quote(
    body: QuoteRequest,
    db:   AsyncSession = Depends(get_db),
    me:   User         = Depends(get_current_user),
):
    """محاسبه حق بیمه بدون ثبت درخواست.

    ابتدا تلاش می‌کند نرخ را از خدمات‌دهندهٔ احرازشده (production) بگیرد؛
    در نبودِ آن، به موتور داخلی دیلیکس fallback می‌کند.
    """
    _validate_product(body.product, body.cargo_type, body.origin, body.destination)
    if body.coverage_type not in COVERAGE_MULTIPLIER:
        raise HTTPException(400, detail="نوع پوشش معتبر نیست")

    source        = "internal"
    provider_name = None
    live = await _try_provider_quote(
        db, body.product, body.cargo_value, body.coverage_type, body.cargo_type
    )
    if live:
        premium       = live["premium"]
        source        = "provider"
        provider_name = live["provider_name"]
    else:
        premium = calc_premium(body.product, body.cargo_value, body.coverage_type, body.cargo_type)

    return QuoteResponse(
        product          = body.product,
        product_label    = product_label(body.product),
        cargo_type       = body.cargo_type,
        cargo_type_label = CARGO_LABEL.get(body.cargo_type) if body.cargo_type else None,
        cargo_value      = body.cargo_value,
        coverage_type    = body.coverage_type,
        coverage_label   = COVERAGE_LABEL.get(body.coverage_type, body.coverage_type),
        base_rate_pct    = round(base_rate_for(body.product, body.cargo_type) * 100, 3),
        premium          = premium,
        source           = source,
        provider_name    = provider_name,
    )


def _premium_usd_cents(premium: int, currency: str, rates: dict) -> Optional[int]:
    """نرمال‌سازیِ حق‌بیمه به سنتِ دلار برای مقایسهٔ منصفانهٔ بین‌ارزی.

    قراردادِ واحد: حق‌بیمهٔ IRR در «تومان» ذخیره می‌شود (×۱۰ → ریال = واحدِ خردِ ISO)،
    و سایرِ ارزها در واحدِ اصلی (مثلِ €۵۰ → ۵۰۰۰ سنت). خروجی = سنتِ USD،
    یا None اگر نرخِ ارز موجود نبود.
    """
    cur = (currency or "IRR").upper()
    if cur == "IRR":
        minor = int(premium) * 10                    # تومان → ریال (واحدِ خردِ IRR)
    else:
        minor = int(premium) * minor_scale(cur)      # واحدِ اصلی → واحدِ خرد
    try:
        return convert_minor(minor, cur, "USD", rates)
    except (ValueError, KeyError, ZeroDivisionError):
        return None


@router.post("/compare", response_model=CompareResponse)
async def compare_quotes(
    body: QuoteRequest,
    db:   AsyncSession = Depends(get_db),
    me:   User         = Depends(get_current_user),
):
    """مقایسهٔ نرخِ همهٔ مراکزِ احرازشده به‌صورتِ هم‌زمان (قلبِ aggregator).

    نرخِ هر مرکزِ production را موازی می‌گیرد، نرخِ پایهٔ دیلیکس را هم به‌عنوانِ
    گزینهٔ داخلی اضافه می‌کند، و لیست را از ارزان به گران مرتب می‌کند
    (ارزان‌ترین = `best`). کاربر یکی را انتخاب و در `/requests` (با `provider_id`)
    صادر می‌کند.
    """
    import asyncio
    _validate_product(body.product, body.cargo_type, body.origin, body.destination)
    if body.coverage_type not in COVERAGE_MULTIPLIER:
        raise HTTPException(400, detail="نوع پوشش معتبر نیست")

    ctxs = await _provider_ctxs(db, limit=8, product=body.product)
    options: List[QuoteOption] = []
    if ctxs:
        results = await asyncio.gather(*[
            _quote_from_ctx(c, body.product, body.cargo_value, body.coverage_type, body.cargo_type)
            for c in ctxs
        ])
        for res in results:
            if res:
                options.append(QuoteOption(
                    source="provider",
                    provider_id=res["provider_id"],
                    provider_name=res["provider_name"],
                    premium=res["premium"],
                    currency=res.get("currency") or "IRR",
                    commission_rate=res["commission_rate"],
                ))

    # نرخِ پایهٔ دیلیکس همیشه به‌عنوانِ گزینهٔ مرجع
    options.append(QuoteOption(
        source="internal",
        provider_name="نرخ پایهٔ دیلیکس",
        premium=calc_premium(body.product, body.cargo_value, body.coverage_type, body.cargo_type),
    ))

    # نرمال‌سازیِ بین‌ارزی: همه را به سنتِ دلار تبدیل کن و بر پایهٔ آن مرتب کن،
    # تا €۵۰ اشتباهاً ارزان‌تر از ﷼۱٬۰۰۰٬۰۰۰ رتبه‌بندی نشود. اگر لایهٔ FX در دسترس
    # نبود (rates خالی) → fallback به مقدارِ خام (رفتارِ قبلی).
    rates = await get_rate_map(db)
    if rates:
        for o in options:
            o.premium_usd = _premium_usd_cents(o.premium, o.currency, rates)
        options.sort(key=lambda o: o.premium_usd if o.premium_usd is not None else float("inf"))
    else:
        options.sort(key=lambda o: o.premium)
    if options:
        options[0].best = True

    return CompareResponse(
        product        = body.product,
        product_label  = product_label(body.product),
        cargo_value    = body.cargo_value,
        coverage_type  = body.coverage_type,
        coverage_label = COVERAGE_LABEL.get(body.coverage_type, body.coverage_type),
        options        = options,
        provider_count = len(ctxs),
    )


@router.post("/inquiry", response_model=InquiryResponse)
async def inquiry(
    body: InquiryRequest,
    db:   AsyncSession = Depends(get_db),
    me:   User         = Depends(get_current_user),
):
    """استعلام سوابق و پیش‌پُرکردنِ فرم (سنهاب / شاهکار).

    فعلاً به‌صورتِ sandbox/mock پاسخ می‌دهد اما seamِ اتصال به سنهابِ واقعی
    (از طریق خدمات‌دهندهٔ احرازشده) در همین‌جا تعبیه شده است. خروجی برای
    پیش‌پُرکردنِ `form_data` در فرانت استفاده می‌شود.
    """
    if body.product not in PRODUCTS:
        raise HTTPException(400, "نوع بیمه‌نامه معتبر نیست")

    nid   = (body.national_id or "").strip()
    plate = (body.plate or "").strip()

    if body.product in ("third_party", "auto_body"):
        if not plate and not nid:
            raise HTTPException(400, "برای استعلام، پلاک یا کد ملی لازم است")
        # سطح تخفیفِ عدم‌خسارت را به‌صورتِ قطعی از ورودی مشتق می‌کنیم (mock پایدار)
        seed  = sum(ord(c) for c in (plate or nid))
        bonus = seed % 11                       # ۰..۱۰
        prefill = {
            "plate":            plate or None,
            "national_id":      nid or None,
            "bonus_malus":      str(bonus),
            "no_claim_years":   str(min(bonus, 10)),
            "previous_insurer": "بیمهٔ قبلی (استعلامی)",
        }
        return InquiryResponse(
            found=True, source="mock",
            message="سوابق راهنمایی و رانندگی به‌صورت آزمایشی بازیابی شد",
            prefill={k: v for k, v in prefill.items() if v is not None},
            bonus_malus=bonus,
        )

    if body.product in ("life", "health"):
        if not nid:
            raise HTTPException(400, "برای استعلام، کد ملی لازم است")
        return InquiryResponse(
            found=True, source="mock",
            message="اطلاعات هویتی (ثبت‌احوال) به‌صورت آزمایشی بازیابی شد",
            prefill={"national_id": nid, "health_status": "standard"},
        )

    return InquiryResponse(
        found=False, source="mock",
        message="برای این نوع بیمه‌نامه استعلامِ خودکار در دسترس نیست",
        prefill={},
    )


@router.post("/requests", response_model=RequestOut, status_code=201)
async def create_request(
    body:  RequestCreate,
    db:    AsyncSession = Depends(get_db),
    me:    User         = Depends(get_current_user),
):
    """ثبت رسمی درخواست/صدور بیمه‌نامه.

    اگر خدمات‌دهندهٔ احرازشده‌ای در دسترس باشد، بیمه‌نامه را نزدِ او **صادر** می‌کند
    (شمارهٔ بیمه‌نامه ذخیره و وضعیت approved می‌شود)؛ در غیر این‌صورت درخواست
    به‌صورتِ داخلی (pending) برای بررسی ثبت می‌شود.
    """
    _validate_product(body.product, body.cargo_type, body.origin, body.destination)
    ref = gen_ref()

    source          = "internal"
    provider_name   = None
    provider_ref    = None
    provider_id     = None
    commission_rate = 0.0
    req_status      = "pending"

    live = await _try_provider_issue(
        db, body.product, body.cargo_value, body.coverage_type,
        body.cargo_type, body.form_data, ref,
        prefer_provider_id=body.provider_id,
    )
    if live:
        premium         = live["premium"]
        source          = "provider"
        provider_name   = live["provider_name"]
        provider_ref    = live["provider_ref"]
        provider_id     = live.get("provider_id")
        commission_rate = float(live.get("commission_rate") or 0.0)
        req_status      = "approved"      # نزدِ خدمات‌دهنده صادر شد
    else:
        premium = calc_premium(body.product, body.cargo_value, body.coverage_type, body.cargo_type)

    req = InsuranceRequest(
        ref           = ref,
        owner_id      = me.id,
        product       = body.product,
        subject       = body.subject,
        cargo_type    = body.cargo_type,
        cargo_value   = body.cargo_value,
        origin        = body.origin,
        destination   = body.destination,
        coverage_type = body.coverage_type,
        premium       = premium,
        form_data     = body.form_data or None,
        notes         = body.notes,
        source        = source,
        provider_name = provider_name,
        provider_ref  = provider_ref,
        status        = req_status,
    )
    db.add(req)
    await db.flush()          # req.id در دسترس شود

    # دفترِ کارمزد: فقط برای صدورِ زندهٔ خدمات‌دهنده
    if source == "provider":
        commission_amount = int(round(premium * commission_rate / 100.0))
        db.add(InsuranceCommission(
            request_id        = req.id,
            request_ref       = ref,
            provider_id       = provider_id,
            provider_name     = provider_name,
            product           = body.product,
            premium           = premium,
            commission_rate   = commission_rate,
            commission_amount = commission_amount,
            status            = "accrued",
        ))

    await db.commit()
    await db.refresh(req)
    return RequestOut.from_orm(req)


@router.get("/requests", response_model=List[RequestOut])
async def list_requests(
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    r = await db.execute(
        select(InsuranceRequest)
        .where(InsuranceRequest.owner_id == me.id)
        .order_by(InsuranceRequest.created_at.desc())
        .limit(50)
    )
    return [RequestOut.from_orm(x) for x in r.scalars().all()]


@router.get("/requests/{req_id}", response_model=RequestOut)
async def get_request(
    req_id: str,
    db:     AsyncSession = Depends(get_db),
    me:     User         = Depends(get_current_user),
):
    req = await db.get(InsuranceRequest, _uuid.UUID(req_id))
    if not req:
        raise HTTPException(404, "درخواست پیدا نشد")
    if req.owner_id != me.id:
        raise HTTPException(403, "دسترسی ندارید")
    return RequestOut.from_orm(req)


# ── کنسولِ کارمزد/تسویه (فقط ادمین) ──────────────────────────────
ADMIN_ROLES = ("admin", "super_admin")


def _require_admin(me: User) -> None:
    if getattr(me, "role", None) not in ADMIN_ROLES:
        raise HTTPException(403, "دسترسیِ مدیر لازم است")


class CommissionOut(BaseModel):
    id:                str
    request_ref:       Optional[str] = None
    provider_id:       Optional[str] = None
    provider_name:     Optional[str] = None
    product:           Optional[str] = None
    premium:           int
    commission_rate:   float
    commission_amount: int
    status:            str
    settled_at:        Optional[datetime] = None
    created_at:        datetime

    @classmethod
    def from_orm(cls, o: "InsuranceCommission") -> "CommissionOut":
        return cls(
            id=str(o.id), request_ref=o.request_ref,
            provider_id=str(o.provider_id) if o.provider_id else None,
            provider_name=o.provider_name, product=o.product,
            premium=int(o.premium or 0), commission_rate=float(o.commission_rate or 0),
            commission_amount=int(o.commission_amount or 0), status=o.status,
            settled_at=o.settled_at, created_at=o.created_at,
        )


class ProviderCommissionSummary(BaseModel):
    provider_id:       Optional[str] = None
    provider_name:     Optional[str] = None
    policies:          int
    total_premium:     int
    total_commission:  int
    accrued_commission: int
    settled_commission: int


class SettleRequest(BaseModel):
    provider_id: Optional[str] = None      # اگر داده شود: تسویهٔ همهٔ accruedهای این مرکز
    note:        Optional[str] = Field(None, max_length=300)


@router.get("/admin/commissions/summary", response_model=List[ProviderCommissionSummary])
async def commissions_summary(
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    """جمعِ کارمزد به تفکیکِ خدمات‌دهنده (accrued/settled)."""
    _require_admin(me)
    accrued = func.sum(
        case((InsuranceCommission.status == "accrued",
              InsuranceCommission.commission_amount), else_=0)
    )
    settled = func.sum(
        case((InsuranceCommission.status == "settled",
              InsuranceCommission.commission_amount), else_=0)
    )
    r = await db.execute(
        select(
            InsuranceCommission.provider_id,
            func.max(InsuranceCommission.provider_name),
            func.count(InsuranceCommission.id),
            func.sum(InsuranceCommission.premium),
            func.sum(InsuranceCommission.commission_amount),
            accrued, settled,
        )
        .group_by(InsuranceCommission.provider_id)
        .order_by(accrued.desc())
    )
    out = []
    for pid, pname, cnt, prem, comm, acc, setl in r.all():
        out.append(ProviderCommissionSummary(
            provider_id=str(pid) if pid else None,
            provider_name=pname,
            policies=int(cnt or 0),
            total_premium=int(prem or 0),
            total_commission=int(comm or 0),
            accrued_commission=int(acc or 0),
            settled_commission=int(setl or 0),
        ))
    return out


@router.get("/admin/commissions", response_model=List[CommissionOut])
async def commissions_list(
    status_filter: Optional[str] = None,
    provider_id:   Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    """لیستِ ردیف‌های دفترِ کارمزد (با فیلترِ اختیاریِ وضعیت/مرکز)."""
    _require_admin(me)
    q = select(InsuranceCommission).order_by(InsuranceCommission.created_at.desc()).limit(200)
    if status_filter in ("accrued", "settled"):
        q = q.where(InsuranceCommission.status == status_filter)
    if provider_id:
        try:
            q = q.where(InsuranceCommission.provider_id == _uuid.UUID(provider_id))
        except ValueError:
            raise HTTPException(400, "شناسهٔ مرکز نامعتبر است")
    r = await db.execute(q)
    return [CommissionOut.from_orm(x) for x in r.scalars().all()]


@router.post("/admin/commissions/settle")
async def commissions_settle(
    body: SettleRequest,
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    """تسویهٔ دسته‌ایِ همهٔ کارمزدهای accruedِ یک مرکز → status=settled."""
    _require_admin(me)
    if not body.provider_id:
        raise HTTPException(400, "شناسهٔ مرکز لازم است")
    try:
        pid = _uuid.UUID(body.provider_id)
    except ValueError:
        raise HTTPException(400, "شناسهٔ مرکز نامعتبر است")
    r = await db.execute(
        select(InsuranceCommission).where(
            InsuranceCommission.provider_id == pid,
            InsuranceCommission.status == "accrued",
        )
    )
    rows = r.scalars().all()
    now = _now()
    total = 0
    for row in rows:
        row.status = "settled"
        row.settled_at = now
        if body.note:
            row.note = body.note[:300]
        total += int(row.commission_amount or 0)
    await db.commit()
    return {"settled_count": len(rows), "settled_amount": total}


@router.post("/admin/commissions/{commission_id}/settle", response_model=CommissionOut)
async def commission_settle_one(
    commission_id: str,
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    """تسویهٔ یک ردیفِ کارمزد."""
    _require_admin(me)
    try:
        cid = _uuid.UUID(commission_id)
    except ValueError:
        raise HTTPException(400, "شناسهٔ نامعتبر است")
    row = await db.get(InsuranceCommission, cid)
    if not row:
        raise HTTPException(404, "ردیف پیدا نشد")
    if row.status != "settled":
        row.status = "settled"
        row.settled_at = _now()
        await db.commit()
        await db.refresh(row)
    return CommissionOut.from_orm(row)


# ── صورت‌حسابِ خدمات‌دهنده (فقط مالکِ همان مرکز) ─────────────────
async def _owned_provider_or_403(db: AsyncSession, provider_id: str, me: User):
    """مرکز را برمی‌گرداند اگر کاربرِ جاری مالکِ آن باشد؛ وگرنه خطا.

    برای صورت‌حسابِ سمتِ شریک: هر مرکز فقط کارمزدِ خودش را می‌بیند.
    """
    try:
        from app.api.v1.provider.router import Provider
    except Exception:
        raise HTTPException(500, "ماژول خدمات‌دهنده در دسترس نیست")
    try:
        pid = _uuid.UUID(str(provider_id))
    except ValueError:
        raise HTTPException(400, "شناسهٔ مرکز نامعتبر است")
    p = await db.get(Provider, pid)
    if not p:
        raise HTTPException(404, "مرکز پیدا نشد")
    if p.owner_id != me.id and getattr(me, "role", None) not in ADMIN_ROLES:
        raise HTTPException(403, "دسترسی ندارید")
    return p


@router.get("/provider/{provider_id}/statement", response_model=ProviderCommissionSummary)
async def provider_statement(
    provider_id: str,
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    """صورت‌حسابِ کارمزدِ خودِ مرکز (مالک‌محور): جمعِ بیمه‌نامه‌ها،
    حق‌بیمهٔ کل، کارمزدِ کل، و تفکیکِ پرداخت‌نشده/تسویه‌شده.
    """
    p = await _owned_provider_or_403(db, provider_id, me)
    accrued = func.sum(
        case((InsuranceCommission.status == "accrued",
              InsuranceCommission.commission_amount), else_=0)
    )
    settled = func.sum(
        case((InsuranceCommission.status == "settled",
              InsuranceCommission.commission_amount), else_=0)
    )
    r = await db.execute(
        select(
            func.count(InsuranceCommission.id),
            func.sum(InsuranceCommission.premium),
            func.sum(InsuranceCommission.commission_amount),
            accrued, settled,
        ).where(InsuranceCommission.provider_id == p.id)
    )
    cnt, prem, comm, acc, setl = r.one()
    return ProviderCommissionSummary(
        provider_id=str(p.id),
        provider_name=p.legal_name,
        policies=int(cnt or 0),
        total_premium=int(prem or 0),
        total_commission=int(comm or 0),
        accrued_commission=int(acc or 0),
        settled_commission=int(setl or 0),
    )


@router.get("/provider/{provider_id}/commissions", response_model=List[CommissionOut])
async def provider_commissions(
    provider_id: str,
    status_filter: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    """ردیف‌های کارمزدِ خودِ مرکز (مالک‌محور، جدیدترین اول)."""
    p = await _owned_provider_or_403(db, provider_id, me)
    q = (
        select(InsuranceCommission)
        .where(InsuranceCommission.provider_id == p.id)
        .order_by(InsuranceCommission.created_at.desc())
        .limit(100)
    )
    if status_filter in ("accrued", "settled"):
        q = q.where(InsuranceCommission.status == status_filter)
    r = await db.execute(q)
    return [CommissionOut.from_orm(x) for x in r.scalars().all()]
