"use client";

import { useState, useEffect, useCallback } from "react";
import AppShell from "@/components/layout/AppShell";
import {
  Wallet, ArrowDownLeft, ArrowUpRight, Clock,
  CheckCircle2, XCircle, Plus, Minus, Send, Eye,
  EyeOff, CreditCard, Loader2, RefreshCw, AlertCircle,
} from "lucide-react";
import { Button } from "@/components/ui/Button";
import { toPersianNum, formatAmount } from "@/lib/utils";
import { walletApi, paymentApi } from "@/lib/api";
import toast from "react-hot-toast";

type TxType =
  | "deposit" | "withdrawal" | "transfer_in" | "transfer_out"
  | "escrow_lock" | "escrow_release" | "bonus_credit" | "fee_deduct";
type TxStatus = "pending" | "completed" | "failed" | "cancelled" | "reversed";

interface WalletData {
  id: string;
  currency: string;
  balance_available: number;
  balance_escrow: number;
  balance_bonus: number;
  is_frozen: boolean;
}

interface Transaction {
  id: string;
  type: TxType;
  status: TxStatus;
  amount: number;
  balance_before: number;
  balance_after: number;
  description: string | null;
  created_at: string;
}

const TX_META: Record<string, { label: string; icon: React.ElementType; color: string; sign: "+" | "-" }> = {
  deposit:         { label: "واریز",             icon: ArrowDownLeft,  color: "text-emerald-400", sign: "+" },
  withdrawal:      { label: "برداشت",            icon: ArrowUpRight,   color: "text-red-400",     sign: "-" },
  transfer_in:     { label: "دریافت",            icon: ArrowDownLeft,  color: "text-blue-400",    sign: "+" },
  transfer_out:    { label: "انتقال",            icon: ArrowUpRight,   color: "text-orange-400",  sign: "-" },
  escrow_lock:     { label: "بلوکه اسکرو",       icon: Clock,          color: "text-yellow-400",  sign: "-" },
  escrow_release:  { label: "آزادسازی اسکرو",    icon: CheckCircle2,   color: "text-emerald-400", sign: "+" },
  bonus_credit:    { label: "جایزه",             icon: Plus,           color: "text-purple-400",  sign: "+" },
  fee_deduct:      { label: "کارمزد",            icon: Minus,          color: "text-red-400",     sign: "-" },
};

const STATUS_ICON: Record<string, React.ElementType> = {
  pending:   Clock,
  completed: CheckCircle2,
  failed:    XCircle,
  cancelled: XCircle,
  reversed:  XCircle,
};

type ModalType = "deposit" | "withdraw" | "transfer" | null;

function formatDate(iso: string): string {
  try {
    const d = new Date(iso);
    return d.toLocaleDateString("fa-IR", { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
  } catch {
    return iso;
  }
}

export default function WalletPage() {
  const [wallet,   setWallet]   = useState<WalletData | null>(null);
  const [txs,      setTxs]      = useState<Transaction[]>([]);
  const [loading,  setLoading]  = useState(true);
  const [txPage,   setTxPage]   = useState(1);
  const [hasMore,  setHasMore]  = useState(true);
  const [hideBalance, setHideBalance] = useState(false);
  const [modal,    setModal]    = useState<ModalType>(null);
  const [amount,   setAmount]   = useState("");
  const [toEarthId, setToEarthId] = useState("");
  const [desc,     setDesc]     = useState("");
  const [sending,  setSending]  = useState(false);
  const [activeTab, setActiveTab] = useState<"all" | "in" | "out">("all");

  const loadWallet = useCallback(async () => {
    try {
      const res = await walletApi.get();
      setWallet(res.data);
    } catch {
      toast.error("خطا در بارگذاری کیف پول");
    }
  }, []);

  const loadTxs = useCallback(async (page: number, reset = false) => {
    try {
      const res = await walletApi.transactions(page);
      const data: Transaction[] = res.data;
      setTxs(prev => reset ? data : [...prev, ...data]);
      setHasMore(data.length === 20);
    } catch {
      // ignore
    }
  }, []);

  useEffect(() => {
    const init = async () => {
      setLoading(true);
      await Promise.all([loadWallet(), loadTxs(1, true)]);
      setLoading(false);
    };
    init();
  }, [loadWallet, loadTxs]);

  const handleDeposit = async () => {
    const amt = Number(amount);
    if (!amt || amt < 10000) { toast.error("حداقل مبلغ ۱۰,۰۰۰ تومان است"); return; }
    setSending(true);
    try {
      const res = await paymentApi.initiate(amt * 10, "IRR", "شارژ کیف پول دیلیکس");
      if (res.data.payment_url) {
        window.location.href = res.data.payment_url;
      } else {
        toast.error(res.data.error || "خطا در اتصال به درگاه پرداخت");
      }
    } catch {
      toast.error("خطا در اتصال به درگاه پرداخت");
    } finally {
      setSending(false);
    }
  };

  const handleTransfer = async () => {
    const amt = Number(amount);
    if (!toEarthId.startsWith("DLX-")) { toast.error("Earth ID معتبر نیست"); return; }
    if (!amt || amt < 1000) { toast.error("حداقل مبلغ ۱,۰۰۰ تومان است"); return; }
    setSending(true);
    try {
      await walletApi.transfer(toEarthId, amt, desc || undefined);
      toast.success(`${toPersianNum(amt.toLocaleString())} تومان منتقل شد ✅`);
      setModal(null);
      setAmount("");
      setToEarthId("");
      setDesc("");
      await loadWallet();
      setTxPage(1);
      await loadTxs(1, true);
    } catch (e: any) {
      toast.error(e?.response?.data?.detail || "خطا در انتقال وجه");
    } finally {
      setSending(false);
    }
  };

  const filtered = txs.filter((tx) => {
    const meta = TX_META[tx.type];
    if (!meta) return activeTab === "all";
    if (activeTab === "in")  return meta.sign === "+";
    if (activeTab === "out") return meta.sign === "-";
    return true;
  });

  const total = wallet
    ? wallet.balance_available + wallet.balance_escrow + wallet.balance_bonus
    : 0;

  const QUICK_AMOUNTS = [100000, 500000, 1000000, 2000000];

  if (loading) {
    return (
      <AppShell title="کیف پول">
        <div className="flex items-center justify-center h-48">
          <Loader2 size={32} className="text-primary-400 animate-spin" />
        </div>
      </AppShell>
    );
  }

  if (!wallet) {
    return (
      <AppShell title="کیف پول">
        <div className="page-inner flex flex-col items-center justify-center h-48 gap-3">
          <AlertCircle size={40} className="text-red-400" />
          <p className="text-surface-400">کیف پول شما هنوز فعال نشده است</p>
          <Button variant="primary" size="sm" onClick={loadWallet}>تلاش مجدد</Button>
        </div>
      </AppShell>
    );
  }

  return (
    <AppShell title="کیف پول">
      <div className="page-inner">
        {/* Balance Card */}
        <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-indigo-900 via-indigo-950 to-[#0A0A0A] border border-indigo-700/30 p-5 mb-5">
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_bottom_right,#4f46e5_0%,transparent_70%)] opacity-20 pointer-events-none" />

          {wallet.is_frozen && (
            <div className="relative mb-3 flex items-center gap-2 bg-red-500/10 border border-red-500/30 rounded-xl p-2.5">
              <AlertCircle size={16} className="text-red-400" />
              <p className="text-sm text-red-300">کیف پول مسدود است</p>
            </div>
          )}

          <div className="relative">
            <div className="flex items-center justify-between mb-1">
              <p className="text-indigo-300 text-sm">موجودی کل</p>
              <div className="flex items-center gap-2">
                <button onClick={() => { setTxPage(1); loadTxs(1, true); loadWallet(); }}
                  className="p-1 hover:text-white text-indigo-300 transition-colors">
                  <RefreshCw size={14} />
                </button>
                <button onClick={() => setHideBalance(!hideBalance)} className="p-1">
                  {hideBalance
                    ? <EyeOff size={16} className="text-indigo-300" />
                    : <Eye    size={16} className="text-indigo-300" />}
                </button>
              </div>
            </div>

            <div className="flex items-baseline gap-2 mb-4">
              <p className="text-4xl font-bold text-white tracking-tight">
                {hideBalance ? "••••••" : toPersianNum(total.toLocaleString())}
              </p>
              <p className="text-indigo-300 text-sm">تومان</p>
            </div>

            <div className="grid grid-cols-3 gap-3">
              {[
                { label: "آزاد",    value: wallet.balance_available, color: "text-white"         },
                { label: "اسکرو",   value: wallet.balance_escrow,    color: "text-yellow-300"    },
                { label: "جایزه",   value: wallet.balance_bonus,     color: "text-purple-300"    },
              ].map((b) => (
                <div key={b.label} className="bg-white/5 rounded-xl p-2.5">
                  <p className="text-xs text-indigo-300/70 mb-1">{b.label}</p>
                  <p className={`text-sm font-semibold ${b.color}`}>
                    {hideBalance ? "••••" : toPersianNum(b.value.toLocaleString())}
                  </p>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* Action buttons */}
        <div className="grid grid-cols-3 gap-3 mb-5">
          {[
            { label: "شارژ",    icon: Plus,         modal: "deposit"  as ModalType, bg: "bg-emerald-600" },
            { label: "برداشت",  icon: ArrowUpRight,  modal: "withdraw" as ModalType, bg: "bg-red-700"     },
            { label: "انتقال",  icon: Send,          modal: "transfer" as ModalType, bg: "bg-indigo-600"  },
          ].map((btn) => (
            <button
              key={btn.label}
              onClick={() => setModal(btn.modal)}
              className="flex flex-col items-center gap-2 py-4 rounded-xl bg-[#1C1C1E] hover:bg-[#2C2C2E] transition-colors border border-white/8"
            >
              <div className={`w-10 h-10 rounded-xl ${btn.bg} flex items-center justify-center`}>
                <btn.icon size={20} className="text-white" />
              </div>
              <p className="text-sm font-medium text-white/80">{btn.label}</p>
            </button>
          ))}
        </div>

        {/* Transactions */}
        <div className="flex items-center justify-between mb-3">
          <h2 className="font-bold text-white">تراکنش‌ها</h2>
          <div className="flex gap-1 bg-[#1C1C1E] rounded-lg p-0.5">
            {[
              { id: "all" as const, label: "همه"    },
              { id: "in"  as const, label: "دریافت" },
              { id: "out" as const, label: "پرداخت" },
            ].map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`px-3 py-1 rounded-md text-xs font-medium transition-all ${
                  activeTab === tab.id
                    ? "bg-indigo-600 text-white"
                    : "text-white/40 hover:text-white/70"
                }`}
              >
                {tab.label}
              </button>
            ))}
          </div>
        </div>

        {filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 gap-3">
            <Wallet size={40} className="text-white/20" />
            <p className="text-white/40 text-sm">تراکنشی ثبت نشده</p>
          </div>
        ) : (
          <div className="space-y-2">
            {filtered.map((tx) => {
              const meta = TX_META[tx.type] ?? { label: tx.type, icon: Clock, color: "text-white/60", sign: "+" as const };
              const StatusIcon = STATUS_ICON[tx.status] ?? Clock;
              return (
                <div key={tx.id} className="bg-[#1C1C1E] border border-white/8 rounded-xl p-3.5 flex items-center gap-3">
                  <div className={`w-10 h-10 rounded-xl bg-white/5 flex items-center justify-center flex-shrink-0 ${meta.color}`}>
                    <meta.icon size={20} />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold text-white truncate">
                      {tx.description || meta.label}
                    </p>
                    <div className="flex items-center gap-1.5 mt-0.5">
                      <StatusIcon size={11} className={
                        tx.status === "completed" ? "text-emerald-400" :
                        tx.status === "pending"   ? "text-yellow-400"  : "text-red-400"
                      } />
                      <p className="text-xs text-white/30">{formatDate(tx.created_at)}</p>
                    </div>
                  </div>
                  <p className={`text-sm font-bold flex-shrink-0 ${meta.sign === "+" ? "text-emerald-400" : "text-red-400"}`}>
                    {meta.sign}{toPersianNum(tx.amount.toLocaleString())} ت
                  </p>
                </div>
              );
            })}

            {hasMore && (
              <button
                onClick={() => { const next = txPage + 1; setTxPage(next); loadTxs(next); }}
                className="w-full py-3 rounded-xl bg-[#1C1C1E] text-white/50 text-sm hover:text-white/80 transition-colors"
              >
                بارگذاری بیشتر
              </button>
            )}
          </div>
        )}

        {/* Modals */}
        {modal && (
          <>
            <div className="fixed inset-0 bg-black/70 z-40" onClick={() => { setModal(null); setAmount(""); }} />
            <div className="fixed bottom-0 inset-x-0 z-50 bg-[#1C1C1E] rounded-t-2xl p-5 pb-10 border-t border-white/8">
              <div className="w-10 h-1 bg-white/10 rounded-full mx-auto mb-5" />
              <h2 className="text-lg font-bold text-white mb-5">
                {modal === "deposit" ? "شارژ کیف پول" : modal === "withdraw" ? "برداشت وجه" : "انتقال وجه"}
              </h2>

              {modal === "deposit" && (
                <div className="space-y-4">
                  <div className="grid grid-cols-4 gap-2">
                    {QUICK_AMOUNTS.map((qa) => (
                      <button
                        key={qa}
                        onClick={() => setAmount(String(qa))}
                        className={`py-2.5 rounded-xl text-sm font-medium border transition-all ${
                          amount === String(qa)
                            ? "border-indigo-500 bg-indigo-500/10 text-indigo-300"
                            : "border-white/10 text-white/50 hover:border-white/30"
                        }`}
                      >
                        {toPersianNum((qa / 1000))}K
                      </button>
                    ))}
                  </div>
                  <input
                    value={amount}
                    onChange={(e) => setAmount(e.target.value.replace(/\D/g, ""))}
                    placeholder="مبلغ دلخواه (تومان)"
                    className="w-full bg-[#262626] border border-white/10 rounded-xl p-4 text-white text-center text-lg placeholder-white/30 focus:outline-none focus:border-indigo-500"
                    inputMode="numeric"
                  />
                  <div className="flex gap-2 bg-white/5 rounded-xl p-3">
                    <CreditCard size={18} className="text-indigo-400 flex-shrink-0 mt-0.5" />
                    <div>
                      <p className="text-sm font-medium text-white">درگاه پرداخت آنلاین</p>
                      <p className="text-xs text-white/40">ریدایرکت به درگاه بانکی (شاپرک)</p>
                    </div>
                  </div>
                  <Button
                    variant="primary" size="lg" fullWidth
                    disabled={!amount || Number(amount) < 10000 || sending}
                    onClick={handleDeposit}
                  >
                    {sending
                      ? <><Loader2 size={16} className="animate-spin ml-2" />در حال اتصال...</>
                      : `پرداخت ${amount ? toPersianNum(Number(amount).toLocaleString()) + " تومان" : ""}`
                    }
                  </Button>
                </div>
              )}

              {modal === "withdraw" && (
                <div className="space-y-4">
                  <input
                    value={amount}
                    onChange={(e) => setAmount(e.target.value.replace(/\D/g, ""))}
                    placeholder="مبلغ برداشت (تومان)"
                    className="w-full bg-[#262626] border border-white/10 rounded-xl p-4 text-white text-center text-lg placeholder-white/30 focus:outline-none focus:border-indigo-500"
                    inputMode="numeric"
                  />
                  <input
                    placeholder="شماره شبا (IR...)"
                    className="w-full bg-[#262626] border border-white/10 rounded-xl p-4 text-white ltr text-left placeholder-white/30 focus:outline-none focus:border-indigo-500 font-mono"
                    dir="ltr"
                  />
                  <p className="text-xs text-white/30 text-center">
                    برداشت ۱ تا ۳ روز کاری — حداقل ۵۰,۰۰۰ تومان
                  </p>
                  <Button
                    variant="secondary" size="lg" fullWidth
                    disabled={!amount || Number(amount) < 50000}
                    onClick={() => { toast("قابلیت برداشت به زودی فعال می‌شود"); setModal(null); }}
                  >
                    ثبت درخواست برداشت
                  </Button>
                </div>
              )}

              {modal === "transfer" && (
                <div className="space-y-3">
                  <div>
                    <label className="text-xs text-white/40 mb-1 block">Earth ID گیرنده</label>
                    <input
                      value={toEarthId}
                      onChange={(e) => setToEarthId(e.target.value.toUpperCase())}
                      placeholder="DLX-XXXXXXXX"
                      className="w-full bg-[#262626] border border-white/10 rounded-xl p-4 text-white text-left ltr placeholder-white/30 focus:outline-none focus:border-indigo-500 font-mono tracking-widest"
                      dir="ltr"
                    />
                  </div>
                  <div>
                    <label className="text-xs text-white/40 mb-1 block">مبلغ (تومان)</label>
                    <input
                      value={amount}
                      onChange={(e) => setAmount(e.target.value.replace(/\D/g, ""))}
                      placeholder="مبلغ"
                      className="w-full bg-[#262626] border border-white/10 rounded-xl p-4 text-white text-center text-lg placeholder-white/30 focus:outline-none focus:border-indigo-500"
                      inputMode="numeric"
                    />
                  </div>
                  <div>
                    <label className="text-xs text-white/40 mb-1 block">توضیح (اختیاری)</label>
                    <input
                      value={desc}
                      onChange={(e) => setDesc(e.target.value)}
                      placeholder="بابت چه؟"
                      className="w-full bg-[#262626] border border-white/10 rounded-xl p-4 text-white placeholder-white/30 focus:outline-none focus:border-indigo-500"
                    />
                  </div>
                  <div className="bg-white/5 rounded-xl p-3 flex justify-between text-sm">
                    <span className="text-white/40">موجودی آزاد</span>
                    <span className="text-white font-medium">{toPersianNum(wallet.balance_available.toLocaleString())} ت</span>
                  </div>
                  <Button
                    variant="primary" size="lg" fullWidth
                    disabled={!amount || !toEarthId || sending}
                    onClick={handleTransfer}
                  >
                    {sending
                      ? <><Loader2 size={16} className="animate-spin ml-2" />در حال انتقال...</>
                      : `انتقال ${amount ? toPersianNum(Number(amount).toLocaleString()) + " تومان" : ""}`
                    }
                  </Button>
                </div>
              )}
            </div>
          </>
        )}
      </div>
    </AppShell>
  );
}
