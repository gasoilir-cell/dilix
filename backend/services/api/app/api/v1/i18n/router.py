"""
Dilix — i18n / Globalization Router
پایهٔ جهانی‌سازی: کاتالوگِ زبان‌ها و ارزها، تشخیصِ خودکارِ زبان/ارز بر اساسِ IP/مرورگر،
و ترجیحاتِ کاربر (locale/currency/country/timezone).

GET  /api/v1/i18n/catalog        فهرستِ زبان‌ها + ارزها + نگاشتِ کشور→پیش‌فرض (عمومی)
GET  /api/v1/i18n/detect         پیشنهادِ زبان/ارز بر اساسِ هدرهای درخواست (عمومی)
GET  /api/v1/i18n/preferences    خواندنِ ترجیحاتِ کاربر (نیازمندِ ورود)
PUT  /api/v1/i18n/preferences    ذخیرهٔ ترجیحاتِ کاربر (نیازمندِ ورود)
"""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models.user import User

router = APIRouter(prefix="/i18n", tags=["i18n"])

# ─── کاتالوگِ زبان‌ها ───────────────────────────────────────────
# code → (نامِ بومی، نامِ انگلیسی، جهت، ارزِ پیش‌فرض، پرچم)
LOCALES = {
    "fa": ("فارسی",     "Persian",  "rtl", "IRR", "🇮🇷"),
    "en": ("English",   "English",  "ltr", "USD", "🇺🇸"),
    "ar": ("العربية",   "Arabic",   "rtl", "AED", "🇸🇦"),
    "tr": ("Türkçe",    "Turkish",  "ltr", "TRY", "🇹🇷"),
    "ru": ("Русский",   "Russian",  "ltr", "RUB", "🇷🇺"),
    "fr": ("Français",  "French",   "ltr", "EUR", "🇫🇷"),
    "de": ("Deutsch",   "German",   "ltr", "EUR", "🇩🇪"),
    "es": ("Español",   "Spanish",  "ltr", "EUR", "🇪🇸"),
    "zh": ("中文",       "Chinese",  "ltr", "CNY", "🇨🇳"),
    "hi": ("हिन्दी",     "Hindi",    "ltr", "INR", "🇮🇳"),
}

# ─── کاتالوگِ ارزها ─────────────────────────────────────────────
# code → (نامِ فارسی، نامِ انگلیسی، نماد، تعدادِ اعشار، واحدِ نمایشِ محلی/فرعی)
CURRENCIES = {
    "IRR": ("ریال ایران",     "Iranian Rial",     "﷼",  0, "تومان"),
    "USD": ("دلار آمریکا",     "US Dollar",        "$",  2, None),
    "EUR": ("یورو",           "Euro",             "€",  2, None),
    "GBP": ("پوند بریتانیا",   "British Pound",    "£",  2, None),
    "AED": ("درهم امارات",     "UAE Dirham",       "د.إ", 2, None),
    "SAR": ("ریال سعودی",      "Saudi Riyal",      "ر.س", 2, None),
    "TRY": ("لیر ترکیه",       "Turkish Lira",     "₺",  2, None),
    "RUB": ("روبل روسیه",      "Russian Ruble",    "₽",  2, None),
    "CNY": ("یوان چین",       "Chinese Yuan",     "¥",  2, None),
    "INR": ("روپیه هند",       "Indian Rupee",     "₹",  2, None),
    "CAD": ("دلار کانادا",     "Canadian Dollar",  "C$", 2, None),
    "AUD": ("دلار استرالیا",   "Australian Dollar","A$", 2, None),
}

# ─── نگاشتِ کشور (ISO alpha-2) → زبان/ارزِ پیش‌فرض ────────────────
COUNTRY_MAP = {
    "IR": ("fa", "IRR"), "US": ("en", "USD"), "GB": ("en", "GBP"),
    "CA": ("en", "CAD"), "AU": ("en", "AUD"), "IE": ("en", "EUR"),
    "DE": ("de", "EUR"), "AT": ("de", "EUR"), "CH": ("de", "EUR"),
    "FR": ("fr", "EUR"), "BE": ("fr", "EUR"),
    "ES": ("es", "EUR"), "MX": ("es", "USD"), "AR": ("es", "USD"),
    "IT": ("en", "EUR"), "NL": ("en", "EUR"),
    "TR": ("tr", "TRY"), "RU": ("ru", "RUB"),
    "CN": ("zh", "CNY"), "HK": ("zh", "USD"), "TW": ("zh", "USD"),
    "AE": ("ar", "AED"), "SA": ("ar", "SAR"), "QA": ("ar", "USD"),
    "KW": ("ar", "USD"), "IQ": ("ar", "USD"), "EG": ("ar", "USD"),
    "IN": ("hi", "INR"),
}

DEFAULT_LOCALE = "en"
DEFAULT_CURRENCY = "USD"


def _dir(locale: str) -> str:
    return LOCALES.get(locale, LOCALES[DEFAULT_LOCALE])[2]


def _default_currency_for(locale: str) -> str:
    return LOCALES.get(locale, LOCALES[DEFAULT_LOCALE])[3]


@router.get("/catalog")
async def get_catalog():
    """کاتالوگِ کاملِ زبان‌ها، ارزها و نگاشتِ کشورها — بدونِ نیاز به ورود."""
    return {
        "locales": [
            {"code": c, "native": v[0], "english": v[1], "dir": v[2],
             "default_currency": v[3], "flag": v[4]}
            for c, v in LOCALES.items()
        ],
        "currencies": [
            {"code": c, "name_fa": v[0], "name_en": v[1], "symbol": v[2],
             "decimals": v[3], "subunit": v[4]}
            for c, v in CURRENCIES.items()
        ],
        "default_locale": DEFAULT_LOCALE,
        "default_currency": DEFAULT_CURRENCY,
    }


@router.get("/detect")
async def detect_locale(request: Request):
    """
    پیشنهادِ زبان/ارز بر اساسِ کشورِ IP (هدرهای پروکسی/CDN) و سپس Accept-Language مرورگر.
    خروجی فقط «پیشنهاد» است؛ کاربر می‌تواند override کند.
    """
    hdr = request.headers
    country = (
        hdr.get("cf-ipcountry")
        or hdr.get("x-country-code")
        or hdr.get("x-geo-country")
        or ""
    ).upper().strip()
    locale: Optional[str] = None
    currency: Optional[str] = None
    source: Optional[str] = None

    if country and country in COUNTRY_MAP:
        locale, currency = COUNTRY_MAP[country]
        source = "geoip"

    accept = hdr.get("accept-language", "") or ""
    if not locale:
        tag = accept.split(",")[0].split(";")[0].strip().lower() if accept else ""
        base = tag.split("-")[0] if tag else ""
        if base in LOCALES:
            locale = base
            source = "accept-language"
        if "-" in tag and not country:
            country = tag.split("-")[1].upper()
            if country in COUNTRY_MAP and not currency:
                currency = COUNTRY_MAP[country][1]

    if not locale:
        locale = DEFAULT_LOCALE
        source = source or "default"
    if not currency:
        currency = _default_currency_for(locale)

    return {
        "suggested_locale": locale,
        "suggested_currency": currency,
        "country": country or None,
        "direction": _dir(locale),
        "source": source,
        "accept_language": accept or None,
    }


class PreferencesOut(BaseModel):
    locale: str
    currency: str
    country_code: Optional[str] = None
    timezone: Optional[str] = None
    direction: str


class UpdatePreferences(BaseModel):
    locale: Optional[str] = Field(default=None, max_length=10)
    currency: Optional[str] = Field(default=None, max_length=3)
    country_code: Optional[str] = Field(default=None, max_length=3)
    timezone: Optional[str] = Field(default=None, max_length=50)


def _prefs_out(user: User) -> PreferencesOut:
    # کاربرانِ موجود (پیش از i18n) locale=NULL دارند و فارسی‌زبانند؛ پس fallbackِ حسابِ
    # کاربر «fa» است. (detect برای بازدیدکنندهٔ ناشناسِ خارجی، آخرین‌راهش «en» است.)
    loc = user.locale or "fa"
    cur = getattr(user, "currency", None) or _default_currency_for(loc)
    return PreferencesOut(
        locale=loc,
        currency=cur,
        country_code=user.country_code,
        timezone=user.timezone_name,
        direction=_dir(loc),
    )


@router.get("/preferences", response_model=PreferencesOut)
async def get_preferences(user: User = Depends(get_current_user)):
    return _prefs_out(user)


@router.put("/preferences", response_model=PreferencesOut)
async def update_preferences(
    body: UpdatePreferences,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if body.locale is not None:
        if body.locale not in LOCALES:
            raise HTTPException(status_code=400, detail="زبانِ انتخاب‌شده پشتیبانی نمی‌شود")
        user.locale = body.locale
    if body.currency is not None:
        cur = body.currency.upper()
        if cur not in CURRENCIES:
            raise HTTPException(status_code=400, detail="ارزِ انتخاب‌شده پشتیبانی نمی‌شود")
        user.currency = cur
    if body.country_code is not None:
        user.country_code = body.country_code.upper()[:3] or None
    if body.timezone is not None:
        user.timezone_name = body.timezone or None
    await db.commit()
    await db.refresh(user)
    return _prefs_out(user)
