"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { api, type PointsOut, type BadgeOut, isAuthenticated } from "@/lib/api";

export default function GamificationPage() {
  const [points, setPoints] = useState<PointsOut | null>(null);
  const [badges, setBadges] = useState<BadgeOut[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const authed = typeof window !== "undefined" && isAuthenticated();

  async function load() {
    if (!authed) {
      setError("برای مشاهده‌ی امتیازها ابتدا وارد شوید.");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const [pts, bdg] = await Promise.all([
        api.gamification.points(),
        api.gamification.badges().catch(() => [] as BadgeOut[]),
      ]);
      setPoints(pts);
      setBadges(bdg);
    } catch {
      setError("بارگذاری امتیازها ممکن نشد.");
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
        <h1 style={{ fontSize: "1.2rem" }}>امتیاز و نشان</h1>
      </div>
      <p className="muted">امتیازهای فعالیت و نشان‌های کسب‌شده</p>

      {!authed && <div className="card danger">برای مشاهده‌ی امتیازها ابتدا وارد شوید.</div>}
      {loading && <p className="muted">در حال بارگذاری…</p>}
      {error && <div className="card danger">{error}</div>}

      {points && (
        <div className="card">
          <div className="row-between">
            <strong>امتیازِ من</strong>
            <span className="badge">{points.balance.toLocaleString("fa-IR")}</span>
          </div>
        </div>
      )}

      <div className="card">
        <strong>نشان‌ها</strong>
        {badges.length === 0 ? (
          <p className="muted">هنوز نشانی کسب نشده است.</p>
        ) : (
          badges.map((b) => (
            <div key={b.id} className="row-between">
              <span>🏅 {b.badge_code}</span>
              {b.description && <span className="muted">{b.description}</span>}
            </div>
          ))
        )}
      </div>
    </main>
  );
}
