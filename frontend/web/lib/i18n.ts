// i18n سبک — fa (RTL) پیش‌فرض. برای زبان‌های بیشتر دیکشنری اضافه کنید.
export type Locale = "fa" | "en" | "ar" | "ru" | "tr";

export const RTL_LOCALES: ReadonlySet<Locale> = new Set(["fa", "ar"]);

export function dir(locale: Locale): "rtl" | "ltr" {
  return RTL_LOCALES.has(locale) ? "rtl" : "ltr";
}

const fa = {
  app_name: "Dilix",
  nav_home: "خانه",
  nav_earth: "کره‌ی زمین",
  nav_messages: "پیام‌ها",
  nav_services: "خدمات",
  nav_me: "من",
  assistant: "دستیار هوشمند",
  feed_empty: "هنوز پستی نیست.",
  earth_title: "کشفِ افراد و کسب‌وکار روی کره",
  earth_privacy: "فقط کاربرانِ opt-in نمایش داده می‌شوند؛ مختصاتِ دقیق هرگز فاش نمی‌شود.",
  services_title: "خدمات",
  freight: "حمل‌ونقل (اسنپِ بار)",
  insurance: "بیمه",
  telecom: "ارتباطات",
  marketplace: "بازارگاه",
  me_title: "حساب من",
  wallet: "کیفِ پاداش",
  membership: "عضویت",
  privacy_settings: "تنظیماتِ حریمِ خصوصی",
  provider_portal: "پورتالِ ارائه‌دهنده",
} as const;

export type Dict = typeof fa;

const dictionaries: Record<Locale, Dict> = {
  fa,
  en: { ...fa, app_name: "Dilix", nav_home: "Home", nav_earth: "Earth", nav_messages: "Messages", nav_services: "Services", nav_me: "Me" },
  ar: fa,
  ru: fa,
  tr: fa,
};

export function t(locale: Locale): Dict {
  return dictionaries[locale] ?? fa;
}
