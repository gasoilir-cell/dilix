import { AuthGuard } from "./AuthGuard";
import LanguageSuggestBanner from "@/components/shared/LanguageSuggestBanner";

// مسیرهای احراز هویت مختص هر کاربر هستند و نباید به‌صورت استاتیک
// prerender/کش شوند؛ در غیر این صورت HTML کش‌شده بعد از هر build به
// چانک‌های قدیمیِ حذف‌شده اشاره می‌کند و صفحه در سمت کلاینت crash می‌کند.
export const dynamic = "force-dynamic";

export default function AuthLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <AuthGuard>
      {children}
      {/* پیشنهادِ زبان/ارز پیش از ورود (جهانی‌سازی) */}
      <LanguageSuggestBanner />
    </AuthGuard>
  );
}
