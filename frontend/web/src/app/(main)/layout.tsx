"use client";

import { useEffect } from "react";
import { useRouter, usePathname } from "next/navigation";
import { useAuthStore } from "@/store/auth";
import CallManager from "@/components/call/CallManager";
import LanguageSuggestBanner from "@/components/shared/LanguageSuggestBanner";
import { getLocale, getCurrency, applyLocale } from "@/lib/i18n";

export default function MainLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);
  const hasHydrated = useAuthStore((s) => s.hasHydrated);

  useEffect(() => {
    // فقط پس از بازیابیِ نشست از localStorage تصمیمِ ریدایرکت بگیر تا رفرشِ صفحه
    // کاربر را اشتباهاً به ورود/شروعِ اولیه نفرستد.
    if (hasHydrated && !isAuthenticated) {
      // مقصد را همراه می‌بریم. لینکِ عمیق مثلِ `/pay/DLX-…?a=…` که از اسکنِ کدِ QR
      // می‌آید بدونِ این، پس از ورود روی داشبورد می‌افتاد و قصدِ پرداخت گم می‌شد.
      const target = pathname + window.location.search;
      router.replace(
        target === "/dashboard" ? "/login" : `/login?next=${encodeURIComponent(target)}`
      );
    }
  }, [hasHydrated, isAuthenticated, pathname, router]);

  // اعمالِ زبان/جهتِ ذخیره‌شدهٔ کاربر روی <html> در هر بار بارگذاری
  useEffect(() => {
    applyLocale(getLocale(), getCurrency());
  }, []);

  // تا وقتی نشست بازیابی نشده یا کاربر احراز نشده، چیزی رندر نکن.
  if (!hasHydrated || !isAuthenticated) return null;

  return (
    <>
      <CallManager />
      <LanguageSuggestBanner />
      {children}
    </>
  );
}
