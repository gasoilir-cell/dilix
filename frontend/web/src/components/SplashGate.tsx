"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAuthStore } from "@/store/auth";
import { Globe2, Loader2 } from "lucide-react";

export default function SplashGate() {
  const router = useRouter();
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);

  useEffect(() => {
    const target = isAuthenticated ? "/dashboard" : "/login";

    // ریدایرکت اصلی بعد از یک مکث کوتاه برای نمایشِ اسپلش.
    const timer = setTimeout(() => {
      try {
        router.replace(target);
      } catch {
        // اگر روترِ کلاینت به هر دلیلی خطا داد، با ناوبریِ سختِ مرورگر آزاد شو.
        window.location.replace(target);
      }
    }, 800);

    // تایم‌اوتِ محافظتی: اگر تا ۸ ثانیه هنوز روی همین صفحه ماندیم
    // (خطای هیدریشن یا شکستِ ریدایرکت)، با ناوبریِ سختِ مرورگر خارج شو
    // تا اسپلش هرگز برای همیشه گیر نکند.
    const guard = setTimeout(() => {
      if (window.location.pathname === "/") {
        window.location.replace(target);
      }
    }, 8000);

    return () => {
      clearTimeout(timer);
      clearTimeout(guard);
    };
  }, [isAuthenticated, router]);

  return (
    <div className="fixed inset-0 bg-surface-900 flex items-center justify-center">
      <div className="text-center space-y-4">
        <div className="inline-flex items-center justify-center w-20 h-20 rounded-3xl bg-gradient-to-br from-primary to-ai shadow-lg shadow-primary/30 animate-pulse-glow">
          <Globe2 className="w-10 h-10 text-white" />
        </div>
        <div>
          <h1 className="text-4xl font-black text-gradient-primary">Dilix</h1>
          <p className="text-surface-500 text-sm mt-1">در حال بارگذاری...</p>
        </div>
        <Loader2 className="w-5 h-5 text-primary animate-spin mx-auto" />
      </div>
    </div>
  );
}
