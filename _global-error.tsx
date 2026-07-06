"use client";

import { useEffect } from "react";

export default function GlobalError({
  error,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  // خطاهای بارگذاریِ چانک (بعد از انتشارِ نسخهٔ جدید، آدرسِ فایل‌های JS عوض می‌شود
  // و تبِ قدیمی فایلِ حذف‌شده را می‌خواهد). این‌ها فقط با بارگذاریِ کاملِ صفحه رفع می‌شوند،
  // نه با reset()؛ پس یک‌بار به‌صورت خودکار صفحه را تازه می‌کنیم.
  useEffect(() => {
    const msg = `${error?.name ?? ""} ${error?.message ?? ""}`.toLowerCase();
    const isLoadError =
      msg.includes("chunk") ||
      msg.includes("loading css") ||
      msg.includes("dynamically imported module") ||
      msg.includes("failed to fetch");
    if (isLoadError) {
      try {
        const KEY = "dilix_chunk_reload";
        if (!sessionStorage.getItem(KEY)) {
          sessionStorage.setItem(KEY, "1");
          window.location.reload();
        }
      } catch {
        window.location.reload();
      }
    }
  }, [error]);

  const retry = () => {
    try {
      sessionStorage.removeItem("dilix_chunk_reload");
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
