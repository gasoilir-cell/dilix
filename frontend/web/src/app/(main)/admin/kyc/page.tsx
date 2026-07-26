"use client";

import { useState, useEffect, useCallback } from "react";
import { useRouter } from "next/navigation";
import {
  ShieldCheck, Loader2, Check, X, Clock, CheckCircle2, XCircle,
  ExternalLink, RefreshCw, Lock,
} from "lucide-react";
import { useAuthStore } from "@/store/auth";
import { authApi, getApiErrorMessage } from "@/lib/api";
import { Button } from "@/components/ui/Button";
import AppShell from "@/components/layout/AppShell";
import { toPersianNum } from "@/lib/utils";
import toast from "react-hot-toast";
import { useTranslation } from "@/store/i18n";

interface KycReq {
  id: string;
  user_id: string;
  level: number;
  full_name: string;
  national_id: string;
  date_of_birth: string;
  doc_front_url: string | null;
  doc_selfie_url: string | null;
  status: string;
  created_at: string | null;
}

type Tab = "pending" | "approved" | "rejected" | "all";

const TABS: { key: Tab; label: string; Icon: typeof Clock }[] = [
  { key: "pending",  label: "kyc.tab.pending",  Icon: Clock },
  { key: "approved", label: "kyc.tab.approved", Icon: CheckCircle2 },
  { key: "rejected", label: "kyc.tab.rejected", Icon: XCircle },
  { key: "all",      label: "kyc.tab.all",      Icon: ShieldCheck },
];

export default function AdminKycPage() {
  const { t } = useTranslation();
  const router = useRouter();
  const { user } = useAuthStore();
  const isAdmin = user?.role === "admin" || user?.role === "super_admin";

  const [tab, setTab] = useState<Tab>("pending");
  const [items, setItems] = useState<KycReq[]>([]);
  const [loading, setLoading] = useState(true);
  const [acting, setActing] = useState<string | null>(null);
  const [notes, setNotes] = useState<Record<string, string>>({});

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await authApi.adminKycList(tab);
      setItems(res.data || []);
    } catch (err) {
      toast.error(getApiErrorMessage(err, t("kyc.toast.loadErr")));
    } finally {
      setLoading(false);
    }
  }, [tab]);

  useEffect(() => {
    if (isAdmin) load();
  }, [isAdmin, load]);

  const review = async (req: KycReq, approve: boolean) => {
    if (acting) return;
    const note = (notes[req.id] || "").trim();
    if (!approve && note.length < 3) {
      toast.error(t("kyc.toast.noteRequired"));
      return;
    }
    setActing(req.id);
    try {
      await authApi.adminKycReview(req.id, approve, approve ? undefined : note);
      toast.success(approve ? t("kyc.toast.approved") : t("kyc.toast.rejected"));
      setItems((prev) => prev.filter((x) => x.id !== req.id || tab === "all"));
      if (tab === "all") load();
    } catch (err) {
      toast.error(getApiErrorMessage(err, t("kyc.toast.reviewErr")));
    } finally {
      setActing(null);
    }
  };

  if (!user) return null;

  if (!isAdmin) {
    return (
      <AppShell title={t("kyc.title")}>
        <div className="page-inner flex flex-col items-center justify-center py-20 text-center gap-3">
          <Lock size={40} className="text-surface-500" />
          <p className="text-sm text-surface-300">{t("kyc.admin.only")}</p>
          <Button variant="outline" size="sm" onClick={() => router.push("/dashboard")}>{t("kyc.btn.dashboard")}</Button>
        </div>
      </AppShell>
    );
  }

  return (
    <AppShell title={t("kyc.title")}>
      <div className="page-inner pb-safe">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2.5">
            <ShieldCheck size={22} className="text-primary-400" />
            <div>
              <h1 className="text-base font-bold text-white">{t("kyc.h1")}</h1>
              <p className="text-xs text-surface-400">{t("kyc.subtitle")}</p>
            </div>
          </div>
          <button onClick={load} className="p-2 rounded-lg bg-surface-800 text-surface-300 hover:bg-surface-700">
            <RefreshCw size={16} className={loading ? "animate-spin" : ""} />
          </button>
        </div>

        {/* Tabs */}
        <div className="flex gap-1.5 mb-4 overflow-x-auto no-scrollbar">
          {TABS.map(({ key, label, Icon }) => (
            <button
              key={key}
              onClick={() => setTab(key)}
              className={`flex items-center gap-1.5 rounded-full px-3.5 py-1.5 text-xs whitespace-nowrap transition ${
                tab === key ? "bg-primary-500 text-white" : "bg-surface-800 text-surface-300 hover:bg-surface-700"
              }`}
            >
              <Icon size={13} />
              {t(label)}
            </button>
          ))}
        </div>

        {loading ? (
          <div className="flex justify-center py-16">
            <Loader2 size={24} className="text-primary-400 animate-spin" />
          </div>
        ) : items.length === 0 ? (
          <div className="text-center py-16 text-surface-500 text-sm">{t("kyc.empty")}</div>
        ) : (
          <div className="space-y-3">
            {items.map((req) => {
              const statusMeta =
                req.status === "approved" ? { c: "text-accent-400", lk: "kyc.tab.approved" }
                : req.status === "rejected" ? { c: "text-rose-400", lk: "kyc.tab.rejected" }
                : { c: "text-yellow-400", lk: "kyc.tab.pending" };
              return (
                <div key={req.id} className="card p-4 space-y-3">
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <p className="text-sm font-semibold text-white truncate">{req.full_name}</p>
                      <p className="text-xs text-surface-400 font-mono ltr text-left">{toPersianNum(req.national_id)}</p>
                    </div>
                    <span className={`text-[11px] shrink-0 ${statusMeta.c}`}>{t(statusMeta.lk)}</span>
                  </div>

                  <div className="grid grid-cols-2 gap-2 text-xs">
                    <div className="bg-surface-800/50 rounded-lg p-2">
                      <span className="text-surface-500 block">{t("kyc.field.dob")}</span>
                      <span className="text-surface-200 ltr">{req.date_of_birth || "—"}</span>
                    </div>
                    <div className="bg-surface-800/50 rounded-lg p-2">
                      <span className="text-surface-500 block">{t("kyc.field.level")}</span>
                      <span className="text-surface-200">{toPersianNum(req.level)}</span>
                    </div>
                  </div>

                  <div className="grid grid-cols-2 gap-2">
                    {[
                      { url: req.doc_front_url, label: "kyc.doc.front" },
                      { url: req.doc_selfie_url, label: "kyc.doc.selfie" },
                    ].map(({ url, label }) => (
                      <a
                        key={label}
                        href={url || "#"}
                        target="_blank"
                        rel="noreferrer"
                        className={`relative block rounded-xl overflow-hidden border border-surface-700 aspect-video bg-surface-800 ${url ? "" : "pointer-events-none opacity-50"}`}
                      >
                        {url ? <img src={url} alt={t(label)} className="w-full h-full object-cover" /> : null}
                        <span className="absolute bottom-0 inset-x-0 bg-black/60 text-[10px] text-white px-2 py-1 flex items-center justify-between">
                          {t(label)}
                          <ExternalLink size={11} />
                        </span>
                      </a>
                    ))}
                  </div>

                  {req.status === "pending" && (
                    <>
                      <input
                        value={notes[req.id] || ""}
                        onChange={(e) => setNotes((n) => ({ ...n, [req.id]: e.target.value }))}
                        placeholder={t("kyc.ph.note")}
                        className="w-full bg-surface-800 border border-surface-700 rounded-xl px-3 py-2 text-white text-xs placeholder-surface-500 focus:outline-none focus:border-primary-500"
                      />
                      <div className="grid grid-cols-2 gap-2">
                        <Button variant="danger" size="sm" onClick={() => review(req, false)} disabled={acting !== null}>
                          {acting === req.id ? <Loader2 size={15} className="animate-spin" /> : <><X size={15} className="ml-1" /> {t("kyc.btn.reject")}</>}
                        </Button>
                        <Button variant="primary" size="sm" onClick={() => review(req, true)} disabled={acting !== null}>
                          {acting === req.id ? <Loader2 size={15} className="animate-spin" /> : <><Check size={15} className="ml-1" /> {t("kyc.btn.approve")}</>}
                        </Button>
                      </div>
                    </>
                  )}

                  {req.created_at && (
                    <p className="text-[10px] text-surface-500 text-left">
                      {new Date(req.created_at).toLocaleString("fa-IR")}
                    </p>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>
    </AppShell>
  );
}
