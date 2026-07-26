import SplashGate from "@/components/SplashGate";

// این صفحه (Server Component) نباید استاتیک prerender/کش شود؛ در غیر این صورت
// HTMLِ کش‌شده بعد از هر build به چانک‌های قدیمیِ حذف‌شده اشاره می‌کند و JSِ
// کلاینت لود نمی‌شود → اسپلش برای همیشه گیر می‌کند (به‌خصوص در PWAِ نصب‌شده).
// force-dynamic فقط در Server Component اثر دارد، پس منطقِ ریدایرکت به
// کامپوننتِ کلاینتِ SplashGate منتقل شده است.
export const dynamic = "force-dynamic";

export default function RootPage() {
  return (
    <>
      {/*
        آخرین سپرِ بدونِ جاوااسکریپت: اگر چانک‌های کلاینت اصلاً لود نشوند،
        خودِ مرورگر بعد از ۸ ثانیه به /login می‌رود تا اسپلش برای همیشه گیر نکند.
        در حالتِ عادی ریدایرکتِ ۸۰۰ms زودتر رخ می‌دهد و این متا اجرا نمی‌شود.
      */}
      <meta httpEquiv="refresh" content="8;url=/login" />
      <SplashGate />
    </>
  );
}
