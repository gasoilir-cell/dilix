"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
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
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);
  const hasHydrated = useAuthStore((s) => s.hasHydrated);

  useEffect(() => {
    // فقط پس از بازیابیِ نشست از localStorage تصمیمِ ریدایرکت بگیر تا رفرشِ صفحه
    // کاربر را اشتباهاً به ورود/شروعِ اولیه نفرستد.
    if (hasHydrated && !isAuthenticated) {
      router.replace("/login");
    }
  }, [hasHydrated, isAuthenticated, router]);

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
