"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { api, type ReferralLink, type RewardWallet, type RevenueShare, isAuthenticated } from "@/lib/api";

function formatMoney(minor: number, currency: string) {
  if (currency === "IRR") return `${(minor / 10).toLocaleString("fa-IR")} تومان`;
  return `${(minor / 100).toLocaleString("fa-IR")} ${currency}`;
}

export default function GrowthPage() {
  const [referral, setReferral] = useState<ReferralLink | null>(null);
  const [rewards, setRewards] = useState<RewardWallet | null>(null);
  const [revenue, setRevenue] = useState<RevenueShare | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const authed = typeof window !== "undefined" && isAuthenticated();

  async function load() {
    if (!authed) {
      setError("برای مشاهده‌ی رشد و دعوت ابتدا وارد شوید.");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const [ref, rw, rev] = await Promise.all([
        api.growth.referralLink(),
        api.growth.rewards(),
        api.growth.revenueShare().catch(() => null),
      ]);
      setReferral(ref);
      setRewards(rw);
      setRevenue(rev);
    } catch {
      setError("بارگذاری اطلاعاتِ رشد ممکن نشد.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function copyLink() {
    if (!referral) return;
    try {
      await navigator.clipboard.writeText(referral.url);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      setError("کپیِ لینک ممکن نشد.");
    }
  }

  return (
    <main className="page">
      <div className="row-between">
        <Link href="/services" className="link-btn">
          ← خدمات
        </Link>
        <h1 style={{ fontSize: "1.2rem" }}>رشد و دعوت</h1>
      </div>
      <p className="muted">لینکِ دعوت، پاداش‌ها و سهمِ درآمد</p>

      {!authed && <div className="card danger">برای مشاهده‌ی رشد و دعوت ابتدا وارد شوید.</div>}
      {loading && <p className="muted">در حال بارگذاری…</p>}
      {error && <div className="card danger">{error}</div>}

      {referral && (
        <div className="card">
          <strong>لینکِ دعوت</strong>
          <p className="muted">دعوت‌شده‌ها: {referral.total_referred.toLocaleString("fa-IR")}</p>
          <input className="input" value={referral.url} readOnly />
          <button className="btn secondary" style={{ marginTop: 8 }} onClick={copyLink}>
            {copied ? "کپی شد" : "کپیِ لینک"}
          </button>
        </div>
      )}

      {rewards && (
        <div className="card">
          <div className="row-between">
            <strong>کیفِ پاداش</strong>
            <span className="badge">در انتظار: {rewards.pending_count.toLocaleString("fa-IR")}</span>
          </div>
          {rewards.balances.length === 0 && <p className="muted">هنوز پاداشی ثبت نشده است.</p>}
          {rewards.balances.map((b) => (
            <div key={b.currency} className="row-between">
              <span className="muted">{b.reward_count.toLocaleString("fa-IR")} پاداش</span>
              <strong>{formatMoney(b.amount_minor, b.currency)}</strong>
            </div>
          ))}
        </div>
      )}

      {revenue && (
        <div className="card">
          <div className="row-between">
            <strong>سهمِ درآمد</strong>
            <span className="badge">{revenue.eligible ? "واجدِ شرایط" : "غیرواجد"}</span>
          </div>
          <div className="row-between">
            <span className="muted">طرح: {revenue.plan}</span>
            <span className="muted">{(revenue.entitlement_bps / 100).toLocaleString("fa-IR")}٪</span>
          </div>
          {revenue.note && <p className="muted">{revenue.note}</p>}
        </div>
      )}
    </main>
  );
}
