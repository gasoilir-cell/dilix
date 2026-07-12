"use client";

import { useState } from "react";
import Link from "next/link";
import { api, type PolicyOut, isAuthenticated } from "@/lib/api";

const STATUS_LABEL: Record<string, string> = {
  quoted: "استعلام‌شده",
  issued: "صادرشده",
  active: "فعال",
  claimed: "خسارت",
  expired: "منقضی",
  cancelled: "لغوشده",
};

function formatMoney(minor: number, currency: string) {
  if (currency === "IRR") return `${(minor / 10).toLocaleString("fa-IR")} تومان`;
  return `${(minor / 100).toLocaleString("fa-IR")} ${currency}`;
}

export default function InsurancePage() {
  const [form, setForm] = useState({ product_code: "", coverage: "" });
  const [policy, setPolicy] = useState<PolicyOut | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const authed = typeof window !== "undefined" && isAuthenticated();

  async function submit() {
    const coverage = Number(form.coverage);
    if (!form.product_code || !coverage) return;
    setLoading(true);
    setError(null);
    try {
      const p = await api.insurance.createQuote({
        product_code: form.product_code,
        coverage_minor: Math.round(coverage * 10),
        currency: "IRR",
      });
      setPolicy(p);
    } catch {
      setError("استعلامِ نرخِ بیمه ناموفق بود. ابتدا وارد شوید.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="page">
      <div className="row-between">
        <Link href="/services" className="link-btn">
          ← خدمات
        </Link>
        <h1 style={{ fontSize: "1.2rem" }}>بیمه</h1>
      </div>
      <p className="muted">کانالِ فروش بیمه‌نامه‌ی شرکای دارای مجوز (مانند بیمه البرز)</p>

      {!authed && <div className="card danger">برای استعلامِ نرخ ابتدا وارد شوید.</div>}
      {error && <div className="card danger">{error}</div>}

      <div className="card">
        <strong>استعلام و مقایسه</strong>
        <p className="muted">
          نرخِ بیمه از طریق Adapterهای بیمه‌گرانِ مجاز استعلام می‌شود. Dilix خود بیمه‌نامه صادر نمی‌کند؛
          صدور و خسارت نزدِ بیمه‌گر انجام می‌شود.
        </p>
        <input className="input" placeholder="کدِ محصول (مثلاً CARGO)" value={form.product_code} onChange={(e) => setForm({ ...form, product_code: e.target.value })} />
        <input className="input" type="number" placeholder="مبلغِ پوشش (تومان)" value={form.coverage} onChange={(e) => setForm({ ...form, coverage: e.target.value })} />
        <button className="btn" style={{ marginTop: 8 }} disabled={!authed || loading} onClick={submit}>
          استعلامِ نرخ
        </button>
        {policy && (
          <div className="card" style={{ marginTop: 8 }}>
            <div className="row-between">
              <strong>{policy.product_code}</strong>
              <span className="badge">{STATUS_LABEL[policy.status] ?? policy.status}</span>
            </div>
            <div className="row-between">
              <span className="muted">پوشش: {formatMoney(policy.coverage_minor, policy.currency)}</span>
              <strong>حقِ بیمه: {formatMoney(policy.premium_minor, policy.currency)}</strong>
            </div>
          </div>
        )}
      </div>

      <div className="card">
        <strong>بیمه‌ی همزمان با بار</strong>
        <p className="muted">هنگام صدورِ بارنامه می‌توانید بیمه‌ی باربری را به‌صورت اختیاری اضافه کنید.</p>
        <Link href="/services/freight" className="btn secondary">
          رفتن به حمل‌ونقل
        </Link>
      </div>
    </main>
  );
}
