export const metadata = { title: "حریمِ خصوصی — Dilix" };

export default function PrivacyPage() {
  return (
    <main className="page">
      <h1>حریمِ خصوصی</h1>
      <p className="muted">آخرین به‌روزرسانی: ۱۴۰۵</p>

      <div className="card">
        <p>
          موقعیتِ مکانیِ شما به‌صورتِ پیش‌فرض روی نقشه نمایش داده نمی‌شود (Opt-in). در صورتِ فعال‌سازی نیز
          موقعیت به‌صورتِ <strong>محو شده (Location Fuzzing)</strong> و در سطحِ منطقه نمایش داده می‌شود؛
          مختصاتِ دقیق هرگز فاش نمی‌شود (ADR-06).
        </p>
      </div>
      <div className="card">
        <p>
          پیام‌های خصوصی با <strong>رمزنگاریِ سرتاسری (E2EE)</strong> منتقل می‌شوند و سرور به محتوای آن‌ها
          دسترسی ندارد. پردازشِ هوشِ مصنوعی فقط روی داده‌هایی انجام می‌شود که خارج از مرزِ E2EE هستند.
        </p>
      </div>
      <div className="card">
        <p>
          داده‌های کاربرانِ ایران در ریجنِ داخلی نگه‌داری می‌شوند (Data Residency) و انتقالِ بین‌مرزی فقط در
          چارچوبِ قوانینِ مربوطه انجام می‌شود.
        </p>
      </div>
    </main>
  );
}
