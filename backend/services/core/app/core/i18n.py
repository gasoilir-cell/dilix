"""سیستم i18n ساده — ترجمه‌ی پیام‌های API (سند ۰: fa, en, ru, ar, tr).

استفاده:
  from app.core.i18n import t
  raise NotFoundError(t("not_found.user", locale="en"))

در نسخه‌ی کامل این catalog از فایل‌های .po/.mo یا Babel بارگذاری می‌شود.
"""
from __future__ import annotations

from fastapi import Request

LOCALES = ("fa", "en", "ru", "ar", "tr")
DEFAULT_LOCALE = "fa"

# ─────────────────────── Catalog ─────────────────────────────
# کلید: namespace.key → {locale: text}
_CATALOG: dict[str, dict[str, str]] = {
    # ── خطاهای عمومی ──
    "error.not_found": {
        "fa": "مورد درخواستی یافت نشد.",
        "en": "The requested resource was not found.",
        "ru": "Запрошенный ресурс не найден.",
        "ar": "لم يتم العثور على المورد المطلوب.",
        "tr": "İstenen kaynak bulunamadı.",
    },
    "error.forbidden": {
        "fa": "دسترسی مجاز نیست.",
        "en": "Access denied.",
        "ru": "Доступ запрещён.",
        "ar": "الوصول مرفوض.",
        "tr": "Erişim reddedildi.",
    },
    "error.conflict": {
        "fa": "تعارض داده — این مورد قبلاً وجود دارد.",
        "en": "Conflict — this resource already exists.",
        "ru": "Конфликт — ресурс уже существует.",
        "ar": "تعارض — هذا المورد موجود بالفعل.",
        "tr": "Çakışma — bu kaynak zaten mevcut.",
    },
    "error.validation": {
        "fa": "داده‌های ورودی معتبر نیستند.",
        "en": "Validation error in request data.",
        "ru": "Ошибка валидации входных данных.",
        "ar": "خطأ في التحقق من صحة البيانات المدخلة.",
        "tr": "Girdi verilerinde doğrulama hatası.",
    },
    # ── Auth ──
    "auth.register_success": {
        "fa": "ثبت‌نام با موفقیت انجام شد.",
        "en": "Registration successful.",
        "ru": "Регистрация прошла успешно.",
        "ar": "تم التسجيل بنجاح.",
        "tr": "Kayıt başarıyla tamamlandı.",
    },
    "auth.login_failed": {
        "fa": "نام کاربری یا رمز عبور نادرست است.",
        "en": "Invalid credentials.",
        "ru": "Неверные учётные данные.",
        "ar": "بيانات الاعتماد غير صحيحة.",
        "tr": "Geçersiz kimlik bilgileri.",
    },
    "auth.mfa_required": {
        "fa": "کد MFA الزامی است.",
        "en": "MFA code is required.",
        "ru": "Требуется код MFA.",
        "ar": "رمز MFA مطلوب.",
        "tr": "MFA kodu gerekli.",
    },
    # ── KYC ──
    "kyc.pending": {
        "fa": "درخواست KYC شما در حال بررسی است.",
        "en": "Your KYC request is under review.",
        "ru": "Ваш запрос KYC на проверке.",
        "ar": "طلب KYC الخاص بك قيد المراجعة.",
        "tr": "KYC talebiniz inceleme aşamasında.",
    },
    # ── Payment ──
    "payment.escrow_created": {
        "fa": "امانت با موفقیت ایجاد شد.",
        "en": "Escrow created successfully.",
        "ru": "Эскроу успешно создан.",
        "ar": "تم إنشاء الضمان بنجاح.",
        "tr": "Emanet başarıyla oluşturuldu.",
    },
    # ── Freight ──
    "freight.bid_placed": {
        "fa": "پیشنهاد قیمت ثبت شد.",
        "en": "Bid placed successfully.",
        "ru": "Ставка успешно размещена.",
        "ar": "تم تقديم العرض بنجاح.",
        "tr": "Teklif başarıyla yerleştirildi.",
    },
    "freight.delivered": {
        "fa": "کالا تحویل داده شد.",
        "en": "Cargo delivered.",
        "ru": "Груз доставлен.",
        "ar": "تم تسليم البضاعة.",
        "tr": "Kargo teslim edildi.",
    },
}


def t(key: str, locale: str = DEFAULT_LOCALE, **kwargs: str) -> str:
    """ترجمه‌ی یک کلید به زبان مشخص. اگر یافت نشد fallback به fa."""
    locale = locale if locale in LOCALES else DEFAULT_LOCALE
    entry = _CATALOG.get(key, {})
    text = entry.get(locale) or entry.get(DEFAULT_LOCALE) or key
    if kwargs:
        try:
            text = text.format(**kwargs)
        except KeyError:
            pass
    return text


def locale_from_request(request: Request) -> str:
    """استخراج locale از Accept-Language header."""
    accept = request.headers.get("Accept-Language", "")
    for part in accept.split(","):
        lang = part.strip().split(";")[0].strip()[:2].lower()
        if lang in LOCALES:
            return lang
    return DEFAULT_LOCALE
