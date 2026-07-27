"use client";

import { useCallback, useEffect, useState } from "react";
import {
  Bookmark, BookmarkPlus, CheckCircle2, FileText, Loader2,
  Receipt, Search, Trash2, Wallet as WalletIcon,
} from "lucide-react";
import toast from "react-hot-toast";

import AppShell from "@/components/layout/AppShell";
import { Button } from "@/components/ui/Button";
import { billsApi, getApiErrorMessage } from "@/lib/api";
import { toPersianNum } from "@/lib/utils";
import { useTranslation } from "@/store/i18n";

// مبالغ از سرور در ریال می‌آید و کاربرِ ایرانی تومان می‌خواند.
function fmtToman(rial: number): string {
  return toPersianNum(Math.round((rial || 0) / 10).toLocaleString("en-US"));
}

function fmtDate(iso: string): string {
  try {
    return toPersianNum(
      new Date(iso).toLocaleDateString("fa-IR", {
        year: "numeric", month: "long", day: "numeric",
      })
    );
  } catch {
    return "";
  }
}

interface BillType {
  key: string;
  label: string;
  emoji: string;
  org_digit: string;
}

interface Decoded {
  bill_id: string;
  payment_id: string;
  type_key: string;
  type_label: string;
  type_emoji: string;
  amount: number;
  year?: number | null;
  period?: number | null;
  already_paid: boolean;
  paid_ref?: string | null;
  balance_enough: boolean;
}

interface Receipt {
  id: string;
  ref: string;
  bill_id: string;
  payment_id: string;
  type_key: string;
  type_label: string;
  type_emoji: string;
  amount: number;
  title?: string | null;
  paid_at: string;
}

interface Saved {
  id: string;
  title: string;
  bill_id: string;
  type_key: string;
  type_label: string;
  type_emoji: string;
  created_at: string;
}

type Tab = "pay" | "history" | "saved";

export default function BillsPage() {
  const { t } = useTranslation();
  const [tab, setTab] = useState<Tab>("pay");

  const [types, setTypes] = useState<BillType[]>([]);
  const [billId, setBillId] = useState("");
  const [paymentId, setPaymentId] = useState("");
  const [barcode, setBarcode] = useState("");
  const [useBarcode, setUseBarcode] = useState(false);
  const [title, setTitle] = useState("");

  const [decoded, setDecoded] = useState<Decoded | null>(null);
  const [checking, setChecking] = useState(false);
  const [paying, setPaying] = useState(false);
  const [done, setDone] = useState<Receipt | null>(null);

  const [history, setHistory] = useState<Receipt[]>([]);
  const [saved, setSaved] = useState<Saved[]>([]);
  const [loadingList, setLoadingList] = useState(false);
  const [savingId, setSavingId] = useState(false);

  useEffect(() => {
    billsApi.types().then((r) => setTypes(r.data)).catch(() => {});
  }, []);

  const loadHistory = useCallback(async () => {
    setLoadingList(true);
    try {
      const r = await billsApi.history();
      setHistory(r.data);
    } catch (e) {
      toast.error(getApiErrorMessage(e, t("bills.loadFailed")));
    } finally {
      setLoadingList(false);
    }
  }, [t]);

  const loadSaved = useCallback(async () => {
    setLoadingList(true);
    try {
      const r = await billsApi.saved();
      setSaved(r.data);
    } catch (e) {
      toast.error(getApiErrorMessage(e, t("bills.loadFailed")));
    } finally {
      setLoadingList(false);
    }
  }, [t]);

  useEffect(() => {
    if (tab === "history") loadHistory();
    if (tab === "saved") loadSaved();
  }, [tab, loadHistory, loadSaved]);

  // بدنهٔ مشترکِ استعلام و پرداخت — یا بارکد، یا زوجِ شناسه.
  const body = () =>
    useBarcode ? { barcode } : { bill_id: billId, payment_id: paymentId };

  const resetForm = () => {
    setBillId("");
    setPaymentId("");
    setBarcode("");
    setTitle("");
    setDecoded(null);
  };

  const inquire = async () => {
    setChecking(true);
    setDone(null);
    try {
      const r = await billsApi.inquiry(body());
      setDecoded(r.data);
    } catch (e) {
      setDecoded(null);
      toast.error(getApiErrorMessage(e, t("bills.invalid")));
    } finally {
      setChecking(false);
    }
  };

  const pay = async () => {
    setPaying(true);
    try {
      const r = await billsApi.pay({ ...body(), title: title.trim() || undefined });
      setDone(r.data);
      setDecoded(null);
      resetForm();
      toast.success(t("bills.paidOk"));
    } catch (e) {
      toast.error(getApiErrorMessage(e, t("bills.payFailed")));
    } finally {
      setPaying(false);
    }
  };

  // شناسهٔ قبض برای هر اشتراک ثابت است، پس ذخیره‌اش دورهٔ بعد را یک‌کلیکی می‌کند.
  const saveCurrent = async () => {
    const id = decoded?.bill_id || billId;
    if (!id) return;
    setSavingId(true);
    try {
      await billsApi.save(title.trim() || decoded?.type_label || t("bills.myBill"), id);
      toast.success(t("bills.savedOk"));
    } catch (e) {
      toast.error(getApiErrorMessage(e, t("bills.saveFailed")));
    } finally {
      setSavingId(false);
    }
  };

  const removeSaved = async (s: Saved) => {
    try {
      await billsApi.unsave(s.id);
      setSaved((prev) => prev.filter((x) => x.id !== s.id));
    } catch (e) {
      toast.error(getApiErrorMessage(e, t("bills.deleteFailed")));
    }
  };

  const useSaved = (s: Saved) => {
    setTab("pay");
    setUseBarcode(false);
    setBillId(s.bill_id);
    setPaymentId("");
    setTitle(s.title);
    setDecoded(null);
    setDone(null);
  };

  const canInquire = useBarcode ? barcode.trim().length >= 20 : billId.trim() && paymentId.trim();

  return (
    <AppShell title={t("bills.title")}>
      <div className="page-inner space-y-4">
        {/* تب‌ها */}
        <div className="flex gap-2">
          {([
            ["pay", t("bills.tabPay"), <Receipt key="i" className="w-4 h-4" />],
            ["history", t("bills.tabHistory"), <FileText key="i" className="w-4 h-4" />],
            ["saved", t("bills.tabSaved"), <Bookmark key="i" className="w-4 h-4" />],
          ] as [Tab, string, React.ReactNode][]).map(([k, label, icon]) => (
            <button
              key={k}
              onClick={() => setTab(k)}
              className={`flex-1 flex items-center justify-center gap-1.5 h-10 rounded-xl text-sm transition-colors ${
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

        {tab === "pay" && (
          <div className="space-y-4">
            {/* انواعِ قبضِ پشتیبانی‌شده — راهنما، نه انتخاب: نوعِ قبض از خودِ
                شناسه خوانده می‌شود و نیازی به انتخابِ دستی نیست. */}
            {types.length > 0 && (
              <div className="flex flex-wrap gap-1.5">
                {types.map((x) => (
                  <span
                    key={x.key}
                    className="px-2.5 py-1 rounded-lg bg-surface-800 text-surface-300 text-xs"
                  >
                    {x.emoji} {x.label}
                  </span>
                ))}
              </div>
            )}

            <div className="card p-4 space-y-3">
              <div className="flex items-center gap-2">
                <button
                  onClick={() => { setUseBarcode(false); setDecoded(null); }}
                  className={`px-3 h-8 rounded-lg text-xs ${
                    !useBarcode ? "bg-primary text-white" : "bg-surface-800 text-surface-300"
                  }`}
                >
                  {t("bills.byIds")}
                </button>
                <button
                  onClick={() => { setUseBarcode(true); setDecoded(null); }}
                  className={`px-3 h-8 rounded-lg text-xs ${
                    useBarcode ? "bg-primary text-white" : "bg-surface-800 text-surface-300"
                  }`}
                >
                  {t("bills.byBarcode")}
                </button>
              </div>

              {useBarcode ? (
                <div>
                  <label className="block text-xs text-surface-400 mb-1">
                    {t("bills.barcode")}
                  </label>
                  <input
                    value={barcode}
                    onChange={(e) => { setBarcode(e.target.value); setDecoded(null); }}
                    inputMode="numeric"
                    placeholder={t("bills.barcodePh")}
                    className="input w-full font-mono"
                    dir="ltr"
                  />
                </div>
              ) : (
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div>
                    <label className="block text-xs text-surface-400 mb-1">
                      {t("bills.billId")}
                    </label>
                    <input
                      value={billId}
                      onChange={(e) => { setBillId(e.target.value); setDecoded(null); }}
                      inputMode="numeric"
                      placeholder={t("bills.billIdPh")}
                      className="input w-full font-mono"
                      dir="ltr"
                    />
                  </div>
                  <div>
                    <label className="block text-xs text-surface-400 mb-1">
                      {t("bills.paymentId")}
                    </label>
                    <input
                      value={paymentId}
                      onChange={(e) => { setPaymentId(e.target.value); setDecoded(null); }}
                      inputMode="numeric"
                      placeholder={t("bills.paymentIdPh")}
                      className="input w-full font-mono"
                      dir="ltr"
                    />
                  </div>
                </div>
              )}

              <div>
                <label className="block text-xs text-surface-400 mb-1">
                  {t("bills.label")}
                </label>
                <input
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  maxLength={120}
                  placeholder={t("bills.labelPh")}
                  className="input w-full"
                />
              </div>

              <Button
                fullWidth
                onClick={inquire}
                loading={checking}
                disabled={!canInquire}
                leftIcon={<Search className="w-4 h-4" />}
              >
                {t("bills.inquiry")}
              </Button>
              <p className="text-[11px] text-surface-500 leading-relaxed">
                {t("bills.hint")}
              </p>
            </div>

            {/* نتیجهٔ استعلام */}
            {decoded && (
              <div className="card p-4 space-y-3 border border-primary/30">
                <div className="flex items-center gap-2">
                  <span className="text-2xl">{decoded.type_emoji}</span>
                  <div className="flex-1">
                    <p className="font-semibold">{decoded.type_label}</p>
                    <p className="text-xs text-surface-400 font-mono" dir="ltr">
                      {decoded.bill_id} / {decoded.payment_id}
                    </p>
                  </div>
                </div>

                <div className="flex items-baseline gap-1.5">
                  <span className="text-2xl font-bold text-primary">
                    {fmtToman(decoded.amount)}
                  </span>
                  <span className="text-sm text-surface-400">{t("bills.toman")}</span>
                </div>

                {decoded.period != null && (
                  <p className="text-xs text-surface-400">
                    {t("bills.period")}: {toPersianNum(String(decoded.period))}
                  </p>
                )}

                {decoded.already_paid ? (
                  <div className="rounded-xl bg-surface-800 p-3 text-sm text-surface-300">
                    {t("bills.alreadyPaid")}
                    {decoded.paid_ref && (
                      <span className="font-mono block mt-1 text-xs" dir="ltr">
                        {decoded.paid_ref}
                      </span>
                    )}
                  </div>
                ) : !decoded.balance_enough ? (
                  <div className="rounded-xl bg-amber-500/10 text-amber-400 p-3 text-sm flex items-center gap-2">
                    <WalletIcon className="w-4 h-4 shrink-0" />
                    {t("bills.noBalance")}
                  </div>
                ) : (
                  <Button
                    fullWidth
                    onClick={pay}
                    loading={paying}
                    leftIcon={<WalletIcon className="w-4 h-4" />}
                  >
                    {t("bills.payBtn")}
                  </Button>
                )}

                <Button
                  fullWidth
                  variant="ghost"
                  onClick={saveCurrent}
                  loading={savingId}
                  leftIcon={<BookmarkPlus className="w-4 h-4" />}
                >
                  {t("bills.saveBtn")}
                </Button>
              </div>
            )}

            {/* رسیدِ پرداخت */}
            {done && (
              <div className="card p-4 space-y-2 border border-emerald-500/30">
                <div className="flex items-center gap-2 text-emerald-400">
                  <CheckCircle2 className="w-5 h-5" />
                  <p className="font-semibold">{t("bills.receipt")}</p>
                </div>
                <p className="text-sm">
                  {done.type_emoji} {done.type_label} —{" "}
                  <span className="font-bold">{fmtToman(done.amount)}</span>{" "}
                  {t("bills.toman")}
                </p>
                <p className="text-xs text-surface-400 font-mono" dir="ltr">
                  {done.ref}
                </p>
                <p className="text-xs text-surface-500">{fmtDate(done.paid_at)}</p>
              </div>
            )}
          </div>
        )}

        {tab === "history" && (
          <div className="space-y-2">
            {loadingList ? (
              <div className="flex justify-center py-10">
                <Loader2 className="w-6 h-6 animate-spin text-surface-500" />
              </div>
            ) : history.length === 0 ? (
              <p className="text-center text-sm text-surface-500 py-10">
                {t("bills.emptyHistory")}
              </p>
            ) : (
              history.map((b) => (
                <div key={b.id} className="card p-3 flex items-center gap-3">
                  <span className="text-xl">{b.type_emoji}</span>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium truncate">
                      {b.title || b.type_label}
                    </p>
                    <p className="text-xs text-surface-500 font-mono" dir="ltr">
                      {b.ref}
                    </p>
                  </div>
                  <div className="text-end shrink-0">
                    <p className="text-sm font-bold">{fmtToman(b.amount)}</p>
                    <p className="text-[11px] text-surface-500">{fmtDate(b.paid_at)}</p>
                  </div>
                </div>
              ))
            )}
          </div>
        )}

        {tab === "saved" && (
          <div className="space-y-2">
            {loadingList ? (
              <div className="flex justify-center py-10">
                <Loader2 className="w-6 h-6 animate-spin text-surface-500" />
              </div>
            ) : saved.length === 0 ? (
              <p className="text-center text-sm text-surface-500 py-10">
                {t("bills.emptySaved")}
              </p>
            ) : (
              saved.map((s) => (
                <div key={s.id} className="card p-3 flex items-center gap-3">
                  <span className="text-xl">{s.type_emoji}</span>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium truncate">{s.title}</p>
                    <p className="text-xs text-surface-500 font-mono" dir="ltr">
                      {s.bill_id}
                    </p>
                  </div>
                  <Button size="sm" variant="ghost" onClick={() => useSaved(s)}>
                    {t("bills.useSaved")}
                  </Button>
                  <button
                    onClick={() => removeSaved(s)}
                    className="p-2 text-surface-500 hover:text-error"
                    aria-label={t("bills.deleteSaved")}
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>
              ))
            )}
          </div>
        )}
      </div>
    </AppShell>
  );
}
