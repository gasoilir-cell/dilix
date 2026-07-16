"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { api, type MembershipOut, isAuthenticated } from "@/lib/api";

const PLANS: { key: "free" | "standard" | "premium"; label: string; desc: string }[] = [
  { key: "free", label: "رایگان", desc: "امکاناتِ پایه" },
  { key: "standard", label: "استاندارد", desc: "کش‌بک و مزایای بیشتر" },
  { key: "premium", label: "ویژه", desc: "بیشترین کش‌بک و اولویت" },
];

export default function MembershipPage() {
  const [membership, setMembership] = useState<MembershipOut | null>(null);
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const authed = typeof window !== "undefined" && isAuthenticated();

  async function load() {
    if (!authed) {
      setError("برای مشاهده‌ی عضویت ابتدا وارد شوید.");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      setMembership(await api.membership.get());
    } catch {
      setError("بارگذاری عضویت ممکن نشد.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function upgrade(plan: "free" | "standard" | "premium") {
    setBusy(plan);
    setError(null);
    try {
      setMembership(await api.membership.upgrade({ plan }));
    } catch {
      setError("تغییرِ طرح ممکن نشد.");
    } finally {
      setBusy(null);
    }
  }

  async function cancel() {
    setBusy("cancel");
    setError(null);
    try {
      setMembership(await api.membership.cancel());
    } catch {
      setError("لغوِ عضویت ممکن نشد.");
    } finally {
      setBusy(null);
    }
  }

  return (
    <main className="page">
      <div className="row-between">
        <Link href="/services" className="link-btn">
          ← خدمات
        </Link>
        <h1 style={{ fontSize: "1.2rem" }}>عضویت</h1>
      </div>
      <p className="muted">طرح‌های اشتراک و کش‌بک</p>

      {!authed && <div className="card danger">برای مشاهده‌ی عضویت ابتدا وارد شوید.</div>}
      {loading && <p className="muted">در حال بارگذاری…</p>}
      {error && <div className="card danger">{error}</div>}

      {membership && (
        <div className="card">
          <div className="row-between">
            <strong>طرحِ فعلی</strong>
            <span className="badge">{membership.status}</span>
          </div>
          <div className="row-between">
            <span className="muted">طرح: {membership.plan}</span>
            <span className="muted">کش‌بک: {(membership.cashback_bps / 100).toLocaleString("fa-IR")}٪</span>
          </div>
          {membership.expires_at && (
            <p className="muted">انقضا: {new Date(membership.expires_at).toLocaleDateString("fa-IR")}</p>
          )}
        </div>
      )}

      <div className="grid">
        {PLANS.map((p) => {
          const active = membership?.plan === p.key;
          return (
            <div key={p.key} className="card service-tile">
              <strong>{p.label}</strong>
              <span className="muted">{p.desc}</span>
              <button
                className={`btn${active ? " secondary" : ""}`}
                style={{ marginTop: 8 }}
                onClick={() => upgrade(p.key)}
                disabled={!authed || active || busy != null}
              >
                {busy === p.key ? "…" : active ? "فعال" : "انتخاب"}
              </button>
            </div>
          );
        })}
      </div>

      {membership && membership.plan !== "free" && (
        <button className="btn secondary" onClick={cancel} disabled={busy != null} style={{ marginTop: 12 }}>
          {busy === "cancel" ? "…" : "لغوِ عضویت"}
        </button>
      )}
    </main>
  );
}
