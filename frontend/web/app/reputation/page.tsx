"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { api, type ScoreOut, type ReviewOut, isAuthenticated } from "@/lib/api";

export default function ReputationPage() {
  const [scores, setScores] = useState<ScoreOut[]>([]);
  const [reviews, setReviews] = useState<ReviewOut[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const authed = typeof window !== "undefined" && isAuthenticated();

  async function load() {
    if (!authed) {
      setError("برای مشاهده‌ی اعتبار ابتدا وارد شوید.");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const me = await api.identity.me();
      const [sc, rv] = await Promise.all([
        api.reputation.scores(me.earth_id).catch(() => [] as ScoreOut[]),
        api.reputation.reviews(me.earth_id).catch(() => [] as ReviewOut[]),
      ]);
      setScores(sc);
      setReviews(rv);
    } catch {
      setError("بارگذاری اعتبار ممکن نشد.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <main className="page">
      <div className="row-between">
        <Link href="/services" className="link-btn">
          ← خدمات
        </Link>
        <h1 style={{ fontSize: "1.2rem" }}>اعتبار</h1>
      </div>
      <p className="muted">امتیازِ اعتبار و نظرهای دریافتی (بر پایه‌ی تراکنش‌های واقعی)</p>

      {!authed && <div className="card danger">برای مشاهده‌ی اعتبار ابتدا وارد شوید.</div>}
      {loading && <p className="muted">در حال بارگذاری…</p>}
      {error && <div className="card danger">{error}</div>}

      <div className="card">
        <strong>امتیازِ اعتبار</strong>
        {scores.length === 0 ? (
          <p className="muted">هنوز امتیازی ثبت نشده است.</p>
        ) : (
          scores.map((s) => (
            <div key={s.domain} className="row-between">
              <span className="muted">{s.domain}</span>
              <span className="badge">{(s.score / 10).toLocaleString("fa-IR")}/۱۰</span>
              <span className="muted">{s.review_count.toLocaleString("fa-IR")} نظر</span>
            </div>
          ))
        )}
      </div>

      <div className="card">
        <strong>نظرهای دریافتی</strong>
        {reviews.length === 0 ? (
          <p className="muted">هنوز نظری ثبت نشده است.</p>
        ) : (
          reviews.map((r) => (
            <div key={r.id} style={{ borderTop: "1px solid var(--color-border)", paddingBlock: 8 }}>
              <div className="row-between">
                <span>{"⭐".repeat(r.rating)}</span>
                <span className="muted">{r.domain}</span>
              </div>
              {r.comment && <p className="muted" style={{ marginTop: 4 }}>{r.comment}</p>}
            </div>
          ))
        )}
      </div>
    </main>
  );
}
