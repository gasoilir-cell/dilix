"use client";

import { getApiErrorMessage } from "@/lib/api";
import { useState, useEffect, useCallback } from "react";
import {
  Building2, Loader2, CheckCircle2, AlertCircle, Clock,
  Plus, Link2, ShieldCheck, RefreshCw, KeyRound, Webhook, Copy, XCircle,
  Wallet, BadgeCheck, ListChecks,
} from "lucide-react";
import { toPersianNum } from "@/lib/utils";
import AppShell from "@/components/layout/AppShell";
import { Button } from "@/components/ui/Button";
import api from "@/lib/api";
import toast from "react-hot-toast";
import { useAuthStore } from "@/store/auth";
import { useTranslation } from "@/store/i18n";

const ADMIN_ROLES = ["admin", "super_admin"];

// ── Types ─────────────────────────────────────────────────────
const PROVIDER_TYPES = [
  { id: "insurer", label: "prov.ptype.insurer", emoji: "🛡️" },
  { id: "bank",    label: "prov.ptype.bank",    emoji: "🏦" },
  { id: "broker",  label: "prov.ptype.broker",  emoji: "🤝" },
  { id: "psp",     label: "prov.ptype.psp",     emoji: "💳" },
  { id: "other",   label: "prov.ptype.other",   emoji: "🏢" },
];

const KYB_BADGE: Record<string, { color: string; icon: React.ElementType }> = {
  pending:  { color: "text-yellow-400",  icon: Clock       },
  verified: { color: "text-emerald-400", icon: CheckCircle2 },
  rejected: { color: "text-red-400",     icon: AlertCircle  },
};

interface Provider {
  id: string; legal_name: string;
  provider_type: string; provider_type_label: string;
  license_no: string; economic_code: string | null;
  contact_name: string | null; contact_phone: string | null; contact_email: string | null;
  commission_rate: number;
  products?: string[];
  products_labels?: string[];
  country?: string; country_flag?: string; currency?: string;
  regulator?: string | null;
  agreement_accepted: boolean;
  kyb_status: string; kyb_status_label: string;
  created_at: string;
}

// کشورهای پرکاربرد + ارزِ پیش‌فرضِ هرکدام (ثبتِ بین‌المللی)
const COUNTRIES: { code: string; flag: string; nameKey: string; ccy: string }[] = [
  { code: "IR", flag: "🇮🇷", nameKey: "country.ir", ccy: "IRR" },
  { code: "DE", flag: "🇩🇪", nameKey: "country.de", ccy: "EUR" },
  { code: "US", flag: "🇺🇸", nameKey: "country.us", ccy: "USD" },
  { code: "GB", flag: "🇬🇧", nameKey: "country.gb", ccy: "GBP" },
  { code: "AE", flag: "🇦🇪", nameKey: "country.ae", ccy: "AED" },
  { code: "TR", flag: "🇹🇷", nameKey: "country.tr", ccy: "TRY" },
  { code: "SA", flag: "🇸🇦", nameKey: "country.sa", ccy: "SAR" },
  { code: "RU", flag: "🇷🇺", nameKey: "country.ru", ccy: "RUB" },
  { code: "CN", flag: "🇨🇳", nameKey: "country.cn", ccy: "CNY" },
  { code: "IN", flag: "🇮🇳", nameKey: "country.in", ccy: "INR" },
  { code: "CA", flag: "🇨🇦", nameKey: "country.ca", ccy: "CAD" },
  { code: "AU", flag: "🇦🇺", nameKey: "country.au", ccy: "AUD" },
];
const CURRENCIES = ["IRR", "USD", "EUR", "GBP", "AED", "TRY", "SAR", "RUB", "CNY", "INR", "CAD", "AUD"];

interface ProviderAPI {
  id: string; name: string; base_url: string; spec_url: string | null;
  env: string; status: string; last_tested_at: string | null; created_at: string;
}

const API_STATUS: Record<string, { label: string; color: string }> = {
  registered: { label: "prov.apiStatus.registered", color: "text-white/50"     },
  tested:     { label: "prov.apiStatus.tested",     color: "text-emerald-400"  },
  failed:     { label: "prov.apiStatus.failed",     color: "text-red-400"      },
};

interface Credential {
  id: string; label: string; auth_type: string; env: string;
  key_prefix: string | null; status: string; created_at: string;
}
interface Webhook {
  id: string; url: string; event_types: string[] | null;
  status: string; created_at: string; secret?: string | null;
}
interface WebhookEvent {
  id: string; event_type: string;
  payload: Record<string, unknown> | null; received_at: string;
}

interface CommissionSummary {
  provider_id: string | null;
  provider_name: string | null;
  policies: number;
  total_premium: number;
  total_commission: number;
  accrued_commission: number;
  settled_commission: number;
}

type Tab = "register" | "list" | "admin";

const inputCls =
  "w-full bg-[#1C1C1E] border border-white/8 rounded-xl p-3 text-sm text-white placeholder-white/20 focus:outline-none focus:border-emerald-500/40";

export default function ProviderPage() {
  const { t } = useTranslation();
  const [tab, setTab] = useState<Tab>("list");
  const role = useAuthStore((s) => s.user?.role ?? "");
  const isAdmin = ADMIN_ROLES.includes(role);

  // ── Register form ──────────────────────────────────────────
  const [legalName,   setLegalName]   = useState("");
  const [ptype,       setPtype]       = useState("insurer");
  const [licenseNo,   setLicenseNo]   = useState("");
  const [economicCode,setEconomicCode]= useState("");
  const [contactName, setContactName] = useState("");
  const [contactPhone,setContactPhone]= useState("");
  const [contactEmail,setContactEmail]= useState("");
  const [commission,  setCommission]  = useState("15");
  const [country,     setCountry]     = useState("IR");
  const [currency,    setCurrency]    = useState("IRR");
  const [regulator,   setRegulator]   = useState("");
  const [agree,       setAgree]       = useState(false);
  const [submitting,  setSubmitting]  = useState(false);

  // ── List ───────────────────────────────────────────────────
  const [providers, setProviders] = useState<Provider[]>([]);
  const [loading,    setLoading]   = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.get("/providers/me");
      setProviders(res.data);
    } catch { /* ignored */ } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { if (tab === "list") load(); }, [tab, load]);

  const handleRegister = async () => {
    if (!legalName || !licenseNo) { toast.error(t("prov.toast.nameLicenseRequired")); return; }
    if (!agree) { toast.error(t("prov.toast.agreeRequired")); return; }
    setSubmitting(true);
    try {
      await api.post("/providers/register", {
        legal_name: legalName,
        provider_type: ptype,
        license_no: licenseNo,
        economic_code: economicCode || undefined,
        contact_name: contactName || undefined,
        contact_phone: contactPhone || undefined,
        contact_email: contactEmail || undefined,
        commission_rate: Number(commission) || 0,
        country,
        currency,
        regulator: regulator || undefined,
        agreement_accepted: true,
      });
      toast.success(t("prov.toast.registered"));
      setLegalName(""); setLicenseNo(""); setEconomicCode("");
      setContactName(""); setContactPhone(""); setContactEmail("");
      setCommission("15"); setCountry("IR"); setCurrency("IRR"); setRegulator(""); setAgree(false);
      setTab("list");
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("prov.toast.registerErr")));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <AppShell title={t("prov.title")}>
      <div className="page-inner">

        <div className="flex gap-1 bg-[#1C1C1E] rounded-xl p-1 mb-5">
          {[
            { id: "list"     as Tab, label: t("prov.tab.list") },
            { id: "register" as Tab, label: t("prov.tab.register") },
            ...(isAdmin ? [{ id: "admin" as Tab, label: t("prov.tab.admin") }] : []),
          ].map((t) => (
            <button
              key={t.id}
              onClick={() => setTab(t.id)}
              className={`flex-1 py-2.5 rounded-lg text-sm font-medium transition-all ${
                tab === t.id ? "bg-emerald-600 text-white" : "text-white/40 hover:text-white/70"
              }`}
            >
              {t.label}
            </button>
          ))}
        </div>

        {/* ── Admin: KYB verify/reject + کارمزد/تسویه ──────── */}
        {tab === "admin" && isAdmin && (
          <div className="space-y-8">
            <AdminPanel />
            <SettlementConsole />
          </div>
        )}

        {/* ── Register ─────────────────────────────────────── */}
        {tab === "register" && (
          <div className="space-y-4">
            <div className="bg-emerald-500/8 border border-emerald-500/20 rounded-xl p-3.5 flex gap-2.5">
              <ShieldCheck size={18} className="text-emerald-400 flex-shrink-0 mt-0.5" />
              <p className="text-xs text-white/60 leading-relaxed">
                {t("prov.register.intro")}
              </p>
            </div>

            <div>
              <label className="text-xs text-white/40 mb-2 block">{t("prov.field.ptype")}</label>
              <div className="grid grid-cols-3 gap-2">
                {PROVIDER_TYPES.map((p) => (
                  <button
                    key={p.id}
                    onClick={() => setPtype(p.id)}
                    className={`flex flex-col items-center gap-1 p-3 rounded-xl border transition-all ${
                      ptype === p.id ? "border-emerald-500/60 bg-emerald-500/10" : "border-white/8 bg-[#1C1C1E]"
                    }`}
                  >
                    <span className="text-xl">{p.emoji}</span>
                    <span className="text-[11px] text-white/70 text-center leading-tight">{t(p.label)}</span>
                  </button>
                ))}
              </div>
            </div>

            <div>
              <label className="text-xs text-white/40 mb-1.5 block">{t("prov.field.legalName")}</label>
              <input value={legalName} onChange={(e) => setLegalName(e.target.value)}
                placeholder={t("prov.ph.legalName")} className={inputCls} />
            </div>

            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="text-xs text-white/40 mb-1.5 block">{t("prov.field.license")}</label>
                <input value={licenseNo} onChange={(e) => setLicenseNo(e.target.value)}
                  placeholder={t("prov.ph.license")} className={inputCls} />
              </div>
              <div>
                <label className="text-xs text-white/40 mb-1.5 block">{t("prov.field.economicCode")}</label>
                <input value={economicCode} onChange={(e) => setEconomicCode(e.target.value.replace(/\D/g, ""))}
                  inputMode="numeric" placeholder={t("prov.ph.optional")} className={inputCls} />
              </div>
            </div>

            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="text-xs text-white/40 mb-1.5 block">{t("prov.field.contactName")}</label>
                <input value={contactName} onChange={(e) => setContactName(e.target.value)}
                  placeholder={t("prov.ph.optional")} className={inputCls} />
              </div>
              <div>
                <label className="text-xs text-white/40 mb-1.5 block">{t("prov.field.contactPhone")}</label>
                <input value={contactPhone} onChange={(e) => setContactPhone(e.target.value.replace(/\D/g, ""))}
                  inputMode="numeric" placeholder={t("prov.ph.optional")} className={inputCls} />
              </div>
            </div>

            <div>
              <label className="text-xs text-white/40 mb-1.5 block">{t("prov.field.contactEmail")}</label>
              <input value={contactEmail} onChange={(e) => setContactEmail(e.target.value)}
                placeholder={t("prov.ph.optional")} className={inputCls} />
            </div>

            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="text-xs text-white/40 mb-1.5 block">{t("prov.field.country")}</label>
                <select
                  value={country}
                  onChange={(e) => {
                    const c = e.target.value;
                    setCountry(c);
                    const m = COUNTRIES.find((x) => x.code === c);
                    if (m) setCurrency(m.ccy);
                  }}
                  className={`${inputCls} appearance-none`}
                >
                  {COUNTRIES.map((c) => (
                    <option key={c.code} value={c.code}>{c.flag} {t(c.nameKey)}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="text-xs text-white/40 mb-1.5 block">{t("prov.field.currency")}</label>
                <select value={currency} onChange={(e) => setCurrency(e.target.value)}
                  className={`${inputCls} appearance-none`}>
                  {CURRENCIES.map((c) => (
                    <option key={c} value={c}>{c}</option>
                  ))}
                </select>
              </div>
            </div>

            <div>
              <label className="text-xs text-white/40 mb-1.5 block">{t("prov.field.regulator")}</label>
              <input value={regulator} onChange={(e) => setRegulator(e.target.value)}
                placeholder={t("prov.ph.regulator")} className={inputCls} />
            </div>

            <div>
              <label className="text-xs text-white/40 mb-1.5 block">{t("prov.field.commission")}</label>
              <input value={commission} onChange={(e) => setCommission(e.target.value.replace(/[^\d.]/g, ""))}
                inputMode="decimal" placeholder="۱۵" className={inputCls} />
            </div>

            <button
              onClick={() => setAgree(!agree)}
              className="w-full flex items-center gap-3 p-3.5 rounded-xl border transition-all text-right"
              style={{ borderColor: agree ? "rgba(16,185,129,0.5)" : "var(--border-1)",
                       background: agree ? "rgba(16,185,129,0.08)" : "var(--surface-1)" }}
            >
              <div className={`w-5 h-5 rounded-md border-2 flex items-center justify-center flex-shrink-0 ${
                agree ? "border-emerald-400 bg-emerald-400" : "border-white/25"
              }`}>
                {agree && <CheckCircle2 size={14} className="text-black" />}
              </div>
              <span className="text-xs text-white/70 leading-relaxed">
                {t("prov.register.agree")}
              </span>
            </button>

            <Button variant="primary" size="lg" fullWidth disabled={submitting} onClick={handleRegister}>
              {submitting
                ? <><Loader2 size={16} className="animate-spin ml-2" />{t("prov.btn.submitting")}</>
                : t("prov.btn.register")}
            </Button>
          </div>
        )}

        {/* ── List ─────────────────────────────────────────── */}
        {tab === "list" && (
          <div>
            {loading ? (
              <div className="flex justify-center pt-12">
                <Loader2 size={28} className="text-emerald-400 animate-spin" />
              </div>
            ) : providers.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-16 gap-3">
                <Building2 size={44} className="text-white/15" />
                <p className="text-white/30 text-sm">{t("prov.list.empty")}</p>
                <button onClick={() => setTab("register")} className="text-emerald-400 text-sm underline">
                  {t("prov.list.registerFirst")}
                </button>
              </div>
            ) : (
              <div className="space-y-3">
                {providers.map((p) => (
                  <ProviderCard key={p.id} provider={p} />
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    </AppShell>
  );
}

// ── Provider card (with APIs) ─────────────────────────────────
function ProviderCard({ provider }: { provider: Provider }) {
  const { t } = useTranslation();
  const [apis, setApis] = useState<ProviderAPI[]>([]);
  const [open, setOpen] = useState(false);
  const [loadingApis, setLoadingApis] = useState(false);
  const [adding, setAdding] = useState(false);
  const [testingId, setTestingId] = useState<string | null>(null);

  const [name, setName] = useState("");
  const [baseUrl, setBaseUrl] = useState("");
  const [specUrl, setSpecUrl] = useState("");
  const [env, setEnv] = useState("sandbox");
  const [showForm, setShowForm] = useState(false);

  const badge = KYB_BADGE[provider.kyb_status] ?? KYB_BADGE.pending;
  const Icon = badge.icon;

  const loadApis = useCallback(async () => {
    setLoadingApis(true);
    try {
      const res = await api.get(`/providers/${provider.id}/apis`);
      setApis(res.data);
    } catch { /* ignored */ } finally {
      setLoadingApis(false);
    }
  }, [provider.id]);

  const toggle = () => {
    const next = !open;
    setOpen(next);
    if (next && apis.length === 0) loadApis();
  };

  const addApi = async () => {
    if (!name || !baseUrl) { toast.error(t("prov.toast.nameBaseRequired")); return; }
    setAdding(true);
    try {
      await api.post(`/providers/${provider.id}/apis`, {
        name, base_url: baseUrl, spec_url: specUrl || undefined, env,
      });
      toast.success(t("prov.toast.apiAdded"));
      setName(""); setBaseUrl(""); setSpecUrl(""); setEnv("sandbox"); setShowForm(false);
      loadApis();
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("prov.toast.apiAddErr")));
    } finally {
      setAdding(false);
    }
  };

  const testApi = async (id: string) => {
    setTestingId(id);
    try {
      const res = await api.post(`/providers/${provider.id}/apis/${id}/sandbox-test`);
      setApis((prev) => prev.map((a) => (a.id === id ? res.data : a)));
      toast[res.data.status === "tested" ? "success" : "error"](
        res.data.status === "tested" ? t("prov.toast.connOk") : t("prov.toast.connFail")
      );
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("prov.toast.testErr")));
    } finally {
      setTestingId(null);
    }
  };

  return (
    <div className="bg-[#1C1C1E] border border-white/8 rounded-xl overflow-hidden">
      <button onClick={toggle} className="w-full p-4 flex items-center justify-between text-right">
        <div>
          <p className="text-white font-semibold text-sm">
            {provider.country_flag ? `${provider.country_flag} ` : ""}{provider.legal_name}
          </p>
          <p className="text-white/40 text-xs mt-0.5">
            {provider.provider_type_label} · {t("prov.card.commission")} {provider.commission_rate}٪
            {provider.currency ? ` · ${t("prov.card.settle")} ${provider.currency}` : ""}
          </p>
        </div>
        <div className={`flex items-center gap-1.5 text-xs font-medium ${badge.color}`}>
          <Icon size={14} />
          {provider.kyb_status_label}
        </div>
      </button>

      {open && (
        <div className="border-t border-white/8 p-4 space-y-3">
          <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
            <div className="flex justify-between">
              <span className="text-white/40">{t("prov.card.license")}</span>
              <span className="text-white font-mono">{provider.license_no}</span>
            </div>
            {provider.economic_code && (
              <div className="flex justify-between">
                <span className="text-white/40">{t("prov.card.economicCode")}</span>
                <span className="text-white font-mono">{provider.economic_code}</span>
              </div>
            )}
            <div className="flex justify-between">
              <span className="text-white/40">{t("prov.card.countryCcy")}</span>
              <span className="text-white">
                {provider.country_flag} {provider.country} · {provider.currency}
              </span>
            </div>
            {provider.regulator && (
              <div className="flex justify-between">
                <span className="text-white/40">{t("prov.card.regulator")}</span>
                <span className="text-white">{provider.regulator}</span>
              </div>
            )}
          </div>

          {/* APIs */}
          <div className="flex items-center justify-between pt-1">
            <p className="text-xs text-white/50 font-medium">{t("prov.card.apis")}</p>
            <button onClick={() => setShowForm((s) => !s)}
              className="text-emerald-400 text-xs flex items-center gap-1">
              <Plus size={13} /> {t("prov.card.addApi")}
            </button>
          </div>

          {showForm && (
            <div className="space-y-2 bg-black/20 rounded-xl p-3">
              <input value={name} onChange={(e) => setName(e.target.value)} placeholder={t("prov.ph.apiName")} className={inputCls} />
              <input value={baseUrl} onChange={(e) => setBaseUrl(e.target.value)} placeholder="Base URL (https://…)" className={inputCls} />
              <input value={specUrl} onChange={(e) => setSpecUrl(e.target.value)} placeholder={t("prov.ph.specUrl")} className={inputCls} />
              <select value={env} onChange={(e) => setEnv(e.target.value)} className={`${inputCls} appearance-none`}>
                <option value="sandbox">{t("prov.env.sandbox")}</option>
                <option value="production">{t("prov.env.production")}</option>
              </select>
              <Button variant="primary" size="sm" fullWidth disabled={adding} onClick={addApi}>
                {adding ? <Loader2 size={14} className="animate-spin" /> : t("prov.btn.addApi")}
              </Button>
            </div>
          )}

          {loadingApis ? (
            <div className="flex justify-center py-3"><Loader2 size={18} className="text-emerald-400 animate-spin" /></div>
          ) : apis.length === 0 ? (
            <p className="text-white/25 text-xs text-center py-2">{t("prov.card.noApi")}</p>
          ) : (
            <div className="space-y-2">
              {apis.map((a) => {
                const st = API_STATUS[a.status] ?? API_STATUS.registered;
                return (
                  <div key={a.id} className="bg-black/20 rounded-xl p-3">
                    <div className="flex items-center justify-between">
                      <div className="min-w-0">
                        <p className="text-white text-sm truncate flex items-center gap-1.5">
                          <Link2 size={13} className="text-white/40 flex-shrink-0" />{a.name}
                        </p>
                        <p className="text-white/30 text-[11px] truncate mt-0.5">{a.base_url}</p>
                      </div>
                      <span className="text-[10px] px-2 py-0.5 rounded-full bg-white/8 text-white/50 flex-shrink-0">{a.env}</span>
                    </div>
                    <div className="flex items-center justify-between mt-2">
                      <span className={`text-xs ${st.color}`}>{t(st.label)}</span>
                      <button onClick={() => testApi(a.id)} disabled={testingId === a.id}
                        className="text-xs text-emerald-400 flex items-center gap-1">
                        {testingId === a.id
                          ? <Loader2 size={12} className="animate-spin" />
                          : <RefreshCw size={12} />}
                        {t("prov.card.testConn")}
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
          )}

          <ProductCoverageSection provider={provider} />
          <EarningsSection provider={provider} />
          <CredentialSection provider={provider} />
          <WebhookSection provider={provider} />
        </div>
      )}
    </div>
  );
}

// ── Earnings / statement (صورت‌حسابِ کارمزدِ خودِ مرکز) ──────────
interface Statement {
  policies: number;
  total_premium: number;
  total_commission: number;
  accrued_commission: number;
  settled_commission: number;
}
interface CommissionRow {
  id: string; request_ref: string | null; product: string | null;
  premium: number; commission_rate: number; commission_amount: number;
  status: string; created_at: string;
}
const fmtT = (n: number, t: (k: string) => string) => toPersianNum(Number(n || 0).toLocaleString("en-US")) + t("prov.tomanSuffix");

function EarningsSection({ provider }: { provider: Provider }) {
  const { t } = useTranslation();
  const [st, setSt] = useState<Statement | null>(null);
  const [rows, setRows] = useState<CommissionRow[] | null>(null);
  const [loading, setLoading] = useState(false);
  const [showRows, setShowRows] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.get(`/insurance/provider/${provider.id}/statement`);
      setSt(res.data);
    } catch { /* بدونِ بیمه‌نامه، صفر */ } finally {
      setLoading(false);
    }
  }, [provider.id]);

  useEffect(() => { load(); }, [load]);

  const loadRows = async () => {
    const next = !showRows;
    setShowRows(next);
    if (next && rows === null) {
      try {
        const res = await api.get(`/insurance/provider/${provider.id}/commissions`);
        setRows(res.data);
      } catch { setRows([]); }
    }
  };

  return (
    <div className="pt-2 border-t border-white/8 space-y-2">
      <p className="text-xs text-white/50 font-medium flex items-center gap-1.5">
        <Wallet size={13} className="text-emerald-400" /> {t("prov.earn.title")}
      </p>
      {loading && !st ? (
        <div className="flex justify-center py-2"><Loader2 size={16} className="text-emerald-400 animate-spin" /></div>
      ) : (
        <>
          <div className="grid grid-cols-2 gap-2">
            <div className="bg-black/20 rounded-xl p-2.5">
              <p className="text-white/40 text-[10px]">{t("prov.earn.unpaidMine")}</p>
              <p className="text-emerald-400 text-sm font-semibold mt-0.5">{fmtT(st?.accrued_commission ?? 0, t)}</p>
            </div>
            <div className="bg-black/20 rounded-xl p-2.5">
              <p className="text-white/40 text-[10px]">{t("prov.earn.settled")}</p>
              <p className="text-white/70 text-sm font-semibold mt-0.5">{fmtT(st?.settled_commission ?? 0, t)}</p>
            </div>
          </div>
          <div className="flex items-center justify-between text-[11px] text-white/40 px-1">
            <span>{toPersianNum(st?.policies ?? 0)} {t("prov.earn.policiesSuf")} · {t("prov.earn.totalPremiumPre")} {fmtT(st?.total_premium ?? 0, t)}</span>
            <button onClick={loadRows} className="text-emerald-400">
              {showRows ? t("prov.common.close") : t("prov.common.details")}
            </button>
          </div>
          {showRows && (
            rows === null ? (
              <div className="flex justify-center py-2"><Loader2 size={14} className="text-emerald-400 animate-spin" /></div>
            ) : rows.length === 0 ? (
              <p className="text-white/25 text-xs text-center py-2">{t("prov.earn.noCommission")}</p>
            ) : (
              <div className="space-y-1.5">
                {rows.map((c) => (
                  <div key={c.id} className="bg-black/20 rounded-lg p-2.5 flex items-center justify-between">
                    <div className="min-w-0">
                      <p className="text-white/80 text-xs font-mono truncate">{c.request_ref ?? "—"}</p>
                      <p className="text-white/30 text-[10px] mt-0.5">
                        {t("prov.earn.premiumPre")} {fmtT(c.premium, t)} · {t("prov.earn.ratePre")} {toPersianNum(c.commission_rate)}٪
                      </p>
                    </div>
                    <div className="text-left flex-shrink-0">
                      <p className="text-emerald-400 text-xs font-semibold">{fmtT(c.commission_amount, t)}</p>
                      <p className={`text-[10px] mt-0.5 ${c.status === "settled" ? "text-white/40" : "text-yellow-400"}`}>
                        {c.status === "settled" ? t("prov.earn.settled") : t("prov.earn.unpaid")}
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            )
          )}
        </>
      )}
    </div>
  );
}

// ── Product coverage (کدام بیمه‌ها را پوشش می‌دهد) ──────────────
function ProductCoverageSection({ provider }: { provider: Provider }) {
  const { t } = useTranslation();
  const [catalog, setCatalog] = useState<{ id: string; label: string }[]>([]);
  const [selected, setSelected] = useState<string[]>(provider.products ?? []);
  const [saving, setSaving] = useState(false);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    let alive = true;
    api.get("/providers/catalog/products")
      .then((res) => { if (alive) { setCatalog(res.data); setLoaded(true); } })
      .catch(() => { if (alive) setLoaded(true); });
    return () => { alive = false; };
  }, []);

  const toggle = (id: string) =>
    setSelected((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));

  const save = async () => {
    setSaving(true);
    try {
      const res = await api.put(`/providers/${provider.id}/products`, { products: selected });
      setSelected(res.data.products ?? []);
      toast.success(t("prov.toast.coverageSaved"));
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("prov.toast.coverageErr")));
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="pt-2 border-t border-white/8 space-y-2">
      <p className="text-xs text-white/50 font-medium flex items-center gap-1.5">
        <ListChecks size={13} className="text-indigo-400" /> {t("prov.cov.title")}
      </p>
      <p className="text-white/30 text-[11px]">
        {t("prov.cov.desc")}
      </p>
      {!loaded ? (
        <div className="flex justify-center py-2"><Loader2 size={16} className="text-indigo-400 animate-spin" /></div>
      ) : (
        <>
          <div className="flex flex-wrap gap-1.5">
            {catalog.map((c) => {
              const on = selected.includes(c.id);
              return (
                <button key={c.id} onClick={() => toggle(c.id)}
                  className={`text-[11px] px-2.5 py-1 rounded-full border transition ${
                    on
                      ? "bg-indigo-500/20 border-indigo-400/50 text-indigo-300"
                      : "bg-white/5 border-white/10 text-white/50"
                  }`}>
                  {c.label}
                </button>
              );
            })}
          </div>
          <Button variant="outline" size="sm" disabled={saving} onClick={save}>
            {saving ? <Loader2 size={14} className="animate-spin" /> : t("prov.cov.save")}
          </Button>
        </>
      )}
    </div>
  );
}

// ── Credentials (Dilix→Provider) ──────────────────────────────
function CredentialSection({ provider }: { provider: Provider }) {
  const { t } = useTranslation();
  const [items, setItems] = useState<Credential[]>([]);
  const [loading, setLoading] = useState(false);
  const [showForm, setShowForm] = useState(false);
  const [saving, setSaving] = useState(false);
  const [label, setLabel] = useState("");
  const [authType, setAuthType] = useState("api_key");
  const [cenv, setCenv] = useState("sandbox");
  const [secret, setSecret] = useState("");

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.get(`/providers/${provider.id}/credentials`);
      setItems(res.data);
    } catch { /* ignored */ } finally { setLoading(false); }
  }, [provider.id]);

  useEffect(() => { load(); }, [load]);

  const add = async () => {
    if (!label || !secret) { toast.error(t("prov.toast.labelSecretRequired")); return; }
    setSaving(true);
    try {
      await api.post(`/providers/${provider.id}/credentials`, {
        label, auth_type: authType, env: cenv, secret,
      });
      toast.success(t("prov.toast.credSaved"));
      setLabel(""); setSecret(""); setAuthType("api_key"); setCenv("sandbox"); setShowForm(false);
      load();
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("prov.toast.credErr")));
    } finally { setSaving(false); }
  };

  const revoke = async (id: string) => {
    try {
      await api.post(`/providers/${provider.id}/credentials/${id}/revoke`);
      toast.success(t("prov.toast.credRevoked"));
      load();
    } catch (e: any) { toast.error(getApiErrorMessage(e, t("prov.toast.error"))); }
  };

  return (
    <div className="pt-3 border-t border-white/8">
      <div className="flex items-center justify-between">
        <p className="text-xs text-white/50 font-medium flex items-center gap-1.5">
          <KeyRound size={13} /> {t("prov.cred.title")}
        </p>
        <button onClick={() => setShowForm((s) => !s)} className="text-emerald-400 text-xs flex items-center gap-1">
          <Plus size={13} /> {t("prov.cred.add")}
        </button>
      </div>

      {showForm && (
        <div className="space-y-2 bg-black/20 rounded-xl p-3 mt-2">
          <input value={label} onChange={(e) => setLabel(e.target.value)} placeholder={t("prov.ph.credLabel")} className={inputCls} />
          <input value={secret} onChange={(e) => setSecret(e.target.value)} placeholder={t("prov.ph.credSecret")} className={inputCls} />
          <div className="grid grid-cols-2 gap-2">
            <select value={authType} onChange={(e) => setAuthType(e.target.value)} className={`${inputCls} appearance-none`}>
              <option value="api_key">API Key</option>
              <option value="bearer">Bearer Token</option>
              <option value="basic">Basic Auth</option>
            </select>
            <select value={cenv} onChange={(e) => setCenv(e.target.value)} className={`${inputCls} appearance-none`}>
              <option value="sandbox">sandbox</option>
              <option value="production">{t("prov.env.productionShort")}</option>
            </select>
          </div>
          <Button variant="primary" size="sm" fullWidth disabled={saving} onClick={add}>
            {saving ? <Loader2 size={14} className="animate-spin" /> : t("prov.cred.save")}
          </Button>
        </div>
      )}

      {loading ? null : items.length === 0 ? (
        <p className="text-white/25 text-xs text-center py-2">{t("prov.cred.empty")}</p>
      ) : (
        <div className="space-y-1.5 mt-2">
          {items.map((c) => (
            <div key={c.id} className="flex items-center justify-between bg-black/20 rounded-lg px-3 py-2 text-xs">
              <div className="min-w-0">
                <span className="text-white">{c.label}</span>
                <span className="text-white/30 font-mono mr-2">{c.key_prefix ? `${c.key_prefix}…` : "•••"}</span>
                <span className="text-white/30">· {c.env}</span>
              </div>
              {c.status === "active" ? (
                <button onClick={() => revoke(c.id)} className="text-red-400/70 hover:text-red-400 flex items-center gap-1 flex-shrink-0">
                  <XCircle size={12} /> {t("prov.cred.revoke")}
                </button>
              ) : (
                <span className="text-white/25 flex-shrink-0">{t("prov.cred.revoked")}</span>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ── Webhooks (Provider→Dilix) ─────────────────────────────────
function WebhookSection({ provider }: { provider: Provider }) {
  const { t } = useTranslation();
  const [items, setItems] = useState<Webhook[]>([]);
  const [loading, setLoading] = useState(false);
  const [showForm, setShowForm] = useState(false);
  const [saving, setSaving] = useState(false);
  const [url, setUrl] = useState("");
  const [events, setEvents] = useState("");
  const [freshSecret, setFreshSecret] = useState<string | null>(null);
  const [received, setReceived] = useState<WebhookEvent[] | null>(null);
  const [loadingEvents, setLoadingEvents] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.get(`/providers/${provider.id}/webhooks`);
      setItems(res.data);
    } catch { /* ignored */ } finally { setLoading(false); }
  }, [provider.id]);

  useEffect(() => { load(); }, [load]);

  const loadEvents = async () => {
    setLoadingEvents(true);
    try {
      const res = await api.get(`/providers/${provider.id}/webhooks/events`);
      setReceived(res.data);
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("prov.toast.eventsErr")));
    } finally { setLoadingEvents(false); }
  };

  const incomingUrl = (id: string) =>
    (typeof window !== "undefined" ? window.location.origin : "") +
    `/api/v1/providers/webhooks/incoming/${id}`;

  const copyText = (txt: string) => {
    navigator.clipboard?.writeText(txt); toast.success(t("prov.toast.copied"));
  };

  const add = async () => {
    if (!url) { toast.error(t("prov.toast.urlRequired")); return; }
    setSaving(true);
    try {
      const res = await api.post(`/providers/${provider.id}/webhooks`, {
        url,
        event_types: events ? events.split(",").map((s) => s.trim()).filter(Boolean) : undefined,
      });
      setFreshSecret(res.data.secret ?? null);
      toast.success(t("prov.toast.webhookAdded"));
      setUrl(""); setEvents(""); setShowForm(false);
      load();
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("prov.toast.webhookErr")));
    } finally { setSaving(false); }
  };

  const copySecret = () => {
    if (freshSecret) { navigator.clipboard?.writeText(freshSecret); toast.success(t("prov.toast.copied")); }
  };

  return (
    <div className="pt-3 border-t border-white/8">
      <div className="flex items-center justify-between">
        <p className="text-xs text-white/50 font-medium flex items-center gap-1.5">
          <Webhook size={13} /> {t("prov.wh.title")}
        </p>
        <button onClick={() => setShowForm((s) => !s)} className="text-emerald-400 text-xs flex items-center gap-1">
          <Plus size={13} /> {t("prov.wh.add")}
        </button>
      </div>

      {freshSecret && (
        <div className="bg-amber-500/8 border border-amber-500/25 rounded-xl p-3 mt-2">
          <p className="text-[11px] text-amber-300/90 mb-1.5">{t("prov.wh.secretOnce")}</p>
          <div className="flex items-center gap-2">
            <code className="text-[11px] text-white/80 font-mono truncate flex-1">{freshSecret}</code>
            <button onClick={copySecret} className="text-emerald-400 flex-shrink-0"><Copy size={14} /></button>
          </div>
        </div>
      )}

      {showForm && (
        <div className="space-y-2 bg-black/20 rounded-xl p-3 mt-2">
          <input value={url} onChange={(e) => setUrl(e.target.value)} placeholder="Webhook URL (https://…)" className={inputCls} />
          <input value={events} onChange={(e) => setEvents(e.target.value)} placeholder={t("prov.ph.events")} className={inputCls} />
          <Button variant="primary" size="sm" fullWidth disabled={saving} onClick={add}>
            {saving ? <Loader2 size={14} className="animate-spin" /> : t("prov.wh.save")}
          </Button>
        </div>
      )}

      {loading ? null : items.length === 0 ? (
        <p className="text-white/25 text-xs text-center py-2">{t("prov.wh.empty")}</p>
      ) : (
        <div className="space-y-1.5 mt-2">
          {items.map((w) => (
            <div key={w.id} className="bg-black/20 rounded-lg px-3 py-2 text-xs">
              <p className="text-white/70 truncate">{w.url}</p>
              {w.event_types && w.event_types.length > 0 && (
                <p className="text-white/30 text-[10px] mt-0.5">{w.event_types.join("، ")}</p>
              )}
              <div className="flex items-center gap-2 mt-1.5 pt-1.5 border-t border-white/5">
                <span className="text-white/30 text-[10px] flex-shrink-0">{t("prov.wh.incomingUrl")}</span>
                <code className="text-sky-300/80 text-[10px] font-mono truncate flex-1 direction-ltr">{incomingUrl(w.id)}</code>
                <button onClick={() => copyText(incomingUrl(w.id))} className="text-emerald-400 flex-shrink-0"><Copy size={12} /></button>
              </div>
            </div>
          ))}
        </div>
      )}

      {items.length > 0 && (
        <div className="mt-2">
          <button onClick={loadEvents} className="text-white/40 text-[11px] flex items-center gap-1 hover:text-white/70">
            {loadingEvents ? <Loader2 size={12} className="animate-spin" /> : <RefreshCw size={12} />}
            {t("prov.wh.receivedEvents")}
          </button>
          {received && (
            received.length === 0 ? (
              <p className="text-white/25 text-[11px] py-1.5">{t("prov.wh.noEvents")}</p>
            ) : (
              <div className="space-y-1 mt-1.5">
                {received.map((ev) => (
                  <div key={ev.id} className="flex items-center justify-between bg-emerald-500/5 rounded-lg px-2.5 py-1.5 text-[11px]">
                    <span className="text-emerald-300 font-mono">{ev.event_type}</span>
                    <span className="text-white/30">{new Date(ev.received_at).toLocaleString("fa-IR")}</span>
                  </div>
                ))}
              </div>
            )
          )}
        </div>
      )}
    </div>
  );
}

// ── Admin panel: KYB verify/reject ────────────────────────────
function AdminPanel() {
  const { t } = useTranslation();
  const [items, setItems] = useState<Provider[]>([]);
  const [loading, setLoading] = useState(false);
  const [actingId, setActingId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.get("/providers/admin/all");
      setItems(res.data);
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("prov.toast.loadErr")));
    } finally { setLoading(false); }
  }, []);

  useEffect(() => { load(); }, [load]);

  const decide = async (id: string, statusVal: string) => {
    setActingId(id);
    try {
      const res = await api.post(`/providers/${id}/kyb`, { status: statusVal });
      setItems((prev) => prev.map((p) => (p.id === id ? res.data : p)));
      toast.success(statusVal === "verified" ? t("prov.toast.verified") : t("prov.toast.rejected"));
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("prov.toast.error")));
    } finally { setActingId(null); }
  };

  if (loading) {
    return <div className="flex justify-center pt-12"><Loader2 size={28} className="text-emerald-400 animate-spin" /></div>;
  }
  if (items.length === 0) {
    return <p className="text-white/30 text-sm text-center py-16">{t("prov.admin.empty")}</p>;
  }

  return (
    <div className="space-y-3">
      {items.map((p) => {
        const badge = KYB_BADGE[p.kyb_status] ?? KYB_BADGE.pending;
        const Icon = badge.icon;
        return (
          <div key={p.id} className="bg-[#1C1C1E] border border-white/8 rounded-xl p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-white font-semibold text-sm">{p.legal_name}</p>
                <p className="text-white/40 text-xs mt-0.5">
                  {p.provider_type_label} · {t("prov.admin.codePre")} {p.license_no} · {t("prov.card.commission")} {p.commission_rate}٪
                </p>
              </div>
              <div className={`flex items-center gap-1.5 text-xs font-medium ${badge.color}`}>
                <Icon size={14} />{p.kyb_status_label}
              </div>
            </div>
            <div className="flex gap-2 mt-3">
              <button
                onClick={() => decide(p.id, "verified")}
                disabled={actingId === p.id || p.kyb_status === "verified"}
                className="flex-1 py-2 rounded-lg text-xs font-medium bg-emerald-600/90 text-white disabled:opacity-40 flex items-center justify-center gap-1"
              >
                {actingId === p.id ? <Loader2 size={13} className="animate-spin" /> : <CheckCircle2 size={13} />}
                {t("prov.admin.verify")}
              </button>
              <button
                onClick={() => decide(p.id, "rejected")}
                disabled={actingId === p.id || p.kyb_status === "rejected"}
                className="flex-1 py-2 rounded-lg text-xs font-medium bg-red-600/80 text-white disabled:opacity-40 flex items-center justify-center gap-1"
              >
                <XCircle size={13} /> {t("prov.admin.reject")}
              </button>
            </div>
          </div>
        );
      })}
    </div>
  );
}

// ── کنسولِ کارمزد و تسویه (ادمین) ──────────────────────────────
function fmtToman(n: number, t: (k: string) => string): string {
  return toPersianNum((n || 0).toLocaleString("en-US")) + t("prov.tomanSuffix");
}

function SettlementConsole() {
  const { t } = useTranslation();
  const [rows, setRows] = useState<CommissionSummary[]>([]);
  const [loading, setLoading] = useState(false);
  const [settlingId, setSettlingId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.get("/insurance/admin/commissions/summary");
      setRows(res.data);
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("prov.toast.commLoadErr")));
    } finally { setLoading(false); }
  }, []);

  useEffect(() => { load(); }, [load]);

  const settle = async (providerId: string | null) => {
    if (!providerId) {
      toast.error(t("prov.toast.noProviderRow"));
      return;
    }
    setSettlingId(providerId);
    try {
      const res = await api.post("/insurance/admin/commissions/settle", { provider_id: providerId });
      toast.success(`${t("prov.toast.settledPre")}${toPersianNum(res.data.settled_count)} ${t("prov.earn.policiesSuf")}`);
      await load();
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("prov.toast.settleErr")));
    } finally { setSettlingId(null); }
  };

  const totalAccrued = rows.reduce((s, r) => s + (r.accrued_commission || 0), 0);
  const totalSettled = rows.reduce((s, r) => s + (r.settled_commission || 0), 0);
  const totalPremium = rows.reduce((s, r) => s + (r.total_premium || 0), 0);

  return (
    <div>
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          <Wallet size={17} className="text-emerald-400" />
          <h3 className="text-white font-semibold text-sm">{t("prov.settle.title")}</h3>
        </div>
        <button
          onClick={load}
          className="text-white/40 hover:text-white/70 flex items-center gap-1 text-xs"
        >
          <RefreshCw size={13} className={loading ? "animate-spin" : ""} /> {t("prov.common.refresh")}
        </button>
      </div>

      {/* کارت‌های جمعِ کل */}
      <div className="grid grid-cols-3 gap-2 mb-4">
        <div className="bg-[#1C1C1E] border border-white/8 rounded-xl p-3">
          <p className="text-white/40 text-[11px]">{t("prov.settle.issuedPremium")}</p>
          <p className="text-white text-xs font-bold mt-1">{fmtToman(totalPremium, t)}</p>
        </div>
        <div className="bg-yellow-500/8 border border-yellow-500/20 rounded-xl p-3">
          <p className="text-yellow-400/70 text-[11px]">{t("prov.settle.accrued")}</p>
          <p className="text-yellow-300 text-xs font-bold mt-1">{fmtToman(totalAccrued, t)}</p>
        </div>
        <div className="bg-emerald-500/8 border border-emerald-500/20 rounded-xl p-3">
          <p className="text-emerald-400/70 text-[11px]">{t("prov.settle.settled")}</p>
          <p className="text-emerald-300 text-xs font-bold mt-1">{fmtToman(totalSettled, t)}</p>
        </div>
      </div>

      {loading ? (
        <div className="flex justify-center pt-6"><Loader2 size={24} className="text-emerald-400 animate-spin" /></div>
      ) : rows.length === 0 ? (
        <p className="text-white/30 text-sm text-center py-10">{t("prov.settle.empty")}</p>
      ) : (
        <div className="space-y-3">
          {rows.map((r) => (
            <div key={r.provider_id ?? "none"} className="bg-[#1C1C1E] border border-white/8 rounded-xl p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-white font-semibold text-sm">{r.provider_name ?? t("prov.settle.unknown")}</p>
                  <p className="text-white/40 text-xs mt-0.5">
                    {toPersianNum(r.policies)} {t("prov.earn.policiesSuf")} · {t("prov.earn.premiumPre")} {fmtToman(r.total_premium, t)}
                  </p>
                </div>
                <div className="text-left">
                  <p className="text-yellow-300 text-xs font-bold">{fmtToman(r.accrued_commission, t)}</p>
                  <p className="text-white/30 text-[10px]">{t("prov.settle.accruedShort")}</p>
                </div>
              </div>
              <div className="flex items-center justify-between mt-3">
                <span className="text-emerald-400/80 text-[11px] flex items-center gap-1">
                  <BadgeCheck size={12} /> {t("prov.settle.settledPre")} {fmtToman(r.settled_commission, t)}
                </span>
                <button
                  onClick={() => settle(r.provider_id)}
                  disabled={settlingId === r.provider_id || r.accrued_commission <= 0}
                  className="py-1.5 px-3 rounded-lg text-xs font-medium bg-emerald-600/90 text-white disabled:opacity-40 flex items-center justify-center gap-1"
                >
                  {settlingId === r.provider_id ? <Loader2 size={13} className="animate-spin" /> : <CheckCircle2 size={13} />}
                  {t("prov.settle.settleBtn")}
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
