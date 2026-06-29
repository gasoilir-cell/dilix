import Link from "next/link";

export default function TelecomPage() {
  return (
    <main className="page">
      <div className="row-between">
        <Link href="/services" className="link-btn">
          ← خدمات
        </Link>
        <h1 style={{ fontSize: "1.2rem" }}>ارتباطات</h1>
      </div>
      <p className="muted">بسته‌های اینترنت و eSIM از اپراتورهای طرف قرارداد</p>

      <div className="card">
        <strong>بسته‌ی اینترنت</strong>
        <p className="muted">خرید بسته از اپراتورها از طریق Telecom Adapter.</p>
      </div>
      <div className="card">
        <strong>eSIM بین‌المللی</strong>
        <p className="muted">برای سفر، eSIM فعال‌سازی فوری (در فازِ جهانی‌سازی).</p>
      </div>
    </main>
  );
}
