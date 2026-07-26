import fa from "./locales/fa.json";
import en from "./locales/en.json";

export type Locale = "fa" | "en";
export type Messages = typeof fa;

const messages: Record<Locale, Messages> = { fa, en };

let currentLocale: Locale = "fa";

export function setLocale(locale: Locale) {
  currentLocale = locale;
}

export function getLocale(): Locale {
  return currentLocale;
}

export function t(key: string, params?: Record<string, string | number>): string {
  const keys = key.split(".");
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let value: any = messages[currentLocale];
  for (const k of keys) {
    value = value?.[k];
    if (value === undefined) return key;
  }
  if (typeof value !== "string") return key;
  if (params) {
    return Object.entries(params).reduce(
      (str, [k, v]) => str.replace(new RegExp(`\\{${k}\\}`, "g"), String(v)),
      value
    );
  }
  return value;
}
