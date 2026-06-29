"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { isAuthenticated } from "@/lib/api";
import AuthPanel from "@/components/AuthPanel";

export default function LoginPage() {
  const router = useRouter();
  const [ready, setReady] = useState(false);

  useEffect(() => {
    if (isAuthenticated()) router.replace("/me");
    else setReady(true);
  }, [router]);

  if (!ready) return null;

  return (
    <main className="auth-screen">
      <div className="auth-brand">
        <div className="auth-logo" aria-hidden>🌐</div>
        <div className="auth-wordmark">DiLIX</div>
        <div className="auth-tagline">CONNECT · EXPLORE · ENGAGE · GLOBALLY</div>
      </div>

      <div className="card auth-card">
        <h1 className="auth-title">ورود / ثبت‌نام</h1>
        <p className="muted">سریع و امن وارد شوید — موبایل، ایمیل یا حسابِ اجتماعی</p>
        <AuthPanel onAuthenticated={() => router.replace("/me")} />
      </div>

      <p className="muted auth-foot">
        <span aria-hidden>🌍</span> هر کاربر یک Earth ID یکتای جهانی دریافت می‌کند
      </p>
    </main>
  );
}
