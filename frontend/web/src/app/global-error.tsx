"use client";

import { useEffect } from "react";

// پنجرهٔ زمانی برای جلوگیری از حلقهٔ بی‌نهایتِ reload (میلی‌ثانیه)
const RELOAD_GUARD_MS = 12_000;
const RELOAD_KEY = "dilix_chunk_reload_at";

/**
 * خطاهای بارگذاریِ چانک (بعد از انتشارِ نسخهٔ جدید، آدرسِ فایل‌های JS عوض می‌شود
 * و تبِ قدیمی فایلِ حذف‌شده را می‌خواهد). این‌ها فقط با بارگذاریِ کاملِ صفحه رفع می‌شوند،
 * نه با reset()؛ پس یک‌بار به‌صورت خودکار صفحه را تازه می‌کنیم.
 *
 * گاردِ زمان‌محور: اگر در ۱۲ ثانیهٔ اخیر reload کرده‌ایم و باز خطا رخ داد،
 * دیگر reload نمی‌کنیم (خطای واقعیِ رندر → صفحهٔ خطا نمایش داده می‌شود).
 * در غیرِ این صورت تبِ کهنه همیشه خودش را بازیابی می‌کند.
 */
function isLoadError(error?: Error & { name?: string }): boolean {
  const msg = `${error?.name ?? ""} ${error?.message ?? ""}`.toLowerCase();
  return (
    msg.includes("chunk") ||
    msg.includes("chunkloaderror") ||
    msg.includes("loading css") ||
    msg.includes("dynamically imported module") ||
    msg.includes("importing a module script failed") ||
    msg.includes("failed to fetch") ||
    msg.includes("error loading")
  );
}

export default function GlobalError({
  error,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    if (!isLoadError(error)) return;
    try {
      const last = Number(sessionStorage.getItem(RELOAD_KEY) ?? 0);
      const now = Date.now();
      if (now - last > RELOAD_GUARD_MS) {
        sessionStorage.setItem(RELOAD_KEY, String(now));
        window.location.reload();
      }
    } catch {
      window.location.reload();
    }
  }, [error]);

  const retry = () => {
    try {
      sessionStorage.removeItem(RELOAD_KEY);
    } catch {
      /* ignore */
    }
    // بارگذاریِ کامل — هم خطاهای رندر و هم خطاهای چانک را جبران می‌کند
    window.location.reload();
  };

  return (
    <html lang="fa" dir="rtl">
      <body
        style={{
          background: "#0A0A0A",
          color: "#fff",
          margin: 0,
          minHeight: "100vh",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontFamily: "Vazirmatn, Tahoma, sans-serif",
        }}
      >
        <div style={{ textAlign: "center", padding: 24, maxWidth: 360 }}>
          <div style={{ fontSize: 48, marginBottom: 12 }}>⚠️</div>
          <h2 style={{ fontSize: 18, margin: "0 0 8px" }}>مشکلی پیش آمد</h2>
          <p style={{ fontSize: 14, color: "rgba(255,255,255,0.6)", margin: "0 0 20px" }}>
            صفحه به‌درستی بارگذاری نشد. لطفاً دوباره تلاش کن.
          </p>
          <button
            onClick={retry}
            style={{
              padding: "10px 24px",
              borderRadius: 12,
              border: "none",
              background: "linear-gradient(135deg,#6366F1,#818CF8)",
              color: "#fff",
              fontSize: 15,
              fontWeight: 700,
            }}
          >
            تلاش مجدد
          </button>
        </div>
      </body>
    </html>
  );
}
