import Link from "next/link";

export default function MarketplacePage() {
  return (
    <main className="page">
      <div className="row-between">
        <Link href="/services" className="link-btn">
          ← خدمات
        </Link>
        <h1 style={{ fontSize: "1.2rem" }}>بازارگاه</h1>
      </div>
      <p className="muted">خدمات و فریلنسری با کارمزدِ پایین</p>

      <div className="card">
        <strong>خدمات نزدیک شما</strong>
        <p className="muted">ارائه‌دهندگانِ خدمات از طریق Service Marketplace به کاربران وصل می‌شوند.</p>
      </div>
      <div className="card">
        <strong>Open API Marketplace</strong>
        <p className="muted">ارائه‌دهندگانِ third-party می‌توانند سرویس‌هایشان را روی بستر منتشر کنند.</p>
      </div>
    </main>
  );
}
