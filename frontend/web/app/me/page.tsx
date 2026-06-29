"use client";

import { useEffect, useState } from "react";
import {
  api,
  setAccessToken,
  isAuthenticated,
  type Identity,
  type RewardWallet,
  type ReferralLink,
  type OAuthProvider,
  type OtpChannel,
} from "@/lib/api";
import { getProviderCredential, SocialAuthError } from "@/lib/social";
import { t } from "@/lib/i18n";

const SOCIAL_PROVIDERS: { id: OAuthProvider; label: string; icon: string }[] = [
  { id: "google", label: "Google", icon: "G" },
  { id: "microsoft", label: "Microsoft", icon: "⊞" },
  { id: "apple", label: "Apple", icon: "" },
  { id: "facebook", label: "Facebook", icon: "f" },
];

export default function MePage() {
  const tr = t("fa");
  const [authed, setAuthed] = useState(false);
  const [me, setMe] = useState<Identity | null>(null);
  const [wallet, setWallet] = useState<RewardWallet | null>(null);
  const [referral, setReferral] = useState<ReferralLink | null>(null);
  const [error, setError] = useState<string | null>(null);

  // login form
  const [identifier, setIdentifier] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState<string | null>(null);

  // OTP (پیامک / فیسبوک)
  const [otpChannel, setOtpChannel] = useState<OtpChannel>("sms");
  const [otpDestination, setOtpDestination] = useState("");
  const [otpChallengeId, setOtpChallengeId] = useState<string | null>(null);
  const [otpCode, setOtpCode] = useState("");

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
    const a = isAuthenticated();
    setAuthed(a);
    if (a) loadAccount();
  }, []);

  async function login() {
    setError(null);
    try {
      const tokens = await api.auth.login(identifier, password);
      setAccessToken(tokens.access_token);
      setAuthed(true);
      await loadAccount();
    } catch {
      setError("ورود ناموفق بود. شناسه یا گذرواژه نادرست است.");
    }
  }

  async function socialLogin(provider: OAuthProvider) {
    setError(null);
    setBusy(provider);
    try {
      const credential = await getProviderCredential(provider);
      const res = await api.auth.oauthLogin(provider, credential);
      setAccessToken(res.tokens.access_token);
      setAuthed(true);
      await loadAccount();
    } catch (e) {
      if (e instanceof SocialAuthError) setError(e.message);
      else setError("ورود با شبکه‌ی اجتماعی ناموفق بود.");
    } finally {
      setBusy(null);
    }
  }

  async function sendOtp() {
    setError(null);
    setBusy("otp");
    try {
      const res = await api.auth.otpRequest(otpChannel, otpDestination.trim());
      setOtpChallengeId(res.challenge_id);
    } catch {
      setError("ارسالِ کد ناموفق بود. مقصد را بررسی کنید.");
    } finally {
      setBusy(null);
    }
  }

  async function verifyOtp() {
    if (!otpChallengeId) return;
    setError(null);
    setBusy("otp");
    try {
      const res = await api.auth.otpVerify(otpChallengeId, otpCode.trim());
      setAccessToken(res.tokens.access_token);
      setAuthed(true);
      await loadAccount();
    } catch {
      setError("کدِ واردشده نادرست یا منقضی است.");
    } finally {
      setBusy(null);
    }
  }

  function logout() {
    setAccessToken(null);
    setAuthed(false);
    setMe(null);
    setWallet(null);
    setReferral(null);
    setOtpChallengeId(null);
    setOtpCode("");
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

  if (!authed) {
    return (
      <main className="page">
        <h1>{tr.me_title}</h1>
        <div className="card">
          <strong>ورود به Earth ID</strong>
          <input
            className="input"
            placeholder="ایمیل یا شماره تلفن"
            value={identifier}
            onChange={(e) => setIdentifier(e.target.value)}
          />
          <input
            className="input"
            type="password"
            placeholder="گذرواژه"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && login()}
          />
          <button className="btn" style={{ marginTop: 8 }} onClick={login}>
            ورود
          </button>
          {error && <p className="danger" style={{ marginTop: 8 }}>{error}</p>}
        </div>

        <div className="card">
          <strong>ورود با حسابِ اجتماعی</strong>
          <p className="muted">با Google، Microsoft، Apple یا Facebook وارد شوید.</p>
          <div className="social-grid">
            {SOCIAL_PROVIDERS.map((p) => (
              <button
                key={p.id}
                className="btn secondary social-btn"
                disabled={busy != null}
                onClick={() => socialLogin(p.id)}
              >
                {p.icon && <span className="social-ico" aria-hidden>{p.icon}</span>}
                {busy === p.id ? "در حال اتصال…" : p.label}
              </button>
            ))}
          </div>
        </div>

        <div className="card">
          <strong>ورود با کدِ یک‌بارمصرف</strong>
          <p className="muted">کدِ تأیید را به موبایل (پیامک) یا Facebook Messenger دریافت کنید.</p>
          <div className="seg">
            <button
              className={`seg-btn ${otpChannel === "sms" ? "active" : ""}`}
              onClick={() => setOtpChannel("sms")}
            >
              پیامک
            </button>
            <button
              className={`seg-btn ${otpChannel === "facebook" ? "active" : ""}`}
              onClick={() => setOtpChannel("facebook")}
            >
              Facebook
            </button>
          </div>
          <input
            className="input"
            placeholder={otpChannel === "sms" ? "شماره موبایل (با کدِ کشور)" : "شناسه‌ی کاربرِ Messenger (PSID)"}
            value={otpDestination}
            onChange={(e) => setOtpDestination(e.target.value)}
            disabled={otpChallengeId != null}
          />
          {otpChallengeId == null ? (
            <button
              className="btn"
              style={{ marginTop: 8 }}
              disabled={busy != null || otpDestination.trim().length < 3}
              onClick={sendOtp}
            >
              {busy === "otp" ? "در حال ارسال…" : "ارسالِ کد"}
            </button>
          ) : (
            <>
              <input
                className="input"
                style={{ marginTop: 8 }}
                placeholder="کدِ دریافتی"
                inputMode="numeric"
                value={otpCode}
                onChange={(e) => setOtpCode(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && verifyOtp()}
              />
              <button
                className="btn"
                style={{ marginTop: 8 }}
                disabled={busy != null || otpCode.trim().length < 4}
                onClick={verifyOtp}
              >
                {busy === "otp" ? "در حال بررسی…" : "تأیید و ورود"}
              </button>
              <button
                className="btn link"
                onClick={() => {
                  setOtpChallengeId(null);
                  setOtpCode("");
                }}
              >
                تغییرِ مقصد
              </button>
            </>
          )}
        </div>

        <p className="muted">حساب ندارید؟ با ورودِ اجتماعی یا کدِ یک‌بارمصرف، حساب به‌صورتِ خودکار ساخته می‌شود.</p>
      </main>
    );
  }

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
