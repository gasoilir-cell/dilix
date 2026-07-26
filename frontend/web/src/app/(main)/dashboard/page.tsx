"use client";

import { useAuthStore } from "@/store/auth";
import AppShell from "@/components/layout/AppShell";
import {
  Truck, Shield, Wallet, Globe2, Users,
  TrendingUp, ChevronLeft, Star, MapPin,
  MessageCircle, Package, Handshake, Megaphone,
  Lock, ChevronDown, ChevronUp, Building2, RefreshCw, Loader2, Landmark,
} from "lucide-react";
import { cn, formatAmount, toPersianNum } from "@/lib/utils";
import Link from "next/link";
import { useState, useEffect, useCallback } from "react";
import { useRouter } from "next/navigation";
import { walletApi, freightApi } from "@/lib/api";
import { useTranslation } from "@/store/i18n";

// ── Role metadata ─────────────────────────────────────────────
const ROLE_META: Record<string, { label: string; color: string; emoji: string }> = {
  user:            { label: "role.user",            color: "#6366F1", emoji: "👤" },
  driver:          { label: "role.driver",          color: "#F97316", emoji: "🚛" },
  cargo_owner:     { label: "role.cargo_owner",     color: "#06B6D4", emoji: "📦" },
  freight_broker:  { label: "role.freight_broker",  color: "#A855F7", emoji: "🤝" },
  insurance_agent: { label: "role.insurance_agent", color: "#10B981", emoji: "🛡️" },
  banker:          { label: "role.banker",          color: "#EAB308", emoji: "🏦" },
  creator:         { label: "role.creator",         color: "#F43F5E", emoji: "📢" },
  admin:           { label: "role.admin",           color: "#EC4899", emoji: "⚙️" },
  company:         { label: "role.company",         color: "#F43F5E", emoji: "🏢" },
};

// ── Core services per role ────────────────────────────────────
function getCoreServices(role: string) {
  switch (role) {
    case "driver":
      return [
        { href:"/freight",  icon:Truck,          label:"dash.g.availLoads", sub:"dash.gs.availLoads",  color:"#F97316", bg:"rgba(249,115,22,0.15)" },
        { href:"/earth",    icon:Globe2,          label:"dash.g.earth",      sub:"dash.gs.earthRoutes", color:"#6366F1", bg:"rgba(99,102,241,0.15)" },
        { href:"/messages", icon:MessageCircle,   label:"dash.g.messages",   sub:"dash.gs.msgOwners",   color:"#10B981", bg:"rgba(16,185,129,0.15)" },
        { href:"/wallet",   icon:Wallet,          label:"dash.g.wallet",     sub:"dash.gs.walletIncome",color:"#A855F7", bg:"rgba(168,85,247,0.15)" },
      ];
    case "cargo_owner":
      return [
        { href:"/freight",   icon:Package,       label:"dash.g.postLoad",       sub:"dash.gs.postLoad",       color:"#06B6D4", bg:"rgba(6,182,212,0.15)" },
        { href:"/insurance", icon:Shield,        label:"dash.g.cargoInsurance", sub:"dash.gs.cargoInsurance", color:"#10B981", bg:"rgba(16,185,129,0.15)" },
        { href:"/earth",     icon:Globe2,        label:"dash.g.findDriver",     sub:"dash.gs.findDriver",     color:"#6366F1", bg:"rgba(99,102,241,0.15)" },
        { href:"/wallet",    icon:Wallet,        label:"dash.g.escrow",         sub:"dash.gs.escrow",         color:"#A855F7", bg:"rgba(168,85,247,0.15)" },
      ];
    case "freight_broker":
      return [
        { href:"/freight",   icon:Handshake,     label:"dash.g.brokerLoad", sub:"dash.gs.brokerLoad", color:"#A855F7", bg:"rgba(168,85,247,0.15)" },
        { href:"/earth",     icon:Globe2,        label:"dash.g.earth",      sub:"dash.gs.networking", color:"#6366F1", bg:"rgba(99,102,241,0.15)" },
        { href:"/insurance", icon:Shield,        label:"dash.g.insurance",  sub:"dash.gs.insurance",  color:"#10B981", bg:"rgba(16,185,129,0.15)" },
        { href:"/wallet",    icon:Wallet,        label:"dash.g.commission", sub:"dash.gs.commission", color:"#F97316", bg:"rgba(249,115,22,0.15)" },
      ];
    case "insurance_agent":
      return [
        { href:"/insurance", icon:Shield,        label:"dash.g.insurancePortal", sub:"dash.gs.insurancePortal", color:"#10B981", bg:"rgba(16,185,129,0.15)" },
        { href:"/earth",     icon:Globe2,        label:"dash.g.customers",       sub:"dash.gs.findCustomers",   color:"#6366F1", bg:"rgba(99,102,241,0.15)" },
        { href:"/messages",  icon:MessageCircle, label:"dash.g.messages",        sub:"dash.gs.msgInsured",      color:"#A855F7", bg:"rgba(168,85,247,0.15)" },
        { href:"/wallet",    icon:Wallet,        label:"dash.g.wallet",          sub:"dash.gs.walletInsComm",   color:"#F97316", bg:"rgba(249,115,22,0.15)" },
        { href:"/provider",  icon:Building2,     label:"dash.g.partnerPortal",   sub:"dash.gs.partnerPortal",   color:"#06B6D4", bg:"rgba(6,182,212,0.15)" },
      ];
    case "banker":
      return [
        { href:"/wallet",    icon:Landmark,      label:"dash.g.bankPortal",        sub:"dash.gs.bankPortal",        color:"#EAB308", bg:"rgba(234,179,8,0.15)" },
        { href:"/services",  icon:Building2,     label:"dash.g.financialServices", sub:"dash.gs.financialServices", color:"#06B6D4", bg:"rgba(6,182,212,0.15)" },
        { href:"/earth",     icon:Globe2,        label:"dash.g.customers",         sub:"dash.gs.financialNetwork",  color:"#6366F1", bg:"rgba(99,102,241,0.15)" },
        { href:"/messages",  icon:MessageCircle, label:"dash.g.messages",          sub:"dash.gs.msgCustomers",      color:"#10B981", bg:"rgba(16,185,129,0.15)" },
        { href:"/provider",  icon:Building2,     label:"dash.g.partnerPortal",     sub:"dash.gs.partnerPortal",     color:"#A855F7", bg:"rgba(168,85,247,0.15)" },
      ];
    case "creator":
    case "company":
      return [
        { href:"/earth",     icon:Globe2,        label:"dash.g.earth",            sub:"dash.gs.globalNetworking", color:"#6366F1", bg:"rgba(99,102,241,0.15)" },
        { href:"/messages",  icon:MessageCircle, label:"dash.g.messages",         sub:"dash.gs.msgAudience",      color:"#10B981", bg:"rgba(16,185,129,0.15)" },
        { href:"/wallet",    icon:Wallet,        label:"dash.g.income",           sub:"dash.gs.income",           color:"#A855F7", bg:"rgba(168,85,247,0.15)" },
        { href:"/services",  icon:Building2,     label:"dash.g.businessServices", sub:"dash.gs.businessServices", color:"#F43F5E", bg:"rgba(244,63,94,0.15)" },
      ];
    default: // user
      return [
        { href:"/messages",  icon:MessageCircle, label:"dash.g.messages",  sub:"dash.gs.msgWhatsapp", color:"#10B981", bg:"rgba(16,185,129,0.15)" },
        { href:"/earth",     icon:Globe2,        label:"dash.g.earth",     sub:"dash.gs.earthPeople", color:"#6366F1", bg:"rgba(99,102,241,0.15)" },
        { href:"/wallet",    icon:Wallet,        label:"dash.g.wallet",    sub:"dash.gs.walletPay",   color:"#A855F7", bg:"rgba(168,85,247,0.15)" },
        { href:"/profile",   icon:Users,         label:"dash.g.myProfile", sub:"dash.gs.myProfile",   color:"#F97316", bg:"rgba(249,115,22,0.15)" },
      ];
  }
}

// ── Locked services (discoverable) ───────────────────────────
const DISCOVER = [
  { icon: Truck,         label: "dash.d.freight",   href: "/freight",   color: "#F97316" },
  { icon: Shield,        label: "dash.d.insurance", href: "/insurance", color: "#10B981" },
  { icon: Megaphone,     label: "dash.d.marketing", href: "/services",  color: "#F43F5E" },
  { icon: Building2,     label: "dash.d.business",  href: "/services",  color: "#06B6D4" },
];

// ── Component ─────────────────────────────────────────────────
export default function DashboardPage() {
  const { t } = useTranslation();
  const router = useRouter();
  const user          = useAuthStore((s) => s.user);
  const [showMore, setShowMore] = useState(false);
  const [walletBal,  setWalletBal]  = useState<{ available: number; escrow: number } | null>(null);
  const [recentFreight, setRecentFreight] = useState<any[]>([]);
  const [loadingWallet, setLoadingWallet] = useState(true);

  const role         = user?.role ?? "user";
  const roleMeta     = ROLE_META[role] ?? ROLE_META["user"];
  const coreServices = getCoreServices(role);

  const EMPTY_CTA: Record<string, { text: string; cta: string; href: string }> = {
    insurance_agent: { text: "dash.empty.insurance_agent.text", cta: "dash.empty.insurance_agent.cta", href: "/insurance" },
    driver:          { text: "dash.empty.driver.text",          cta: "dash.empty.driver.cta",          href: "/freight" },
    freight_broker:  { text: "dash.empty.freight_broker.text",  cta: "dash.empty.freight_broker.cta",  href: "/freight" },
    banker:          { text: "dash.empty.banker.text",          cta: "dash.empty.banker.cta",          href: "/wallet" },
  };
  const emptyCta = EMPTY_CTA[role] ?? { text: "dash.empty.default.text", cta: "dash.empty.default.cta", href: "/freight" };

  const hiddenServices = DISCOVER.filter(
    (d) => !coreServices.some((c) => c.href === d.href)
  );

  const loadData = useCallback(async () => {
    setLoadingWallet(true);
    try {
      const [walletRes, freightRes] = await Promise.allSettled([
        walletApi.get(),
        freightApi.list(true),
      ]);
      if (walletRes.status === "fulfilled") {
        setWalletBal({
          available: walletRes.value.data.balance_available,
          escrow:    walletRes.value.data.balance_escrow,
        });
      }
      if (freightRes.status === "fulfilled") {
        setRecentFreight(freightRes.value.data.slice(0, 3));
      }
    } catch { /* ignore */ } finally {
      setLoadingWallet(false);
    }
  }, []);

  useEffect(() => { loadData(); }, [loadData]);

  return (
    <AppShell showSearch>
      <div className="px-4 pt-4 space-y-5 pb-6">

        {/* ── سلام کاربر ── */}
        <section>
          <div className="flex items-start justify-between mb-1">
            <div>
              <p className="text-sm mb-0.5" style={{ color: "var(--t-3)" }}>
                {t(getGreeting())}،
              </p>
              <h2 className="text-xl font-bold text-white">
                {user?.full_name || t("dash.defaultName")} 👋
              </h2>
              <div className="flex items-center gap-2 mt-1.5">
                <span
                  className="text-xs px-2.5 py-1 rounded-full font-semibold"
                  style={{ background: `${roleMeta.color}22`, color: roleMeta.color }}
                >
                  {roleMeta.emoji} {t(roleMeta.label)}
                </span>
              </div>
            </div>
            <div className="text-left">
              <p className="text-[10px] mb-0.5" style={{ color: "var(--t-4)" }}>
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
              <p className="text-sm flex items-center gap-1.5" style={{ color: "var(--t-2)" }}>
                <Wallet className="w-4 h-4" />
                {t("dash.wallet.balance")}
              </p>
              <Link
                href="/wallet"
                className="text-xs flex items-center gap-0.5"
                style={{ color: "#818CF8" }}
              >
                {t("dash.wallet.details")} <ChevronLeft className="w-3.5 h-3.5" />
              </Link>
            </div>
            {loadingWallet ? (
              <Loader2 size={24} className="text-white/30 animate-spin mb-1" />
            ) : (
              <>
                <p className="text-3xl font-black text-white mb-1">
                  {walletBal ? toPersianNum((walletBal.available).toLocaleString()) + " ت" : "—"}
                </p>
                <p className="text-xs" style={{ color: "var(--t-3)" }}>
                  {t("dash.wallet.escrow")} {walletBal ? toPersianNum(walletBal.escrow.toLocaleString()) + " ت" : "۰ ت"}
                </p>
              </>
            )}
            <div className="flex gap-2 mt-4">
              {[
                { label: "dash.wallet.topup",    action: "deposit"  },
                { label: "dash.wallet.transfer", action: "transfer" },
                { label: "dash.wallet.withdraw", action: "withdraw" },
              ].map((a) => (
                <button
                  key={a.action}
                  onClick={() => router.push(`/wallet?action=${a.action}`)}
                  className="flex-1 py-2 rounded-xl text-sm font-medium transition-colors active:scale-95"
                  style={{ background: "var(--surface-hover)", color: "var(--t-2)" }}
                >
                  {t(a.label)}
                </button>
              ))}
            </div>
          </div>
        </section>

        {/* ── خدمات اصلی بر اساس نقش ── */}
        <section>
          <h3 className="section-title">{t("dash.myServices")}</h3>
          <div className="grid grid-cols-2 gap-3">
            {coreServices.map((svc) => (
              <ServiceCard key={svc.href} {...svc} label={t(svc.label)} sub={t(svc.sub)} />
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
                  <h3 className="font-bold text-white">{t("dash.earth.title")}</h3>
                  <p className="text-xs" style={{ color: "var(--t-3)" }}>
                    {t("dash.earth.sub")}
                  </p>
                </div>
              </div>
              <p className="text-sm" style={{ color: "var(--t-2)" }}>
                {t(role === "driver" ? "dash.earth.descDriver" : "dash.earth.descOther")}
              </p>
              <div className="flex items-center gap-1.5 mt-3">
                <span className="badge-primary">
                  <MapPin className="w-3 h-3" />
                  {t("dash.earth.online")}
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
              style={{ color: "var(--t-2)" }}
            >
              {showMore ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
              {showMore ? t("dash.discover.close") : t("dash.discover.more")}
            </button>
            {showMore && (
              <div className="grid grid-cols-2 gap-3">
                {hiddenServices.map((s) => (
                  <Link key={s.href} href={s.href}>
                    <div
                      className="rounded-2xl p-4 transition-all active:scale-95"
                      style={{
                        background: "var(--surface-2)",
                        border:     "1px solid var(--border-1)",
                      }}
                    >
                      <div className="flex items-center gap-2 mb-1">
                        <div
                          className="w-8 h-8 rounded-xl flex items-center justify-center"
                          style={{ background: `${s.color}22` }}
                        >
                          <s.icon size={16} style={{ color: s.color }} />
                        </div>
                        <Lock size={12} style={{ color: "var(--t-5)" }} />
                      </div>
                      <p className="text-sm font-semibold" style={{ color: "var(--t-2)" }}>
                        {t(s.label)}
                      </p>
                      <p className="text-[10px] mt-0.5" style={{ color: "var(--t-4)" }}>
                        {t("dash.discover.enableHint")}
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
          <h3 className="section-title">{t("dash.stats.title")}</h3>
          <div className="grid grid-cols-3 gap-3">
            {[
              { label: t("dash.stats.trips"),  value: user?.total_trips ?? 0,              icon: Truck,  color: "#F97316",  suffix: "" },
              { label: t("dash.stats.rating"), value: ((user?.avg_rating ?? 0) / 100).toFixed(1), icon: Star, color: "#FCD34D", suffix: "/۵" },
              { label: t("dash.stats.trust"),  value: user?.trust_score ?? 0,              icon: Shield, color: "#10B981",  suffix: "/۱۰۰۰" },
            ].map((stat) => (
              <div
                key={stat.label}
                className="rounded-2xl p-3 text-center"
                style={{ background: "var(--surface-1)", border: "1px solid var(--border-1)" }}
              >
                <stat.icon
                  className="w-5 h-5 mx-auto mb-1"
                  style={{ color: stat.color }}
                />
                <p className="text-lg font-black text-white">
                  {toPersianNum(Number(stat.value))}
                  {stat.suffix && (
                    <span className="text-xs" style={{ color: "var(--t-4)" }}>
                      {stat.suffix}
                    </span>
                  )}
                </p>
                <p className="text-[11px]" style={{ color: "var(--t-3)" }}>
                  {stat.label}
                </p>
              </div>
            ))}
          </div>
        </section>

        {/* ── آخرین فعالیت‌ها ── */}
        <section>
          <div className="flex items-center justify-between mb-3">
            <h3 className="section-title mb-0">{t("dash.activity.title")}</h3>
            <button className="text-xs" style={{ color: "#6366F1" }}>{t("dash.activity.all")}</button>
          </div>
          {recentFreight.length === 0 ? (
            <div className="rounded-2xl p-5 text-center"
              style={{ background: "var(--surface-1)", border: "1px solid var(--border-soft)" }}>
              <TrendingUp className="w-7 h-7 mx-auto mb-2" style={{ color: "var(--t-5)" }} />
              <p className="text-sm" style={{ color: "var(--t-3)" }}>{t(emptyCta.text)}</p>
              <Link href={emptyCta.href} className="text-xs mt-1.5 inline-block" style={{ color: "#6366F1" }}>
                {t(emptyCta.cta)}
              </Link>
            </div>
          ) : (
            <div className="space-y-2">
              {recentFreight.map((p: any) => (
                <Link key={p.id} href="/freight">
                  <div className="flex items-center gap-3 p-3.5 rounded-xl"
                    style={{ background: "var(--surface-1)", border: "1px solid var(--border-soft)" }}>
                    <div className="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0"
                      style={{ background: "rgba(249,115,22,0.15)" }}>
                      <Truck size={18} style={{ color: "#F97316" }} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium text-white truncate">
                        {p.origin} → {p.destination}
                      </p>
                      <p className="text-xs" style={{ color: "var(--t-4)" }}>
                        {p.ref} · {p.weight_kg} {t("dash.unit.kg")}
                      </p>
                    </div>
                    <span className={`text-xs px-2 py-0.5 rounded-full font-medium flex-shrink-0 ${
                      p.status === "open"        ? "bg-emerald-500/15 text-emerald-400" :
                      p.status === "in_progress" ? "bg-yellow-500/15 text-yellow-400"  :
                      p.status === "delivered"   ? "bg-blue-500/15 text-blue-400"      :
                                                   "bg-white/10 text-white/40"
                    }`}>
                      {p.status === "open" ? t("dash.status.open") : p.status === "in_progress" ? t("dash.status.inProgress") : p.status === "delivered" ? t("dash.status.delivered") : t("dash.status.cancelled")}
                    </span>
                  </div>
                </Link>
              ))}
            </div>
          )}
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
        style={{ background: "var(--surface-1)", border: "1px solid var(--border-1)" }}
      >
        <div
          className="w-10 h-10 rounded-xl flex items-center justify-center mb-2.5"
          style={{ background: bg }}
        >
          <Icon size={20} style={{ color }} />
        </div>
        <p className="text-sm font-semibold text-white">{label}</p>
        <p className="text-xs mt-0.5" style={{ color: "var(--t-3)" }}>{sub}</p>
      </div>
    </Link>
  );
}

function getGreeting(): string {
  const h = new Date().getHours();
  if (h < 6)  return "dash.greeting.night";
  if (h < 12) return "dash.greeting.morning";
  if (h < 17) return "dash.greeting.noon";
  if (h < 21) return "dash.greeting.evening";
  return "dash.greeting.night";
}

