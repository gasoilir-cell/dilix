"use client";

import { useCallback, useEffect, useState } from "react";
import {
  Blocks, Check, Copy, ExternalLink, Loader2, Plus, Search, Send,
  ShieldCheck, Trash2, Wallet, X,
} from "lucide-react";
import toast from "react-hot-toast";

import AppShell from "@/components/layout/AppShell";
import { Button } from "@/components/ui/Button";
import { getApiErrorMessage, miniappsApi } from "@/lib/api";
import { toPersianNum } from "@/lib/utils";
import { useTranslation } from "@/store/i18n";

// سرور ریال می‌دهد؛ کاربر تومان می‌خواند.
function fmtToman(rial: number): string {
  return toPersianNum(Math.round((rial || 0) / 10).toLocaleString("en-US"));
}

function fmtNum(n: number): string {
  return toPersianNum((n || 0).toLocaleString("en-US"));
}

interface MiniApp {
  app_id: string;
  name: string;
  tagline?: string | null;
  description?: string | null;
  icon_url?: string | null;
  entry_url?: string | null;
  category: string;
  scopes: string[];
  status: string;
  status_label: string;
  review_note?: string | null;
  install_count: number;
  open_count: number;
  owner_earth_id: string;
  owner_name?: string | null;
  is_mine: boolean;
  is_installed: boolean;
  installed_scopes: string[];
  needs_reconsent: boolean;
  created_at: string;
  app_secret?: string;
}

interface Payment {
  ref: string;
  app_id: string;
  app_name: string;
  app_icon?: string | null;
  out_trade_no: string;
  subject: string;
  amount: number;
  commission: number;
  status: string;
  created_at: string;
  expires_at: string;
}

type Tab = "store" | "installed" | "developer" | "payments";

const CATEGORIES = [
  "tools", "games", "shopping", "finance", "travel",
  "food", "education", "health", "social", "other",
] as const;

const ALL_SCOPES = ["profile", "payment", "location"] as const;

const STATUS_STYLE: Record<string, string> = {
  draft: "bg-surface-700 text-surface-400",
  pending: "bg-amber-500/12 text-amber-400",
  approved: "bg-emerald-500/12 text-emerald-400",
  rejected: "bg-rose-500/12 text-rose-400",
  suspended: "bg-rose-500/12 text-rose-400",
};

export default function MiniAppsPage() {
  const { t } = useTranslation();

  const [tab, setTab] = useState<Tab>("store");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);

  const [store, setStore] = useState<MiniApp[]>([]);
  const [query, setQuery] = useState("");
  const [installed, setInstalled] = useState<MiniApp[]>([]);
  const [mine, setMine] = useState<MiniApp[]>([]);
  const [payments, setPayments] = useState<Payment[]>([]);

  // فرمِ ساختِ برنامه
  const [nName, setNName] = useState("");
  const [nUrl, setNUrl] = useState("");
  const [nTagline, setNTagline] = useState("");
  const [nCategory, setNCategory] = useState<string>("tools");
  const [nScopes, setNScopes] = useState<string[]>(["profile"]);
  const [creating, setCreating] = useState(false);
  // کلیدِ مخفی فقط یک‌بار از سرور می‌آید؛ تا وقتی کاربر نبسته نگهش می‌داریم.
  const [secret, setSecret] = useState<{ app_id: string; value: string } | null>(null);

  const loadStore = useCallback(async (q?: string) => {
    try {
      const { data } = await miniappsApi.list(q ? { q } : undefined);
      setStore(data || []);
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    }
  }, []);

  const loadInstalled = useCallback(async () => {
    try {
      const { data } = await miniappsApi.installed();
      setInstalled(data || []);
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    }
  }, []);

  const loadMine = useCallback(async () => {
    try {
      const { data } = await miniappsApi.mine();
      setMine(data || []);
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    }
  }, []);

  const loadPayments = useCallback(async () => {
    try {
      const { data } = await miniappsApi.pendingPayments();
      setPayments(data || []);
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    }
  }, []);

  useEffect(() => {
    (async () => {
      setLoading(true);
      await loadStore();
      setLoading(false);
    })();
  }, [loadStore]);

  useEffect(() => {
    if (tab === "installed") loadInstalled();
    if (tab === "developer") loadMine();
    if (tab === "payments") loadPayments();
  }, [tab, loadInstalled, loadMine, loadPayments]);

  function toggleScope(s: string) {
    setNScopes((prev) =>
      prev.includes(s) ? prev.filter((x) => x !== s) : [...prev, s]);
  }

  async function createApp() {
    const name = nName.trim();
    const url = nUrl.trim();
    if (name.length < 2) return toast.error(t("miniapps.errName"));
    if (!/^https?:\/\/.+/i.test(url)) return toast.error(t("miniapps.errUrl"));
    if (nScopes.length === 0) return toast.error(t("miniapps.errScopes"));
    setCreating(true);
    try {
      const { data } = await miniappsApi.create({
        name,
        entry_url: url,
        tagline: nTagline.trim() || null,
        category: nCategory,
        scopes: nScopes,
      });
      setSecret({ app_id: data.app_id, value: data.app_secret });
      toast.success(t("miniapps.created"));
      setNName(""); setNUrl(""); setNTagline("");
      await loadMine();
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setCreating(false);
    }
  }

  async function submitApp(a: MiniApp) {
    setBusy(a.app_id);
    try {
      await miniappsApi.submit(a.app_id);
      toast.success(t("miniapps.submitted"));
      await loadMine();
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setBusy(null);
    }
  }

  async function rotate(a: MiniApp) {
    if (!confirm(t("miniapps.confirmRotate"))) return;
    setBusy(a.app_id);
    try {
      const { data } = await miniappsApi.rotateSecret(a.app_id);
      setSecret({ app_id: a.app_id, value: data.app_secret });
      toast.success(t("miniapps.rotated"));
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setBusy(null);
    }
  }

  async function install(a: MiniApp) {
    const names = a.scopes.map((s) => t(`miniapps.scope.${s}`)).join("، ");
    if (!confirm(`${t("miniapps.confirmInstall")}\n${a.name}\n${names}`)) return;
    setBusy(a.app_id);
    try {
      await miniappsApi.install(a.app_id, a.scopes);
      toast.success(t("miniapps.installed"));
      await loadStore(query.trim() || undefined);
      if (tab === "installed") await loadInstalled();
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setBusy(null);
    }
  }

  async function uninstall(a: MiniApp) {
    if (!confirm(t("miniapps.confirmUninstall"))) return;
    setBusy(a.app_id);
    try {
      await miniappsApi.uninstall(a.app_id);
      toast.success(t("miniapps.uninstalled"));
      await loadInstalled();
      await loadStore(query.trim() || undefined);
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setBusy(null);
    }
  }

  async function launch(a: MiniApp) {
    setBusy(a.app_id);
    try {
      const { data } = await miniappsApi.launch(a.app_id);
      // کد یک‌بارمصرف و کوتاه‌عمر است؛ باز کردنِ تبِ تازه بلافاصله انجام می‌شود.
      window.open(data.url, "_blank", "noopener,noreferrer");
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setBusy(null);
    }
  }

  async function payAction(p: Payment, action: "confirm" | "cancel") {
    if (action === "confirm" &&
        !confirm(`${t("miniapps.confirmPay")}\n${p.subject}\n${fmtToman(p.amount)} ${t("miniapps.toman")}`))
      return;
    setBusy(p.ref);
    try {
      if (action === "confirm") await miniappsApi.confirmPayment(p.ref);
      else await miniappsApi.cancelPayment(p.ref);
      toast.success(action === "confirm" ? t("miniapps.paid") : t("miniapps.payCancelled"));
      await loadPayments();
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setBusy(null);
    }
  }

  function copy(text: string) {
    navigator.clipboard?.writeText(text);
    toast.success(t("miniapps.copied"));
  }

  function AppCard({ a, mode }: { a: MiniApp; mode: "store" | "installed" | "mine" }) {
    return (
      <div className="card p-4">
        <div className="flex items-start gap-3">
          <div className="w-12 h-12 rounded-2xl bg-primary/12 flex items-center justify-center shrink-0 overflow-hidden">
            {a.icon_url
              ? /* eslint-disable-next-line @next/next/no-img-element */
                <img src={a.icon_url} alt="" className="w-full h-full object-cover" />
              : <Blocks className="w-5 h-5 text-primary" />}
          </div>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="font-semibold text-surface-50 truncate">{a.name}</span>
              {mode === "mine" && (
                <span className={`px-2 py-0.5 rounded-md text-[10px] ${
                  STATUS_STYLE[a.status] || "bg-surface-700 text-surface-400"}`}>
                  {a.status_label}
                </span>
              )}
              {a.needs_reconsent && (
                <span className="px-2 py-0.5 rounded-md bg-amber-500/10 text-amber-400 text-[10px]">
                  {t("miniapps.needsReconsent")}
                </span>
              )}
            </div>
            <div className="text-xs text-surface-400 mt-0.5 truncate">
              {t(`miniapps.cat.${a.category}`)} · {a.owner_name || a.owner_earth_id}
            </div>
            {a.tagline && (
              <p className="text-xs text-surface-300 mt-1.5 leading-5 line-clamp-2">
                {a.tagline}
              </p>
            )}
            <div className="flex flex-wrap gap-1 mt-2">
              {a.scopes.map((s) => (
                <span key={s} className="px-2 py-0.5 rounded-md bg-surface-800 text-surface-300 text-[10px]">
                  {t(`miniapps.scope.${s}`)}
                </span>
              ))}
            </div>
            <div className="text-[11px] text-surface-500 mt-1.5">
              {t("miniapps.installs")}: {fmtNum(a.install_count)}
              {mode === "mine" && ` · ${t("miniapps.opens")}: ${fmtNum(a.open_count)}`}
            </div>
            {mode === "mine" && a.review_note && (
              <div className="text-[11px] text-rose-400 mt-1">
                {t("miniapps.reviewNote")}: {a.review_note}
              </div>
            )}
            {mode === "mine" && secret?.app_id === a.app_id && (
              <div className="mt-2 p-2.5 rounded-xl bg-amber-500/8 border border-amber-500/20">
                <div className="text-[11px] text-amber-400 mb-1">{t("miniapps.secretOnce")}</div>
                <div className="flex items-center gap-2">
                  <code dir="ltr" className="flex-1 text-[11px] text-surface-100 break-all">
                    {secret.value}
                  </code>
                  <button onClick={() => copy(secret.value)}
                          className="text-surface-300 hover:text-surface-50 shrink-0">
                    <Copy className="w-3.5 h-3.5" />
                  </button>
                  <button onClick={() => setSecret(null)}
                          className="text-surface-300 hover:text-surface-50 shrink-0">
                    <X className="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>

        <div className="flex gap-2 mt-3">
          {mode === "store" && !a.is_installed && !a.is_mine && (
            <Button size="sm" onClick={() => install(a)}
                    disabled={busy === a.app_id} className="flex-1">
              <Plus className="w-3.5 h-3.5" />{t("miniapps.install")}
            </Button>
          )}
          {(a.is_installed || a.is_mine) && a.status === "approved" && (
            <Button size="sm" onClick={() => launch(a)}
                    disabled={busy === a.app_id} className="flex-1">
              <ExternalLink className="w-3.5 h-3.5" />{t("miniapps.open")}
            </Button>
          )}
          {mode === "installed" && (
            <Button size="sm" variant="ghost" onClick={() => uninstall(a)}
                    disabled={busy === a.app_id} className="flex-1">
              <Trash2 className="w-3.5 h-3.5" />{t("miniapps.uninstall")}
            </Button>
          )}
          {mode === "mine" && (a.status === "draft" || a.status === "rejected") && (
            <Button size="sm" onClick={() => submitApp(a)}
                    disabled={busy === a.app_id} className="flex-1">
              <Send className="w-3.5 h-3.5" />{t("miniapps.submit")}
            </Button>
          )}
          {mode === "mine" && (
            <Button size="sm" variant="ghost" onClick={() => rotate(a)}
                    disabled={busy === a.app_id} className="flex-1">
              <ShieldCheck className="w-3.5 h-3.5" />{t("miniapps.rotate")}
            </Button>
          )}
        </div>
      </div>
    );
  }

  if (loading) {
    return (
      <AppShell title={t("miniapps.title")}>
        <div className="page-inner flex justify-center py-20">
          <Loader2 className="w-6 h-6 animate-spin text-surface-400" />
        </div>
      </AppShell>
    );
  }

  return (
    <AppShell title={t("miniapps.title")}>
      <div className="page-inner space-y-4">
        <div className="flex gap-2 overflow-x-auto">
          {([
            ["store", t("miniapps.tabStore"), <Blocks key="i" className="w-4 h-4" />],
            ["installed", t("miniapps.tabInstalled"), <Check key="i" className="w-4 h-4" />],
            ["developer", t("miniapps.tabDeveloper"), <Plus key="i" className="w-4 h-4" />],
            ["payments", t("miniapps.tabPayments"), <Wallet key="i" className="w-4 h-4" />],
          ] as [Tab, string, React.ReactNode][]).map(([k, label, icon]) => (
            <button
              key={k}
              onClick={() => setTab(k)}
              className={`flex-1 min-w-[7rem] flex items-center justify-center gap-1.5 h-10 rounded-xl text-sm transition-colors ${
                tab === k
                  ? "bg-primary text-white"
                  : "bg-surface-800 text-surface-300 hover:bg-surface-700"
              }`}
            >
              {icon}
              {label}
            </button>
          ))}
        </div>

        {/* ── ویترین ────────────────────────────────────────────────────── */}
        {tab === "store" && (
          <div className="space-y-3">
            <div className="card p-3 flex items-center gap-2">
              <Search className="w-4 h-4 text-surface-400 shrink-0" />
              <input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                onKeyDown={(e) => { if (e.key === "Enter") loadStore(query.trim()); }}
                placeholder={t("miniapps.searchPh")}
                className="bg-transparent flex-1 outline-none text-sm text-surface-100"
              />
              <Button size="sm" onClick={() => loadStore(query.trim())}>
                {t("miniapps.search")}
              </Button>
            </div>
            {store.length === 0 && (
              <div className="card p-8 text-center text-surface-400 text-sm">
                {t("miniapps.emptyStore")}
              </div>
            )}
            {store.map((a) => <AppCard key={a.app_id} a={a} mode="store" />)}
          </div>
        )}

        {/* ── نصب‌شده‌ها ─────────────────────────────────────────────────── */}
        {tab === "installed" && (
          <div className="space-y-3">
            {installed.length === 0 && (
              <div className="card p-8 text-center text-surface-400 text-sm">
                {t("miniapps.emptyInstalled")}
              </div>
            )}
            {installed.map((a) => <AppCard key={a.app_id} a={a} mode="installed" />)}
          </div>
        )}

        {/* ── توسعه‌دهنده ────────────────────────────────────────────────── */}
        {tab === "developer" && (
          <div className="space-y-3">
            <div className="card p-4 space-y-3">
              <div className="font-semibold text-surface-50 text-sm">
                {t("miniapps.newApp")}
              </div>
              <input
                value={nName}
                onChange={(e) => setNName(e.target.value)}
                placeholder={t("miniapps.namePh")}
                className="w-full h-11 px-3 rounded-xl bg-surface-800 text-sm text-surface-100 outline-none"
              />
              <input
                value={nUrl}
                onChange={(e) => setNUrl(e.target.value)}
                dir="ltr"
                placeholder="https://example.com/app"
                className="w-full h-11 px-3 rounded-xl bg-surface-800 text-sm text-surface-100 outline-none"
              />
              <input
                value={nTagline}
                onChange={(e) => setNTagline(e.target.value)}
                placeholder={t("miniapps.taglinePh")}
                className="w-full h-11 px-3 rounded-xl bg-surface-800 text-sm text-surface-100 outline-none"
              />
              <select
                value={nCategory}
                onChange={(e) => setNCategory(e.target.value)}
                className="w-full h-11 px-3 rounded-xl bg-surface-800 text-sm text-surface-100 outline-none"
              >
                {CATEGORIES.map((c) => (
                  <option key={c} value={c}>{t(`miniapps.cat.${c}`)}</option>
                ))}
              </select>
              <div>
                <div className="text-xs text-surface-400 mb-1.5">{t("miniapps.scopes")}</div>
                <div className="flex flex-wrap gap-2">
                  {ALL_SCOPES.map((s) => (
                    <button
                      key={s}
                      onClick={() => toggleScope(s)}
                      className={`px-3 h-8 rounded-lg text-xs transition-colors ${
                        nScopes.includes(s)
                          ? "bg-primary text-white"
                          : "bg-surface-800 text-surface-300"
                      }`}
                    >
                      {t(`miniapps.scope.${s}`)}
                    </button>
                  ))}
                </div>
              </div>
              <Button onClick={createApp} disabled={creating} className="w-full">
                {creating
                  ? <Loader2 className="w-4 h-4 animate-spin" />
                  : <Plus className="w-4 h-4" />}
                {t("miniapps.create")}
              </Button>
              <p className="text-[11px] text-surface-500 leading-5">
                {t("miniapps.devHint")}
              </p>
            </div>

            {mine.map((a) => <AppCard key={a.app_id} a={a} mode="mine" />)}
          </div>
        )}

        {/* ── پرداخت‌های در انتظار ───────────────────────────────────────── */}
        {tab === "payments" && (
          <div className="space-y-3">
            {payments.length === 0 && (
              <div className="card p-8 text-center text-surface-400 text-sm">
                {t("miniapps.emptyPayments")}
              </div>
            )}
            {payments.map((p) => (
              <div key={p.ref} className="card p-4">
                <div className="font-semibold text-surface-50 truncate">{p.subject}</div>
                <div className="text-xs text-surface-400 mt-0.5">{p.app_name}</div>
                <div className="text-xs text-surface-500 mt-0.5" dir="ltr">{p.ref}</div>
                <div className="text-sm text-surface-200 mt-1.5">
                  <span className="font-bold">{fmtToman(p.amount)}</span> {t("miniapps.toman")}
                </div>
                <div className="flex gap-2 mt-3">
                  <Button size="sm" onClick={() => payAction(p, "confirm")}
                          disabled={busy === p.ref} className="flex-1">
                    <Check className="w-3.5 h-3.5" />{t("miniapps.pay")}
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => payAction(p, "cancel")}
                          disabled={busy === p.ref} className="flex-1">
                    <X className="w-3.5 h-3.5" />{t("miniapps.reject")}
                  </Button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </AppShell>
  );
}
