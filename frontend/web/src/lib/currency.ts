/**
 * Dilix — ارز (Currency) سمتِ کلاینت
 * کاتالوگِ ارزها + قالب‌بندیِ مبلغ با نماد/اعشار، مستقل از زبان.
 * نکته: کیف‌پولِ ایرانی مبلغ را «ریال» نگه می‌دارد و نمایشِ داخلی «تومان» است
 * (تومان = ریال ÷ ۱۰). برای ارزهای دیگر، مبلغ در واحدِ فرعی (cents) نگهداری می‌شود.
 */

export interface CurrencyMeta {
  code: string;
  nameFa: string;
  nameEn: string;
  symbol: string;
  decimals: number;
  /** واحدِ فرعیِ نمایشِ محلی (مثلِ «تومان» برای ریال) */
  subunit?: string | null;
  /** نوعِ ارز: فیات یا ارزِ دیجیتال */
  kind?: "fiat" | "crypto";
}

export const CURRENCIES: Record<string, CurrencyMeta> = {
  IRR: { code: "IRR", nameFa: "ریال ایران", nameEn: "Iranian Rial", symbol: "﷼", decimals: 0, subunit: "تومان" },
  USD: { code: "USD", nameFa: "دلار آمریکا", nameEn: "US Dollar", symbol: "$", decimals: 2 },
  EUR: { code: "EUR", nameFa: "یورو", nameEn: "Euro", symbol: "€", decimals: 2 },
  GBP: { code: "GBP", nameFa: "پوند بریتانیا", nameEn: "British Pound", symbol: "£", decimals: 2 },
  AED: { code: "AED", nameFa: "درهم امارات", nameEn: "UAE Dirham", symbol: "د.إ", decimals: 2 },
  SAR: { code: "SAR", nameFa: "ریال سعودی", nameEn: "Saudi Riyal", symbol: "ر.س", decimals: 2 },
  TRY: { code: "TRY", nameFa: "لیر ترکیه", nameEn: "Turkish Lira", symbol: "₺", decimals: 2 },
  RUB: { code: "RUB", nameFa: "روبل روسیه", nameEn: "Russian Ruble", symbol: "₽", decimals: 2 },
  CNY: { code: "CNY", nameFa: "یوان چین", nameEn: "Chinese Yuan", symbol: "¥", decimals: 2 },
  INR: { code: "INR", nameFa: "روپیه هند", nameEn: "Indian Rupee", symbol: "₹", decimals: 2 },
  CAD: { code: "CAD", nameFa: "دلار کانادا", nameEn: "Canadian Dollar", symbol: "C$", decimals: 2 },
  AUD: { code: "AUD", nameFa: "دلار استرالیا", nameEn: "Australian Dollar", symbol: "A$", decimals: 2 },
  // ── ارزهای دیجیتال (اعشار مطابقِ minor_scale بک‌اند) ──
  BTC: { code: "BTC", nameFa: "بیت‌کوین", nameEn: "Bitcoin", symbol: "₿", decimals: 8, kind: "crypto" },
  ETH: { code: "ETH", nameFa: "اتریوم", nameEn: "Ethereum", symbol: "Ξ", decimals: 8, kind: "crypto" },
  TON: { code: "TON", nameFa: "تون‌کوین", nameEn: "Toncoin", symbol: "TON", decimals: 6, kind: "crypto" },
  TRX: { code: "TRX", nameFa: "ترون", nameEn: "Tron", symbol: "TRX", decimals: 6, kind: "crypto" },
};

/** آیا این ارز دیجیتال است؟ */
export function isCrypto(code?: string | null): boolean {
  return currencyMeta(code).kind === "crypto";
}

export function currencyMeta(code?: string | null): CurrencyMeta {
  return (code && CURRENCIES[code]) || CURRENCIES.IRR;
}

const FA_DIGITS = "۰۱۲۳۴۵۶۷۸۹";
function toPersianDigits(s: string): string {
  return s.replace(/[0-9]/g, (d) => FA_DIGITS[+d]);
}

/**
 * قالب‌بندیِ مبلغ برای نمایش.
 * @param amount مبلغ در واحدِ پایه (ریال برای IRR، cents برای بقیه)
 * @param currency کدِ ارز
 * @param locale برای رقم‌های فارسی/لاتین و جداکننده‌ها
 */
export function formatMoney(amount: number, currency?: string | null, locale = "fa"): string {
  const m = currencyMeta(currency);
  let value: number;
  let unit: string;
  if (m.code === "IRR") {
    // نمایشِ ایرانی بر حسبِ تومان (ریال ÷ ۱۰)
    value = Math.round(amount / 10);
    unit = m.subunit || "تومان";
  } else {
    value = amount / Math.pow(10, m.decimals);
    unit = m.symbol;
  }
  const localeTag = locale === "fa" ? "en-US" : locale;
  if (m.kind === "crypto") {
    // ارزِ دیجیتال: تا ۸ رقمِ اعشار، صفرهای انتهایی حذف، کد بعد از عدد
    const formattedC = value.toLocaleString(localeTag, {
      minimumFractionDigits: 0,
      maximumFractionDigits: m.decimals,
    });
    const shownC = locale === "fa" ? toPersianDigits(formattedC) : formattedC;
    return `${shownC} ${m.code}`;
  }
  const formatted = value.toLocaleString(localeTag, {
    minimumFractionDigits: m.code === "IRR" ? 0 : m.decimals,
    maximumFractionDigits: m.code === "IRR" ? 0 : m.decimals,
  });
  const shown = locale === "fa" ? toPersianDigits(formatted) : formatted;
  // برای IRR واحد بعد از عدد؛ برای ارزهای نمادی، نماد قبل از عدد
  return m.code === "IRR" ? `${shown} ${unit}` : `${unit}${shown}`;
}
