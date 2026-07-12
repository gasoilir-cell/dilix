"use client";

import { useState } from "react";

interface FAQItem {
  q: string;
  a: string;
}

const FAQ: FAQItem[] = [
  {
    q: "چطور کیف پول خود را شارژ کنم؟",
    a: "از منوی «کیف پول» → دکمه «افزایش موجودی» را بزنید. مبلغ را وارد کنید و به درگاه پرداخت هدایت می‌شوید. بعد از پرداخت موفق، موجودی بلافاصله اضافه می‌شود.",
  },
  {
    q: "چطور بار ثبت کنم؟",
    a: "از بخش «باربری» → «ثبت بار جدید» را انتخاب کنید. مبدأ، مقصد، نوع بار، وزن و قیمت پیشنهادی را وارد کنید. بار شما به رانندگان در مسیر نمایش داده می‌شود.",
  },
  {
    q: "تأیید هویت (KYC) چیست و چرا مهم است؟",
    a: "KYC (Know Your Customer) برای امنیت حساب و افزایش سقف تراکنش‌ها الزامی است. سطح ۱: تأیید شماره موبایل. سطح ۲: بارگذاری کارت ملی. سطح ۳: تأیید کامل با selfie.",
  },
  {
    q: "دستیار هوشمند Dilix چه کمکی می‌کند؟",
    a: "دستیار هوشمند ما به سوالات درباره نرخ‌های حمل، بیمه بار، راهنمای استفاده از پلتفرم، و اطلاعات مسیرها پاسخ می‌دهد.",
  },
  {
    q: "آیا می‌توانم با رانندگان مستقیم در تماس باشم؟",
    a: "بله. از طریق بخش «پیام‌ها» می‌توانید با هر کاربری که Earth ID آن را دارید چت کنید. کافیست Earth ID را در کادر «گفتگوی جدید» وارد کنید.",
  },
  {
    q: "انتقال وجه به کاربر دیگر چطور است؟",
    a: "از کیف پول → «انتقال وجه» → Earth ID گیرنده را وارد کنید. انتقال فوری است و بدون کارمزد. توجه: Earth ID باید دقیق باشد.",
  },
];

function FAQRow({ item }: { item: FAQItem }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="faq-row">
      <button className="row-between faq-q" onClick={() => setOpen(!open)}>
        <strong>{item.q}</strong>
        <span aria-hidden>{open ? "▲" : "▼"}</span>
      </button>
      {open && <p className="muted">{item.a}</p>}
    </div>
  );
}

export default function SupportPage() {
  return (
    <main className="page">
      <h1>پشتیبانی</h1>

      <div className="card">
        <strong>راه‌های ارتباط</strong>
        <div className="role-switch" style={{ marginTop: 8 }}>
          <a className="role-chip" href="/messages">
            پشتیبانی آنلاین
          </a>
          <a className="role-chip" href="mailto:support@dilix.ir">
            ایمیل
          </a>
          <a className="role-chip" href="tel:+982100000000">
            تماس تلفنی
          </a>
        </div>
      </div>

      <div className="card">
        <strong>تماس مستقیم</strong>
        <ul className="plain-list">
          <li>
            خط پشتیبانی: <span className="muted">۰۲۱-۰۰۰۰۰۰۰۰</span>
          </li>
          <li>
            ایمیل: <span className="muted">support@dilix.ir</span>
          </li>
        </ul>
      </div>

      <div className="card">
        <strong>سوالات متداول</strong>
        <div style={{ marginTop: 8 }}>
          {FAQ.map((item, i) => (
            <FAQRow key={i} item={item} />
          ))}
        </div>
      </div>

      <p className="muted" style={{ textAlign: "center" }}>
        Dilix v1.0.0 · ساخته‌شده با ❤️ در ایران
      </p>
    </main>
  );
}
