import Link from "next/link";

// هابِ verticalها (سند ۷ §۲ آیتم ۴): Freight / Insurance / Telecom / Marketplace.
const services = [
  { href: "/services/freight", icon: "🚚", title: "حمل‌ونقل", desc: "اسنپِ بار: ثبت بار، تطبیق راننده، بارنامه و ردیابی" },
  { href: "/services/insurance", icon: "🛡️", title: "بیمه", desc: "استعلام، مقایسه و صدور بیمه‌نامه" },
  { href: "/services/telecom", icon: "📶", title: "ارتباطات", desc: "بسته‌های اینترنت و eSIM" },
  { href: "/services/marketplace", icon: "🛍️", title: "بازارگاه", desc: "خدمات و فریلنسری" },
];

export default function ServicesHub() {
  return (
    <main className="page">
      <h1>خدمات</h1>
      <p className="muted">ارائه‌دهندگانِ دارای مجوز، از طریق بستر Dilix</p>

      <div className="grid">
        {services.map((s) => (
          <Link key={s.href} href={s.href} className="card service-tile">
            <span className="ico-lg" aria-hidden>
              {s.icon}
            </span>
            <strong>{s.title}</strong>
            <span className="muted">{s.desc}</span>
          </Link>
        ))}
      </div>
    </main>
  );
}
