"use client";

import { useEffect } from "react";
import { useTranslation } from "@/store/i18n";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense } from "react";
import { Loader2, Gift } from "lucide-react";

function JoinInner() {
  const { t } = useTranslation();
  const router = useRouter();
  const params = useSearchParams();

  useEffect(() => {
    const ref = params.get("ref");
    if (ref) {
      localStorage.setItem("dilix_ref_code", ref.toUpperCase());
    }
    // Redirect to login after short delay
    const timer = setTimeout(() => router.replace("/login"), 1200);
    return () => clearTimeout(timer);
  }, [params, router]);

  const ref = params.get("ref");

  return (
    <div className="fixed inset-0 bg-[#0A0A0A] flex flex-col items-center justify-center p-6 text-center">
      <div className="w-20 h-20 rounded-3xl bg-violet-500/15 border border-violet-500/30 flex items-center justify-center mb-6">
        <Gift size={36} className="text-violet-400" />
      </div>
      <h1 className="text-2xl font-bold text-white mb-2">{t("join.title")}</h1>
      {ref ? (
        <p className="text-surface-400 text-sm mb-6">
          {t("join.codePre")}<span className="text-violet-400 font-mono font-bold">{ref}</span>{t("join.codeSuf")}
        </p>
      ) : (
        <p className="text-surface-400 text-sm mb-6">{t("join.redirecting")}</p>
      )}
      <div className="flex items-center gap-2 text-surface-500 text-sm">
        <Loader2 size={16} className="animate-spin text-violet-400" />
        <span>{t("join.entering")}</span>
      </div>
    </div>
  );
}

export default function JoinPage() {
  return (
    <Suspense fallback={
      <div className="fixed inset-0 bg-[#0A0A0A] flex items-center justify-center">
        <Loader2 size={28} className="text-violet-400 animate-spin" />
      </div>
    }>
      <JoinInner />
    </Suspense>
  );
}
