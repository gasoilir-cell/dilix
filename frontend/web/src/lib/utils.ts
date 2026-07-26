import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/** تبدیل اعداد به فارسی */
export function toPersianNum(n: number | string): string {
  const persianDigits = ["۰", "۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹"];
  return String(n).replace(/\d/g, (d) => persianDigits[parseInt(d)]);
}

/** فرمت مبلغ تومان */
export function formatAmount(amount: number, currency = "تومان"): string {
  const formatted = new Intl.NumberFormat("fa-IR").format(amount);
  return `${formatted} ${currency}`;
}

/** ماسک شماره موبایل */
export function maskPhone(phone: string): string {
  if (phone.length <= 4) return "***";
  return `${"*".repeat(phone.length - 4)}${phone.slice(-4)}`;
}

/** تشخیص RTL بودن زبان */
export function isRTL(locale: string): boolean {
  return ["fa", "ar"].includes(locale);
}
