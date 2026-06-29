"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  api,
  setAccessToken,
  isAuthenticated,
  type Identity,
  type RewardWallet,
  type ReferralLink,
} from "@/lib/api";
import { t } from "@/lib/i18n";

export default function MePage() {
  const tr = t("fa");
  const router = useRouter();
  const [me, setMe] = useState<Identity | null>(null);
  const [wallet, setWallet] = useState<RewardWallet | null>(null);
  const [referral, setReferral] = useState<ReferralLink | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [ready, setReady] = useState(false);

  async function loadAccount() {
    try {
      const [identity, w, r] = await Promise.all([
        api.identity.me(),
        api.growth.rewards().catch(() => null),
        api.growth.referralLink().catch(() => null),
      ]);
      setMe(identity);
      setWallet(w);
      setReferral(r);
    } catch {
      setError("بارگذاری حساب ممکن نشد.");
    }
  }

  useEffect(() => {
    if (!isAuthenticated()) {
      router.replace("/login");
      return;
    }
    setReady(true);
    loadAccount();
  }, [router]);

  function logout() {
    setAccessToken(null);
    router.replace("/login");
  }

  async function enableVisibility() {
    try {
      await api.identity.setVisibility({
        discoverable: true,
        audience: "connections",
        geo_precision: "region",
        visible_fields: [],
      });
      alert("اکنون روی نقشه (به‌صورت محدود و fuzzed) دیده می‌شوید.");
    } catch {
      setError("به‌روزرسانی حریم خصوصی ممکن نشد.");
    }
  }

  if (!ready) return null;

  return (
    <main className="page">
      <h1>{tr.me_title}</h1>
      {error && <div className="card danger">{error}</div>}

      <div className="card">
        <div className="row-between">
          <div>
            <strong>{me?.profile?.display_name ?? "کاربر"}</strong>
            <div className="muted">Earth ID: {me?.earth_id.slice(0, 12)}…</div>
          </div>
          <span className="badge">KYC L{me?.kyc_level ?? 0}</span>
        </div>
      </div>

      <div className="card">
        <strong>{tr.wallet}</strong>
        {wallet && Object.keys(wallet.total_by_currency).length > 0 ? (
          <ul className="plain-list">
            {Object.entries(wallet.total_by_currency).map(([cur, amount]) => (
              <li key={cur}>
                {amount.toLocaleString("fa-IR")} <span className="muted">{cur}</span>
              </li>
            ))}
          </ul>
        ) : (
          <p className="muted">هنوز پاداشی ثبت نشده است.</p>
        )}
      </div>

      <div className="card">
        <strong>لینکِ دعوت</strong>
        {referral ? (
          <p className="muted" style={{ wordBreak: "break-all" }}>
            {referral.url}
          </p>
        ) : (
          <p className="muted">لینک در دسترس نیست.</p>
        )}
      </div>

      <div className="card">
        <strong>{tr.privacy_settings}</strong>
        <p className="muted">پیش‌فرض: روی نقشه دیده نمی‌شوید (ADR-06). با فعال‌سازی، فقط در سطحِ منطقه نمایش داده می‌شوید.</p>
        <button className="btn secondary" onClick={enableVisibility}>
          فعال‌سازی دیده‌شدن (محدود)
        </button>
      </div>

      <a className="card service-tile" href="/provider">
        <span className="ico-lg" aria-hidden>🏢</span>
        <strong>{tr.provider_portal}</strong>
        <span className="muted">ثبتِ سرویس، sandbox، webhook و کلیدها</span>
      </a>

      <button className="btn secondary" onClick={logout} style={{ marginTop: 12 }}>
        خروج
      </button>
    </main>
  );
}
