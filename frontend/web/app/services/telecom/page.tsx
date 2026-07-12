"use client";

import { useState } from "react";
import Link from "next/link";
import { api, type TopUpOut, type EsimOut, isAuthenticated } from "@/lib/api";

const STATUS_LABEL: Record<string, string> = {
  pending: "در انتظار",
  processing: "در حال پردازش",
  completed: "انجام‌شده",
  failed: "ناموفق",
  active: "فعال",
};

export default function TelecomPage() {
  const [topupForm, setTopupForm] = useState({ msisdn: "", product_code: "", amount: "" });
  const [esimForm, setEsimForm] = useState({ iccid: "", country_code: "" });
  const [topup, setTopup] = useState<TopUpOut | null>(null);
  const [esim, setEsim] = useState<EsimOut | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const authed = typeof window !== "undefined" && isAuthenticated();

  async function submitTopUp() {
    const amount = Number(topupForm.amount);
    if (!topupForm.msisdn || !topupForm.product_code || !amount) return;
    setBusy(true);
    setError(null);
    try {
      const order = await api.telecom.topUp({
        msisdn: topupForm.msisdn,
        product_code: topupForm.product_code,
        amount_minor: Math.round(amount * 10),
        currency: "IRR",
      });
      setTopup(order);
      setTopupForm({ msisdn: "", product_code: "", amount: "" });
    } catch {
      setError("خریدِ بسته ناموفق بود. ابتدا وارد شوید.");
    } finally {
      setBusy(false);
    }
  }

  async function submitEsim() {
    if (!esimForm.iccid || !esimForm.country_code) return;
    setBusy(true);
    setError(null);
    try {
      const profile = await api.telecom.activateEsim({
        iccid: esimForm.iccid,
        country_code: esimForm.country_code,
      });
      setEsim(profile);
      setEsimForm({ iccid: "", country_code: "" });
    } catch {
      setError("فعال‌سازیِ eSIM ناموفق بود. ابتدا وارد شوید.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="page">
      <div className="row-between">
        <Link href="/services" className="link-btn">
          ← خدمات
        </Link>
        <h1 style={{ fontSize: "1.2rem" }}>ارتباطات</h1>
      </div>
      <p className="muted">بسته‌های اینترنت و eSIM از اپراتورهای طرف قرارداد</p>

      {!authed && <div className="card danger">برای خرید بسته یا فعال‌سازیِ eSIM ابتدا وارد شوید.</div>}
      {error && <div className="card danger">{error}</div>}

      <div className="card">
        <strong>بسته‌ی اینترنت / شارژ</strong>
        <input className="input" placeholder="شماره (msisdn)" value={topupForm.msisdn} onChange={(e) => setTopupForm({ ...topupForm, msisdn: e.target.value })} />
        <input className="input" placeholder="کدِ محصول" value={topupForm.product_code} onChange={(e) => setTopupForm({ ...topupForm, product_code: e.target.value })} />
        <input className="input" type="number" placeholder="مبلغ (تومان)" value={topupForm.amount} onChange={(e) => setTopupForm({ ...topupForm, amount: e.target.value })} />
        <button className="btn" style={{ marginTop: 8 }} disabled={!authed || busy} onClick={submitTopUp}>
          خرید
        </button>
        {topup && (
          <div className="row-between" style={{ marginTop: 8 }}>
            <span className="muted">{topup.msisdn} · {topup.product_code}</span>
            <span className="badge">{STATUS_LABEL[topup.status] ?? topup.status}</span>
          </div>
        )}
      </div>

      <div className="card">
        <strong>eSIM بین‌المللی</strong>
        <p className="muted">برای سفر، eSIM فعال‌سازی فوری.</p>
        <input className="input" placeholder="ICCID" value={esimForm.iccid} onChange={(e) => setEsimForm({ ...esimForm, iccid: e.target.value })} />
        <input className="input" placeholder="کدِ کشور (مثلاً IR)" value={esimForm.country_code} onChange={(e) => setEsimForm({ ...esimForm, country_code: e.target.value })} />
        <button className="btn" style={{ marginTop: 8 }} disabled={!authed || busy} onClick={submitEsim}>
          فعال‌سازی
        </button>
        {esim && (
          <div className="row-between" style={{ marginTop: 8 }}>
            <span className="muted">{esim.iccid} · {esim.country_code}</span>
            <span className="badge">{STATUS_LABEL[esim.status] ?? esim.status}</span>
          </div>
        )}
      </div>
    </main>
  );
}
