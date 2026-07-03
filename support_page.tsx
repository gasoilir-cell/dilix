"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import {
  ChevronDown, ChevronUp, MessageCircle, Bot,
  Phone, Mail, FileText, Shield, CreditCard, Package,
} from "lucide-react";
import AppShell from "@/components/layout/AppShell";

interface FAQItem {
  q: string;
  a: string;
  icon: React.ReactNode;
}

const FAQ: FAQItem[] = [
  {
    icon: <CreditCard size={18} className="text-green-400" />,
    q: "چطور کیف پول خود را شارژ کنم؟",
    a: "از منوی «کیف پول» → دکمه «افزایش موجودی» را بزنید. مبلغ را وارد کنید و به درگاه پرداخت هدایت می‌شوید. بعد از پرداخت موفق، موجودی بلافاصله اضافه می‌شود.",
  },
  {
    icon: <Package size={18} className="text-primary-400" />,
    q: "چطور بار ثبت کنم؟",
    a: "از بخش «باربری» → «ثبت بار جدید» را انتخاب کنید. مبدأ، مقصد، نوع بار، وزن و قیمت پیشنهادی را وارد کنید. بار شما به رانندگان در مسیر نمایش داده می‌شود.",
  },
  {
    icon: <Shield size={18} className="text-indigo-400" />,
    q: "تأیید هویت (KYC) چیست و چرا مهم است؟",
    a: "KYC (Know Your Customer) برای امنیت حساب و افزایش سقف تراکنش‌ها الزامی است. سطح ۱: تأیید شماره موبایل. سطح ۲: بارگذاری کارت ملی. سطح ۳: تأیید کامل با selfie.",
  },
  {
    icon: <Bot size={18} className="text-ai" />,
    q: "دستیار هوشمند Dilix چه کمکی می‌کند؟",
    a: "دستیار هوشمند ما به سوالات درباره نرخ‌های حمل، بیمه بار، راهنمای استفاده از پلتفرم، و اطلاعات مسیرها پاسخ می‌دهد. از منوی «دستیار هوشمند» دسترسی دارید.",
  },
  {
    icon: <MessageCircle size={18} className="text-cyan-400" />,
    q: "آیا می‌توانم با رانندگان مستقیم در تماس باشم؟",
    a: "بله. از طریق بخش «پیام‌ها» می‌توانید با هر کاربری که Earth ID آن را دارید چت کنید. کافیست Earth ID را در کادر «گفتگوی جدید» وارد کنید.",
  },
  {
    icon: <CreditCard size={18} className="text-yellow-400" />,
    q: "انتقال وجه به کاربر دیگر چطور است؟",
    a: "از کیف پول → «انتقال وجه» → Earth ID گیرنده را وارد کنید. انتقال فوری است و بدون کارمزد. توجه: Earth ID باید دقیق باشد.",
  },
];

function FAQRow({ item }: { item: FAQItem }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="border-b border-surface-800/60 last:border-0">
      <button
        onClick={() => setOpen(!open)}
        className="w-full flex items-center justify-between p-4 text-right hover:bg-surface-800/20 transition-colors"
      >
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 rounded-lg bg-surface-800 flex items-center justify-center flex-shrink-0">
            {item.icon}
          </div>
          <p className="text-sm font-semibold text-white text-right">{item.q}</p>
        </div>
        {open
          ? <ChevronUp size={18} className="text-surface-400 flex-shrink-0" />
          : <ChevronDown size={18} className="text-surface-400 flex-shrink-0" />
        }
      </button>
      {open && (
        <div className="px-4 pb-4 pr-16">
          <p className="text-sm text-surface-400 leading-relaxed">{item.a}</p>
        </div>
      )}
    </div>
  );
}

export default function SupportPage() {
  const router = useRouter();

  return (
    <AppShell title="پشتیبانی">
      <div className="page-inner pb-safe space-y-4">

        {/* Quick actions */}
        <div className="grid grid-cols-2 gap-3">
          <button
            onClick={() => router.push("/ai")}
            className="card p-4 flex flex-col items-center gap-2 hover:bg-surface-800/50 transition-colors"
          >
            <div className="w-12 h-12 rounded-2xl bg-ai/10 flex items-center justify-center">
              <Bot size={24} className="text-ai" />
            </div>
            <p className="text-sm font-semibold text-white">دستیار هوشمند</p>
            <p className="text-xs text-surface-500 text-center">پاسخ فوری به سوالات</p>
          </button>

          <button
            onClick={() => router.push("/messages")}
            className="card p-4 flex flex-col items-center gap-2 hover:bg-surface-800/50 transition-colors"
          >
            <div className="w-12 h-12 rounded-2xl bg-cyan-500/10 flex items-center justify-center">
              <MessageCircle size={24} className="text-cyan-400" />
            </div>
            <p className="text-sm font-semibold text-white">پشتیبانی آنلاین</p>
            <p className="text-xs text-surface-500 text-center">چت با تیم Dilix</p>
          </button>
        </div>

        {/* Contact info */}
        <div className="card p-4">
          <h3 className="text-sm font-semibold text-surface-300 mb-3">تماس مستقیم</h3>
          <div className="space-y-3">
            <a
              href="tel:+982100000000"
              className="flex items-center gap-3 py-2 hover:opacity-80 transition-opacity"
            >
              <div className="w-9 h-9 rounded-xl bg-green-500/10 flex items-center justify-center">
                <Phone size={18} className="text-green-400" />
              </div>
              <div>
                <p className="text-sm font-medium text-white">خط پشتیبانی</p>
                <p className="text-xs text-surface-500 ltr text-right">۰۲۱-۰۰۰۰۰۰۰۰</p>
              </div>
            </a>
            <a
              href="mailto:support@dilix.ir"
              className="flex items-center gap-3 py-2 hover:opacity-80 transition-opacity"
            >
              <div className="w-9 h-9 rounded-xl bg-blue-500/10 flex items-center justify-center">
                <Mail size={18} className="text-blue-400" />
              </div>
              <div>
                <p className="text-sm font-medium text-white">ایمیل</p>
                <p className="text-xs text-surface-500 ltr text-right">support@dilix.ir</p>
              </div>
            </a>
          </div>
        </div>

        {/* FAQ */}
        <div>
          <h3 className="text-sm font-semibold text-surface-400 mb-2 px-1">سوالات متداول</h3>
          <div className="card">
            {FAQ.map((item, i) => (
              <FAQRow key={i} item={item} />
            ))}
          </div>
        </div>

        {/* Version */}
        <div className="text-center py-2">
          <p className="text-xs text-surface-700">Dilix v1.0.0 · ساخته‌شده با ❤️ در ایران</p>
        </div>
      </div>
    </AppShell>
  );
}
