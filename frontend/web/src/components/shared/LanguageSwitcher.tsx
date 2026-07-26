"use client";

/**
 * Dilix — سوییچرِ زبانِ برنامه (جهانی‌سازی)
 * یک ردیفِ منو در پروفایل که مودالِ انتخابِ زبان/ارز را باز می‌کند. کاربر هر زبانی را
 * انتخاب کند، به‌صورتِ محلی ذخیره و (در صورتِ ورود) روی سرور هم ثبت می‌شود؛ سپس reload.
 */
import { useState } from "react";
import toast from "react-hot-toast";
import { Languages, Check, X, ChevronLeft } from "lucide-react";

import { i18nApi } from "@/lib/api";
import { useAuthStore } from "@/store/auth";
import { useI18nStore } from "@/store/i18n";
import { LOCALES, localeMeta, getLocale, t } from "@/lib/i18n";
import { currencyMeta } from "@/lib/currency";

export default function LanguageSwitcher() {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);
  const setLocale = useI18nStore((s) => s.setLocale);
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);

  const current = getLocale();
  const currentMeta = localeMeta(current);

  const choose = async (code: string) => {
    if (busy) return;
    const meta = localeMeta(code);
    if (code === current) {
      setOpen(false);
      return;
    }
    setBusy(code);
    setLocale(code, meta.defaultCurrency);
    if (isAuthenticated) {
      try {
        await i18nApi.setPreferences({ locale: code, currency: meta.defaultCurrency });
      } catch {
        /* ذخیرهٔ محلی کافی است */
      }
    }
    toast.success(t("lang.saved", code));
    setTimeout(() => window.location.reload(), 400);
  };

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="w-full flex items-center justify-between p-4 hover:bg-surface-800/30 transition-colors text-right"
      >
        <div className="flex items-center gap-3">
          <Languages size={20} className="text-surface-400" />
          <div>
            <p className="text-sm font-semibold text-white">{t("lang.switch.title")}</p>
            <p className="text-xs text-surface-400">
              {currentMeta.flag} {currentMeta.native}
            </p>
          </div>
        </div>
        <ChevronLeft size={18} className="text-surface-500" />
      </button>

      {open && (
        <div
          className="fixed inset-0 z-[70] flex items-end sm:items-center justify-center bg-black/60 backdrop-blur-sm p-0 sm:p-4"
          onClick={() => setOpen(false)}
        >
          <div
            className="w-full sm:max-w-md bg-surface-900 border border-white/10 rounded-t-2xl sm:rounded-2xl max-h-[80vh] flex flex-col"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between p-4 border-b border-white/8">
              <div className="flex items-center gap-2">
                <Languages size={18} className="text-accent-400" />
                <div>
                  <p className="text-sm font-bold text-white">{t("lang.switch.title")}</p>
                  <p className="text-[11px] text-surface-400">{t("lang.switch.subtitle")}</p>
                </div>
              </div>
              <button
                onClick={() => setOpen(false)}
                className="p-2 rounded-lg bg-surface-800 text-surface-300 hover:bg-surface-700"
                aria-label="close"
              >
                <X size={16} />
              </button>
            </div>

            <div className="overflow-y-auto p-2">
              {Object.values(LOCALES).map((loc) => {
                const cur = currencyMeta(loc.defaultCurrency);
                const active = loc.code === current;
                return (
                  <button
                    key={loc.code}
                    onClick={() => choose(loc.code)}
                    disabled={!!busy}
                    className={`w-full flex items-center gap-3 p-3 rounded-xl transition-colors text-right ${
                      active ? "bg-accent-500/10 border border-accent-500/40" : "hover:bg-surface-800/50 border border-transparent"
                    } ${busy && busy !== loc.code ? "opacity-40" : ""}`}
                  >
                    <span className="text-2xl leading-none">{loc.flag}</span>
                    <div className="flex-1 min-w-0" dir={loc.dir}>
                      <p className="text-sm font-semibold text-white truncate">{loc.native}</p>
                      <p className="text-[11px] text-surface-400 truncate">
                        {loc.english} · {cur.symbol} {loc.defaultCurrency}
                      </p>
                    </div>
                    {active && <Check size={18} className="text-accent-400 flex-shrink-0" />}
                  </button>
                );
              })}
            </div>
          </div>
        </div>
      )}
    </>
  );
}
