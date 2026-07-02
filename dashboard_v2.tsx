"use client";

import { useAuthStore } from "@/store/auth";
import AppShell from "@/components/layout/AppShell";
import {
  Truck, Shield, Wallet, Globe2, Users,
  TrendingUp, ChevronLeft, Star, MapPin,
  MessageCircle, Package, Handshake, Megaphone,
  Lock, ChevronDown, ChevronUp, Building2,
} from "lucide-react";
import { cn, formatAmount, toPersianNum } from "@/lib/utils";
import Link from "next/link";
import { useState } from "react";

// ── Role metadata ─────────────────────────────────────────────
const ROLE_META: Record<string, { label: string; color: string; emoji: string }> = {
  user:            { label: "کاربر",        color: "#6366F1", emoji: "👤" },
  driver:          { label: "راننده",       color: "#F97316", emoji: "🚛" },
  cargo_owner:     { label: "صاحب بار",     color: "#06B6D4", emoji: "📦" },
  freight_broker:  { label: "کارگزار",      color: "#A855F7", emoji: "🤝" },
  insurance_agent: { label: "نمایندگی بیمه",color: "#10B981", emoji: "🛡️" },
  creator:         { label: "سازنده",       color: "#F43F5E", emoji: "📢" },
  admin:           { label: "مدیر",         color: "#EC4899", emoji: "⚙️" },
  company:         { label: "شرکت",         color: "#F43F5E", emoji: "🏢" },
};

// ── Core services per role ────────────────────────────────────
function getCoreServices(role: string) {
  switch (role) {
    case "driver":
      return [
        { href:"/freight",  icon:Truck,          label:"بارهای موجود",   sub:"پیدا کن و قبول کن",   color:"#F97316", bg:"rgba(249,115,22,0.15)" },
        { href:"/earth",    icon:Globe2,          label:"کره زمین",        sub:"کشف مسیرها",           color:"#6366F1", bg:"rgba(99,102,241,0.15)" },
        { href:"/messages", icon:MessageCircle,   label:"پیام‌ها",         sub:"ارتباط با صاحبان بار", color:"#10B981", bg:"rgba(16,185,129,0.15)" },
        { href:"/wallet",   icon:Wallet,          label:"کیف پول",         sub:"درآمد و تسویه",        color:"#A855F7", bg:"rgba(168,85,247,0.15)" },
      ];
    case "cargo_owner":
      return [
        { href:"/freight",   icon:Package,       label:"ثبت بار",         sub:"پست و مدیریت بار",     color:"#06B6D4", bg:"rgba(6,182,212,0.15)" },
        { href:"/insurance", icon:Shield,        label:"بیمه بار",        sub:"استعلام و صدور",       color:"#10B981", bg:"rgba(16,185,129,0.15)" },
        { href:"/earth",     icon:Globe2,        label:"یافتن راننده",    sub:"کره سه‌بعدی",          color:"#6366F1", bg:"rgba(99,102,241,0.15)" },
        { href:"/wallet",    icon:Wallet,        label:"escrow",          sub:"امانت مالی",           color:"#A855F7", bg:"rgba(168,85,247,0.15)" },
      ];
    case "freight_broker":
      return [
        { href:"/freight",   icon:Handshake,     label:"واسطه بار",       sub:"مدیریت معامله",        color:"#A855F7", bg:"rgba(168,85,247,0.15)" },
        { href:"/earth",     icon:Globe2,        label:"کره زمین",        sub:"شبکه‌سازی",            color:"#6366F1", bg:"rgba(99,102,241,0.15)" },
        { href:"/insurance", icon:Shield,        label:"بیمه",            sub:"خدمات بیمه‌ای",        color:"#10B981", bg:"rgba(16,185,129,0.15)" },
        { href:"/wallet",    icon:Wallet,        label:"کمیسیون",         sub:"درآمد واسطه",          color:"#F97316", bg:"rgba(249,115,22,0.15)" },
      ];
    case "insurance_agent":
      return [
        { href:"/insurance", icon:Shield,        label:"پورتال بیمه",     sub:"صدور و مدیریت",        color:"#10B981", bg:"rgba(16,185,129,0.15)" },
        { href:"/earth",     icon:Globe2,        label:"مشتریان",         sub:"پیدا کردن مشتری",      color:"#6366F1", bg:"rgba(99,102,241,0.15)" },
        { href:"/messages",  icon:MessageCircle, label:"پیام‌ها",         sub:"ارتباط با بیمه‌گذار",  color:"#A855F7", bg:"rgba(168,85,247,0.15)" },
        { href:"/wallet",    icon:Wallet,        label:"کیف پول",         sub:"کمیسیون بیمه",         color:"#F97316", bg:"rgba(249,115,22,0.15)" },
      ];
    case "creator":
    case "company":
      return [
        { href:"/earth",     icon:Globe2,        label:"کره زمین",        sub:"شبکه‌سازی جهانی",      color:"#6366F1", bg:"rgba(99,102,241,0.15)" },
        { href:"/messages",  icon:MessageCircle, label:"پیام‌ها",         sub:"ارتباط با مخاطبان",    color:"#10B981", bg:"rgba(16,185,129,0.15)" },
        { href:"/wallet",    icon:Wallet,        label:"درآمد",           sub:"سهم از پلتفرم",        color:"#A855F7", bg:"rgba(168,85,247,0.15)" },
        { href:"/services",  icon:Building2,     label:"خدمات کسب‌وکار", sub:"پورتال سازمانی",       color:"#F43F5E", bg:"rgba(244,63,94,0.15)" },
      ];
    default: // user
      return [
        { href:"/messages",  icon:MessageCircle, label:"پیام‌ها",         sub:"مثل WhatsApp",         color:"#10B981", bg:"rgba(16,185,129,0.15)" },
        { href:"/earth",     icon:Globe2,        label:"کره زمین",        sub:"کشف افراد دنیا",       color:"#6366F1", bg:"rgba(99,102,241,0.15)" },
        { href:"/wallet",    icon:Wallet,        label:"کیف پول",         sub:"مالی و پرداخت",        color:"#A855F7", bg:"rgba(168,85,247,0.15)" },
        { href:"/profile",   icon:Users,         label:"پروفایل من",      sub:"Earth ID و تنظیمات",   color:"#F97316", bg:"rgba(249,115,22,0.15)" },
      ];
  }
}

// ── Locked services (discoverable) ───────────────────────────
const DISCOVER = [
  { icon: Truck,         label: "حمل بار",      href: "/freight",   color: "#F97316" },
  { icon: Shield,        label: "بیمه",          href: "/insurance", color: "#10B981" },
  { icon: Megaphone,     label: "بازاریابی",    href: "/services",  color: "#F43F5E" },
  { icon: Building2,     label: "کسب‌وکار",     href: "/services",  color: "#06B6D4" },
];

// ── Component ─────────────────────────────────────────────────
export default function DashboardPage() {
  const user          = useAuthStore((s) => s.user);
  const [showMore, setShowMore] = useState(false);

  const role         = user?.role ?? "user";
  const roleMeta     = ROLE_META[role] ?? ROLE_META["user"];
  const coreServices = getCoreServices(role);

  const hiddenServices = DISCOVER.filter(
    (d) => !coreServices.some((c) => c.href === d.href)
  );

  return (
    <AppShell showSearch>
      <div className="px-4 pt-4 space-y-5 pb-6">

        {/* ── سلام کاربر ── */}
        <section>
          <div className="flex items-start justify-between mb-1">
            <div>
              <p className="text-sm mb-0.5" style={{ color: "rgba(255,255,255,0.5)" }}>
                {getGreeting()}،
              </p>
              <h2 className="text-xl font-bold text-white">
                {user?.full_name || "کاربر دیلیکس"} 👋
              </h2>
              <div className="flex items-center gap-2 mt-1.5">
                <span
                  className="text-xs px-2.5 py-1 rounded-full font-semibold"
                  style={{ background: `${roleMeta.color}22`, color: roleMeta.color }}
                >
                  {roleMeta.emoji} {roleMeta.label}
                </span>
              </div>
            </div>
            <div className="text-left">
              <p className="text-[10px] mb-0.5" style={{ color: "rgba(255,255,255,0.35)" }}>
                Earth ID
              </p>
              <p className="text-primary font-mono text-sm font-bold">
                {user?.earth_id}
              </p>
            </div>
          </div>
        </section>

        {/* ── کیف پول ── */}
        <section>
          <div
            className="rounded-2xl p-4"
            style={{
              background: "linear-gradient(135deg, rgba(99,102,241,0.2) 0%, rgba(168,85,247,0.15) 100%)",
              border:     "1px solid rgba(99,102,241,0.25)",
            }}
          >
            <div className="flex items-center justify-between mb-3">
              <p className="text-sm flex items-center gap-1.5" style={{ color: "rgba(255,255,255,0.6)" }}>
                <Wallet className="w-4 h-4" />
                موجودی کیف پول
              </p>
              <Link
                href="/wallet"
                className="text-xs flex items-center gap-0.5"
                style={{ color: "#818CF8" }}
              >
                جزئیات <ChevronLeft className="w-3.5 h-3.5" />
              </Link>
            </div>
            <p className="text-3xl font-black text-white mb-1">{formatAmount(0)}</p>
            <p className="text-xs" style={{ color: "rgba(255,255,255,0.4)" }}>
              در escrow: {formatAmount(0)}
            </p>
            <div className="flex gap-2 mt-4">
              {["شارژ", "انتقال", "برداشت"].map((a) => (
                <button
                  key={a}
                  className="flex-1 py-2 rounded-xl text-sm font-medium transition-colors"
                  style={{ background: "rgba(255,255,255,0.08)", color: "rgba(255,255,255,0.75)" }}
                >
                  {a}
                </button>
              ))}
            </div>
          </div>
        </section>

        {/* ── خدمات اصلی بر اساس نقش ── */}
        <section>
          <h3 className="section-title">خدمات من</h3>
          <div className="grid grid-cols-2 gap-3">
            {coreServices.map((svc) => (
              <ServiceCard key={svc.href} {...svc} />
            ))}
          </div>
        </section>

        {/* ── کره زمین (همیشه) ── */}
        <section>
          <Link href="/earth">
            <div
              className="relative rounded-2xl overflow-hidden p-4 transition-all active:scale-[0.99]"
              style={{
                background: "linear-gradient(135deg, rgba(6,182,212,0.15) 0%, rgba(99,102,241,0.15) 100%)",
                border:     "1px solid rgba(6,182,212,0.2)",
              }}
            >
              <div className="flex items-center gap-3 mb-2">
                <div
                  className="w-10 h-10 rounded-xl flex items-center justify-center"
                  style={{ background: "rgba(6,182,212,0.2)" }}
                >
                  <Globe2 className="w-6 h-6" style={{ color: "#06B6D4" }} />
                </div>
                <div>
                  <h3 className="font-bold text-white">کره زمین</h3>
                  <p className="text-xs" style={{ color: "rgba(255,255,255,0.45)" }}>
                    اکتشاف جهانی ۳D
                  </p>
                </div>
              </div>
              <p className="text-sm" style={{ color: "rgba(255,255,255,0.6)" }}>
                کاربران و {roleMeta.label === "راننده" ? "مسیرها" : "تجار"} دنیا را روی کره سه‌بعدی پیدا کن
              </p>
              <div className="flex items-center gap-1.5 mt-3">
                <span className="badge-primary">
                  <MapPin className="w-3 h-3" />
                  ۱۲٬۴۸۰ کاربر آنلاین
                </span>
              </div>
            </div>
          </Link>
        </section>

        {/* ── کشف خدمات بیشتر ── */}
        {hiddenServices.length > 0 && (
          <section>
            <button
              onClick={() => setShowMore((v) => !v)}
              className="flex items-center gap-2 text-sm font-semibold mb-3 w-full text-right"
              style={{ color: "rgba(255,255,255,0.55)" }}
            >
              {showMore ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
              {showMore ? "بستن" : "کشف خدمات بیشتر"}
            </button>
            {showMore && (
              <div className="grid grid-cols-2 gap-3">
                {hiddenServices.map((s) => (
                  <Link key={s.href} href={s.href}>
                    <div
                      className="rounded-2xl p-4 transition-all active:scale-95"
                      style={{
                        background: "rgba(255,255,255,0.03)",
                        border:     "1px solid rgba(255,255,255,0.07)",
                      }}
                    >
                      <div className="flex items-center gap-2 mb-1">
                        <div
                          className="w-8 h-8 rounded-xl flex items-center justify-center"
                          style={{ background: `${s.color}22` }}
                        >
                          <s.icon size={16} style={{ color: s.color }} />
                        </div>
                        <Lock size={12} style={{ color: "rgba(255,255,255,0.25)" }} />
                      </div>
                      <p className="text-sm font-semibold" style={{ color: "rgba(255,255,255,0.6)" }}>
                        {s.label}
                      </p>
                      <p className="text-[10px] mt-0.5" style={{ color: "rgba(255,255,255,0.3)" }}>
                        از تنظیمات فعال کن
                      </p>
                    </div>
                  </Link>
                ))}
              </div>
            )}
          </section>
        )}

        {/* ── آمار من ── */}
        <section>
          <h3 className="section-title">آمار من</h3>
          <div className="grid grid-cols-3 gap-3">
            {[
              { label: "سفرها",  value: user?.total_trips ?? 0,              icon: Truck,  color: "#F97316",  suffix: "" },
              { label: "امتیاز", value: ((user?.avg_rating ?? 0) / 100).toFixed(1), icon: Star, color: "#FCD34D", suffix: "/۵" },
              { label: "Trust",  value: user?.trust_score ?? 0,              icon: Shield, color: "#10B981",  suffix: "/۱۰۰۰" },
            ].map((stat) => (
              <div
                key={stat.label}
                className="rounded-2xl p-3 text-center"
                style={{ background: "#1C1C1E", border: "1px solid rgba(255,255,255,0.07)" }}
              >
                <stat.icon
                  className="w-5 h-5 mx-auto mb-1"
                  style={{ color: stat.color }}
                />
                <p className="text-lg font-black text-white">
                  {toPersianNum(Number(stat.value))}
                  {stat.suffix && (
                    <span className="text-xs" style={{ color: "rgba(255,255,255,0.35)" }}>
                      {stat.suffix}
                    </span>
                  )}
                </p>
                <p className="text-[11px]" style={{ color: "rgba(255,255,255,0.4)" }}>
                  {stat.label}
                </p>
              </div>
            ))}
          </div>
        </section>

        {/* ── آخرین فعالیت‌ها ── */}
        <section>
          <div className="flex items-center justify-between mb-3">
            <h3 className="section-title mb-0">آخرین فعالیت‌ها</h3>
            <button className="text-xs" style={{ color: "#6366F1" }}>همه</button>
          </div>
          <div
            className="rounded-2xl p-6 text-center"
            style={{ background: "#1C1C1E", border: "1px solid rgba(255,255,255,0.06)" }}
          >
            <TrendingUp className="w-8 h-8 mx-auto mb-2" style={{ color: "rgba(255,255,255,0.2)" }} />
            <p className="text-sm" style={{ color: "rgba(255,255,255,0.4)" }}>
              هنوز فعالیتی ثبت نشده
            </p>
            <p className="text-xs mt-1" style={{ color: "rgba(255,255,255,0.25)" }}>
              اولین بار خود را ثبت کنید
            </p>
          </div>
        </section>

      </div>
    </AppShell>
  );
}

// ── Service card ──────────────────────────────────────────────
interface SvcProps {
  href: string;
  icon: React.ElementType;
  label: string;
  sub: string;
  color: string;
  bg: string;
}
function ServiceCard({ href, icon: Icon, label, sub, color, bg }: SvcProps) {
  return (
    <Link href={href}>
      <div
        className="rounded-2xl p-4 transition-all active:scale-95 cursor-pointer"
        style={{ background: "#1C1C1E", border: "1px solid rgba(255,255,255,0.07)" }}
      >
        <div
          className="w-10 h-10 rounded-xl flex items-center justify-center mb-2.5"
          style={{ background: bg }}
        >
          <Icon size={20} style={{ color }} />
        </div>
        <p className="text-sm font-semibold text-white">{label}</p>
        <p className="text-xs mt-0.5" style={{ color: "rgba(255,255,255,0.45)" }}>{sub}</p>
      </div>
    </Link>
  );
}

function getGreeting(): string {
  const h = new Date().getHours();
  if (h < 6)  return "شب بخیر";
  if (h < 12) return "صبح بخیر";
  if (h < 17) return "ظهر بخیر";
  if (h < 21) return "عصر بخیر";
  return "شب بخیر";
}
