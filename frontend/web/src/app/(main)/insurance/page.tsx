"use client";

import { getApiErrorMessage } from "@/lib/api";
import { useState, useEffect, useCallback } from "react";
import {
  Shield, Loader2, CheckCircle2,
  FileText, AlertCircle, RefreshCw, Search, Zap,
  Scale, Trophy,
} from "lucide-react";
import AppShell from "@/components/layout/AppShell";
import { Button } from "@/components/ui/Button";
import { toPersianNum } from "@/lib/utils";
import { useTranslation } from "@/store/i18n";
import api from "@/lib/api";
import toast from "react-hot-toast";

// ── Dynamic field schema ──────────────────────────────────────
type FieldType = "text" | "number" | "select" | "national_id" | "date";
interface FieldDef {
  key: string;
  label: string;
  type: FieldType;
  required?: boolean;
  options?: { value: string; label: string }[];
  placeholder?: string;
}
interface ProductDef {
  id: string; label: string; emoji: string;
  needsRoute: boolean; needsCargoType: boolean;
  valueLabel: string; subjectLabel: string | null;
  subjectPlaceholder?: string;
  fields: FieldDef[];
}

const sel = (value: string, label: string) => ({ value, label });

// برچسب‌ها/گزینه‌ها/placeholderها اکنون کلیدِ i18n هستند و در رندر با t() ترجمه می‌شوند.
const PRODUCTS: ProductDef[] = [
  {
    id: "cargo", label: "ins.prod.cargo", emoji: "📦",
    needsRoute: true, needsCargoType: true,
    valueLabel: "ins.val.cargo", subjectLabel: null,
    fields: [
      { key: "transport_mode", label: "ins.f.transport_mode", type: "select", required: true, options: [
        sel("road", "ins.o.tm.road"), sel("sea", "ins.o.tm.sea"), sel("air", "ins.o.tm.air"), sel("rail", "ins.o.tm.rail") ] },
      { key: "packaging", label: "ins.f.packaging", type: "select", options: [
        sel("standard", "ins.o.pk.standard"), sel("pallet", "ins.o.pk.pallet"), sel("container", "ins.o.pk.container"), sel("bulk", "ins.o.pk.bulk") ] },
    ],
  },
  {
    id: "third_party", label: "ins.prod.third_party", emoji: "🚗",
    needsRoute: false, needsCargoType: false,
    valueLabel: "ins.val.third_party", subjectLabel: "ins.subj.third_party",
    subjectPlaceholder: "ins.subjph.third_party",
    fields: [
      { key: "plate", label: "ins.f.plate", type: "text", required: true, placeholder: "ins.ph.plate" },
      { key: "national_id", label: "ins.f.nid_owner", type: "national_id", required: true, placeholder: "ins.ph.nid10" },
      { key: "coverage_ceiling", label: "ins.f.coverage_ceiling", type: "select", required: true, options: [
        sel("base", "ins.o.cc.base"), sel("x1_5", "ins.o.cc.x1_5"), sel("x2", "ins.o.cc.x2"), sel("x3", "ins.o.cc.x3") ] },
      { key: "duration", label: "ins.f.duration", type: "select", required: true, options: [
        sel("12m", "ins.o.dur.12m"), sel("6m", "ins.o.dur.6m"), sel("3m", "ins.o.dur.3m") ] },
    ],
  },
  {
    id: "auto_body", label: "ins.prod.auto_body", emoji: "🚙",
    needsRoute: false, needsCargoType: false,
    valueLabel: "ins.val.auto_body", subjectLabel: "ins.subj.auto_body",
    subjectPlaceholder: "ins.subjph.auto_body",
    fields: [
      { key: "plate", label: "ins.f.plate", type: "text", required: true, placeholder: "ins.ph.plate" },
      { key: "national_id", label: "ins.f.nid_owner", type: "national_id", required: true, placeholder: "ins.ph.nid10" },
      { key: "model_year", label: "ins.f.model_year", type: "number", required: true, placeholder: "ins.ph.model_year" },
      { key: "add_ons", label: "ins.f.addons", type: "select", options: [
        sel("none", "ins.o.addon.none"), sel("theft", "ins.o.ao.theft"), sel("glass", "ins.o.ao.glass"),
        sel("natural", "ins.o.ao.natural"), sel("full", "ins.o.ao.full") ] },
    ],
  },
  {
    id: "life", label: "ins.prod.life", emoji: "❤️",
    needsRoute: false, needsCargoType: false,
    valueLabel: "ins.val.life", subjectLabel: "ins.subj.life",
    subjectPlaceholder: "ins.subjph.name",
    fields: [
      { key: "national_id", label: "ins.f.nid_insured", type: "national_id", required: true, placeholder: "ins.ph.nid10" },
      { key: "birth_date", label: "ins.f.birth_date", type: "date", required: true },
      { key: "duration_years", label: "ins.f.duration_years", type: "number", required: true, placeholder: "ins.ph.duration_years" },
      { key: "rider", label: "ins.f.addons", type: "select", options: [
        sel("none", "ins.o.addon.none"), sel("disability", "ins.o.rd.disability"),
        sel("critical", "ins.o.rd.critical"), sel("both", "ins.o.rd.both") ] },
      { key: "health_status", label: "ins.f.health_status", type: "select", required: true, options: [
        sel("healthy", "ins.o.hs.healthy"), sel("history", "ins.o.hs.history") ] },
    ],
  },
  {
    id: "fire", label: "ins.prod.fire", emoji: "🔥",
    needsRoute: false, needsCargoType: false,
    valueLabel: "ins.val.fire", subjectLabel: "ins.subj.fire",
    subjectPlaceholder: "ins.subjph.fire",
    fields: [
      { key: "property_type", label: "ins.f.property_type", type: "select", required: true, options: [
        sel("residential", "ins.o.pt.residential"), sel("commercial", "ins.o.pt.commercial"),
        sel("industrial", "ins.o.pt.industrial"), sel("warehouse", "ins.o.pt.warehouse") ] },
      { key: "contents_value", label: "ins.f.contents_value", type: "number", placeholder: "ins.ph.optional" },
      { key: "perils", label: "ins.f.perils", type: "select", options: [
        sel("none", "ins.o.pr.none"), sel("quake", "ins.o.pr.quake"), sel("flood", "ins.o.pr.flood"),
        sel("theft", "ins.o.pr.theft"), sel("all", "ins.o.pr.all") ] },
    ],
  },
  {
    id: "liability", label: "ins.prod.liability", emoji: "⚖️",
    needsRoute: false, needsCargoType: false,
    valueLabel: "ins.val.liability", subjectLabel: "ins.subj.liability",
    subjectPlaceholder: "ins.subjph.liability",
    fields: [
      { key: "liability_type", label: "ins.f.liability_type", type: "select", required: true, options: [
        sel("employer", "ins.o.lt.employer"), sel("professional", "ins.o.lt.professional"),
        sel("product", "ins.o.lt.product"), sel("public", "ins.o.lt.public") ] },
      { key: "headcount", label: "ins.f.headcount", type: "number", required: true, placeholder: "ins.ph.headcount" },
    ],
  },
  {
    id: "health", label: "ins.prod.health", emoji: "🩺",
    needsRoute: false, needsCargoType: false,
    valueLabel: "ins.val.health", subjectLabel: "ins.subj.health",
    subjectPlaceholder: "ins.subjph.name",
    fields: [
      { key: "national_id", label: "ins.f.nid_head", type: "national_id", required: true, placeholder: "ins.ph.nid10" },
      { key: "members_count", label: "ins.f.members_count", type: "number", required: true, placeholder: "ins.ph.members_count" },
      { key: "plan_level", label: "ins.f.plan_level", type: "select", required: true, options: [
        sel("plan1", "ins.o.pl.plan1"), sel("plan2", "ins.o.pl.plan2"), sel("plan3", "ins.o.pl.plan3") ] },
    ],
  },
  {
    id: "travel", label: "ins.prod.travel", emoji: "✈️",
    needsRoute: false, needsCargoType: false,
    valueLabel: "ins.val.travel", subjectLabel: "ins.subj.travel",
    subjectPlaceholder: "ins.subjph.name",
    fields: [
      { key: "passport", label: "ins.f.passport", type: "text", required: true, placeholder: "ins.ph.passport" },
      { key: "destination_zone", label: "ins.f.destination_zone", type: "select", required: true, options: [
        sel("schengen", "ins.o.dz.schengen"), sel("asia", "ins.o.dz.asia"),
        sel("americas", "ins.o.dz.americas"), sel("world", "ins.o.dz.world") ] },
      { key: "age", label: "ins.f.age", type: "number", required: true, placeholder: "ins.ph.age" },
      { key: "duration_days", label: "ins.f.duration_days", type: "number", required: true, placeholder: "ins.ph.duration_days" },
    ],
  },
  {
    id: "engineering", label: "ins.prod.engineering", emoji: "🏗️",
    needsRoute: false, needsCargoType: false,
    valueLabel: "ins.val.engineering", subjectLabel: "ins.subj.engineering",
    subjectPlaceholder: "ins.subjph.engineering",
    fields: [
      { key: "project_type", label: "ins.f.project_type", type: "select", required: true, options: [
        sel("construction", "ins.o.pj.construction"), sel("erection", "ins.o.pj.erection"),
        sel("equipment", "ins.o.pj.equipment") ] },
      { key: "duration_months", label: "ins.f.duration_months", type: "number", required: true, placeholder: "ins.ph.duration_months" },
      { key: "address", label: "ins.f.address", type: "text", placeholder: "ins.ph.address" },
    ],
  },
];

// ── Constants ─────────────────────────────────────────────────
const CARGO_TYPES = [
  { id: "electronics",   label: "ins.cargo.electronics",   emoji: "📱", rate: "۰.۸٪" },
  { id: "perishables",   label: "ins.cargo.perishables",   emoji: "🥩", rate: "۰.۶٪" },
  { id: "machinery",     label: "ins.cargo.machinery",     emoji: "⚙️", rate: "۰.۵٪" },
  { id: "textiles",      label: "ins.cargo.textiles",      emoji: "🧵", rate: "۰.۴٪" },
  { id: "raw_materials", label: "ins.cargo.raw_materials", emoji: "📦", rate: "۰.۳٪" },
  { id: "chemicals",     label: "ins.cargo.chemicals",     emoji: "⚗️", rate: "۰.۹٪" },
  { id: "artwork",       label: "ins.cargo.artwork",       emoji: "🎨", rate: "۱.۰٪" },
  { id: "vehicles",      label: "ins.cargo.vehicles",      emoji: "🚗", rate: "۰.۶٪" },
  { id: "general",       label: "ins.cargo.general",       emoji: "📫", rate: "۰.۴٪" },
];

const COVERAGE_TYPES = [
  { id: "basic",         label: "ins.cov.basic.l",         desc: "ins.cov.basic.d",         color: "border-blue-500/40 bg-blue-500/5" },
  { id: "comprehensive", label: "ins.cov.comprehensive.l", desc: "ins.cov.comprehensive.d", color: "border-indigo-500/40 bg-indigo-500/5", popular: true },
  { id: "all_risk",      label: "ins.cov.all_risk.l",      desc: "ins.cov.all_risk.d",      color: "border-purple-500/40 bg-purple-500/5" },
];

const STATUS_MAP: Record<string, { label: string; color: string; icon: React.ElementType }> = {
  pending:  { label: "ins.status.pending",  color: "text-yellow-400",  icon: Loader2      },
  reviewed: { label: "ins.status.reviewed", color: "text-blue-400",    icon: RefreshCw    },
  approved: { label: "ins.status.approved", color: "text-emerald-400", icon: CheckCircle2 },
  rejected: { label: "ins.status.rejected", color: "text-red-400",     icon: AlertCircle  },
};

interface InsuranceReq {
  id: string; ref: string;
  product: string; product_label: string;
  subject: string | null;
  cargo_type: string | null; cargo_value: number;
  origin: string | null; destination: string | null;
  coverage_type: string; premium: number;
  form_data: Record<string, string> | null;
  notes: string | null; status: string;
  source?: string; provider_name?: string | null; provider_ref?: string | null;
  created_at: string;
}

interface QuoteResult {
  product_label: string;
  cargo_type_label: string | null;
  coverage_label: string;
  base_rate_pct: number;
  cargo_value: number;
  premium: number;
  source?: string;
  provider_name?: string | null;
}

interface QuoteOption {
  source: string;                       // provider | internal
  provider_id?: string | null;
  provider_name?: string | null;
  premium: number;
  currency?: string;                    // ارزِ تسویهٔ مرکز (بین‌المللی)
  premium_usd?: number | null;          // حق‌بیمهٔ نرمال‌شده به سنتِ دلار (مقایسهٔ بین‌ارزی)
  commission_rate?: number | null;
  best?: boolean;
}

interface CompareResult {
  product_label: string;
  cargo_value: number;
  coverage_label: string;
  options: QuoteOption[];
  provider_count: number;
}

// محصولاتی که استعلامِ خودکار (سنهاب/شاهکار) دارند
const INQUIRY_PRODUCTS = ["third_party", "auto_body", "life", "health"];

type Tab = "quote" | "requests";

function formatDate(iso: string) {
  try {
    return new Date(iso).toLocaleDateString("fa-IR", { year: "numeric", month: "short", day: "numeric" });
  } catch { return iso; }
}

// نمایش مقدارِ ذخیره‌شده با برچسبِ i18n (برای تب «بیمه‌نامه‌های من»).
// label و (برای selectها) text کلیدِ i18n هستند؛ textIsKey مشخص می‌کند text باید ترجمه شود یا مقدارِ خام است.
function fieldDisplay(productId: string, key: string, value: string): { label: string; text: string; textIsKey: boolean } {
  const p = PRODUCTS.find((x) => x.id === productId);
  const f = p?.fields.find((x) => x.key === key);
  if (!f) return { label: key, text: value, textIsKey: false };
  if (f.type === "select") {
    const opt = f.options?.find((o) => o.value === value);
    return { label: f.label, text: opt ? opt.label : value, textIsKey: !!opt };
  }
  return { label: f.label, text: value, textIsKey: false };
}

export default function InsurancePage() {
  const { t } = useTranslation();
  const [tab, setTab] = useState<Tab>("quote");

  // ── Quote form ──────────────────────────────────────────────
  const [product,      setProduct]      = useState("cargo");
  const [subject,      setSubject]      = useState("");
  const [cargoType,    setCargoType]    = useState("");
  const [cargoValue,   setCargoValue]   = useState("");
  const [coverageType, setCoverageType] = useState("comprehensive");
  const [origin,       setOrigin]       = useState("");
  const [destination,  setDestination]  = useState("");
  const [formData,     setFormData]     = useState<Record<string, string>>({});
  const [notes,        setNotes]        = useState("");
  const [quoting,      setQuoting]      = useState(false);
  const [submitting,   setSubmitting]   = useState(false);
  const [quote,        setQuote]        = useState<QuoteResult | null>(null);
  const [inquiring,    setInquiring]    = useState(false);
  const [comparing,    setComparing]    = useState(false);
  const [compare,      setCompare]      = useState<CompareResult | null>(null);
  const [selectedIdx,  setSelectedIdx]  = useState(0);

  // پاک‌کردنِ نتیجهٔ نرخ/مقایسه هنگام تغییرِ ورودی‌ها
  const clearResults = useCallback(() => { setQuote(null); setCompare(null); }, []);

  const pdef = PRODUCTS.find((p) => p.id === product) ?? PRODUCTS[0];
  const canInquire = INQUIRY_PRODUCTS.includes(product);

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

  function selectProduct(id: string) {
    setProduct(id);
    clearResults();
    setCargoType("");
    setSubject("");
    setFormData({});
    const next = PRODUCTS.find((p) => p.id === id);
    if (!next?.needsRoute) { setOrigin(""); setDestination(""); }
  }

  function setField(key: string, value: string) {
    setFormData((prev) => ({ ...prev, [key]: value }));
    clearResults();
  }

  function buildPayload() {
    const fd: Record<string, string> = {};
    for (const f of pdef.fields) {
      const v = (formData[f.key] ?? "").trim();
      if (v) fd[f.key] = v;
    }
    return {
      product,
      subject:       pdef.subjectLabel ? (subject || undefined) : undefined,
      cargo_type:    pdef.needsCargoType ? cargoType : undefined,
      cargo_value:   Number(cargoValue),
      coverage_type: coverageType,
      origin:        pdef.needsRoute ? origin : undefined,
      destination:   pdef.needsRoute ? destination : undefined,
      form_data:     Object.keys(fd).length ? fd : undefined,
    };
  }

  function validate(): string | null {
    if (!cargoValue) return t("ins.err.value");
    if (pdef.needsCargoType && !cargoType) return t("ins.err.cargo");
    if (pdef.needsRoute && (!origin || !destination)) return t("ins.err.route");
    for (const f of pdef.fields) {
      if (f.required && !(formData[f.key] ?? "").trim()) return `${t("ins.err.reqPre")}${t(f.label)}${t("ins.err.reqPost")}`;
      if (f.type === "national_id") {
        const v = (formData[f.key] ?? "").trim();
        if (v && v.length !== 10) return `${t("ins.err.nidPre")}${t(f.label)}${t("ins.err.nidPost")}`;
      }
    }
    return null;
  }

  const handleInquiry = async () => {
    const plate = (formData["plate"] ?? "").trim();
    const nid   = (formData["national_id"] ?? "").trim();
    if (!plate && !nid) {
      toast.error(t("ins.err.inquiryInput"));
      return;
    }
    setInquiring(true);
    try {
      const res = await api.post("/insurance/inquiry", {
        product, plate: plate || undefined, national_id: nid || undefined,
      });
      const data = res.data;
      if (!data.found) { toast(data.message || t("ins.inquiry.notFound")); return; }
      const prefill: Record<string, string> = data.prefill || {};
      // فقط فیلدهایی را پُر کن که در همین محصول تعریف شده‌اند
      setFormData((prev) => {
        const next = { ...prev };
        for (const f of pdef.fields) {
          if (prefill[f.key] != null && prefill[f.key] !== "") next[f.key] = String(prefill[f.key]);
        }
        return next;
      });
      clearResults();
      toast.success(data.message || t("ins.inquiry.applied"));
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("ins.err.inquiry")));
    } finally {
      setInquiring(false);
    }
  };

  const handleQuote = async () => {
    const err = validate();
    if (err) { toast.error(err); return; }
    setQuoting(true);
    clearResults();
    try {
      const res = await api.post("/insurance/quote", buildPayload());
      setQuote(res.data);
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("ins.err.quote")));
    } finally {
      setQuoting(false);
    }
  };

  const handleCompare = async () => {
    const err = validate();
    if (err) { toast.error(err); return; }
    setComparing(true);
    clearResults();
    try {
      const res = await api.post("/insurance/compare", buildPayload());
      setCompare(res.data);
      setSelectedIdx(0);   // ارزان‌ترین (best) پیش‌فرض
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("ins.err.compare")));
    } finally {
      setComparing(false);
    }
  };

  // گزینهٔ انتخابی از لیستِ مقایسه (اگر مقایسه فعال باشد)
  const chosen = compare?.options[selectedIdx] ?? null;
  const canIssue = !!quote || !!chosen;

  const handleSubmit = async () => {
    if (!canIssue) { await handleQuote(); return; }
    setSubmitting(true);
    try {
      const providerId =
        chosen && chosen.source === "provider" ? chosen.provider_id : undefined;
      await api.post("/insurance/requests", {
        ...buildPayload(),
        provider_id: providerId || undefined,
        notes: notes || undefined,
      });
      toast.success(t("ins.issued"));
      setTab("requests");
      clearResults();
      setSubject(""); setCargoType(""); setCargoValue(""); setOrigin(""); setDestination("");
      setFormData({}); setNotes("");
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("ins.err.submit")));
    } finally {
      setSubmitting(false);
    }
  };

  const inputCls = "w-full bg-[#1C1C1E] border border-white/8 rounded-xl p-3 text-sm text-white placeholder-white/20 focus:outline-none focus:border-emerald-500/40";

  function renderField(f: FieldDef) {
    const val = formData[f.key] ?? "";
    return (
      <div key={f.key}>
        <label className="text-xs text-white/40 mb-1.5 block">
          {t(f.label)} {f.required && <span className="text-emerald-400">*</span>}
        </label>
        {f.type === "select" ? (
          <select
            value={val}
            onChange={(e) => setField(f.key, e.target.value)}
            className={`${inputCls} appearance-none`}
          >
            <option value="" disabled>{t("ins.selectPlaceholder")}</option>
            {f.options?.map((o) => (
              <option key={o.value} value={o.value}>{t(o.label)}</option>
            ))}
          </select>
        ) : (
          <input
            value={val}
            onChange={(e) => {
              let v = e.target.value;
              if (f.type === "number" || f.type === "national_id") v = v.replace(/\D/g, "");
              if (f.type === "national_id") v = v.slice(0, 10);
              setField(f.key, v);
            }}
            type={f.type === "date" ? "date" : "text"}
            inputMode={f.type === "number" || f.type === "national_id" ? "numeric" : undefined}
            placeholder={f.placeholder ? t(f.placeholder) : ""}
            className={inputCls}
          />
        )}
      </div>
    );
  }

  return (
    <AppShell title={t("ins.title")}>
      <div className="page-inner">

        {/* Tabs */}
        <div className="flex gap-1 bg-[#1C1C1E] rounded-xl p-1 mb-5">
          {[
            { id: "quote"    as Tab, label: "ins.tab.quote" },
            { id: "requests" as Tab, label: "ins.tab.requests" },
          ].map((tb) => (
            <button
              key={tb.id}
              onClick={() => setTab(tb.id)}
              className={`flex-1 py-2.5 rounded-lg text-sm font-medium transition-all ${
                tab === tb.id ? "bg-emerald-600 text-white" : "text-white/40 hover:text-white/70"
              }`}
            >
              {t(tb.label)}
            </button>
          ))}
        </div>

        {/* ── Quote Tab ──────────────────────────────────────── */}
        {tab === "quote" && (
          <div className="space-y-4">

            {/* Product picker */}
            <div>
              <label className="text-xs text-white/40 mb-2 block">{t("ins.productType")} *</label>
              <div className="grid grid-cols-3 gap-2">
                {PRODUCTS.map((p) => (
                  <button
                    key={p.id}
                    onClick={() => selectProduct(p.id)}
                    className={`flex flex-col items-center gap-1 p-3 rounded-xl border transition-all ${
                      product === p.id
                        ? "border-emerald-500/60 bg-emerald-500/10"
                        : "border-white/8 bg-[#1C1C1E] hover:border-white/20"
                    }`}
                  >
                    <span className="text-xl">{p.emoji}</span>
                    <span className="text-[11px] text-white/70 text-center leading-tight">{t(p.label)}</span>
                  </button>
                ))}
              </div>
            </div>

            {/* Cargo type grid (فقط باربری) */}
            {pdef.needsCargoType && (
              <div>
                <label className="text-xs text-white/40 mb-2 block">{t("ins.cargoTypeLabel")} *</label>
                <div className="grid grid-cols-3 gap-2">
                  {CARGO_TYPES.map((c) => (
                    <button
                      key={c.id}
                      onClick={() => { setCargoType(c.id); clearResults(); }}
                      className={`flex flex-col items-center gap-1 p-3 rounded-xl border transition-all ${
                        cargoType === c.id
                          ? "border-emerald-500/60 bg-emerald-500/10"
                          : "border-white/8 bg-[#1C1C1E] hover:border-white/20"
                      }`}
                    >
                      <span className="text-xl">{c.emoji}</span>
                      <span className="text-[11px] text-white/70 text-center leading-tight">{t(c.label)}</span>
                      <span className="text-[10px] text-white/30">{c.rate}</span>
                    </button>
                  ))}
                </div>
              </div>
            )}

            {/* Subject */}
            {pdef.subjectLabel && (
              <div>
                <label className="text-xs text-white/40 mb-1.5 block">{t(pdef.subjectLabel)}</label>
                <input
                  value={subject}
                  onChange={(e) => { setSubject(e.target.value); clearResults(); }}
                  placeholder={pdef.subjectPlaceholder ? t(pdef.subjectPlaceholder) : ""}
                  className={inputCls}
                />
              </div>
            )}

            {/* Product-specific dynamic fields */}
            {pdef.fields.length > 0 && (
              <div className="space-y-3">
                {pdef.fields.map(renderField)}
              </div>
            )}

            {/* استعلام سوابق (سنهاب/شاهکار) — پیش‌پُرکردنِ فرم */}
            {canInquire && (
              <button
                onClick={handleInquiry}
                disabled={inquiring}
                className="w-full flex items-center justify-center gap-2 p-3 rounded-xl border border-sky-500/30 bg-sky-500/8 text-sky-300 text-sm font-medium transition-all hover:bg-sky-500/12 disabled:opacity-50"
              >
                {inquiring
                  ? <Loader2 size={15} className="animate-spin" />
                  : <Search size={15} />}
                {t("ins.inquiryBtn")}
              </button>
            )}

            {/* Insured value */}
            <div>
              <label className="text-xs text-white/40 mb-1.5 block">{t(pdef.valueLabel)} *</label>
              <input
                value={cargoValue}
                onChange={(e) => { setCargoValue(e.target.value.replace(/\D/g, "")); clearResults(); }}
                placeholder={t("ins.valuePlaceholder")}
                inputMode="numeric"
                className="w-full bg-[#1C1C1E] border border-white/8 rounded-xl p-4 text-white text-lg text-center placeholder-white/20 focus:outline-none focus:border-emerald-500/40"
              />
              {cargoValue && (
                <p className="text-xs text-white/30 text-center mt-1">
                  {toPersianNum(Number(cargoValue).toLocaleString())} {t("ins.toman")}
                </p>
              )}
            </div>

            {/* Route (باربری) */}
            {pdef.needsRoute && (
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <label className="text-xs text-white/40 mb-1.5 block">{t("ins.origin")} *</label>
                  <input
                    value={origin}
                    onChange={(e) => { setOrigin(e.target.value); clearResults(); }}
                    placeholder={t("ins.originPh")}
                    className={inputCls}
                  />
                </div>
                <div>
                  <label className="text-xs text-white/40 mb-1.5 block">{t("ins.destination")} *</label>
                  <input
                    value={destination}
                    onChange={(e) => { setDestination(e.target.value); clearResults(); }}
                    placeholder={t("ins.destPh")}
                    className={inputCls}
                  />
                </div>
              </div>
            )}

            {/* Coverage type */}
            <div>
              <label className="text-xs text-white/40 mb-2 block">{t("ins.coverageType")} *</label>
              <div className="space-y-2">
                {COVERAGE_TYPES.map((c) => (
                  <button
                    key={c.id}
                    onClick={() => { setCoverageType(c.id); clearResults(); }}
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
                          <p className="text-sm font-medium text-white">{t(c.label)}</p>
                          {c.popular && (
                            <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-emerald-500/15 text-emerald-400">{t("ins.popular")}</span>
                          )}
                        </div>
                        <p className="text-xs text-white/40">{t(c.desc)}</p>
                      </div>
                    </div>
                  </button>
                ))}
              </div>
            </div>

            {/* Notes */}
            <div>
              <label className="text-xs text-white/40 mb-1.5 block">{t("ins.notes")}</label>
              <textarea
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                placeholder={t("ins.notesPh")}
                rows={2}
                className={`${inputCls} resize-none`}
              />
            </div>

            {/* Quote result */}
            {quote && (
              <div className="bg-emerald-500/8 border border-emerald-500/25 rounded-2xl p-4">
                <div className="flex items-center gap-2 mb-3">
                  <Shield size={18} className="text-emerald-400" />
                  <p className="text-emerald-300 font-semibold text-sm">{t("ins.quoteResult")}</p>
                  {quote.source === "provider" ? (
                    <span className="mr-auto text-[10px] px-2 py-0.5 rounded-full bg-sky-500/15 text-sky-300 flex items-center gap-1">
                      <Zap size={11} /> {t("ins.liveRate")} {quote.provider_name || t("ins.provider")}
                    </span>
                  ) : (
                    <span className="mr-auto text-[10px] px-2 py-0.5 rounded-full bg-white/8 text-white/40">
                      {t("ins.baseRate")}
                    </span>
                  )}
                </div>
                <div className="space-y-2 text-sm">
                  <div className="flex justify-between">
                    <span className="text-white/40">{t("ins.rowProduct")}</span>
                    <span className="text-white">{quote.product_label}</span>
                  </div>
                  {quote.cargo_type_label && (
                    <div className="flex justify-between">
                      <span className="text-white/40">{t("ins.rowCargo")}</span>
                      <span className="text-white">{quote.cargo_type_label}</span>
                    </div>
                  )}
                  <div className="flex justify-between">
                    <span className="text-white/40">{t("ins.rowCoverage")}</span>
                    <span className="text-white">{quote.coverage_label}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-white/40">{t("ins.rowCapital")}</span>
                    <span className="text-white">{toPersianNum(quote.cargo_value.toLocaleString())} {t("ins.tomanShort")}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-white/40">{t("ins.rowBaseRate")}</span>
                    <span className="text-white">{toPersianNum(quote.base_rate_pct.toFixed(3))}٪</span>
                  </div>
                  <div className="h-px bg-white/8 my-1" />
                  <div className="flex justify-between items-center">
                    <span className="text-white font-semibold">{t("ins.premium")}</span>
                    <span className="text-emerald-400 text-xl font-bold">
                      {toPersianNum(quote.premium.toLocaleString())} {t("ins.tomanShort")}
                    </span>
                  </div>
                </div>
              </div>
            )}

            {/* Comparison result — قلبِ aggregator */}
            {compare && (
              <div className="bg-[#111214] border border-white/10 rounded-2xl p-4">
                <div className="flex items-center gap-2 mb-3">
                  <Scale size={18} className="text-sky-400" />
                  <p className="text-sky-300 font-semibold text-sm">{t("ins.compareTitle")}</p>
                  <span className="mr-auto text-[10px] px-2 py-0.5 rounded-full bg-white/8 text-white/40">
                    {compare.provider_count > 0
                      ? `${toPersianNum(compare.provider_count)} ${t("ins.liveCenters")}`
                      : t("ins.onlyBase")}
                  </span>
                </div>

                <div className="space-y-2">
                  {compare.options.map((opt, idx) => {
                    const active = idx === selectedIdx;
                    // اگر لیست ارزِ غیرِ IRR دارد، معیارِ نرمال‌شدهٔ دلاری را کنارِ هر گزینه نشان بده
                    const showUsd =
                      compare.options.some((o) => o.currency && o.currency !== "IRR") &&
                      opt.premium_usd != null;
                    return (
                      <button
                        key={idx}
                        type="button"
                        onClick={() => setSelectedIdx(idx)}
                        className={`w-full text-right rounded-xl p-3 border transition-colors flex items-center gap-3 ${
                          active
                            ? "border-emerald-500/60 bg-emerald-500/10"
                            : "border-white/8 bg-[#1C1C1E] hover:border-white/20"
                        }`}
                      >
                        <span
                          className={`w-4 h-4 rounded-full border-2 flex-shrink-0 ${
                            active ? "border-emerald-400 bg-emerald-400" : "border-white/25"
                          }`}
                        />
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-1.5">
                            <span className="text-white text-sm font-medium truncate">
                              {opt.source === "provider"
                                ? opt.provider_name || t("ins.provider")
                                : t("ins.baseRate")}
                            </span>
                            {opt.best && (
                              <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-amber-500/15 text-amber-300 flex items-center gap-0.5 flex-shrink-0">
                                <Trophy size={9} /> {t("ins.best")}
                              </span>
                            )}
                            {opt.source === "provider" && (
                              <Zap size={11} className="text-sky-400 flex-shrink-0" />
                            )}
                            {opt.currency && opt.currency !== "IRR" && (
                              <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-sky-500/15 text-sky-300 flex-shrink-0">
                                {opt.currency}
                              </span>
                            )}
                          </div>
                        </div>
                        <div className="flex flex-col items-end flex-shrink-0">
                          <span className={`text-sm font-bold ${active ? "text-emerald-300" : "text-white/80"}`}>
                            {opt.currency && opt.currency !== "IRR"
                              ? `${opt.premium.toLocaleString()} ${opt.currency}`
                              : `${toPersianNum(opt.premium.toLocaleString())} ${t("ins.tomanShort")}`}
                          </span>
                          {showUsd && (
                            <span className="text-[10px] text-white/35 mt-0.5">
                              ≈ ${(opt.premium_usd! / 100).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                            </span>
                          )}
                        </div>
                      </button>
                    );
                  })}
                </div>

                <p className="text-white/30 text-[11px] mt-3 leading-relaxed">
                  {t("ins.compareHint")}
                </p>
              </div>
            )}

            {/* Buttons */}
            <div className="flex gap-3">
              <Button variant="outline" size="lg" fullWidth disabled={quoting || comparing} onClick={handleQuote}>
                {quoting
                  ? <><Loader2 size={16} className="animate-spin ml-2" />{t("ins.calculating")}</>
                  : t("ins.calcBtn")}
              </Button>
              <Button variant="outline" size="lg" fullWidth disabled={comparing || quoting} onClick={handleCompare}>
                {comparing
                  ? <><Loader2 size={16} className="animate-spin ml-2" />{t("ins.comparingBtn")}</>
                  : <><Scale size={16} className="ml-2" />{t("ins.compareBtn")}</>}
              </Button>
            </div>
            {canIssue && (
              <Button variant="primary" size="lg" fullWidth disabled={submitting} onClick={handleSubmit}>
                {submitting
                  ? <><Loader2 size={16} className="animate-spin ml-2" />{t("ins.submitting")}</>
                  : chosen && chosen.source === "provider"
                    ? `${t("ins.issueAt")} ${chosen.provider_name || t("ins.provider")}`
                    : t("ins.issueBtn")}
              </Button>
            )}
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
                <p className="text-white/30 text-sm">{t("ins.empty")}</p>
                <button onClick={() => setTab("quote")} className="text-emerald-400 text-sm underline">
                  {t("ins.issueFirst")}
                </button>
              </div>
            ) : (
              <div className="space-y-3">
                {requests.map((req) => {
                  const st = STATUS_MAP[req.status] ?? STATUS_MAP.pending;
                  const Icon = st.icon;
                  const hasRoute = req.origin && req.destination;
                  const fdEntries = req.form_data ? Object.entries(req.form_data) : [];
                  return (
                    <div key={req.id} className="bg-[#1C1C1E] border border-white/8 rounded-xl p-4">
                      <div className="flex items-start justify-between mb-2">
                        <div>
                          <p className="text-white font-semibold text-sm font-mono">{req.ref}</p>
                          <p className="text-white/30 text-xs">{formatDate(req.created_at)}</p>
                        </div>
                        <div className={`flex items-center gap-1.5 text-xs font-medium ${st.color}`}>
                          <Icon size={13} />
                          {t(st.label)}
                        </div>
                      </div>
                      <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs mt-3">
                        <div className="flex justify-between col-span-2">
                          <span className="text-white/40">{t("ins.rowType")}</span>
                          <span className="text-white">{req.product_label}</span>
                        </div>
                        {req.subject && (
                          <div className="flex justify-between col-span-2">
                            <span className="text-white/40">{t("ins.rowSubject")}</span>
                            <span className="text-white">{req.subject}</span>
                          </div>
                        )}
                        {hasRoute && (
                          <div className="flex justify-between col-span-2">
                            <span className="text-white/40">{t("ins.rowRoute")}</span>
                            <span className="text-white">{req.origin} → {req.destination}</span>
                          </div>
                        )}
                        {fdEntries.map(([k, v]) => {
                          const d = fieldDisplay(req.product, k, String(v));
                          return (
                            <div key={k} className="flex justify-between col-span-2">
                              <span className="text-white/40">{t(d.label)}</span>
                              <span className="text-white">{d.textIsKey ? t(d.text) : d.text}</span>
                            </div>
                          );
                        })}
                        <div className="flex justify-between">
                          <span className="text-white/40">{t("ins.rowCapitalShort")}</span>
                          <span className="text-white">{toPersianNum(req.cargo_value.toLocaleString())} {t("ins.tomanShort")}</span>
                        </div>
                        <div className="flex justify-between">
                          <span className="text-white/40">{t("ins.premium")}</span>
                          <span className="text-emerald-400 font-medium">{toPersianNum(req.premium.toLocaleString())} {t("ins.tomanShort")}</span>
                        </div>
                        {req.source === "provider" && (
                          <div className="flex justify-between col-span-2">
                            <span className="text-white/40">{t("ins.rowIssuer")}</span>
                            <span className="text-sky-300 flex items-center gap-1">
                              <Zap size={11} /> {req.provider_name || t("ins.provider")}
                              {req.provider_ref && (
                                <span className="text-white/50 font-mono mr-1">· {req.provider_ref}</span>
                              )}
                            </span>
                          </div>
                        )}
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
