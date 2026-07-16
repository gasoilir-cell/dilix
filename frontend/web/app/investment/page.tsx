"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { api, type PositionOut, isAuthenticated } from "@/lib/api";

function formatMoney(minor: number, currency: string) {
  if (currency === "IRR") return `${(minor / 10).toLocaleString("fa-IR")} تومان`;
  return `${(minor / 100).toLocaleString("fa-IR")} ${currency}`;
}

export default function InvestmentPage() {
  const [positions, setPositions] = useState<PositionOut[]>([]);
  const [fundCode, setFundCode] = useState("GOLD01");
  const [navMinor, setNavMinor] = useState<number | null>(null);
  const [amount, setAmount] = useState("");
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const authed = typeof window !== "undefined" && isAuthenticated();

  async function load() {
    if (!authed) {
      setError("برای مشاهده‌ی سرمایه‌گذاری ابتدا وارد شوید.");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      setPositions(await api.investment.positions());
    } catch {
      setError("بارگذاری موقعیت‌های سرمایه‌گذاری ممکن نشد.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function fetchNav() {
    setError(null);
    setNotice(null);
    try {
      const nav = await api.investment.nav(fundCode.trim());
      setNavMinor(nav.nav_minor);
    } catch {
      setError("دریافتِ NAV صندوق ممکن نشد.");
    }
  }

  async function buy() {
    const value = Number(amount);
    if (!fundCode.trim() || !Number.isFinite(value) || value <= 0) {
      setError("مبلغ و کدِ صندوق را درست وارد کنید.");
      return;
    }
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      // مبلغ به واحدِ خرد (ریال) — ورودی به تومان گرفته می‌شود.
      const pos = await api.investment.buy({ fund_code: fundCode.trim(), amount_minor: value * 10 });
      setPositions((p) => [pos, ...p.filter((x) => x.id !== pos.id)]);
      setAmount("");
      setNotice("خرید ثبت شد.");
    } catch {
      setError("خرید ممکن نشد. موجودی یا احرازِ هویت را بررسی کنید.");
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
        <h1 style={{ fontSize: "1.2rem" }}>سرمایه‌گذاری</h1>
      </div>
      <p className="muted">صندوق‌های دارای مجوز، از طریق بستر Dilix (ADR-09)</p>

      {!authed && <div className="card danger">برای مشاهده‌ی سرمایه‌گذاری ابتدا وارد شوید.</div>}
      {loading && <p className="muted">در حال بارگذاری…</p>}
      {error && <div className="card danger">{error}</div>}
      {notice && <div className="card">{notice}</div>}

      <div className="card">
        <strong>خرید واحدِ صندوق</strong>
        <label className="muted" style={{ display: "block", marginTop: 6 }}>کدِ صندوق</label>
        <input className="input" value={fundCode} onChange={(e) => setFundCode(e.target.value)} />
        <div className="row" style={{ gap: 8, marginTop: 8 }}>
          <button className="btn secondary" onClick={fetchNav}>
            استعلامِ NAV
          </button>
          {navMinor != null && (
            <span className="badge">NAV: {formatMoney(navMinor, "IRR")}</span>
          )}
        </div>
        <label className="muted" style={{ display: "block", marginTop: 8 }}>مبلغ (تومان)</label>
        <input
          className="input"
          inputMode="numeric"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          placeholder="مثلاً ۵۰۰۰۰۰"
        />
        <button className="btn" style={{ marginTop: 8 }} onClick={buy} disabled={busy || !authed}>
          {busy ? "…" : "خرید"}
        </button>
      </div>

      <div className="card">
        <strong>موقعیت‌های من</strong>
        {positions.length === 0 ? (
          <p className="muted">هنوز سرمایه‌گذاری‌ای ثبت نشده است.</p>
        ) : (
          positions.map((p) => (
            <div key={p.id} className="row-between">
              <span>{p.fund_code}</span>
              <span className="muted">{p.units.toLocaleString("fa-IR")} واحد</span>
              <span className="badge">{p.status}</span>
            </div>
          ))
        )}
      </div>
    </main>
  );
}
