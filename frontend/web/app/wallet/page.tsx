"use client";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import {
  ApiError,
  api,
  isAuthenticated,
  type PaymentOrderOut,
  type ReferralLink,
  type RevenueShare,
  type RewardWallet,
} from "@/lib/api";

type Modal = "escrow" | null;

function formatMoney(amountMinor: number, currency: string): string {
  const cur = currency.toUpperCase();
  if (cur === "IRR") return `${Math.round(amountMinor / 10).toLocaleString("fa-IR")} تومان`;
  return `${(amountMinor / 100).toLocaleString("fa-IR", { maximumFractionDigits: 2 })} ${cur}`;
}

function apiMessage(error: unknown): string {
  if (error instanceof ApiError) return error.message || "درخواست ناموفق بود.";
  return "درخواست ناموفق بود.";
}

export default function WalletPage() {
  const router = useRouter();
  const [wallet, setWallet] = useState<RewardWallet | null>(null);
  const [referral, setReferral] = useState<ReferralLink | null>(null);
  const [revenue, setRevenue] = useState<RevenueShare | null>(null);
  const [orders, setOrders] = useState<PaymentOrderOut[]>([]);
  const [ready, setReady] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [modal, setModal] = useState<Modal>(null);
  const [payee, setPayee] = useState("");
  const [amount, setAmount] = useState("");
  const [currency, setCurrency] = useState("IRR");
  const [sending, setSending] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [w, r, rev] = await Promise.all([
        api.growth.rewards(),
        api.growth.referralLink().catch(() => null),
        api.growth.revenueShare().catch(() => null),
      ]);
      setWallet(w);
      setReferral(r);
      setRevenue(rev);
    } catch (err) {
      setError(apiMessage(err));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!isAuthenticated()) {
      router.replace("/login");
      return;
    }
    setReady(true);
    load();
  }, [router, load]);

  const balances = wallet?.balances ?? [];
  const totalRewards = useMemo(
    () => balances.reduce((sum, item) => sum + item.amount_minor, 0),
    [balances],
  );

  async function createEscrow(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setNotice(null);
    setError(null);

    const trimmedPayee = payee.trim();
    const amountNumber = Number(amount);
    if (!trimmedPayee) {
      setError("Earth ID مقصد را وارد کن.");
      return;
    }
    if (!Number.isFinite(amountNumber) || amountNumber <= 0) {
      setError("مبلغ معتبر نیست.");
      return;
    }

    setSending(true);
    try {
      const amountMinor = currency.toUpperCase() === "IRR"
        ? Math.round(amountNumber * 10)
        : Math.round(amountNumber * 100);
      const order = await api.payments.createEscrow({
        payee_earth_id: trimmedPayee,
        amount_minor: amountMinor,
        currency: currency.toUpperCase(),
        provider_code: "sandbox",
      });
      setOrders((prev) => [order, ...prev]);
      setNotice("سفارش امانی ساخته شد. برای تسویه یا برگشت از عملیات همان کارت استفاده کن.");
      setPayee("");
      setAmount("");
      setModal(null);
    } catch (err) {
      setError(apiMessage(err));
    } finally {
      setSending(false);
    }
  }

  async function updateOrder(orderId: string, action: "capture" | "refund") {
    setError(null);
    setNotice(null);
    try {
      const updated = action === "capture"
        ? await api.payments.capture(orderId)
        : await api.payments.refund(orderId);
      setOrders((prev) => prev.map((order) => order.id === orderId ? updated : order));
      setNotice(action === "capture" ? "سفارش امانی تسویه شد." : "سفارش امانی برگشت خورد.");
    } catch (err) {
      setError(apiMessage(err));
    }
  }

  if (!ready) return null;

  return (
    <main className="page">
      <div className="row-between">
        <div>
          <h1>کیف پول</h1>
          <p className="muted">کیفِ پاداش و پرداخت امانی Dilix</p>
        </div>
        <button className="btn secondary" type="button" onClick={load} disabled={loading}>
          {loading ? "در حال بارگذاری…" : "تلاش مجدد"}
        </button>
      </div>

      {error && <div className="card danger">{error}</div>}
      {notice && <div className="card" style={{ borderColor: "var(--color-success)" }}>{notice}</div>}

      <section className="card">
        <div className="row-between">
          <strong>موجودی پاداش</strong>
          <span className="badge">{wallet?.pending_count ?? 0} pending</span>
        </div>
        {loading ? (
          <p className="muted">در حال دریافت موجودی…</p>
        ) : balances.length > 0 ? (
          <ul className="plain-list">
            {balances.map((item) => (
              <li key={item.currency} className="row-between">
                <span>{item.currency}</span>
                <strong>{formatMoney(item.amount_minor, item.currency)}</strong>
              </li>
            ))}
          </ul>
        ) : (
          <p className="muted">هنوز پاداشی ثبت نشده است. کیف پول فعال است، اما موجودی پاداش ندارد.</p>
        )}
        {balances.length > 0 && (
          <p className="muted">جمع خام پاداش‌ها: {totalRewards.toLocaleString("fa-IR")} واحد خرد</p>
        )}
      </section>

      <section className="grid">
        <button className="card service-tile" type="button" onClick={() => setModal("escrow")}>
          <span className="service-ico">↔</span>
          <strong>انتقال امن</strong>
          <span className="muted">ساخت سفارش امانی</span>
        </button>
        <div className="card service-tile" aria-disabled="true">
          <span className="service-ico">＋</span>
          <strong>شارژ مستقیم</strong>
          <span className="muted">در Core فعلی فقط پرداخت امانی فعال است.</span>
        </div>
        <div className="card service-tile" aria-disabled="true">
          <span className="service-ico">−</span>
          <strong>برداشت</strong>
          <span className="muted">نیازمند ماژول درگاه/تسویه است.</span>
        </div>
        <div className="card service-tile" aria-disabled="true">
          <span className="service-ico">◎</span>
          <strong>درآمد</strong>
          <span className="muted">{revenue?.eligible ? "فعال" : "غیرفعال"}</span>
        </div>
      </section>

      {revenue && (
        <section className="card">
          <div className="row-between">
            <strong>سهم از درآمد</strong>
            <span className="badge">{revenue.plan}</span>
          </div>
          <p className="muted">
            سهم فعلی: {(revenue.entitlement_bps / 100).toLocaleString("fa-IR")}٪ ·
            واحد سرمایه‌گذاری: {revenue.investment_units.toLocaleString("fa-IR")}
          </p>
          <p className="muted">{revenue.note}</p>
        </section>
      )}

      <section className="card">
        <strong>لینک دعوت</strong>
        {referral ? (
          <>
            <p className="muted" style={{ wordBreak: "break-all" }}>{referral.url}</p>
            <p className="muted">دعوت‌شده‌ها: {referral.total_referred.toLocaleString("fa-IR")}</p>
          </>
        ) : (
          <p className="muted">لینک دعوت در دسترس نیست.</p>
        )}
      </section>

      {orders.length > 0 && (
        <section className="card">
          <strong>سفارش‌های امانی همین نشست</strong>
          <ul className="plain-list">
            {orders.map((order) => (
              <li key={order.id}>
                <div className="row-between">
                  <span>{formatMoney(order.amount_minor, order.currency)}</span>
                  <span className="badge">{order.status}</span>
                </div>
                <p className="muted" style={{ wordBreak: "break-all" }}>مقصد: {order.payee_earth_id}</p>
                {order.status === "held" && (
                  <div className="row" style={{ gap: 8 }}>
                    <button className="btn" type="button" onClick={() => updateOrder(order.id, "capture")}>تسویه</button>
                    <button className="btn secondary" type="button" onClick={() => updateOrder(order.id, "refund")}>برگشت</button>
                  </div>
                )}
              </li>
            ))}
          </ul>
        </section>
      )}

      {modal === "escrow" && (
        <div className="card" role="dialog" aria-modal="true">
          <div className="row-between">
            <strong>انتقال امن (Escrow)</strong>
            <button className="btn link" type="button" onClick={() => setModal(null)}>بستن</button>
          </div>
          <form onSubmit={createEscrow}>
            <label className="muted" htmlFor="payee">Earth ID مقصد</label>
            <input
              id="payee"
              className="input"
              value={payee}
              onChange={(event) => setPayee(event.target.value)}
              placeholder="UUID مقصد"
              dir="ltr"
            />
            <label className="muted" htmlFor="amount">مبلغ</label>
            <input
              id="amount"
              className="input"
              value={amount}
              onChange={(event) => setAmount(event.target.value)}
              inputMode="decimal"
              placeholder="مثلاً 50000"
            />
            <label className="muted" htmlFor="currency">ارز</label>
            <select id="currency" className="input" value={currency} onChange={(event) => setCurrency(event.target.value)}>
              <option value="IRR">IRR (ورودی به تومان)</option>
              <option value="USD">USD</option>
              <option value="EUR">EUR</option>
            </select>
            <button className="btn" type="submit" disabled={sending}>
              {sending ? "در حال ساخت…" : "ساخت سفارش امانی"}
            </button>
          </form>
        </div>
      )}
    </main>
  );
}
