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
  type RoleOption,
} from "@/lib/api";
import { t } from "@/lib/i18n";
import { panelsForRole, setStoredRole } from "@/lib/roles";

export default function MePage() {
  const tr = t("fa");
  const router = useRouter();
  const [me, setMe] = useState<Identity | null>(null);
  const [wallet, setWallet] = useState<RewardWallet | null>(null);
  const [referral, setReferral] = useState<ReferralLink | null>(null);
  const [roles, setRoles] = useState<RoleOption[]>([]);
  const [switching, setSwitching] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [ready, setReady] = useState(false);

  async function loadAccount() {
    try {
      const [identity, w, r, roleList] = await Promise.all([
        api.identity.me(),
        api.growth.rewards().catch(() => null),
        api.growth.referralLink().catch(() => null),
        api.identity.roles().catch(() => [] as RoleOption[]),
      ]);
      setMe(identity);
      setWallet(w);
      setReferral(r);
      setRoles(roleList);
      // هم‌گام‌سازیِ ناوبریِ نقش‌آگاه با نقشِ واقعیِ کاربر.
      setStoredRole(identity.entity_type);
    } catch {
      setError("بارگذاری حساب ممکن نشد.");
    }
  }

  async function switchRole(entityType: string) {
    if (!me || entityType === me.entity_type) return;
    setSwitching(entityType);
    setError(null);
    try {
      const updated = await api.identity.changeRole(entityType);
      setMe(updated);
      setStoredRole(updated.entity_type);
    } catch {
      setError("تغییرِ نقش ممکن نشد. برخی نقش‌ها نیازمندِ تأیید هستند.");
    } finally {
      setSwitching(null);
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
    setStoredRole(null);
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
        <strong>نقشِ من</strong>
        <p className="muted">
          نقشِ فعلی، پنل و ابزارهایی که می‌بینید را تعیین می‌کند. می‌توانید هر زمان بین
          نقش‌های زیر جابجا شوید.
        </p>
        <div className="role-switch">
          {roles.map((r) => {
            const active = me?.entity_type === r.entity_type;
            return (
              <button
                key={r.entity_type}
                className={`role-chip${active ? " active" : ""}`}
                onClick={() => switchRole(r.entity_type)}
                disabled={active || switching != null}
                title={r.description}
              >
                {switching === r.entity_type ? "…" : r.label}
                {active && <span className="role-current"> ✓</span>}
              </button>
            );
          })}
        </div>
        {roles.length === 0 && (
          <p className="muted">فهرستِ نقش‌ها در دسترس نیست.</p>
        )}
      </div>

      {me &&
        panelsForRole(me.entity_type).map((panel) => (
          <a key={panel.href} className="card service-tile" href={panel.href}>
            <span className="ico-lg" aria-hidden>
              {panel.icon}
            </span>
            <strong>{panel.title}</strong>
            <span className="muted">{panel.subtitle}</span>
          </a>
        ))}

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

      <a className="card service-tile" href="/dashboard">
        <span className="ico-lg" aria-hidden>📊</span>
        <strong>داشبورد</strong>
        <span className="muted">میان‌برهای نقش‌محور، کیف پول و خدمات</span>
      </a>

      <a className="card service-tile" href="/onboarding">
        <span className="ico-lg" aria-hidden>🚀</span>
        <strong>راه‌اندازی حساب</strong>
        <span className="muted">انتخابِ نقش، تکمیلِ پروفایل و حریمِ خصوصی</span>
      </a>

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
