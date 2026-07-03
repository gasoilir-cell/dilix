"use client";

import { useEffect } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense } from "react";
import { Loader2, Gift } from "lucide-react";

function JoinInner() {
  const router = useRouter();
  const params = useSearchParams();

  useEffect(() => {
    const ref = params.get("ref");
    if (ref) {
      localStorage.setItem("dilix_ref_code", ref.toUpperCase());
    }
    // Redirect to login after short delay
    const t = setTimeout(() => router.replace("/login"), 1200);
    return () => clearTimeout(t);
  }, [params, router]);

  const ref = params.get("ref");

  return (
    <div className="min-h-dvh bg-[#0A0A0A] flex flex-col items-center justify-center p-6 text-center">
      <div className="w-20 h-20 rounded-3xl bg-violet-500/15 border border-violet-500/30 flex items-center justify-center mb-6">
        <Gift size={36} className="text-violet-400" />
      </div>
      <h1 className="text-2xl font-bold text-white mb-2">دعوت‌نامه دریافت شد</h1>
      {ref ? (
        <p className="text-surface-400 text-sm mb-6">
          کد دعوت <span className="text-violet-400 font-mono font-bold">{ref}</span> ثبت شد
        </p>
      ) : (
        <p className="text-surface-400 text-sm mb-6">در حال انتقال به صفحه ورود...</p>
      )}
      <div className="flex items-center gap-2 text-surface-500 text-sm">
        <Loader2 size={16} className="animate-spin text-violet-400" />
        <span>در حال ورود به Dilix...</span>
      </div>
    </div>
  );
}

export default function JoinPage() {
  return (
    <Suspense fallback={
      <div className="min-h-dvh bg-[#0A0A0A] flex items-center justify-center">
        <Loader2 size={28} className="text-violet-400 animate-spin" />
      </div>
    }>
      <JoinInner />
    </Suspense>
  );
}
