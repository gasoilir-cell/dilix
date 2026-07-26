"use client";

/**
 * Dilix — صفحهٔ پرداخت با کد QR (`/pay/DLX-…?a=<ریال>&n=<یادداشت>`)
 *
 * مقصدِ همان نشانی‌ای است که در کدِ QRِ کیف‌پول رمزگذاری می‌شود. چون یک لینکِ
 * https معمولی است، دوربینِ خودِ گوشی هم آن را باز می‌کند و کاربر بدونِ اپ به
 * این‌جا می‌رسد.
 *
 * پول هرگز مستقیماً پس از باز شدنِ لینک جابه‌جا نمی‌شود: اول `qr/resolve` نام و
 * آواتارِ گیرنده را از سرور می‌گیرد تا کاربر مقصد را *ببیند*، بعد خودش تأیید
 * می‌کند. برچسبِ جعلی روی QRِ فروشنده کلاسیک‌ترین کلاهبرداریِ این حوزه است.
 */

import { useCallback, useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import {
  ArrowRight, Loader2, ShieldCheck, AlertCircle,
  CheckCircle2, Lock, User as UserIcon,
} from "lucide-react";
import AppShell from "@/components/layout/AppShell";
import { Button } from "@/components/ui/Button";
import { walletApi, getApiErrorMessage } from "@/lib/api";
import { formatMoney, minorScale } from "@/lib/currency";
import { toPersianNum } from "@/lib/utils";
import { useTranslation } from "@/store/i18n";
import toast from "react-hot-toast";

/**
 * بارِ QR همیشه با دامنهٔ رسمی ساخته می‌شود، نه با `window.location.origin`.
 * سرور میزبان را در برابرِ فهرستِ مجاز بررسی می‌کند؛ اگر نشانیِ همین مرورگر را
 * می‌فرستادیم، روی دامنهٔ آزمایشی یا IP خام رد می‌شد.
 */
const PAY_ORIGIN = "https://dilix.ir";

interface Target {
  earth_id: string;
  display_name: string;
  avatar_url: string | null;
  /** مبلغِ داخلِ کد، به واحدِ خرد (ریال). اگر کد مبلغ نداشته باشد null است. */
  amount: number | null;
  note: string | null;
  is_self: boolean;
}

interface WalletData {
  currency: string;
  balance_available: number;
  is_frozen: boolean;
}

export default function PayPage() {
  const { t } = useTranslation();
  const router = useRouter();
  const params = useParams();
  const earthId = String(params?.earthId || "").toUpperCase();

  const [target, setTarget] = useState<Target | null>(null);
  const [wallet, setWallet] = useState<WalletData | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const [amount, setAmount] = useState("");   // واحدِ نمایشی (تومان)
  const [note, setNote] = useState("");
  const [sending, setSending] = useState(false);
  const [done, setDone] = useState(false);

  const scale = minorScale(wallet?.currency);
  const amountLocked = target?.amount != null;

  const load = useCallback(async () => {
    setLoading(true);
    setLoadError(null);
    try {
      // بازسازیِ بارِ رسمی از پارامترهای همین نشانی.
      const q = new URLSearchParams(window.location.search);
      const carried = new URLSearchParams();
      const a = q.get("a");
      const n = q.get("n");
      if (a) carried.set("a", a);
      if (n) carried.set("n", n);
      const qs = carried.toString();
      const payload = `${PAY_ORIGIN}/pay/${earthId}${qs ? `?${qs}` : ""}`;

      const [resolved, w] = await Promise.all([
        walletApi.qrResolve(payload),
        walletApi.get(),
      ]);
      const tgt: Target = resolved.data;
      setTarget(tgt);
      setWallet(w.data);
      if (tgt.note) setNote(tgt.note);
      if (tgt.amount != null) {
        setAmount(String(Math.round(tgt.amount / minorScale(w.data.currency))));
      }
    } catch (e: unknown) {
      setLoadError(getApiErrorMessage(e, t("pay.err.resolve")));
    } finally {
      setLoading(false);
    }
  }, [earthId, t]);

  useEffect(() => {
    load();
  }, [load]);

  const amountMain = Number(amount || 0);
  const amountMinor = Math.round(amountMain * scale);
  const insufficient =
    wallet != null && amountMinor > 0 && amountMinor > wallet.balance_available;

  const onPay = async () => {
    if (!target) return;
    if (!amountMinor) {
      toast.error(t("pay.err.amountRequired"));
      return;
    }
    setSending(true);
    try {
      await walletApi.transfer(target.earth_id, amountMinor, note || undefined);
      setDone(true);
      toast.success(t("pay.toast.ok"));
    } catch (e: unknown) {
      toast.error(getApiErrorMessage(e, t("pay.err.transfer")));
    } finally {
      setSending(false);
    }
  };

  // ── حالت‌های پایانی ────────────────────────────────────────
  if (loading) {
    return (
      <AppShell title={t("pay.title")}>
        <div className="flex items-center justify-center h-56">
          <Loader2 size={32} className="text-primary-400 animate-spin" />
        </div>
      </AppShell>
    );
  }

  if (loadError || !target || !wallet) {
    return (
      <AppShell title={t("pay.title")}>
        <div className="page-inner flex flex-col items-center justify-center h-56 gap-3 text-center">
          <AlertCircle size={40} className="text-red-400" />
          <p className="text-surface-400">{loadError || t("pay.err.resolve")}</p>
          <Button variant="primary" size="sm" onClick={load}>{t("pay.retry")}</Button>
        </div>
      </AppShell>
    );
  }

  if (done) {
    return (
      <AppShell title={t("pay.title")}>
        <div className="page-inner flex flex-col items-center justify-center h-72 gap-4 text-center">
          <CheckCircle2 size={56} className="text-emerald-400" />
          <p className="text-white text-lg font-bold">{t("pay.done.title")}</p>
          <p className="text-surface-400 text-sm">
            {formatMoney(amountMinor, wallet.currency)} → {target.display_name}
          </p>
          <div className="flex gap-2 mt-2">
            <Button variant="primary" size="md" onClick={() => router.replace("/wallet")}>
              {t("pay.done.wallet")}
            </Button>
            <Button variant="ghost" size="md" onClick={() => router.replace("/dashboard")}>
              {t("pay.done.home")}
            </Button>
          </div>
        </div>
      </AppShell>
    );
  }

  // پرداخت به خود بی‌معناست و سرور هم ردش می‌کند؛ پیش از پر کردنِ فرم بگو.
  if (target.is_self) {
    return (
      <AppShell title={t("pay.title")}>
        <div className="page-inner flex flex-col items-center justify-center h-56 gap-3 text-center">
          <AlertCircle size={40} className="text-amber-400" />
          <p className="text-surface-300">{t("pay.self")}</p>
          <Button variant="primary" size="sm" onClick={() => router.replace("/wallet")}>
            {t("pay.done.wallet")}
          </Button>
        </div>
      </AppShell>
    );
  }

  return (
    <AppShell title={t("pay.title")}>
      <div className="page-inner space-y-4">
        <button
          onClick={() => router.back()}
          className="flex items-center gap-1 text-surface-400 hover:text-white text-sm"
        >
          <ArrowRight size={16} />
          {t("pay.back")}
        </button>

        {/* ── گیرنده ── */}
        <div className="rounded-2xl bg-gradient-to-br from-indigo-900 via-indigo-950 to-[#0A0A0A] border border-indigo-700/30 p-5 flex items-center gap-4">
          <div className="w-14 h-14 rounded-full bg-white/10 overflow-hidden flex items-center justify-center shrink-0">
            {target.avatar_url ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={target.avatar_url} alt="" className="w-full h-full object-cover" />
            ) : (
              <UserIcon size={26} className="text-indigo-200" />
            )}
          </div>
          <div className="min-w-0">
            <p className="text-xs text-indigo-300 mb-0.5">{t("pay.recipient")}</p>
            <p className="text-white font-bold truncate">{target.display_name}</p>
            <p className="text-indigo-300/70 text-xs font-mono ltr text-left" dir="ltr">
              {target.earth_id}
            </p>
          </div>
        </div>

        <div className="flex items-start gap-2 rounded-xl bg-white/5 border border-white/8 p-3">
          <ShieldCheck size={16} className="text-emerald-400 shrink-0 mt-0.5" />
          <p className="text-xs text-surface-400 leading-5">{t("pay.verifyHint")}</p>
        </div>

        {/* ── مبلغ ── */}
        <div>
          <label className="text-xs text-white/40 mb-1 flex items-center gap-1">
            {t("pay.amount")}
            {amountLocked && <Lock size={11} className="text-white/40" />}
          </label>
          <input
            value={amount}
            onChange={(e) => setAmount(e.target.value.replace(/\D/g, ""))}
            readOnly={amountLocked}
            placeholder={t("pay.amountPh")}
            inputMode="numeric"
            className={`w-full bg-[#262626] border rounded-xl p-4 text-white text-center text-lg placeholder-white/30 focus:outline-none ${
              amountLocked
                ? "border-white/5 opacity-80 cursor-not-allowed"
                : "border-white/10 focus:border-indigo-500"
            }`}
          />
          {/* مبلغِ داخلِ کد قفل است: اگر کاربر بتواند عددِ فروشنده را عوض کند،
              «مبلغِ ثابتِ فاکتور» دیگر معنایی ندارد. */}
          {amountLocked && (
            <p className="text-[11px] text-white/35 mt-1">{t("pay.amountLocked")}</p>
          )}
        </div>

        {/* ── یادداشت ── */}
        <div>
          <label className="text-xs text-white/40 mb-1 block">{t("pay.note")}</label>
          <input
            value={note}
            onChange={(e) => setNote(e.target.value.slice(0, 60))}
            placeholder={t("pay.notePh")}
            className="w-full bg-[#262626] border border-white/10 rounded-xl p-4 text-white placeholder-white/30 focus:outline-none focus:border-indigo-500"
          />
        </div>

        {/* ── موجودی ── */}
        <div className="bg-white/5 rounded-xl p-3 flex justify-between text-sm">
          <span className="text-white/40">{t("pay.balance")}</span>
          <span className={insufficient ? "text-red-400 font-medium" : "text-white font-medium"}>
            {formatMoney(wallet.balance_available, wallet.currency)}
          </span>
        </div>

        {wallet.is_frozen && (
          <div className="flex items-center gap-2 bg-red-500/10 border border-red-500/30 rounded-xl p-3">
            <AlertCircle size={16} className="text-red-400" />
            <p className="text-sm text-red-300">{t("pay.frozen")}</p>
          </div>
        )}

        <Button
          variant="primary"
          size="lg"
          fullWidth
          disabled={!amountMinor || sending || insufficient || wallet.is_frozen}
          onClick={onPay}
        >
          {sending ? (
            <><Loader2 size={16} className="animate-spin ml-2" />{t("pay.paying")}</>
          ) : insufficient ? (
            t("pay.insufficient")
          ) : (
            `${t("pay.confirm")} ${amountMain ? toPersianNum(amountMain.toLocaleString()) : ""}`
          )}
        </Button>
      </div>
    </AppShell>
  );
}
