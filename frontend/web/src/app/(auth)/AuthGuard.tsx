"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAuthStore } from "@/store/auth";

export function AuthGuard({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);
  const user = useAuthStore((s) => s.user);
  const hasHydrated = useAuthStore((s) => s.hasHydrated);

  useEffect(() => {
    // تا نشست از localStorage بازیابی نشده، تصمیمی نگیر (جلوگیری از ریدایرکتِ اشتباه).
    if (!hasHydrated) return;
    if (isAuthenticated && user) {
      // کاربر قبلاً وارد شده — به مسیر مناسب هدایت می‌شود
      if (!user.full_name) {
        router.replace("/onboarding");
      } else {
        router.replace("/dashboard");
      }
    }
  }, [hasHydrated, isAuthenticated, user, router]);

  return <>{children}</>;
}
