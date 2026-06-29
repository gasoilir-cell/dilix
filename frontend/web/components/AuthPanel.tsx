"use client";

// پنلِ احرازِ هویتِ یکپارچه و آسان — همه‌ی روش‌ها در یک‌جا، با حفظِ امنیت:
//  ۱) اجتماعی (Google/Microsoft/Apple/Facebook) — یک‌لمسی
//  ۲) موبایل با کدِ یک‌بارمصرف (passwordless) — سریع‌ترین مسیر
//  ۳) ایمیل + گذرواژه — با امکانِ «ورود» و «ثبت‌نام»
//
// پس از موفقیت، توکن ذخیره و onAuthenticated فراخوانی می‌شود.

import { useState } from "react";
import {
  api,
  setAccessToken,
  type OAuthProvider,
} from "@/lib/api";
import { getProviderCredential, SocialAuthError } from "@/lib/social";

type Method = "phone" | "email";
type EmailMode = "login" | "register";

const SOCIAL_PROVIDERS: { id: OAuthProvider; label: string; icon: string }[] = [
  { id: "google", label: "Google", icon: "G" },
  { id: "microsoft", label: "Microsoft", icon: "⊞" },
  { id: "apple", label: "Apple", icon: "" },
  { id: "facebook", label: "Facebook", icon: "f" },
];

export default function AuthPanel({ onAuthenticated }: { onAuthenticated: () => void }) {
  const [method, setMethod] = useState<Method>("phone");
  const [emailMode, setEmailMode] = useState<EmailMode>("login");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [showPwd, setShowPwd] = useState(false);

  // phone OTP
  const [phone, setPhone] = useState("");
  const [otpChallengeId, setOtpChallengeId] = useState<string | null>(null);
  const [otpCode, setOtpCode] = useState("");

  // email login/register
  const [displayName, setDisplayName] = useState("");
  const [identifier, setIdentifier] = useState("");
  const [password, setPassword] = useState("");

  function finish() {
    setError(null);
    onAuthenticated();
  }

  async function socialLogin(provider: OAuthProvider) {
    setError(null);
    setBusy(provider);
    try {
      const credential = await getProviderCredential(provider);
      const res = await api.auth.oauthLogin(provider, credential);
      setAccessToken(res.tokens.access_token);
      finish();
    } catch (e) {
      setError(e instanceof SocialAuthError ? e.message : "ورود با شبکه‌ی اجتماعی ناموفق بود.");
    } finally {
      setBusy(null);
    }
  }

  async function sendOtp() {
    setError(null);
    setBusy("otp");
    try {
      const res = await api.auth.otpRequest("sms", phone.trim());
      setOtpChallengeId(res.challenge_id);
    } catch {
      setError("ارسالِ کد ناموفق بود. شماره‌ی موبایل را بررسی کنید.");
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
      finish();
    } catch {
      setError("کدِ واردشده نادرست یا منقضی است.");
    } finally {
      setBusy(null);
    }
  }

  async function emailLogin() {
    setError(null);
    setBusy("email");
    try {
      const tokens = await api.auth.login(identifier.trim(), password);
      if (tokens.mfa_required) {
        setError("این حساب تأییدِ دومرحله‌ای دارد؛ لطفاً از اپِ موبایل ادامه دهید.");
        return;
      }
      setAccessToken(tokens.access_token);
      finish();
    } catch {
      setError("ورود ناموفق بود. ایمیل/شماره یا گذرواژه نادرست است.");
    } finally {
      setBusy(null);
    }
  }

  async function emailRegister() {
    setError(null);
    if (password.length < 8) {
      setError("گذرواژه باید حداقل ۸ نویسه باشد.");
      return;
    }
    const id = identifier.trim();
    const isEmail = id.includes("@");
    setBusy("email");
    try {
      const res = await api.auth.register({
        display_name: displayName.trim(),
        password,
        email: isEmail ? id : undefined,
        phone: isEmail ? undefined : id,
      });
      setAccessToken(res.tokens.access_token);
      finish();
    } catch {
      setError("ثبت‌نام ناموفق بود. ممکن است این ایمیل/شماره قبلاً ثبت شده باشد.");
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="auth-panel">
      {/* ── روشِ سریع: شبکه‌های اجتماعی ── */}
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

      <div className="divider"><span>یا</span></div>

      {/* ── انتخابِ روشِ موبایل / ایمیل ── */}
      <div className="seg">
        <button
          className={`seg-btn ${method === "phone" ? "active" : ""}`}
          onClick={() => { setMethod("phone"); setError(null); }}
        >
          موبایل
        </button>
        <button
          className={`seg-btn ${method === "email" ? "active" : ""}`}
          onClick={() => { setMethod("email"); setError(null); }}
        >
          ایمیل
        </button>
      </div>

      {method === "phone" && (
        <div>
          <input
            className="input"
            inputMode="tel"
            placeholder="۰۹۱۲۱۲۳۴۵۶۷ یا ‎+۹۸۹۱۲۱۲۳۴۵۶۷"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            disabled={otpChallengeId != null}
            dir="ltr"
          />
          {otpChallengeId == null ? (
            <button
              className="btn block"
              disabled={busy != null || phone.trim().length < 8}
              onClick={sendOtp}
            >
              {busy === "otp" ? "در حال ارسال…" : "ارسالِ کدِ تأیید"}
            </button>
          ) : (
            <>
              <input
                className="input"
                inputMode="numeric"
                placeholder="کدِ ۶ رقمی"
                value={otpCode}
                onChange={(e) => setOtpCode(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && verifyOtp()}
                dir="ltr"
              />
              <button
                className="btn block"
                disabled={busy != null || otpCode.trim().length < 4}
                onClick={verifyOtp}
              >
                {busy === "otp" ? "در حال بررسی…" : "تأیید و ورود"}
              </button>
              <button
                className="btn link"
                onClick={() => { setOtpChallengeId(null); setOtpCode(""); }}
              >
                تغییرِ شماره
              </button>
            </>
          )}
        </div>
      )}

      {method === "email" && (
        <div>
          <div className="seg sub">
            <button
              className={`seg-btn ${emailMode === "login" ? "active" : ""}`}
              onClick={() => { setEmailMode("login"); setError(null); }}
            >
              ورود
            </button>
            <button
              className={`seg-btn ${emailMode === "register" ? "active" : ""}`}
              onClick={() => { setEmailMode("register"); setError(null); }}
            >
              ثبت‌نام
            </button>
          </div>

          {emailMode === "register" && (
            <input
              className="input"
              placeholder="نامِ نمایشی"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
            />
          )}

          <input
            className="input"
            placeholder="ایمیل یا شماره موبایل"
            value={identifier}
            onChange={(e) => setIdentifier(e.target.value)}
            dir="ltr"
          />

          <div className="password-field">
            <input
              className="input"
              type={showPwd ? "text" : "password"}
              placeholder="گذرواژه (حداقل ۸ نویسه)"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && (emailMode === "login" ? emailLogin() : emailRegister())}
              dir="ltr"
            />
            <button
              type="button"
              className="pwd-toggle"
              onClick={() => setShowPwd((v) => !v)}
              aria-label={showPwd ? "پنهان‌کردنِ گذرواژه" : "نمایشِ گذرواژه"}
            >
              {showPwd ? "🙈" : "👁"}
            </button>
          </div>

          {emailMode === "login" ? (
            <button
              className="btn block"
              disabled={busy != null || identifier.trim().length < 3 || password.length < 1}
              onClick={emailLogin}
            >
              {busy === "email" ? "در حال ورود…" : "ورود"}
            </button>
          ) : (
            <button
              className="btn block"
              disabled={
                busy != null ||
                displayName.trim().length < 2 ||
                identifier.trim().length < 3 ||
                password.length < 8
              }
              onClick={emailRegister}
            >
              {busy === "email" ? "در حال ساخت…" : "ساختِ حساب"}
            </button>
          )}
        </div>
      )}

      {error && <p className="danger auth-error">{error}</p>}

      <p className="muted auth-terms">
        با ورود، <a href="/legal/terms">قوانین</a> و <a href="/legal/privacy">حریمِ خصوصی</a> را می‌پذیرید.
      </p>
    </div>
  );
}
