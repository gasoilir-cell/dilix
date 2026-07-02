"use client";

import { useState, useEffect, useCallback } from "react";
import {
  Shield, ChevronDown, Loader2, CheckCircle2,
  ArrowRight, FileText, AlertCircle, RefreshCw,
} from "lucide-react";
import AppShell from "@/components/layout/AppShell";
import { Button } from "@/components/ui/Button";
import { toPersianNum } from "@/lib/utils";
import api from "@/lib/api";
import toast from "react-hot-toast";

// ── Constants ─────────────────────────────────────────────────
const CARGO_TYPES = [
  { id: "electronics",   label: "الکترونیک",           emoji: "📱", rate: "۰.۸٪" },
  { id: "perishables",   label: "مواد فاسدشدنی",        emoji: "🥩", rate: "۰.۶٪" },
  { id: "machinery",     label: "ماشین‌آلات",           emoji: "⚙️", rate: "۰.۵٪" },
  { id: "textiles",      label: "منسوجات و پارچه",      emoji: "🧵", rate: "۰.۴٪" },
  { id: "raw_materials", label: "مواد اولیه",           emoji: "📦", rate: "۰.۳٪" },
  { id: "chemicals",     label: "مواد شیمیایی",         emoji: "⚗️", rate: "۰.۹٪" },
  { id: "artwork",       label: "آثار هنری",            emoji: "🎨", rate: "۱.۰٪" },
  { id: "vehicles",      label: "خودرو",                emoji: "🚗", rate: "۰.۶٪" },
  { id: "general",       label: "عمومی",                emoji: "📫", rate: "۰.۴٪" },
];

const COVERAGE_TYPES = [
  {
    id: "basic",
    label: "پوشش پایه",
    desc: "خسارت فیزیکی در حمل‌ونقل",
    color: "border-blue-500/40 bg-blue-500/5",
    badgeColor: "bg-blue-500/10 text-blue-300",
  },
  {
    id: "comprehensive",
    label: "پوشش جامع",
    desc: "خسارت فیزیکی + سرقت",
    color: "border-indigo-500/40 bg-indigo-500/5",
    badgeColor: "bg-indigo-500/10 text-indigo-300",
    popular: true,
  },
  {
    id: "all_risk",
    label: "همه‌خطر",
    desc: "کامل‌ترین پوشش (All Risk)",
    color: "border-purple-500/40 bg-purple-500/5",
    badgeColor: "bg-purple-500/10 text-purple-300",
  },
];

const STATUS_MAP: Record<string, { label: string; color: string; icon: React.ElementType }> = {
  pending:   { label: "در انتظار بررسی", color: "text-yellow-400", icon: Loader2         },
  reviewed:  { label: "در حال بررسی",    color: "text-blue-400",   icon: RefreshCw        },
  approved:  { label: "تأیید شده",       color: "text-emerald-400",icon: CheckCircle2     },
  rejected:  { label: "رد شده",          color: "text-red-400",    icon: AlertCircle      },
};

interface InsuranceReq {
  id: string; ref: string;
  cargo_type: string; cargo_value: number;
  origin: string; destination: string;
  coverage_type: string; premium: number;
  notes: string | null; status: string;
  created_at: string;
}

interface QuoteResult {
  cargo_type_label: string;
  coverage_label: string;
  base_rate_pct: number;
  cargo_value: number;
  premium: number;
}

type Tab = "quote" | "requests";

function formatDate(iso: string) {
  try {
    return new Date(iso).toLocaleDateString("fa-IR", { year: "numeric", month: "short", day: "numeric" });
  } catch { return iso; }
}

export default function InsurancePage() {
  const [tab, setTab] = useState<Tab>("quote");

  // ── Quote form ──────────────────────────────────────────────
  const [cargoType,    setCargoType]    = useState("");
  const [cargoValue,   setCargoValue]   = useState("");
  const [coverageType, setCoverageType] = useState("comprehensive");
  const [origin,       setOrigin]       = useState("");
  const [destination,  setDestination]  = useState("");
  const [notes,        setNotes]        = useState("");
  const [quoting,      setQuoting]      = useState(false);
  const [submitting,   setSubmitting]   = useState(false);
  const [quote,        setQuote]        = useState<QuoteResult | null>(null);

  // ── My requests ─────────────────────────────────────────────
  const [requests, setRequests] = useState<InsuranceReq[]>([]);
  const [loadingReqs, setLoadingReqs] = useState(false);

  const loadRequests = useCallback(async () => {
    setLoadingReqs(true);
    try {
      const res = await api.get("/insurance/requests");
      setRequests(res.data);
    } catch { /* ignored */ } finally {
      setLoadingReqs(false);
    }
  }, []);

  useEffect(() => {
    if (tab === "requests") loadRequests();
  }, [tab, loadRequests]);

  const handleQuote = async () => {
    if (!cargoType || !cargoValue || !origin || !destination) {
      toast.error("لطفاً همه فیلدهای اجباری را پر کنید");
      return;
    }
    setQuoting(true);
    setQuote(null);
    try {
      const res = await api.post("/insurance/quote", {
        cargo_type:    cargoType,
        cargo_value:   Number(cargoValue),
        coverage_type: coverageType,
        origin,
        destination,
      });
      setQuote(res.data);
    } catch (e: any) {
      toast.error(e?.response?.data?.detail || "خطا در محاسبه");
    } finally {
      setQuoting(false);
    }
  };

  const handleSubmit = async () => {
    if (!quote) { await handleQuote(); return; }
    setSubmitting(true);
    try {
      await api.post("/insurance/requests", {
        cargo_type:    cargoType,
        cargo_value:   Number(cargoValue),
        coverage_type: coverageType,
        origin,
        destination,
        notes:         notes || undefined,
      });
      toast.success("درخواست بیمه ثبت شد ✅");
      setTab("requests");
      setQuote(null);
      setCargoType(""); setCargoValue(""); setOrigin(""); setDestination(""); setNotes("");
    } catch (e: any) {
      toast.error(e?.response?.data?.detail || "خطا در ثبت");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <AppShell title="بیمه بار">
      <div className="page-inner">

        {/* Tabs */}
        <div className="flex gap-1 bg-[#1C1C1E] rounded-xl p-1 mb-5">
          {[
            { id: "quote"    as Tab, label: "محاسبه حق بیمه" },
            { id: "requests" as Tab, label: "درخواست‌های من"  },
          ].map((t) => (
            <button
              key={t.id}
              onClick={() => setTab(t.id)}
              className={`flex-1 py-2.5 rounded-lg text-sm font-medium transition-all ${
                tab === t.id
                  ? "bg-emerald-600 text-white"
                  : "text-white/40 hover:text-white/70"
              }`}
            >
              {t.label}
            </button>
          ))}
        </div>

        {/* ── Quote Tab ──────────────────────────────────────── */}
        {tab === "quote" && (
          <div className="space-y-4">

            {/* Cargo type grid */}
            <div>
              <label className="text-xs text-white/40 mb-2 block">نوع کالا *</label>
              <div className="grid grid-cols-3 gap-2">
                {CARGO_TYPES.map((c) => (
                  <button
                    key={c.id}
                    onClick={() => setCargoType(c.id)}
                    className={`flex flex-col items-center gap-1 p-3 rounded-xl border transition-all ${
                      cargoType === c.id
                        ? "border-emerald-500/60 bg-emerald-500/10"
                        : "border-white/8 bg-[#1C1C1E] hover:border-white/20"
                    }`}
                  >
                    <span className="text-xl">{c.emoji}</span>
                    <span className="text-[11px] text-white/70 text-center leading-tight">{c.label}</span>
                    <span className="text-[10px] text-white/30">{c.rate}</span>
                  </button>
                ))}
              </div>
            </div>

            {/* Cargo value */}
            <div>
              <label className="text-xs text-white/40 mb-1.5 block">ارزش کالا (تومان) *</label>
              <input
                value={cargoValue}
                onChange={(e) => { setCargoValue(e.target.value.replace(/\D/g, "")); setQuote(null); }}
                placeholder="مثال: ۵۰۰۰۰۰۰۰۰"
                inputMode="numeric"
                className="w-full bg-[#1C1C1E] border border-white/8 rounded-xl p-4 text-white text-lg text-center placeholder-white/20 focus:outline-none focus:border-emerald-500/40"
              />
              {cargoValue && (
                <p className="text-xs text-white/30 text-center mt-1">
                  {toPersianNum(Number(cargoValue).toLocaleString())} تومان
                </p>
              )}
            </div>

            {/* Route */}
            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="text-xs text-white/40 mb-1.5 block">مبدأ *</label>
                <input
                  value={origin}
                  onChange={(e) => { setOrigin(e.target.value); setQuote(null); }}
                  placeholder="تهران"
                  className="w-full bg-[#1C1C1E] border border-white/8 rounded-xl p-3 text-sm text-white placeholder-white/20 focus:outline-none focus:border-emerald-500/40"
                />
              </div>
              <div>
                <label className="text-xs text-white/40 mb-1.5 block">مقصد *</label>
                <input
                  value={destination}
                  onChange={(e) => { setDestination(e.target.value); setQuote(null); }}
                  placeholder="مشهد"
                  className="w-full bg-[#1C1C1E] border border-white/8 rounded-xl p-3 text-sm text-white placeholder-white/20 focus:outline-none focus:border-emerald-500/40"
                />
              </div>
            </div>

            {/* Coverage type */}
            <div>
              <label className="text-xs text-white/40 mb-2 block">نوع پوشش *</label>
              <div className="space-y-2">
                {COVERAGE_TYPES.map((c) => (
                  <button
                    key={c.id}
                    onClick={() => { setCoverageType(c.id); setQuote(null); }}
                    className={`w-full flex items-center justify-between p-3.5 rounded-xl border transition-all ${
                      coverageType === c.id ? c.color : "border-white/8 bg-[#1C1C1E]"
                    }`}
                  >
                    <div className="flex items-center gap-3">
                      <div className={`w-5 h-5 rounded-full border-2 flex items-center justify-center flex-shrink-0 ${
                        coverageType === c.id ? "border-emerald-400" : "border-white/20"
                      }`}>
                        {coverageType === c.id && <div className="w-2.5 h-2.5 rounded-full bg-emerald-400" />}
                      </div>
                      <div className="text-right">
                        <div className="flex items-center gap-2">
                          <p className="text-sm font-medium text-white">{c.label}</p>
                          {c.popular && (
                            <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-emerald-500/15 text-emerald-400">پیشنهادی</span>
                          )}
                        </div>
                        <p className="text-xs text-white/40">{c.desc}</p>
                      </div>
                    </div>
                  </button>
                ))}
              </div>
            </div>

            {/* Notes */}
            <div>
              <label className="text-xs text-white/40 mb-1.5 block">توضیحات (اختیاری)</label>
              <textarea
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                placeholder="اطلاعات بیشتر درباره محموله..."
                rows={2}
                className="w-full bg-[#1C1C1E] border border-white/8 rounded-xl p-3 text-sm text-white placeholder-white/20 focus:outline-none focus:border-emerald-500/40 resize-none"
              />
            </div>

            {/* Quote result */}
            {quote && (
              <div className="bg-emerald-500/8 border border-emerald-500/25 rounded-2xl p-4">
                <div className="flex items-center gap-2 mb-3">
                  <Shield size={18} className="text-emerald-400" />
                  <p className="text-emerald-300 font-semibold text-sm">نتیجه محاسبه حق بیمه</p>
                </div>
                <div className="space-y-2 text-sm">
                  <div className="flex justify-between">
                    <span className="text-white/40">نوع کالا</span>
                    <span className="text-white">{quote.cargo_type_label}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-white/40">پوشش</span>
                    <span className="text-white">{quote.coverage_label}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-white/40">ارزش کالا</span>
                    <span className="text-white">{toPersianNum(quote.cargo_value.toLocaleString())} ت</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-white/40">نرخ پایه</span>
                    <span className="text-white">{toPersianNum(quote.base_rate_pct.toFixed(3))}٪</span>
                  </div>
                  <div className="h-px bg-white/8 my-1" />
                  <div className="flex justify-between items-center">
                    <span className="text-white font-semibold">حق بیمه</span>
                    <span className="text-emerald-400 text-xl font-bold">
                      {toPersianNum(quote.premium.toLocaleString())} ت
                    </span>
                  </div>
                </div>
              </div>
            )}

            {/* Buttons */}
            <div className="flex gap-3">
              <Button
                variant="outline"
                size="lg"
                fullWidth
                disabled={quoting}
                onClick={handleQuote}
              >
                {quoting
                  ? <><Loader2 size={16} className="animate-spin ml-2" />محاسبه...</>
                  : "محاسبه حق بیمه"
                }
              </Button>
              {quote && (
                <Button
                  variant="primary"
                  size="lg"
                  fullWidth
                  disabled={submitting}
                  onClick={handleSubmit}
                >
                  {submitting
                    ? <><Loader2 size={16} className="animate-spin ml-2" />ثبت...</>
                    : "ثبت درخواست"
                  }
                </Button>
              )}
            </div>
          </div>
        )}

        {/* ── Requests Tab ───────────────────────────────────── */}
        {tab === "requests" && (
          <div>
            {loadingReqs ? (
              <div className="flex justify-center pt-12">
                <Loader2 size={28} className="text-emerald-400 animate-spin" />
              </div>
            ) : requests.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-16 gap-3">
                <FileText size={44} className="text-white/15" />
                <p className="text-white/30 text-sm">هنوز درخواستی ثبت نکرده‌ای</p>
                <button
                  onClick={() => setTab("quote")}
                  className="text-emerald-400 text-sm underline"
                >
                  محاسبه و ثبت بیمه بار
                </button>
              </div>
            ) : (
              <div className="space-y-3">
                {requests.map((req) => {
                  const st = STATUS_MAP[req.status] ?? STATUS_MAP.pending;
                  const Icon = st.icon;
                  return (
                    <div key={req.id} className="bg-[#1C1C1E] border border-white/8 rounded-xl p-4">
                      <div className="flex items-start justify-between mb-2">
                        <div>
                          <p className="text-white font-semibold text-sm font-mono">{req.ref}</p>
                          <p className="text-white/30 text-xs">{formatDate(req.created_at)}</p>
                        </div>
                        <div className={`flex items-center gap-1.5 text-xs font-medium ${st.color}`}>
                          <Icon size={13} className={req.status === "pending" ? "" : ""} />
                          {st.label}
                        </div>
                      </div>
                      <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs mt-3">
                        <div className="flex justify-between col-span-2">
                          <span className="text-white/40">مسیر</span>
                          <span className="text-white">{req.origin} → {req.destination}</span>
                        </div>
                        <div className="flex justify-between">
                          <span className="text-white/40">ارزش</span>
                          <span className="text-white">{toPersianNum(req.cargo_value.toLocaleString())} ت</span>
                        </div>
                        <div className="flex justify-between">
                          <span className="text-white/40">حق بیمه</span>
                          <span className="text-emerald-400 font-medium">{toPersianNum(req.premium.toLocaleString())} ت</span>
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        )}
      </div>
    </AppShell>
  );
}
