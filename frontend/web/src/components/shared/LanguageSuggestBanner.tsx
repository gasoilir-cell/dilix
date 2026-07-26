"use client";

/**
 * Dilix — نوارِ پیشنهادِ زبان/ارز (جهانی‌سازی)
 * در نخستین بازدید، بر اساسِ کشورِ IP (هدرهای پروکسی) و زبانِ مرورگر، زبان و ارزِ
 * مناسب را پیشنهاد می‌دهد. کاربر می‌تواند اعمال یا رد کند؛ انتخاب ذخیره می‌شود.
 */
import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { Globe, X } from "lucide-react";

import { i18nApi } from "@/lib/api";
import { useAuthStore } from "@/store/auth";
import {
  LOCALES,
  DEFAULT_LOCALE,
  LS_LOCALE,
  LS_LANG_DISMISSED,
  localeMeta,
  applyLocale,
  t,
} from "@/lib/i18n";
import { currencyMeta } from "@/lib/currency";

export default function LanguageSuggestBanner() {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);
  const [suggest, setSuggest] = useState<{ locale: string; currency: string } | null>(null);

  useEffect(() => {
    if (typeof window === "undefined") return;
    // اگر کاربر قبلاً زبان انتخاب یا پیشنهاد را رد کرده، چیزی نشان نده
    if (localStorage.getItem(LS_LOCALE) || localStorage.getItem(LS_LANG_DISMISSED)) return;

    let cancelled = false;
    (async () => {
      try {
        const { data } = await i18nApi.detect();
        const loc = data?.suggested_locale as string | undefined;
        const cur = data?.suggested_currency as string | undefined;
        if (cancelled || !loc || !LOCALES[loc]) return;
        // فقط وقتی پیشنهاد با زبانِ پیش‌فرضِ سایت (fa) فرق دارد
        if (loc === DEFAULT_LOCALE) return;
        setSuggest({ locale: loc, currency: cur || localeMeta(loc).defaultCurrency });
      } catch {
        /* بی‌صدا */
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  if (!suggest) return null;

  const meta = localeMeta(suggest.locale);
  const cur = currencyMeta(suggest.currency);

  const apply = async () => {
    applyLocale(suggest.locale, suggest.currency);
    if (isAuthenticated) {
      try {
        await i18nApi.setPreferences({ locale: suggest.locale, currency: suggest.currency });
      } catch {
        /* ذخیرهٔ محلی کافی است */
      }
    }
    toast.success(t("lang.saved", suggest.locale));
    setSuggest(null);
    setTimeout(() => window.location.reload(), 400);
  };

  const dismiss = () => {
    localStorage.setItem(LS_LANG_DISMISSED, "1");
    setSuggest(null);
  };

  return (
    <div className="fixed bottom-20 inset-x-0 z-[60] flex justify-center px-3 pointer-events-none">
      <div className="pointer-events-auto w-full max-w-md rounded-2xl border border-white/10 bg-neutral-900/95 backdrop-blur shadow-2xl p-4">
        <div className="flex items-start gap-3">
          <div className="shrink-0 h-10 w-10 rounded-xl bg-gradient-to-br from-sky-500 to-indigo-500 grid place-items-center">
            <Globe className="h-5 w-5 text-white" />
          </div>
          <div className="flex-1 min-w-0">
            <div className="text-white text-sm font-bold mb-0.5">{t("lang.suggest.title", suggest.locale)}</div>
            <div className="text-white/60 text-xs mb-2">{t("lang.suggest.body", suggest.locale)}</div>
            <div className="flex items-center gap-2 text-sm">
              <span className="text-lg">{meta.flag}</span>
              <span className="text-white font-medium">{meta.native}</span>
              <span className="text-white/30">·</span>
              <span className="text-white/70">{cur.symbol} {suggest.locale === "fa" ? cur.nameFa : cur.nameEn}</span>
            </div>
            <div className="flex items-center gap-2 mt-3">
              <button
                onClick={apply}
                className="flex-1 rounded-xl bg-gradient-to-r from-sky-500 to-indigo-500 text-white text-sm font-bold py-2 hover:opacity-90 transition"
              >
                {t("lang.suggest.apply", suggest.locale)}
              </button>
              <button
                onClick={dismiss}
                className="rounded-xl bg-white/5 text-white/70 text-sm py-2 px-3 hover:bg-white/10 transition"
              >
                {t("lang.suggest.keep", suggest.locale)}
              </button>
            </div>
          </div>
          <button onClick={dismiss} className="shrink-0 text-white/40 hover:text-white transition" aria-label="close">
            <X className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  );
}
