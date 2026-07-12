"use client";

import { Suspense, useEffect } from "react";
import { useRouter, useSearchParams } from "next/navigation";

function JoinInner() {
  const router = useRouter();
  const params = useSearchParams();
  const ref = params.get("ref");

  useEffect(() => {
    if (ref) localStorage.setItem("dilix_ref_code", ref.toUpperCase());
    const t = setTimeout(() => router.replace("/login"), 1200);
    return () => clearTimeout(t);
  }, [ref, router]);

  return (
    <main className="page">
      <div className="card" style={{ textAlign: "center" }}>
        <div style={{ fontSize: "2.5rem" }} aria-hidden>🎁</div>
        <h1 style={{ fontSize: "1.3rem" }}>دعوت‌نامه دریافت شد</h1>
        {ref ? (
          <p className="muted">
            کد دعوت <strong>{ref}</strong> ثبت شد
          </p>
        ) : (
          <p className="muted">در حال انتقال به صفحه‌ی ورود…</p>
        )}
        <p className="muted">در حال ورود به Dilix…</p>
      </div>
    </main>
  );
}

export default function JoinPage() {
  return (
    <Suspense fallback={<main className="page"><p className="muted">در حال بارگذاری…</p></main>}>
      <JoinInner />
    </Suspense>
  );
}
