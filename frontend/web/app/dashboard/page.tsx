"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  api,
  isAuthenticated,
  type Identity,
  type RewardWallet,
} from "@/lib/api";
import { panelsForRole } from "@/lib/roles";

const ROLE_LABELS: Record<string, string> = {
  individual: "کاربر",
  driver: "راننده",
  cargo_owner: "صاحب بار",
  freelancer: "فریلنسر",
};

function greeting(): string {
  const h = new Date().getHours();
  if (h < 6) return "شب بخیر";
  if (h < 12) return "صبح بخیر";
  if (h < 17) return "ظهر بخیر";
  if (h < 21) return "عصر بخیر";
  return "شب بخیر";
}

export default function DashboardPage() {
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [me, setMe] = useState<Identity | null>(null);
  const [wallet, setWallet] = useState<RewardWallet | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!isAuthenticated()) {
      router.replace("/login");
      return;
    }
    setReady(true);
    api.identity
      .me()
      .then(setMe)
      .catch(() => setError("بارگذاری حساب ممکن نشد."));
    api.growth
      .rewards()
      .then(setWallet)
      .catch(() => {});
  }, [router]);

  if (!ready) return null;

  const role = me?.entity_type ?? "individual";
  const panels = panelsForRole(role);

  return (
    <main className="page">
      {error && <div className="card danger">{error}</div>}

      <div className="card">
        <div className="row-between">
          <div>
            <div className="muted">{greeting()}،</div>
            <strong style={{ fontSize: "1.2rem" }}>
              {me?.profile?.display_name ?? "کاربر دیلیکس"} 👋
            </strong>
            <div style={{ marginTop: 4 }}>
              <span className="badge">{ROLE_LABELS[role] ?? "کاربر"}</span>
            </div>
          </div>
          <div style={{ textAlign: "start" }}>
            <div className="muted">Earth ID</div>
            <div style={{ fontFamily: "monospace" }}>{me?.earth_id.slice(0, 12) ?? "…"}…</div>
          </div>
        </div>
      </div>

      <a className="card service-tile" href="/wallet">
        <span className="ico-lg" aria-hidden>💳</span>
        <strong>کیف پول</strong>
        {wallet && wallet.balances.length > 0 ? (
          <span className="muted">
            {wallet.balances
              .map((b) => `${(b.amount_minor / 100).toLocaleString("fa-IR")} ${b.currency}`)
              .join(" · ")}
            {wallet.pending_count > 0 && ` · ${wallet.pending_count} در انتظار`}
          </span>
        ) : (
          <span className="muted">مالی، escrow و پرداخت‌ها</span>
        )}
      </a>

      <h2 style={{ fontSize: "1rem", marginTop: 8 }}>خدمات من</h2>
      <div className="grid">
        {panels.map((panel) => (
          <a key={panel.href} className="card service-tile" href={panel.href}>
            <span className="ico-lg" aria-hidden>{panel.icon}</span>
            <strong>{panel.title}</strong>
            <span className="muted">{panel.subtitle}</span>
          </a>
        ))}
      </div>

      <a className="card service-tile" href="/earth">
        <span className="ico-lg" aria-hidden>🌍</span>
        <strong>کره زمین</strong>
        <span className="muted">اکتشاف جهانی افراد و کسب‌وکارها روی نقشه سه‌بعدی</span>
      </a>

      <a className="card service-tile" href="/services">
        <span className="ico-lg" aria-hidden>🧩</span>
        <strong>همه‌ی خدمات</strong>
        <span className="muted">حمل‌ونقل، بیمه، بازار، ارتباطات و بیشتر</span>
      </a>
    </main>
  );
}
