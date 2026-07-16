"use client";

// پنلِ احرازِ هویت — فعلاً فقط ایمیل (ثبت‌نام و ورود). سایرِ روش‌ها (اجتماعی و
// موبایلِ یک‌بارمصرف) موقتاً غیرفعال‌اند و پس از آماده‌سازیِ زیرساخت بازمی‌گردند.
//
// پس از موفقیت، هر دو توکن (access + refresh) ذخیره و onAuthenticated فراخوانی می‌شود.

import { useState } from "react";
import { api, setSession } from "@/lib/api";

type EmailMode = "login" | "register";

export default function AuthPanel({ onAuthenticated }: { onAuthenticated: () => void }) {
  const [emailMode, setEmailMode] = useState<EmailMode>("login");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [showPwd, setShowPwd] = useState(false);

  // email login/register
  const [displayName, setDisplayName] = useState("");
  const [identifier, setIdentifier] = useState("");
  const [password, setPassword] = useState("");

  function finish() {
    setError(null);
    onAuthenticated();
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
      setSession(tokens);
      finish();
    } catch {
      setError("ورود ناموفق بود. ایمیل یا گذرواژه نادرست است.");
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
      setSession(res.tokens);
      finish();
    } catch {
      setError("ثبت‌نام ناموفق بود. ممکن است این ایمیل قبلاً ثبت شده باشد.");
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="auth-panel">
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
        placeholder="ایمیل"
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

      {error && <p className="danger auth-error">{error}</p>}

      <p className="muted auth-terms">
        با ورود، <a href="/legal/terms">قوانین</a> و <a href="/legal/privacy">حریمِ خصوصی</a> را می‌پذیرید.
      </p>
    </div>
  );
}
