"use client";

/**
 * Dilix — سوییچرِ پوستهٔ روشن/تیره
 * یک ردیفِ تنظیمات در پروفایل که بین حالتِ روز (light) و شب (dark) جابه‌جا می‌کند.
 * انتخاب توسطِ next-themes در localStorage ذخیره می‌شود (بدونِ flash؛ پیش‌فرض = تیره).
 */
import { useEffect, useState } from "react";
import { useTheme } from "next-themes";
import { Moon, Sun } from "lucide-react";

import { t } from "@/lib/i18n";
import { useI18nStore } from "@/store/i18n";

export default function ThemeToggle() {
  const { theme, resolvedTheme, setTheme } = useTheme();
  const [mounted, setMounted] = useState(false);
  // اشتراک به locale تا با تعویضِ زبان، برچسب‌ها دوباره رندر شوند
  useI18nStore((s) => s.locale);
  useEffect(() => setMounted(true), []);

  const isLight = mounted && (theme === "light" || resolvedTheme === "light");

  return (
    <div className="w-full flex items-center justify-between p-4">
      <div className="flex items-center gap-3">
        {isLight ? (
          <Sun size={20} className="text-amber-400" />
        ) : (
          <Moon size={20} className="text-surface-400" />
        )}
        <div>
          <p className="text-sm font-semibold text-white">{t("theme.title")}</p>
          <p className="text-xs text-surface-400">
            {isLight ? t("theme.light") : t("theme.dark")}
          </p>
        </div>
      </div>

      <div className="flex items-center rounded-xl bg-surface-800 p-0.5 border border-white/8">
        <button
          type="button"
          onClick={() => setTheme("light")}
          aria-pressed={isLight}
          className={`px-3 py-1.5 rounded-lg text-xs font-semibold flex items-center gap-1 transition-colors ${
            isLight ? "bg-white text-surface-900" : "text-surface-400"
          }`}
        >
          <Sun size={13} /> {t("theme.light")}
        </button>
        <button
          type="button"
          onClick={() => setTheme("dark")}
          aria-pressed={!isLight}
          className={`px-3 py-1.5 rounded-lg text-xs font-semibold flex items-center gap-1 transition-colors ${
            !isLight ? "bg-surface-700 text-white" : "text-surface-400"
          }`}
        >
          <Moon size={13} /> {t("theme.dark")}
        </button>
      </div>
    </div>
  );
}
