/**
 * Dilix — i18n Store (Zustand)
 * زبانِ جاری را به‌صورتِ واکنش‌گرا (reactive) نگه می‌دارد تا کامپوننت‌های ترجمه‌شده
 * با تغییرِ زبان دوباره render شوند. مقدارِ اولیه = DEFAULT_LOCALE تا با SSR هم‌خوان
 * بماند و hydration mismatch رخ ندهد؛ سپس در AppShell از localStorage همگام می‌شود.
 */
import { create } from "zustand";
import { DEFAULT_LOCALE, applyLocale, dirOf, t as translate } from "@/lib/i18n";

interface I18nState {
  locale: string;
  setLocale: (locale: string, currency?: string) => void;
}

export const useI18nStore = create<I18nState>((set) => ({
  locale: DEFAULT_LOCALE,
  setLocale: (locale, currency) => {
    applyLocale(locale, currency);
    set({ locale });
  },
}));

/** هوکِ ترجمه — با تغییرِ زبان، کامپوننت دوباره render می‌شود. */
export function useTranslation() {
  const locale = useI18nStore((s) => s.locale);
  return {
    locale,
    dir: dirOf(locale),
    t: (key: string) => translate(key, locale),
  };
}
