"use client";

import { useState, useEffect, useCallback } from "react";
import AppShell from "@/components/layout/AppShell";
import {
  Wallet, ArrowDownLeft, ArrowUpRight, Clock,
  CheckCircle2, XCircle, Plus, Minus, Send, Eye,
  EyeOff, CreditCard, Loader2, RefreshCw, AlertCircle,
  ArrowLeftRight, Coins, Copy, ArrowDownToLine, ExternalLink,
} from "lucide-react";
import { Button } from "@/components/ui/Button";
import { toPersianNum, formatAmount } from "@/lib/utils";
import { walletApi, paygateApi, fxApi, holdingsApi, getApiErrorMessage} from "@/lib/api";
import { currencyMeta, formatMoney, isCrypto } from "@/lib/currency";
import { useTranslation } from "@/store/i18n";
import toast from "react-hot-toast";

interface Gateway {
  code: string;
  name: string;
  supported_currencies: string[];
  countries: string[];
  logo_url: string | null;
  is_sandbox: boolean;
}

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

interface Pocket {
  currency: string;
  balance: number;
  scale: number;
  is_primary: boolean;
  usd_value: number | null;
  base_value: number | null;
}

interface HoldingsData {
  base_currency: string;
  pockets: Pocket[];
  total_base: number;
  total_usd: number;
}

const TX_META: Record<string, { label: string; icon: React.ElementType; color: string; sign: "+" | "-" }> = {
  deposit:         { label: "wallet.tx.deposit",        icon: ArrowDownLeft,  color: "text-emerald-400", sign: "+" },
  withdrawal:      { label: "wallet.tx.withdrawal",     icon: ArrowUpRight,   color: "text-red-400",     sign: "-" },
  transfer_in:     { label: "wallet.tx.transfer_in",    icon: ArrowDownLeft,  color: "text-blue-400",    sign: "+" },
  transfer_out:    { label: "wallet.tx.transfer_out",   icon: ArrowUpRight,   color: "text-orange-400",  sign: "-" },
  exchange:        { label: "wallet.tx.exchange",       icon: ArrowLeftRight, color: "text-cyan-400",    sign: "+" },
  escrow_lock:     { label: "wallet.tx.escrow_lock",    icon: Clock,          color: "text-yellow-400",  sign: "-" },
  escrow_release:  { label: "wallet.tx.escrow_release", icon: CheckCircle2,   color: "text-emerald-400", sign: "+" },
  bonus_credit:    { label: "wallet.tx.bonus_credit",   icon: Plus,           color: "text-purple-400",  sign: "+" },
  fee_deduct:      { label: "wallet.tx.fee_deduct",     icon: Minus,          color: "text-red-400",     sign: "-" },
};

const STATUS_ICON: Record<string, React.ElementType> = {
  pending:   Clock,
  completed: CheckCircle2,
  failed:    XCircle,
  cancelled: XCircle,
  reversed:  XCircle,
};

type ModalType = "deposit" | "withdraw" | "transfer" | "exchange" | null;

// ارزهای دیجیتالِ پشتیبانی‌شده (هم‌راستا با بک‌اند services/crypto_wallet.py)
const CRYPTOS = ["BTC", "ETH", "TON", "TRX"];

interface ReceiveInfo {
  currency: string;
  earth_id: string;
  is_crypto: boolean;
  address?: string;
  network?: string;
  note?: string;
}
interface CryptoPay {
  intentId: string;
  authority?: string;
  address: string;
  network: string;
  currency: string;
  amount: string;
}

function formatDate(iso: string): string {
  try {
    const d = new Date(iso);
    return d.toLocaleDateString("fa-IR", { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
  } catch {
    return iso;
  }
}

export default function WalletPage() {
  const { t } = useTranslation();
  const [wallet,   setWallet]   = useState<WalletData | null>(null);
  const [txs,      setTxs]      = useState<Transaction[]>([]);
  const [loading,  setLoading]  = useState(true);
  const [txPage,   setTxPage]   = useState(1);
  const [hasMore,  setHasMore]  = useState(true);
  const [hideBalance, setHideBalance] = useState(false);
  const [modal,    setModal]    = useState<ModalType>(null);
  const [amount,   setAmount]   = useState("");
  const [iban,     setIban]     = useState("");
  const [toEarthId, setToEarthId] = useState("");
  const [desc,     setDesc]     = useState("");
  const [sending,  setSending]  = useState(false);
  const [activeTab, setActiveTab] = useState<"all" | "in" | "out">("all");
  const [gateways, setGateways] = useState<Gateway[]>([]);
  const [gwCode,   setGwCode]   = useState<string>("");
  const [gwLoading, setGwLoading] = useState(false);
  const [fxCredit, setFxCredit] = useState<number | null>(null);   // مبلغِ واریز پس از تبدیل (واحدِ خردِ مقصد)
  const [creditTo, setCreditTo] = useState("");                    // جیبِ مقصد؛ خالی = ارزِ پایه
  const [holdings, setHoldings] = useState<HoldingsData | null>(null);
  const [fxFrom, setFxFrom]     = useState("");
  const [fxTo, setFxTo]         = useState("");
  const [fxAmount, setFxAmount] = useState("");
  const [fxPreview, setFxPreview] = useState<number | null>(null);
  const [fxCurrencies, setFxCurrencies] = useState<string[]>([]);
  // ارز دیجیتال: شیتِ دریافت/ارسال + پنلِ آدرسِ پرداختِ کریپتو
  const [cryptoSheet, setCryptoSheet] = useState<{ currency: string; tab: "receive" | "send" } | null>(null);
  const [receiveInfo, setReceiveInfo] = useState<ReceiveInfo | null>(null);
  const [sendMode, setSendMode] = useState<"internal" | "external">("internal");
  const [sendTo, setSendTo] = useState("");
  const [sendAddr, setSendAddr] = useState("");
  const [sendAmount, setSendAmount] = useState("");
  const [cryptoPay, setCryptoPay] = useState<CryptoPay | null>(null);
  const [copied, setCopied] = useState(false);

  const loadWallet = useCallback(async () => {
    try {
      const res = await walletApi.get();
      setWallet(res.data);
    } catch {
      toast.error(t("wallet.loadError"));
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

  const loadHoldings = useCallback(async () => {
    try {
      const res = await holdingsApi.list();
      setHoldings(res.data);
    } catch {
      // ignore
    }
  }, []);

  useEffect(() => {
    const init = async () => {
      setLoading(true);
      await Promise.all([loadWallet(), loadTxs(1, true), loadHoldings()]);
      setLoading(false);
    };
    init();
  }, [loadWallet, loadTxs, loadHoldings]);

  // بازکردنِ خودکارِ مودال بر اساسِ ?action= (از دکمه‌های شارژ/انتقال/برداشتِ داشبورد)
  useEffect(() => {
    const action = new URLSearchParams(window.location.search).get("action");
    if (action === "deposit" || action === "withdraw" || action === "transfer" || action === "exchange") {
      setModal(action as ModalType);
      // پارامتر را از نشانی پاک می‌کنیم تا رفرشِ صفحه دوباره همان مودال (مثلاً «انتقال وجه») را باز نکند
      // و کاربر روی صفحهٔ اصلیِ کیف‌پول در جای خودش بماند.
      window.history.replaceState(null, "", window.location.pathname);
    }
  }, []);

  // بارگذاریِ فهرستِ ارزها هنگامِ بازکردنِ مودالِ تبدیل یا شارژ (انتخابِ جیبِ مقصد)
  useEffect(() => {
    if (modal !== "exchange" && modal !== "deposit") return;
    fxApi.rates()
      .then(({ data }) => setFxCurrencies(Object.keys(data.rates || {})))
      .catch(() => setFxCurrencies([]));
  }, [modal]);

  // ارزِ کیف‌پول (مقصدِ واریز). ورودیِ IRR «تومان»، بقیه واحدِ اصلی.
  const walletCur = wallet?.currency || "IRR";
  // مقیاسِ واحدِ خرد در هر واحدِ ISO: IRR ذخیره در ریال ولی ورودی تومان → ×۱۰؛ بقیه ×۱۰^decimals.
  const scaleOf = (cur: string) => (cur === "IRR" ? 10 : Math.pow(10, currencyMeta(cur).decimals || 2));

  // درگاهِ انتخاب‌شده → ارزِ پرداخت (اگر درگاه ارزِ کیف‌پول را بپذیرد بدونِ تبدیل، وگرنه ارزِ خودِ درگاه)
  const selectedGw = gateways.find((g) => g.code === gwCode) || null;
  const payCur = selectedGw
    ? (!selectedGw.supported_currencies.length || selectedGw.supported_currencies.includes(walletCur)
        ? walletCur : selectedGw.supported_currencies[0])
    : walletCur;
  const payMeta = currencyMeta(payCur);
  const payIsIRR = payCur === "IRR";
  const payIsCrypto = isCrypto(payCur);
  // جیبِ مقصدِ واریز: خالی = ارزِ پایه؛ وگرنه یک جیبِ ارزی (holding)
  const creditTarget = (creditTo || walletCur).toUpperCase();
  const needsFx = payCur !== creditTarget;
  const toMinor = (main: number) => Math.round(main * scaleOf(payCur));   // ورودی → واحدِ خردِ ارزِ پرداخت
  // حداقلِ واریز: IRR ده‌هزار تومان؛ کریپتو معادلِ ۱۰۰۰ واحدِ خرد؛ بقیه ۱ واحد
  const minDeposit = payIsIRR ? 10000 : payIsCrypto ? 1000 / scaleOf(payCur) : 1;
  // فهرستِ ارزهای مقصد: ارزِ پایه + سایرِ ارزهای پشتیبانی‌شده
  const targetCurrencies = Array.from(new Set([walletCur, ...fxCurrencies]));

  // بارگذاریِ همهٔ درگاه‌های فعال (شاملِ بین‌المللی) هنگامِ بازکردنِ مودالِ شارژ
  const loadGateways = useCallback(async () => {
    setGwLoading(true);
    try {
      const res = await paygateApi.gateways();
      const list: Gateway[] = res.data || [];
      setGateways(list);
      setGwCode((prev) => prev || (list[0]?.code ?? ""));
    } catch {
      setGateways([]);
    } finally {
      setGwLoading(false);
    }
  }, []);

  useEffect(() => {
    if (modal === "deposit") loadGateways();
  }, [modal, loadGateways]);

  // پیش‌نمایشِ مبلغِ واریز پس از تبدیلِ ارز (وقتی ارزِ پرداخت با کیف‌پول متفاوت است)
  useEffect(() => {
    const amt = Number(amount);
    if (!needsFx || !amt || amt < minDeposit) { setFxCredit(null); return; }
    let alive = true;
    const t = setTimeout(async () => {
      try {
        const { data } = await fxApi.quote(toMinor(amt), payCur, creditTarget);
        if (alive) setFxCredit(data.converted ?? null);
      } catch {
        if (alive) setFxCredit(null);
      }
    }, 350);
    return () => { alive = false; clearTimeout(t); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [amount, payCur, creditTarget, needsFx]);

  const handleDeposit = async () => {
    const amt = Number(amount);
    if (!amt || amt < minDeposit) {
      toast.error(payIsIRR ? t("wallet.minIrr") : `${t("wallet.minAmount")} ${minDeposit} ${payMeta.code}`);
      return;
    }
    if (!gwCode) { toast.error(t("wallet.selectGateway")); return; }
    setSending(true);
    try {
      const { data } = await paygateApi.initiate(
        gwCode, toMinor(amt), payCur, t("wallet.depositDesc"),
        creditTo || undefined,
      );
      if (data.crypto && data.address) {
        // پرداختِ کریپتو: آدرسِ واریز را نشان می‌دهیم؛ پس از ارسال، کاربر «تأیید» می‌زند
        setCryptoPay({
          intentId: data.intent_id, authority: data.authority,
          address: data.address, network: data.network,
          currency: payCur, amount,
        });
        setSending(false);
        return;
      }
      if (data.sandbox) {
        // درگاهِ آزمایشی: بدونِ ریدایرکت، همان‌جا تأیید و واریز می‌کنیم
        await paygateApi.verify(data.intent_id, data.authority);
        toast.success(
          creditTarget !== walletCur
            ? `${t("wallet.pocketPrefix")} ${creditTarget} ${t("wallet.chargedSuffix")}`
            : t("wallet.walletCharged")
        );
        setModal(null);
        setAmount("");
        setCreditTo("");
        await Promise.all([loadWallet(), loadHoldings()]);
        setTxPage(1);
        await loadTxs(1, true);
      } else if (data.payment_url) {
        window.location.href = data.payment_url;
      } else {
        toast.error(t("wallet.gatewayError"));
      }
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("wallet.gatewayError")));
    } finally {
      setSending(false);
    }
  };

  // تبدیلِ ارز بینِ جیب‌ها (holdings)
  const fxScale = (cur: string) => (cur === "IRR" ? 10 : Math.pow(10, currencyMeta(cur).decimals || 2));
  const fxToMinor = (main: number) => Math.round(main * fxScale(fxFrom));
  const fromPockets = (holdings?.pockets || []).filter((p) => p.balance > 0);

  const openExchange = () => {
    setFxFrom(holdings?.base_currency || walletCur);
    setFxTo("");
    setFxAmount("");
    setFxPreview(null);
    setModal("exchange");
  };

  useEffect(() => {
    const amt = Number(fxAmount);
    if (!fxFrom || !fxTo || fxFrom === fxTo || !amt) { setFxPreview(null); return; }
    let alive = true;
    const t = setTimeout(async () => {
      try {
        const { data } = await fxApi.quote(fxToMinor(amt), fxFrom, fxTo);
        if (alive) setFxPreview(data.converted ?? null);
      } catch {
        if (alive) setFxPreview(null);
      }
    }, 350);
    return () => { alive = false; clearTimeout(t); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fxAmount, fxFrom, fxTo]);

  const handleExchange = async () => {
    const amt = Number(fxAmount);
    if (!fxFrom || !fxTo) { toast.error(t("wallet.selectFromTo")); return; }
    if (fxFrom === fxTo)  { toast.error(t("wallet.sameFromTo")); return; }
    if (!amt || amt <= 0) { toast.error(t("wallet.enterAmount")); return; }
    setSending(true);
    try {
      await holdingsApi.exchange(fxFrom, fxTo, fxToMinor(amt));
      toast.success(t("wallet.exchangeDone"));
      setModal(null);
      setFxAmount("");
      setFxPreview(null);
      await Promise.all([loadWallet(), loadHoldings()]);
      setTxPage(1);
      await loadTxs(1, true);
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("wallet.exchangeError")));
    } finally {
      setSending(false);
    }
  };

  const handleTransfer = async () => {
    const amt = Number(amount);
    if (!toEarthId.startsWith("DLX-")) { toast.error(t("wallet.invalidEarthId")); return; }
    if (!amt || amt < 1000) { toast.error(t("wallet.minTransfer")); return; }
    setSending(true);
    try {
      await walletApi.transfer(toEarthId, amt, desc || undefined);
      toast.success(`${toPersianNum(amt.toLocaleString())} ${t("wallet.transferredSuffix")}`);
      setModal(null);
      setAmount("");
      setToEarthId("");
      setDesc("");
      await loadWallet();
      setTxPage(1);
      await loadTxs(1, true);
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("wallet.transferError")));
    } finally {
      setSending(false);
    }
  };

  // کپیِ متن در کلیپ‌بورد (آدرسِ واریز/Earth ID)
  const copyText = async (text: string) => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      toast.error(t("wallet.copyError"));
    }
  };

  // تأییدِ پرداختِ کریپتو: پس از ارسالِ ارز به آدرس، کاربر «تأیید» می‌زند تا واریز ثبت شود
  const confirmCryptoPay = async () => {
    if (!cryptoPay) return;
    setSending(true);
    try {
      await paygateApi.verify(cryptoPay.intentId, cryptoPay.authority);
      toast.success(
        creditTarget !== walletCur
          ? `${t("wallet.pocketPrefix")} ${creditTarget} ${t("wallet.chargedSuffix")}`
          : t("wallet.walletCharged")
      );
      setCryptoPay(null);
      setModal(null);
      setAmount("");
      setCreditTo("");
      await Promise.all([loadWallet(), loadHoldings()]);
      setTxPage(1);
      await loadTxs(1, true);
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("wallet.gatewayError")));
    } finally {
      setSending(false);
    }
  };

  // بازکردنِ شیتِ دریافت/ارسالِ ارز دیجیتال + گرفتنِ آدرسِ واریز
  const openCryptoSheet = async (currency: string, tab: "receive" | "send") => {
    setCryptoSheet({ currency, tab });
    setReceiveInfo(null);
    setSendMode("internal");
    setSendTo("");
    setSendAddr("");
    setSendAmount("");
    try {
      const { data } = await holdingsApi.receive(currency);
      setReceiveInfo(data);
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("wallet.loadError")));
    }
  };

  // ارسالِ ارز دیجیتال: داخلی (به Earth ID) یا بیرونی (برداشت به آدرسِ خارجی)
  const handleCryptoSend = async () => {
    if (!cryptoSheet) return;
    const cur = cryptoSheet.currency;
    const amt = Number(sendAmount);
    if (!amt || amt <= 0) { toast.error(t("wallet.enterAmount")); return; }
    const minor = Math.round(amt * scaleOf(cur));
    setSending(true);
    try {
      if (sendMode === "internal") {
        if (!sendTo.startsWith("DLX-")) { toast.error(t("wallet.invalidEarthId")); setSending(false); return; }
        await holdingsApi.transfer(sendTo, cur, minor, desc || undefined);
        toast.success(t("wallet.cryptoSent"));
      } else {
        if (sendAddr.trim().length < 8) { toast.error(t("wallet.invalidAddress")); setSending(false); return; }
        await holdingsApi.withdraw(cur, minor, sendAddr.trim(), desc || undefined);
        toast.success(t("wallet.withdrawQueued"));
      }
      setCryptoSheet(null);
      setSendAmount("");
      setSendTo("");
      setSendAddr("");
      setDesc("");
      await Promise.all([loadWallet(), loadHoldings()]);
      setTxPage(1);
      await loadTxs(1, true);
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("wallet.transferError")));
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
      <AppShell title={t("wallet.title")}>
        <div className="flex items-center justify-center h-48">
          <Loader2 size={32} className="text-primary-400 animate-spin" />
        </div>
      </AppShell>
    );
  }

  if (!wallet) {
    return (
      <AppShell title={t("wallet.title")}>
        <div className="page-inner flex flex-col items-center justify-center h-48 gap-3">
          <AlertCircle size={40} className="text-red-400" />
          <p className="text-surface-400">{t("wallet.notActive")}</p>
          <Button variant="primary" size="sm" onClick={loadWallet}>{t("wallet.retry")}</Button>
        </div>
      </AppShell>
    );
  }

  return (
    <AppShell title={t("wallet.title")}>
      <div className="page-inner">
        {/* Balance Card */}
        <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-indigo-900 via-indigo-950 to-[#0A0A0A] border border-indigo-700/30 p-5 mb-5">
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_bottom_right,#4f46e5_0%,transparent_70%)] opacity-20 pointer-events-none" />

          {wallet.is_frozen && (
            <div className="relative mb-3 flex items-center gap-2 bg-red-500/10 border border-red-500/30 rounded-xl p-2.5">
              <AlertCircle size={16} className="text-red-400" />
              <p className="text-sm text-red-300">{t("wallet.frozen")}</p>
            </div>
          )}

          <div className="relative">
            <div className="flex items-center justify-between mb-1">
              <p className="text-indigo-300 text-sm">{t("wallet.totalBalance")}</p>
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
              <p className="text-indigo-300 text-sm">{t("wallet.toman")}</p>
            </div>

            <div className="grid grid-cols-3 gap-3">
              {[
                { label: "wallet.available", value: wallet.balance_available, color: "text-white"         },
                { label: "wallet.escrow",    value: wallet.balance_escrow,    color: "text-yellow-300"    },
                { label: "wallet.bonus",     value: wallet.balance_bonus,     color: "text-purple-300"    },
              ].map((b) => (
                <div key={b.label} className="bg-white/5 rounded-xl p-2.5">
                  <p className="text-xs text-indigo-300/70 mb-1">{t(b.label)}</p>
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
            { label: "wallet.deposit",  icon: Plus,         modal: "deposit"  as ModalType, bg: "bg-emerald-600" },
            { label: "wallet.withdraw", icon: ArrowUpRight,  modal: "withdraw" as ModalType, bg: "bg-red-700"     },
            { label: "wallet.transfer", icon: Send,          modal: "transfer" as ModalType, bg: "bg-indigo-600"  },
          ].map((btn) => (
            <button
              key={btn.label}
              onClick={() => setModal(btn.modal)}
              className="flex flex-col items-center gap-2 py-4 rounded-xl bg-[#1C1C1E] hover:bg-[#2C2C2E] transition-colors border border-white/8"
            >
              <div className={`w-10 h-10 rounded-xl ${btn.bg} flex items-center justify-center`}>
                <btn.icon size={20} className="text-white" />
              </div>
              <p className="text-sm font-medium text-white/80">{t(btn.label)}</p>
            </button>
          ))}
        </div>

        {/* ارزهای من (کیف‌پولِ چندارزی) */}
        {holdings && (
          <div className="bg-[#1C1C1E] border border-white/8 rounded-2xl p-4 mb-5">
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center gap-2">
                <Coins size={16} className="text-cyan-400" />
                <h2 className="font-bold text-white text-sm">{t("wallet.myCurrencies")}</h2>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => openCryptoSheet("BTC", "receive")}
                  className="flex items-center gap-1.5 text-xs font-medium text-amber-300 bg-amber-500/10 border border-amber-500/20 rounded-lg px-2.5 py-1.5 hover:bg-amber-500/20 transition-colors"
                >
                  <ArrowDownToLine size={13} /> {t("wallet.cryptoReceiveSend")}
                </button>
                <button
                  onClick={openExchange}
                  className="flex items-center gap-1.5 text-xs font-medium text-cyan-300 bg-cyan-500/10 border border-cyan-500/20 rounded-lg px-2.5 py-1.5 hover:bg-cyan-500/20 transition-colors"
                >
                  <ArrowLeftRight size={13} /> {t("wallet.exchange")}
                </button>
              </div>
            </div>
            <div className="flex gap-2 overflow-x-auto pb-1">
              {holdings.pockets.map((p) => {
                const crypto = isCrypto(p.currency);
                return (
                <button
                  key={p.currency}
                  onClick={crypto ? () => openCryptoSheet(p.currency, "receive") : undefined}
                  disabled={!crypto}
                  className={`flex-shrink-0 min-w-[7rem] rounded-xl p-3 border text-right ${
                    p.is_primary ? "bg-indigo-500/10 border-indigo-500/25" : "bg-white/5 border-white/10"
                  } ${crypto ? "hover:border-amber-500/40 transition-colors cursor-pointer" : "cursor-default"}`}
                >
                  <div className="flex items-center gap-1.5 mb-1">
                    <span className="text-xs font-semibold text-white/70">{currencyMeta(p.currency).code}</span>
                    {crypto && (
                      <span className="text-[9px] px-1 py-px rounded bg-amber-500/15 text-amber-300/80 leading-none">دیجیتال</span>
                    )}
                    {p.is_primary && <span className="text-[10px] text-indigo-300/70">{t("wallet.base")}</span>}
                  </div>
                  <p className="text-sm font-bold text-white">
                    {hideBalance ? "••••" : formatMoney(p.balance, p.currency, "fa")}
                  </p>
                  {!p.is_primary && p.usd_value !== null && (
                    <p className="text-[11px] text-white/35 mt-0.5">≈ ${toPersianNum(p.usd_value.toLocaleString())}</p>
                  )}
                </button>
                );
              })}
            </div>
            {holdings.total_usd > 0 && (
              <p className="text-[11px] text-white/35 mt-2">
                {t("wallet.portfolioValue")} ${toPersianNum(holdings.total_usd.toLocaleString())}
              </p>
            )}
          </div>
        )}

        {/* Transactions */}
        <div className="flex items-center justify-between mb-3">
          <h2 className="font-bold text-white">{t("wallet.transactions")}</h2>
          <div className="flex gap-1 bg-[#1C1C1E] rounded-lg p-0.5">
            {[
              { id: "all" as const, label: "wallet.tabAll" },
              { id: "in"  as const, label: "wallet.tabIn"  },
              { id: "out" as const, label: "wallet.tabOut" },
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
                {t(tab.label)}
              </button>
            ))}
          </div>
        </div>

        {filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 gap-3">
            <Wallet size={40} className="text-white/20" />
            <p className="text-white/40 text-sm">{t("wallet.noTx")}</p>
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
                      {tx.description || t(meta.label)}
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
                    {meta.sign}{toPersianNum(tx.amount.toLocaleString())} {t("wallet.tomanShort")}
                  </p>
                </div>
              );
            })}

            {hasMore && (
              <button
                onClick={() => { const next = txPage + 1; setTxPage(next); loadTxs(next); }}
                className="w-full py-3 rounded-xl bg-[#1C1C1E] text-white/50 text-sm hover:text-white/80 transition-colors"
              >
                {t("wallet.loadMore")}
              </button>
            )}
          </div>
        )}

        {/* Modals */}
        {modal && (
          <>
            <div className="fixed inset-0 bg-black/70 z-[60]" onClick={() => { setModal(null); setAmount(""); setCryptoPay(null); }} />
            <div className="fixed bottom-0 inset-x-0 z-[70] bg-[#1C1C1E] rounded-t-2xl p-5 pb-[calc(var(--nav-height)+2rem)] border-t border-white/8 max-h-[88vh] overflow-y-auto">
              <div className="w-10 h-1 bg-white/10 rounded-full mx-auto mb-5" />
              <h2 className="text-lg font-bold text-white mb-5">
                {modal === "deposit" ? t("wallet.depositTitle")
                  : modal === "withdraw" ? t("wallet.withdrawTitle")
                  : modal === "exchange" ? t("wallet.exchangeTitle")
                  : t("wallet.transferTitle")}
              </h2>

              {modal === "deposit" && cryptoPay && (
                <div className="space-y-4">
                  <div className="flex items-center gap-2 text-amber-300 text-sm">
                    <ArrowDownToLine size={16} />
                    <span>{t("wallet.cryptoPayTitle")} · {cryptoPay.network}</span>
                  </div>
                  <p className="text-xs text-white/50 leading-relaxed">
                    {t("wallet.cryptoPayNote")}
                  </p>
                  <div className="bg-[#262626] border border-white/10 rounded-xl p-3">
                    <p className="text-[11px] text-white/40 mb-1.5">{t("wallet.depositAddress")}</p>
                    <div className="flex items-center gap-2">
                      <code className="flex-1 text-xs text-white/90 break-all ltr text-left font-mono" dir="ltr">
                        {cryptoPay.address}
                      </code>
                      <button
                        onClick={() => copyText(cryptoPay.address)}
                        className="flex-shrink-0 w-9 h-9 rounded-lg bg-white/5 hover:bg-white/10 flex items-center justify-center text-white/70 transition-colors"
                      >
                        {copied ? <CheckCircle2 size={16} className="text-emerald-400" /> : <Copy size={16} />}
                      </button>
                    </div>
                  </div>
                  <div className="bg-white/5 rounded-xl p-3 flex justify-between text-sm">
                    <span className="text-white/40">{t("wallet.amount")}</span>
                    <span className="text-white font-medium ltr" dir="ltr">{cryptoPay.amount} {cryptoPay.currency}</span>
                  </div>
                  <Button
                    variant="primary" size="lg" fullWidth
                    disabled={sending}
                    onClick={confirmCryptoPay}
                  >
                    {sending
                      ? <><Loader2 size={16} className="animate-spin ml-2" />{t("wallet.verifying")}</>
                      : t("wallet.cryptoPayConfirm")}
                  </Button>
                  <button
                    onClick={() => setCryptoPay(null)}
                    className="w-full py-2 text-sm text-white/40 hover:text-white/70 transition-colors"
                  >
                    {t("wallet.back")}
                  </button>
                </div>
              )}

              {modal === "deposit" && !cryptoPay && (
                <div className="space-y-4">
                  {payIsIRR && (
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
                  )}
                  <input
                    value={amount}
                    onChange={(e) => setAmount(
                      payIsCrypto
                        ? e.target.value.replace(/[^\d.]/g, "")
                        : e.target.value.replace(/\D/g, "")
                    )}
                    placeholder={payIsIRR ? t("wallet.customAmountToman") : `${t("wallet.amount")} (${payMeta.code})`}
                    className="w-full bg-[#262626] border border-white/10 rounded-xl p-4 text-white text-center text-lg placeholder-white/30 focus:outline-none focus:border-indigo-500"
                    inputMode={payIsCrypto ? "decimal" : "numeric"}
                  />

                  {/* انتخابِ درگاهِ پرداخت (pluggable) */}
                  <div>
                    <p className="text-xs text-white/40 mb-2">{t("wallet.paymentGateway")}</p>
                    {gwLoading ? (
                      <div className="flex items-center justify-center py-4">
                        <Loader2 size={20} className="animate-spin text-indigo-400" />
                      </div>
                    ) : gateways.length === 0 ? (
                      <p className="text-sm text-white/40 py-3 text-center">
                        {t("wallet.noGateway")}
                      </p>
                    ) : (
                      <div className="space-y-2 max-h-52 overflow-y-auto">
                        {gateways.map((gw) => (
                          <button
                            key={gw.code}
                            onClick={() => setGwCode(gw.code)}
                            className={`w-full flex items-center gap-3 p-3 rounded-xl border transition-all text-right ${
                              gwCode === gw.code
                                ? "border-indigo-500 bg-indigo-500/10"
                                : "border-white/10 hover:border-white/30"
                            }`}
                          >
                            <div className="w-9 h-9 rounded-lg bg-white/5 flex items-center justify-center flex-shrink-0 overflow-hidden">
                              {gw.logo_url
                                ? <img src={gw.logo_url} alt={gw.name} className="w-full h-full object-contain" />
                                : <CreditCard size={18} className="text-indigo-400" />}
                            </div>
                            <div className="flex-1 min-w-0">
                              <p className="text-sm font-medium text-white truncate">{gw.name}</p>
                              <div className="flex items-center gap-1.5 mt-0.5">
                                <span className="text-[11px] text-white/40">
                                  {gw.supported_currencies.length ? gw.supported_currencies.join(" · ") : t("wallet.allCurrencies")}
                                </span>
                                {gw.is_sandbox && <span className="text-[11px] text-yellow-400/80">· {t("wallet.sandbox")}</span>}
                              </div>
                            </div>
                            {gwCode === gw.code && <CheckCircle2 size={18} className="text-indigo-400 flex-shrink-0" />}
                          </button>
                        ))}
                      </div>
                    )}
                  </div>

                  {/* انتخابِ جیبِ مقصد (ارزِ پایه یا یک ارزِ خارجی) */}
                  <div>
                    <p className="text-xs text-white/40 mb-2">{t("wallet.depositToPocket")}</p>
                    <div className="flex flex-wrap gap-2">
                      {targetCurrencies.map((cur) => {
                        const active = creditTarget === cur;
                        const isBase = cur === walletCur;
                        return (
                          <button
                            key={cur}
                            onClick={() => setCreditTo(isBase ? "" : cur)}
                            className={`px-3 py-1.5 rounded-lg text-sm border transition-all ${
                              active
                                ? "border-indigo-500 bg-indigo-500/10 text-indigo-300"
                                : "border-white/10 text-white/50 hover:border-white/30"
                            }`}
                          >
                            {cur}{isBase && ` · ${t("wallet.base")}`}
                          </button>
                        );
                      })}
                    </div>
                  </div>

                  {/* پیش‌نمایشِ تبدیلِ ارز (وقتی ارزِ پرداخت با جیبِ مقصد متفاوت است) */}
                  {needsFx && Number(amount) >= minDeposit && (
                    <div className="flex items-center justify-between bg-indigo-500/10 border border-indigo-500/20 rounded-xl p-3 text-sm">
                      <span className="text-white/60">{t("wallet.payTo")} {payMeta.code} · {t("wallet.receiveIn")} {creditTarget}</span>
                      <span className="text-indigo-300 font-semibold">
                        {fxCredit !== null ? `≈ ${formatMoney(fxCredit, creditTarget, "fa")}` : "…"}
                      </span>
                    </div>
                  )}

                  <Button
                    variant="primary" size="lg" fullWidth
                    disabled={!amount || Number(amount) < minDeposit || !gwCode || sending}
                    onClick={handleDeposit}
                  >
                    {sending
                      ? <><Loader2 size={16} className="animate-spin ml-2" />{t("wallet.paying")}</>
                      : `${t("wallet.pay")} ${amount ? toPersianNum(Number(amount).toLocaleString()) + (payIsIRR ? ` ${t("wallet.toman")}` : ` ${payMeta.code}`) : ""}`
                    }
                  </Button>
                </div>
              )}

              {modal === "withdraw" && (
                <div className="space-y-4">
                  <input
                    value={amount}
                    onChange={(e) => setAmount(e.target.value.replace(/\D/g, ""))}
                    placeholder={t("wallet.withdrawAmount")}
                    className="w-full bg-[#262626] border border-white/10 rounded-xl p-4 text-white text-center text-lg placeholder-white/30 focus:outline-none focus:border-indigo-500"
                    inputMode="numeric"
                  />
                  <input
                    value={iban}
                    onChange={(e) => setIban(e.target.value.replace(/[^\dIR]/gi, "").toUpperCase())}
                    placeholder={t("wallet.iban")}
                    className="w-full bg-[#262626] border border-white/10 rounded-xl p-4 text-white ltr text-left placeholder-white/30 focus:outline-none focus:border-indigo-500 font-mono"
                    dir="ltr"
                  />
                  <p className="text-xs text-white/30 text-center">
                    {t("wallet.withdrawNote")}
                  </p>
                  <Button
                    variant="primary" size="lg" fullWidth
                    disabled={!amount || Number(amount) < 50000 || iban.replace(/\D/g, "").length < 24}
                    onClick={() => { toast(t("wallet.withdrawSoon")); setModal(null); setIban(""); }}
                  >
                    {t("wallet.submitWithdraw")}
                  </Button>
                </div>
              )}

              {modal === "exchange" && (
                <div className="space-y-4">
                  <div>
                    <label className="text-xs text-white/40 mb-2 block">{t("wallet.fromCurrency")}</label>
                    {fromPockets.length === 0 ? (
                      <p className="text-sm text-white/40">{t("wallet.noBalance")}</p>
                    ) : (
                      <div className="flex flex-wrap gap-2">
                        {fromPockets.map((p) => (
                          <button
                            key={p.currency}
                            onClick={() => setFxFrom(p.currency)}
                            className={`px-3 py-2 rounded-xl border text-sm transition-all ${
                              fxFrom === p.currency
                                ? "border-cyan-500 bg-cyan-500/10 text-cyan-200"
                                : "border-white/10 text-white/60 hover:border-white/30"
                            }`}
                          >
                            {currencyMeta(p.currency).code}
                            {!hideBalance && (
                              <span className="text-[11px] text-white/30 mr-1.5">
                                {formatMoney(p.balance, p.currency, "fa")}
                              </span>
                            )}
                          </button>
                        ))}
                      </div>
                    )}
                  </div>

                  <input
                    value={fxAmount}
                    onChange={(e) => setFxAmount(e.target.value.replace(/[^\d.]/g, ""))}
                    placeholder={`${t("wallet.amount")} (${currencyMeta(fxFrom).code}${fxFrom === "IRR" ? ` ${t("wallet.toman")}` : ""})`}
                    className="w-full bg-[#262626] border border-white/10 rounded-xl p-4 text-white text-center text-lg placeholder-white/30 focus:outline-none focus:border-cyan-500"
                    inputMode="decimal"
                  />

                  <div>
                    <label className="text-xs text-white/40 mb-2 block">{t("wallet.toCurrency")}</label>
                    <div className="flex flex-wrap gap-2 max-h-28 overflow-y-auto">
                      {fxCurrencies.filter((c) => c !== fxFrom).map((c) => (
                        <button
                          key={c}
                          onClick={() => setFxTo(c)}
                          className={`px-3 py-2 rounded-xl border text-sm transition-all ${
                            fxTo === c
                              ? "border-cyan-500 bg-cyan-500/10 text-cyan-200"
                              : "border-white/10 text-white/60 hover:border-white/30"
                          }`}
                        >
                          {currencyMeta(c).code}
                        </button>
                      ))}
                    </div>
                  </div>

                  {fxFrom && fxTo && Number(fxAmount) > 0 && (
                    <div className="flex items-center justify-between bg-cyan-500/10 border border-cyan-500/20 rounded-xl p-3 text-sm">
                      <span className="text-white/60">{t("wallet.youReceive")}</span>
                      <span className="text-cyan-300 font-semibold">
                        {fxPreview !== null ? `≈ ${formatMoney(fxPreview, fxTo, "fa")}` : "…"}
                      </span>
                    </div>
                  )}

                  <Button
                    variant="primary" size="lg" fullWidth
                    disabled={!fxFrom || !fxTo || !Number(fxAmount) || sending}
                    onClick={handleExchange}
                  >
                    {sending
                      ? <><Loader2 size={16} className="animate-spin ml-2" />{t("wallet.exchanging")}</>
                      : t("wallet.exchange")}
                  </Button>
                </div>
              )}

              {modal === "transfer" && (
                <div className="space-y-3">
                  <div>
                    <label className="text-xs text-white/40 mb-1 block">{t("wallet.recipientEarthId")}</label>
                    <input
                      value={toEarthId}
                      onChange={(e) => setToEarthId(e.target.value.toUpperCase())}
                      placeholder="DLX-XXXXXXXX"
                      className="w-full bg-[#262626] border border-white/10 rounded-xl p-4 text-white text-left ltr placeholder-white/30 focus:outline-none focus:border-indigo-500 font-mono tracking-widest"
                      dir="ltr"
                    />
                  </div>
                  <div>
                    <label className="text-xs text-white/40 mb-1 block">{t("wallet.amountToman")}</label>
                    <input
                      value={amount}
                      onChange={(e) => setAmount(e.target.value.replace(/\D/g, ""))}
                      placeholder={t("wallet.amount")}
                      className="w-full bg-[#262626] border border-white/10 rounded-xl p-4 text-white text-center text-lg placeholder-white/30 focus:outline-none focus:border-indigo-500"
                      inputMode="numeric"
                    />
                  </div>
                  <div>
                    <label className="text-xs text-white/40 mb-1 block">{t("wallet.descOptional")}</label>
                    <input
                      value={desc}
                      onChange={(e) => setDesc(e.target.value)}
                      placeholder={t("wallet.descPlaceholder")}
                      className="w-full bg-[#262626] border border-white/10 rounded-xl p-4 text-white placeholder-white/30 focus:outline-none focus:border-indigo-500"
                    />
                  </div>
                  <div className="bg-white/5 rounded-xl p-3 flex justify-between text-sm">
                    <span className="text-white/40">{t("wallet.availableBalance")}</span>
                    <span className="text-white font-medium">{toPersianNum(wallet.balance_available.toLocaleString())} {t("wallet.tomanShort")}</span>
                  </div>
                  <Button
                    variant="primary" size="lg" fullWidth
                    disabled={!amount || !toEarthId || sending}
                    onClick={handleTransfer}
                  >
                    {sending
                      ? <><Loader2 size={16} className="animate-spin ml-2" />{t("wallet.transferring")}</>
                      : `${t("wallet.transfer")} ${amount ? toPersianNum(Number(amount).toLocaleString()) + ` ${t("wallet.toman")}` : ""}`
                    }
                  </Button>
                </div>
              )}
            </div>
          </>
        )}

        {/* شیتِ دریافت/ارسالِ ارز دیجیتال */}
        {cryptoSheet && (
          <>
            <div className="fixed inset-0 bg-black/70 z-[60]" onClick={() => setCryptoSheet(null)} />
            <div className="fixed bottom-0 inset-x-0 z-[70] bg-[#1C1C1E] rounded-t-2xl p-5 pb-[calc(var(--nav-height)+2rem)] border-t border-white/8 max-h-[88vh] overflow-y-auto">
              <div className="w-10 h-1 bg-white/10 rounded-full mx-auto mb-5" />
              <div className="flex items-center gap-2 mb-4">
                <Coins size={18} className="text-amber-400" />
                <h2 className="text-lg font-bold text-white">
                  {currencyMeta(cryptoSheet.currency).code} · {receiveInfo?.network || t("wallet.cryptoReceiveSend")}
                </h2>
              </div>

              {/* انتخابِ ارز دیجیتال */}
              <div className="flex flex-wrap gap-2 mb-4">
                {CRYPTOS.map((c) => (
                  <button
                    key={c}
                    onClick={() => openCryptoSheet(c, cryptoSheet.tab)}
                    className={`px-3 py-1.5 rounded-lg text-sm border transition-all ${
                      cryptoSheet.currency === c
                        ? "border-amber-500 bg-amber-500/10 text-amber-300"
                        : "border-white/10 text-white/50 hover:border-white/30"
                    }`}
                  >
                    {c}
                  </button>
                ))}
              </div>

              {/* تب‌های دریافت / ارسال */}
              <div className="flex gap-1 bg-[#262626] rounded-xl p-1 mb-4">
                {([
                  { id: "receive" as const, label: "wallet.receive",  icon: ArrowDownToLine },
                  { id: "send"    as const, label: "wallet.send",     icon: Send },
                ]).map((tab) => (
                  <button
                    key={tab.id}
                    onClick={() => setCryptoSheet({ currency: cryptoSheet.currency, tab: tab.id })}
                    className={`flex-1 flex items-center justify-center gap-1.5 py-2.5 rounded-lg text-sm font-medium transition-all ${
                      cryptoSheet.tab === tab.id ? "bg-amber-600 text-white" : "text-white/40 hover:text-white/70"
                    }`}
                  >
                    <tab.icon size={15} /> {t(tab.label)}
                  </button>
                ))}
              </div>

              {cryptoSheet.tab === "receive" ? (
                !receiveInfo ? (
                  <div className="flex items-center justify-center py-8">
                    <Loader2 size={22} className="animate-spin text-amber-400" />
                  </div>
                ) : (
                  <div className="space-y-4">
                    <p className="text-xs text-white/50 leading-relaxed">{receiveInfo.note || t("wallet.cryptoReceiveNote")}</p>
                    {receiveInfo.address && (
                      <div className="bg-[#262626] border border-white/10 rounded-xl p-3">
                        <p className="text-[11px] text-white/40 mb-1.5">{t("wallet.depositAddress")} · {receiveInfo.network}</p>
                        <div className="flex items-center gap-2">
                          <code className="flex-1 text-xs text-white/90 break-all ltr text-left font-mono" dir="ltr">
                            {receiveInfo.address}
                          </code>
                          <button
                            onClick={() => copyText(receiveInfo.address!)}
                            className="flex-shrink-0 w-9 h-9 rounded-lg bg-white/5 hover:bg-white/10 flex items-center justify-center text-white/70 transition-colors"
                          >
                            {copied ? <CheckCircle2 size={16} className="text-emerald-400" /> : <Copy size={16} />}
                          </button>
                        </div>
                      </div>
                    )}
                    <div className="bg-white/5 rounded-xl p-3">
                      <p className="text-[11px] text-white/40 mb-1.5">{t("wallet.yourEarthId")}</p>
                      <div className="flex items-center gap-2">
                        <code className="flex-1 text-sm text-white/90 ltr text-left font-mono tracking-wider" dir="ltr">
                          {receiveInfo.earth_id}
                        </code>
                        <button
                          onClick={() => copyText(receiveInfo.earth_id)}
                          className="flex-shrink-0 w-9 h-9 rounded-lg bg-white/5 hover:bg-white/10 flex items-center justify-center text-white/70 transition-colors"
                        >
                          <Copy size={16} />
                        </button>
                      </div>
                    </div>
                  </div>
                )
              ) : (
                <div className="space-y-4">
                  {/* داخلی (به کاربرِ نقطه) یا بیرونی (آدرسِ خارجی) */}
                  <div className="flex gap-1 bg-[#262626] rounded-xl p-1">
                    {([
                      { id: "internal" as const, label: "wallet.sendInternal" },
                      { id: "external" as const, label: "wallet.sendExternal" },
                    ]).map((m) => (
                      <button
                        key={m.id}
                        onClick={() => setSendMode(m.id)}
                        className={`flex-1 py-2 rounded-lg text-xs font-medium transition-all ${
                          sendMode === m.id ? "bg-indigo-600 text-white" : "text-white/40 hover:text-white/70"
                        }`}
                      >
                        {t(m.label)}
                      </button>
                    ))}
                  </div>

                  {sendMode === "internal" ? (
                    <input
                      value={sendTo}
                      onChange={(e) => setSendTo(e.target.value.toUpperCase())}
                      placeholder="DLX-XXXXXXXX"
                      className="w-full bg-[#262626] border border-white/10 rounded-xl p-4 text-white text-left ltr placeholder-white/30 focus:outline-none focus:border-indigo-500 font-mono tracking-widest"
                      dir="ltr"
                    />
                  ) : (
                    <input
                      value={sendAddr}
                      onChange={(e) => setSendAddr(e.target.value)}
                      placeholder={`${t("wallet.externalAddress")} (${currencyMeta(cryptoSheet.currency).code})`}
                      className="w-full bg-[#262626] border border-white/10 rounded-xl p-4 text-white text-left ltr placeholder-white/30 focus:outline-none focus:border-indigo-500 font-mono text-sm"
                      dir="ltr"
                    />
                  )}

                  <input
                    value={sendAmount}
                    onChange={(e) => setSendAmount(e.target.value.replace(/[^\d.]/g, ""))}
                    placeholder={`${t("wallet.amount")} (${currencyMeta(cryptoSheet.currency).code})`}
                    className="w-full bg-[#262626] border border-white/10 rounded-xl p-4 text-white text-center text-lg placeholder-white/30 focus:outline-none focus:border-indigo-500"
                    inputMode="decimal"
                  />
                  <input
                    value={desc}
                    onChange={(e) => setDesc(e.target.value)}
                    placeholder={t("wallet.descPlaceholder")}
                    className="w-full bg-[#262626] border border-white/10 rounded-xl p-4 text-white placeholder-white/30 focus:outline-none focus:border-indigo-500"
                  />
                  {sendMode === "external" && (
                    <p className="text-xs text-white/30 text-center flex items-center justify-center gap-1.5">
                      <ExternalLink size={12} /> {t("wallet.withdrawExternalNote")}
                    </p>
                  )}
                  <Button
                    variant="primary" size="lg" fullWidth
                    disabled={!sendAmount || Number(sendAmount) <= 0 || sending ||
                      (sendMode === "internal" ? !sendTo : sendAddr.trim().length < 8)}
                    onClick={handleCryptoSend}
                  >
                    {sending
                      ? <><Loader2 size={16} className="animate-spin ml-2" />{t("wallet.sending")}</>
                      : t("wallet.send")}
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
