"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import {
  ChevronDown, ChevronUp, MessageCircle, Bot,
  Phone, Mail, FileText, Shield, CreditCard, Package,
} from "lucide-react";
import AppShell from "@/components/layout/AppShell";
import { useTranslation } from "@/store/i18n";

interface FAQItem {
  q: string;
  a: string;
  icon: React.ReactNode;
}

const FAQ: FAQItem[] = [
  { icon: <CreditCard size={18} className="text-green-400" />,   q: "support.faq.1.q", a: "support.faq.1.a" },
  { icon: <Package size={18} className="text-primary-400" />,    q: "support.faq.2.q", a: "support.faq.2.a" },
  { icon: <Shield size={18} className="text-indigo-400" />,      q: "support.faq.3.q", a: "support.faq.3.a" },
  { icon: <Bot size={18} className="text-ai" />,                 q: "support.faq.4.q", a: "support.faq.4.a" },
  { icon: <MessageCircle size={18} className="text-cyan-400" />, q: "support.faq.5.q", a: "support.faq.5.a" },
  { icon: <CreditCard size={18} className="text-yellow-400" />,  q: "support.faq.6.q", a: "support.faq.6.a" },
];

function FAQRow({ item }: { item: FAQItem }) {
  const { t } = useTranslation();
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
          <p className="text-sm font-semibold text-white text-right">{t(item.q)}</p>
        </div>
        {open
          ? <ChevronUp size={18} className="text-surface-400 flex-shrink-0" />
          : <ChevronDown size={18} className="text-surface-400 flex-shrink-0" />
        }
      </button>
      {open && (
        <div className="px-4 pb-4 pr-16">
          <p className="text-sm text-surface-400 leading-relaxed">{t(item.a)}</p>
        </div>
      )}
    </div>
  );
}

export default function SupportPage() {
  const router = useRouter();
  const { t } = useTranslation();

  return (
    <AppShell title={t("support.title")}>
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
            <p className="text-sm font-semibold text-white">{t("support.ai")}</p>
            <p className="text-xs text-surface-500 text-center">{t("support.ai.sub")}</p>
          </button>

          <button
            onClick={() => router.push("/messages")}
            className="card p-4 flex flex-col items-center gap-2 hover:bg-surface-800/50 transition-colors"
          >
            <div className="w-12 h-12 rounded-2xl bg-cyan-500/10 flex items-center justify-center">
              <MessageCircle size={24} className="text-cyan-400" />
            </div>
            <p className="text-sm font-semibold text-white">{t("support.online")}</p>
            <p className="text-xs text-surface-500 text-center">{t("support.online.sub")}</p>
          </button>
        </div>

        {/* Contact info */}
        <div className="card p-4">
          <h3 className="text-sm font-semibold text-surface-300 mb-3">{t("support.contact")}</h3>
          <div className="space-y-3">
            <a
              href="tel:+982100000000"
              className="flex items-center gap-3 py-2 hover:opacity-80 transition-opacity"
            >
              <div className="w-9 h-9 rounded-xl bg-green-500/10 flex items-center justify-center">
                <Phone size={18} className="text-green-400" />
              </div>
              <div>
                <p className="text-sm font-medium text-white">{t("support.phone")}</p>
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
                <p className="text-sm font-medium text-white">{t("support.email")}</p>
                <p className="text-xs text-surface-500 ltr text-right">support@dilix.ir</p>
              </div>
            </a>
          </div>
        </div>

        {/* FAQ */}
        <div>
          <h3 className="text-sm font-semibold text-surface-400 mb-2 px-1">{t("support.faqTitle")}</h3>
          <div className="card">
            {FAQ.map((item, i) => (
              <FAQRow key={i} item={item} />
            ))}
          </div>
        </div>

        {/* Version */}
        <div className="text-center py-2">
          <p className="text-xs text-surface-700">{t("support.version")}</p>
        </div>
      </div>
    </AppShell>
  );
}
