import Link from "next/link";

// هابِ verticalها (سند ۷ §۲ آیتم ۴): همهٔ زیرسرویس‌های موجود در frontend/web.
const services = [
  { href: "/services/freight", icon: "🚚", title: "حمل‌ونقل", desc: "اسنپِ بار: ثبت بار، تطبیق راننده، بارنامه و ردیابی" },
  { href: "/services/insurance", icon: "🛡️", title: "بیمه", desc: "استعلام، مقایسه و صدور بیمه‌نامه" },
  { href: "/services/telecom", icon: "📶", title: "ارتباطات", desc: "بسته‌های اینترنت و eSIM" },
  { href: "/services/marketplace", icon: "🛍️", title: "بازارگاه", desc: "خدمات و فریلنسری" },
  { href: "/services/discovery", icon: "🧭", title: "کشف", desc: "یافتنِ افراد و کسب‌وکارهای نزدیک" },
  { href: "/services/growth", icon: "🌱", title: "رشد", desc: "دعوت، پاداش و سهمِ درآمد" },
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
