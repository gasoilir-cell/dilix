"use client";

import Link from "next/link";
import {
  Truck, Shield, Globe2, Wallet, Bot, FileText,
  ChevronLeft, Zap, Lock, Package,
} from "lucide-react";
import AppShell from "@/components/layout/AppShell";
import { useAuthStore } from "@/store/auth";

type Service = {
  id: string;
  href: string;
  icon: React.ElementType;
  label: string;
  description: string;
  color: string;
  bg: string;
  border: string;
  badge?: string;
  locked?: boolean;
};

const SERVICES: Service[] = [
  {
    id: "freight",
    href: "/freight",
    icon: Truck,
    label: "باربری",
    description: "ثبت و قبول بار — سراسر کشور",
    color: "text-orange-400",
    bg: "bg-orange-500/8",
    border: "border-orange-500/20",
  },
  {
    id: "earth",
    href: "/earth",
    icon: Globe2,
    label: "کره زمین",
    description: "شبکه جهانی رانندگان و تجار",
    color: "text-indigo-400",
    bg: "bg-indigo-500/8",
    border: "border-indigo-500/20",
    badge: "زنده",
  },
  {
    id: "insurance",
    href: "/insurance",
    icon: Shield,
    label: "بیمه بار",
    description: "محاسبه و ثبت بیمه محموله",
    color: "text-emerald-400",
    bg: "bg-emerald-500/8",
    border: "border-emerald-500/20",
    badge: "جدید",
  },
  {
    id: "wallet",
    href: "/wallet",
    icon: Wallet,
    label: "کیف پول",
    description: "مدیریت مالی، escrow، انتقال",
    color: "text-purple-400",
    bg: "bg-purple-500/8",
    border: "border-purple-500/20",
  },
  {
    id: "messages",
    href: "/messages",
    icon: Package,
    label: "پیام‌ها",
    description: "ارتباط مستقیم با رانندگان و تجار",
    color: "text-blue-400",
    bg: "bg-blue-500/8",
    border: "border-blue-500/20",
  },
  {
    id: "ai",
    href: "/ai",
    icon: Bot,
    label: "دستیار AI",
    description: "مشاور هوشمند لجستیک و قیمت‌گذاری",
    color: "text-pink-400",
    bg: "bg-pink-500/8",
    border: "border-pink-500/20",
  },
  {
    id: "contracts",
    href: "#",
    icon: FileText,
    label: "قراردادها",
    description: "امضای الکترونیک و مدیریت اسناد",
    color: "text-yellow-400",
    bg: "bg-yellow-500/8",
    border: "border-yellow-500/20",
    badge: "به‌زودی",
    locked: true,
  },
  {
    id: "express",
    href: "#",
    icon: Zap,
    label: "ارسال اکسپرس",
    description: "تحویل فوری در کمتر از ۲۴ ساعت",
    color: "text-rose-400",
    bg: "bg-rose-500/8",
    border: "border-rose-500/20",
    badge: "به‌زودی",
    locked: true,
  },
];

export default function ServicesPage() {
  const user = useAuthStore((s) => s.user);
  const kycLevel = user?.kyc_level ?? 0;

  const active = SERVICES.filter((s) => !s.locked);
  const locked = SERVICES.filter((s) => s.locked);

  return (
    <AppShell title="خدمات">
      <div className="page-inner">

        {/* KYC banner */}
        {kycLevel < 2 && (
          <Link href="/profile">
            <div className="flex items-center gap-3 p-3.5 rounded-xl bg-[#1C1C1E] border border-white/8 mb-5 hover:border-indigo-500/30 transition-colors">
              <div className="w-8 h-8 rounded-xl bg-indigo-600/15 flex items-center justify-center flex-shrink-0">
                <Zap size={16} className="text-indigo-400" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-white">سطح دسترسی: KYC {kycLevel}</p>
                <p className="text-xs text-white/40">برای فعال‌سازی همه امکانات، هویت را تأیید کنید</p>
              </div>
              <ChevronLeft size={16} className="text-white/30 flex-shrink-0" />
            </div>
          </Link>
        )}

        {/* Active services */}
        <p className="text-xs text-white/30 font-medium mb-3 pr-1">خدمات فعال</p>
        <div className="space-y-2.5 mb-6">
          {active.map((svc) => (
            <Link key={svc.id} href={svc.href}>
              <div className={`flex items-center gap-4 p-4 rounded-2xl border transition-all hover:scale-[1.005] active:scale-[0.995] ${svc.bg} ${svc.border}`}>
                <div className="w-12 h-12 rounded-xl bg-[#0A0A0A]/60 flex items-center justify-center flex-shrink-0 border border-white/5">
                  <svc.icon size={24} className={svc.color} />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-0.5">
                    <p className="font-semibold text-white text-sm">{svc.label}</p>
                    {svc.badge && (
                      <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded-full ${
                        svc.badge === "زنده" ? "bg-emerald-500/15 text-emerald-400" :
                        svc.badge === "جدید" ? "bg-blue-500/15 text-blue-400" :
                        "bg-white/10 text-white/50"
                      }`}>
                        {svc.badge}
                      </span>
                    )}
                  </div>
                  <p className="text-xs text-white/45 leading-relaxed">{svc.description}</p>
                </div>
                <ChevronLeft size={16} className="text-white/25 flex-shrink-0" />
              </div>
            </Link>
          ))}
        </div>

        {/* Coming soon */}
        <p className="text-xs text-white/30 font-medium mb-3 pr-1">به‌زودی</p>
        <div className="grid grid-cols-2 gap-2.5">
          {locked.map((svc) => (
            <div key={svc.id} className={`p-4 rounded-2xl border ${svc.bg} ${svc.border} opacity-50`}>
              <div className="flex items-start justify-between mb-2.5">
                <svc.icon size={22} className={svc.color} />
                <Lock size={13} className="text-white/25" />
              </div>
              <p className="font-semibold text-white/80 text-sm">{svc.label}</p>
              <p className="text-[11px] text-white/35 mt-1 leading-relaxed">{svc.description}</p>
            </div>
          ))}
        </div>
      </div>
    </AppShell>
  );
}
