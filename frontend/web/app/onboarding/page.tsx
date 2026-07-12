"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { api, isAuthenticated, type RoleOption } from "@/lib/api";
import { setStoredRole } from "@/lib/roles";

// نقش‌های پیش‌فرض اگر فهرستِ سرور در دسترس نباشد (خودسرویس).
const FALLBACK_ROLES: RoleOption[] = [
  { entity_type: "individual", label: "کاربر عادی", description: "پیام و ارتباط", self_service: true },
  { entity_type: "driver", label: "راننده", description: "حمل بار و ارائه ظرفیت", self_service: true },
  { entity_type: "cargo_owner", label: "صاحب بار / تاجر", description: "ارسال و دریافت محموله", self_service: true },
  { entity_type: "freelancer", label: "فریلنسر", description: "ارائه‌ی خدمات و کارها", self_service: true },
];

export default function OnboardingPage() {
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [step, setStep] = useState<1 | 2 | 3 | 4>(1);
  const [roles, setRoles] = useState<RoleOption[]>(FALLBACK_ROLES);
  const [selectedRole, setSelectedRole] = useState<string | null>(null);
  const [displayName, setDisplayName] = useState("");
  const [visibleOnMap, setVisibleOnMap] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!isAuthenticated()) {
      router.replace("/login");
      return;
    }
    setReady(true);
    api.identity
      .roles()
      .then((list) => {
        const selfService = list.filter((r) => r.self_service);
        if (selfService.length) setRoles(selfService);
      })
      .catch(() => {});
    api.identity
      .me()
      .then((me) => {
        if (me.profile?.display_name) setDisplayName(me.profile.display_name);
        setSelectedRole(me.entity_type);
      })
      .catch(() => {});
  }, [router]);

  function nextFromRole() {
    if (!selectedRole) {
      setError("لطفاً نوعِ حساب خود را انتخاب کنید.");
      return;
    }
    setError(null);
    setStep(2);
  }

  function nextFromProfile() {
    if (displayName.trim().length < 2) {
      setError("نام باید حداقل ۲ کاراکتر باشد.");
      return;
    }
    setError(null);
    setStep(3);
  }

  async function complete() {
    setLoading(true);
    setError(null);
    try {
      await api.identity.updateProfile({ display_name: displayName.trim() });
      // تغییرِ نقش ممکن است نیازمندِ تأیید باشد؛ خطا را بی‌صدا می‌پذیریم.
      if (selectedRole) {
        try {
          await api.identity.changeRole(selectedRole);
          setStoredRole(selectedRole);
        } catch {
          setStoredRole(selectedRole);
        }
      }
      await api.identity
        .setVisibility({
          discoverable: visibleOnMap,
          audience: "connections",
          geo_precision: "region",
          visible_fields: [],
        })
        .catch(() => {});
      setStep(4);
      setTimeout(() => router.push("/me"), 1400);
    } catch {
      setError("ذخیره‌ی اطلاعات ممکن نشد. دوباره تلاش کنید.");
    } finally {
      setLoading(false);
    }
  }

  if (!ready) return null;

  const steps = ["نوع حساب", "پروفایل", "حریم خصوصی"];

  return (
    <main className="page">
      {step < 4 && (
        <div className="row" style={{ gap: 8, justifyContent: "center", marginBottom: 8 }}>
          {steps.map((label, i) => (
            <span key={label} className={`badge${step === i + 1 ? "" : " muted"}`}>
              {i + 1}. {label}
            </span>
          ))}
        </div>
      )}

      {error && <div className="card danger">{error}</div>}

      {step === 1 && (
        <div className="card">
          <strong>خوش آمدید به Dilix 👋</strong>
          <p className="muted">چه نوع حسابی می‌خواهید داشته باشید؟ بعداً از تنظیمات قابل تغییر است.</p>
          <div className="role-switch">
            {roles.map((r) => {
              const active = selectedRole === r.entity_type;
              return (
                <button
                  key={r.entity_type}
                  className={`role-chip${active ? " active" : ""}`}
                  onClick={() => setSelectedRole(r.entity_type)}
                  title={r.description}
                >
                  {r.label}
                  {active && <span className="role-current"> ✓</span>}
                </button>
              );
            })}
          </div>
          <button className="btn" style={{ marginTop: 12 }} onClick={nextFromRole}>
            بعدی
          </button>
        </div>
      )}

      {step === 2 && (
        <div className="card">
          <strong>اطلاعات پروفایل</strong>
          <p className="muted">نامی که دیگران می‌بینند.</p>
          <input
            className="input"
            placeholder="مثلاً: علی رضایی"
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
          />
          <div className="row" style={{ gap: 8, marginTop: 12 }}>
            <button className="btn secondary" onClick={() => setStep(1)}>
              بازگشت
            </button>
            <button className="btn" onClick={nextFromProfile}>
              بعدی
            </button>
          </div>
        </div>
      )}

      {step === 3 && (
        <div className="card">
          <strong>حریم خصوصی</strong>
          <p className="muted">کنترل کنید چه کسی شما را روی نقشه ببیند. پیش‌فرض: مخفی (ADR-06).</p>
          <div className="seg" style={{ marginTop: 8 }}>
            <button
              className={`seg-btn${!visibleOnMap ? " active" : ""}`}
              onClick={() => setVisibleOnMap(false)}
            >
              مخفی (پیشنهادی)
            </button>
            <button
              className={`seg-btn${visibleOnMap ? " active" : ""}`}
              onClick={() => setVisibleOnMap(true)}
            >
              دیده‌شدن در سطحِ منطقه
            </button>
          </div>
          <p className="muted" style={{ marginTop: 8 }}>
            این تنظیم را هر زمان از پروفایل تغییر می‌دهید.
          </p>
          <div className="row" style={{ gap: 8, marginTop: 12 }}>
            <button className="btn secondary" onClick={() => setStep(2)} disabled={loading}>
              بازگشت
            </button>
            <button className="btn" onClick={complete} disabled={loading}>
              {loading ? "در حال ذخیره…" : "شروع کن!"}
            </button>
          </div>
        </div>
      )}

      {step === 4 && (
        <div className="card" style={{ textAlign: "center" }}>
          <div className="ico-lg" aria-hidden>
            ✅
          </div>
          <strong>همه‌چیز آماده است! 🎉</strong>
          <p className="muted">در حال انتقال به حساب شما…</p>
        </div>
      )}
    </main>
  );
}
