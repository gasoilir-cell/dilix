"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  api,
  isAuthenticated,
  type RewardWallet,
  type ReferralLink,
  type RevenueShare,
} from "@/lib/api";

export default function WalletPage() {
  const router = useRouter();
  const [wallet, setWallet] = useState<RewardWallet | null>(null);
  const [referral, setReferral] = useState<ReferralLink | null>(null);
  const [revenue, setRevenue] = useState<RevenueShare | null>(null);
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const [w, r, rev] = await Promise.all([
        api.growth.rewards().catch(() => null),
        api.growth.referralLink().catch(() => null),
        api.growth.revenueShare().catch(() => null),
      ]);
      setWallet(w);
      setReferral(r);
      setRevenue(rev);
    } catch {
      setError("بارگذاری کیف پول ممکن نشد.");
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

  if (!ready) return null;

  const balances = wallet ? Object.entries(wallet.total_by_currency) : [];

  return (
    <main className="page">
      <h1>کیف پول</h1>
      {error && <div className="card danger">{error}</div>}

      <div className="card">
        <strong>موجودیِ پاداش</strong>
        {balances.length > 0 ? (
          <ul className="plain-list">
            {balances.map(([cur, amount]) => (
              <li key={cur}>
                {amount.toLocaleString("fa-IR")} <span className="muted">{cur}</span>
              </li>
            ))}
          </ul>
        ) : (
          <p className="muted">هنوز پاداشی ثبت نشده است.</p>
        )}
      </div>

      {revenue && (
        <div className="card">
          <div className="row-between">
            <strong>سهم از درآمد</strong>
            <span className="badge">{revenue.eligible ? "واجد شرایط" : "غیرفعال"}</span>
          </div>
          <p className="muted">
            سهمِ فعلی: {(revenue.entitlement_bps / 100).toLocaleString("fa-IR")}٪
          </p>
        </div>
      )}

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
        <strong>شارژ و انتقال</strong>
        <p className="muted">
          شارژ، برداشت و انتقالِ وجه به‌زودی از طریق درگاهِ پرداخت فعال می‌شود.
        </p>
      </div>
    </main>
  );
}
