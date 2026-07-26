"use client";

/**
 * Dilix — دکمهٔ فشردهٔ تعویضِ پوستهٔ روز/شب برای هدرِ برنامه.
 * آیکونِ حالتِ فعلی را نشان می‌دهد و با کلیک بین light/dark جابه‌جا می‌کند.
 * انتخاب توسطِ next-themes در localStorage ذخیره می‌شود (پیش‌فرضِ برنامه = روز).
 */
import { useEffect, useState } from "react";
import { useTheme } from "next-themes";
import { Moon, Sun } from "lucide-react";

import { t } from "@/lib/i18n";
import { useI18nStore } from "@/store/i18n";
import { cn } from "@/lib/utils";

export default function ThemeToggleButton({ className }: { className?: string }) {
  const { theme, resolvedTheme, setTheme } = useTheme();
  const [mounted, setMounted] = useState(false);
  useI18nStore((s) => s.locale); // ری‌رندر با تعویضِ زبان برای aria-label
  useEffect(() => setMounted(true), []);

  const isLight = mounted && (theme === "light" || resolvedTheme === "light");

  return (
    <button
      type="button"
      onClick={() => setTheme(isLight ? "dark" : "light")}
      aria-label={isLight ? t("theme.dark") : t("theme.light")}
      title={isLight ? t("theme.dark") : t("theme.light")}
      className={cn("app-header-icon p-2 rounded-xl transition-colors", className)}
    >
      {/* پیش از mount برای جلوگیری از پرشِ hydration، آیکونِ خنثی */}
      {!mounted ? (
        <Sun className="w-5 h-5 opacity-0" />
      ) : isLight ? (
        <Sun className="w-5 h-5 text-amber-500" />
      ) : (
        <Moon className="w-5 h-5" />
      )}
    </button>
  );
}
