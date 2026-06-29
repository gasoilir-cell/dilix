import Link from "next/link";

export default function InsurancePage() {
  return (
    <main className="page">
      <div className="row-between">
        <Link href="/services" className="link-btn">
          ← خدمات
        </Link>
        <h1 style={{ fontSize: "1.2rem" }}>بیمه</h1>
      </div>
      <p className="muted">کانالِ فروش بیمه‌نامه‌ی شرکای دارای مجوز (مانند بیمه البرز)</p>

      <div className="card">
        <strong>استعلام و مقایسه</strong>
        <p className="muted">
          نرخِ بیمه از طریق Adapterهای بیمه‌گرانِ مجاز استعلام می‌شود. Dilix خود بیمه‌نامه صادر نمی‌کند؛
          صدور و خسارت نزدِ بیمه‌گر انجام می‌شود.
        </p>
      </div>
      <div className="card">
        <strong>بیمه‌ی همزمان با بار</strong>
        <p className="muted">هنگام صدورِ بارنامه می‌توانید بیمه‌ی باربری را به‌صورت اختیاری اضافه کنید.</p>
        <Link href="/services/freight" className="btn secondary">
          رفتن به حمل‌ونقل
        </Link>
      </div>
    </main>
  );
}
