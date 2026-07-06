"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import {
  User, Eye, EyeOff, ChevronLeft, ChevronRight, Check,
  Truck, Package, Handshake, Shield, Megaphone, Building2, Landmark,
} from "lucide-react";
import { authApi, getApiErrorMessage } from "@/lib/api";
import api from "@/lib/api";
import { useAuthStore } from "@/store/auth";
import { Button } from "@/components/ui/Button";
import toast from "react-hot-toast";

// ── Role definitions ──────────────────────────────────────────
const ROLES = [
  {
    id: "user",
    label: "کاربر عادی",
    desc: "مثل WhatsApp — فقط پیام و ارتباط",
    icon: User,
    color: "#6366F1",
    bg: "rgba(99,102,241,0.15)",
  },
  {
    id: "driver",
    label: "راننده",
    desc: "حمل بار و ارائه ظرفیت",
    icon: Truck,
    color: "#F97316",
    bg: "rgba(249,115,22,0.15)",
  },
  {
    id: "cargo_owner",
    label: "صاحب بار / تاجر",
    desc: "ارسال و دریافت محموله",
    icon: Package,
    color: "#06B6D4",
    bg: "rgba(6,182,212,0.15)",
  },
  {
    id: "freight_broker",
    label: "کارگزار / شرکت حمل",
    desc: "واسطه و هماهنگی بار",
    icon: Handshake,
    color: "#A855F7",
    bg: "rgba(168,85,247,0.15)",
  },
  {
    id: "insurance_agent",
    label: "نماینده بیمه",
    desc: "صدور و پشتیبانی بیمه",
    icon: Shield,
    color: "#10B981",
    bg: "rgba(16,185,129,0.15)",
  },
  {
    id: "banker",
    label: "بانکدار",
    desc: "خدمات و تراکنش‌های مالی",
    icon: Landmark,
    color: "#EAB308",
    bg: "rgba(234,179,8,0.15)",
  },
  {
    id: "creator",
    label: "شرکت / سازمان",
    desc: "شخصیت حقوقی",
    icon: Building2,
    color: "#F43F5E",
    bg: "rgba(244,63,94,0.15)",
  },
] as const;

// ── Form schema ───────────────────────────────────────────────
const profileSchema = z.object({
  full_name: z.string().min(2, "نام باید حداقل ۲ کاراکتر باشد"),
  username: z
    .string()
    .transform((v) => v.trim().toLowerCase())
    .pipe(
      z
        .string()
        .min(3, "نام کاربری باید حداقل ۳ کاراکتر باشد")
        .max(30, "نام کاربری باید حداکثر ۳۰ کاراکتر باشد")
        .regex(
          /^[a-z0-9_.]+$/,
          "فقط حروف انگلیسی، اعداد، نقطه و زیرخط (_) مجاز است"
        )
    )
    .optional()
    .or(z.literal("")),
});
type ProfileData = z.infer<typeof profileSchema>;

// ── Component ─────────────────────────────────────────────────

// ── Apply referral code from localStorage after registration ──────────────
async function applyRefCode() {
  const ref = localStorage.getItem("dilix_ref_code");
  if (!ref) return;
  try {
    await api.post("/referral/apply", { ref_code: ref });
    localStorage.removeItem("dilix_ref_code");
  } catch {
    // code already applied or invalid — remove anyway
    localStorage.removeItem("dilix_ref_code");
  }
}

export default function OnboardingPage() {
  const router     = useRouter();
  const user       = useAuthStore((s) => s.user);
  const updateUser = useAuthStore((s) => s.updateUser);

  const [step,         setStep]         = useState<1 | 2 | 3 | 4>(1);
  const [selectedRole, setSelectedRole] = useState<string | null>(null);
  const [profileData,  setProfileData]  = useState<ProfileData | null>(null);
  const [privacyOnMap, setPrivacyOnMap] = useState(false);
  const [isLoading,    setIsLoading]    = useState(false);

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<ProfileData>({
    resolver: zodResolver(profileSchema),
    defaultValues: {
      full_name: user?.full_name ?? "",
      username:  user?.username  ?? "",
    },
  });

  // ── Step handlers ─────────────────────────────────────────
  const onRoleSelect = (roleId: string) => {
    setSelectedRole(roleId);
  };

  const onRoleNext = () => {
    if (!selectedRole) { toast.error("لطفاً نوع حساب خود را انتخاب کن"); return; }
    setStep(2);
  };

  const onProfileSubmit = (data: ProfileData) => {
    setProfileData(data);
    setStep(3);
  };

  const onComplete = async () => {
    if (!profileData || !selectedRole) return;
    setIsLoading(true);
    try {
      const payload: Record<string, unknown> = {
        full_name:      profileData.full_name,
        role:           selectedRole,
        privacy_on_map: privacyOnMap,
      };
      if (profileData.username) payload.username = profileData.username.toLowerCase();

      const res = await authApi.updateProfile(payload);
      updateUser(res.data);
      setStep(4);
      applyRefCode();
      setTimeout(() => router.push("/dashboard"), 1500);
    } catch {
      // اگر role reject شد، بدون role ذخیره کن
      try {
        const res2 = await authApi.updateProfile({
          full_name:      profileData.full_name,
          privacy_on_map: privacyOnMap,
          ...(profileData.username ? { username: profileData.username.toLowerCase() } : {}),
        });
        updateUser({ ...res2.data, role: selectedRole });
        setStep(4);
        setTimeout(() => router.push("/dashboard"), 1500);
      } catch (err2: unknown) {
        toast.error(getApiErrorMessage(err2, "خطا در ذخیره اطلاعات"));
      }
    } finally {
      setIsLoading(false);
    }
  };

  // ── Shared styles ─────────────────────────────────────────
  const card: React.CSSProperties = {
    background: "#1C1C1E",
    border:     "1px solid rgba(255,255,255,0.08)",
    borderRadius: "20px",
    padding: "24px",
  };

  // ── Progress indicator ────────────────────────────────────
  const steps = [
    { n: 1, label: "نوع حساب" },
    { n: 2, label: "پروفایل" },
    { n: 3, label: "حریم خصوصی" },
  ];

  return (
    <div
      className="fixed inset-0 flex flex-col items-center justify-center px-4 py-10 overflow-y-auto"
      style={{ background: "#0A0A0A" }}
    >
      {/* Progress */}
      {step < 4 && (
        <div className="w-full max-w-md mb-8">
          <div className="flex items-center justify-center gap-2 mb-3">
            {steps.map((s, i) => (
              <div key={s.n} className="flex items-center gap-2">
                <div className="flex flex-col items-center gap-1">
                  <div
                    className="w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold transition-all"
                    style={{
                      background: step > s.n ? "#10B981" : step === s.n ? "#6366F1" : "rgba(255,255,255,0.08)",
                      color:      step >= s.n ? "#fff" : "rgba(255,255,255,0.4)",
                      boxShadow:  step === s.n ? "0 0 0 3px rgba(99,102,241,0.3)" : "none",
                    }}
                  >
                    {step > s.n ? <Check size={14} /> : s.n}
                  </div>
                  <span className="text-[10px]" style={{ color: step >= s.n ? "rgba(255,255,255,0.7)" : "rgba(255,255,255,0.25)" }}>
                    {s.label}
                  </span>
                </div>
                {i < steps.length - 1 && (
                  <div
                    className="h-px w-10 mb-4"
                    style={{ background: step > s.n ? "#10B981" : "rgba(255,255,255,0.1)" }}
                  />
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      <div className="w-full max-w-md">

        {/* ── Step 1: Role Selection ── */}
        {step === 1 && (
          <div style={card}>
            <div className="text-center mb-6">
              <div
                className="w-16 h-16 rounded-2xl flex items-center justify-center mx-auto mb-4 text-3xl"
                style={{ background: "rgba(99,102,241,0.15)" }}
              >
                👋
              </div>
              <h1 className="text-xl font-bold text-white">خوش اومدی به Dilix!</h1>
              <p className="text-sm mt-1" style={{ color: "rgba(255,255,255,0.5)" }}>
                چه نوع حسابی می‌خوای باز کنی؟
              </p>
            </div>

            <div className="grid grid-cols-2 gap-3 mb-6">
              {ROLES.map((r) => {
                const Icon    = r.icon;
                const active  = selectedRole === r.id;
                return (
                  <button
                    key={r.id}
                    onClick={() => onRoleSelect(r.id)}
                    className="text-right p-3 rounded-2xl transition-all active:scale-95"
                    style={{
                      background:  active ? r.bg : "rgba(255,255,255,0.04)",
                      border:      active
                        ? `2px solid ${r.color}`
                        : "2px solid rgba(255,255,255,0.06)",
                      boxShadow:   active ? `0 0 0 3px ${r.color}22` : "none",
                    }}
                  >
                    <div
                      className="w-9 h-9 rounded-xl flex items-center justify-center mb-2"
                      style={{ background: r.bg }}
                    >
                      <Icon size={18} style={{ color: r.color }} />
                    </div>
                    <p
                      className="text-sm font-semibold leading-tight"
                      style={{ color: active ? r.color : "rgba(255,255,255,0.85)" }}
                    >
                      {r.label}
                    </p>
                    <p
                      className="text-[11px] mt-0.5 leading-tight"
                      style={{ color: "rgba(255,255,255,0.4)" }}
                    >
                      {r.desc}
                    </p>
                  </button>
                );
              })}
            </div>

            <p className="text-xs text-center mb-4" style={{ color: "rgba(255,255,255,0.35)" }}>
              نگران نباش — بعداً از تنظیمات قابل تغییر است
            </p>

            <button
              onClick={onRoleNext}
              disabled={!selectedRole}
              className="w-full py-3 rounded-2xl font-bold text-white transition-all active:scale-95 disabled:opacity-40"
              style={{ background: "linear-gradient(135deg,#6366F1,#818CF8)", boxShadow: selectedRole ? "0 4px 16px rgba(99,102,241,0.4)" : "none" }}
            >
              بعدی
            </button>
          </div>
        )}

        {/* ── Step 2: Profile Info ── */}
        {step === 2 && (
          <div style={card}>
            <div className="text-center mb-6">
              <div
                className="w-16 h-16 rounded-2xl flex items-center justify-center mx-auto mb-4"
                style={{ background: "rgba(99,102,241,0.15)" }}
              >
                <User size={28} className="text-primary" />
              </div>
              <h2 className="text-xl font-bold text-white">اطلاعات پروفایل</h2>
              <p className="text-sm mt-1" style={{ color: "rgba(255,255,255,0.5)" }}>
                Earth ID: <span className="text-primary font-mono">{user?.earth_id}</span>
              </p>
            </div>

            <form onSubmit={handleSubmit(onProfileSubmit)} className="space-y-4">
              <div>
                <label className="block text-sm font-medium mb-1.5" style={{ color: "rgba(255,255,255,0.7)" }}>
                  نام و نام خانوادگی <span className="text-red-400">*</span>
                </label>
                <input
                  {...register("full_name")}
                  placeholder="مثلاً: علی رضایی"
                  className="input w-full"
                />
                {errors.full_name && (
                  <p className="text-red-400 text-xs mt-1">{errors.full_name.message}</p>
                )}
              </div>

              <div>
                <label className="block text-sm font-medium mb-1.5" style={{ color: "rgba(255,255,255,0.7)" }}>
                  نام کاربری <span style={{ color: "rgba(255,255,255,0.35)" }}>(اختیاری)</span>
                </label>
                <div className="relative">
                  <span
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-sm"
                    style={{ color: "rgba(255,255,255,0.35)" }}
                  >
                    @
                  </span>
                  <input
                    {...register("username")}
                    placeholder="ali_rezaei"
                    className="input w-full pr-8 ltr text-left"
                    dir="ltr"
                    autoCapitalize="none"
                    autoCorrect="off"
                    spellCheck={false}
                    style={{ textTransform: "lowercase" }}
                  />
                </div>
                {errors.username && (
                  <p className="text-red-400 text-xs mt-1">{errors.username.message}</p>
                )}
              </div>

              <div className="flex gap-3 mt-6">
                <button
                  type="button"
                  onClick={() => setStep(1)}
                  className="flex-shrink-0 w-12 h-12 rounded-2xl flex items-center justify-center transition-all active:scale-95"
                  style={{ background: "rgba(255,255,255,0.07)", border: "1px solid rgba(255,255,255,0.12)" }}
                >
                  <ChevronRight size={20} style={{ color: "rgba(255,255,255,0.6)" }} />
                </button>
                <button
                  type="submit"
                  className="flex-1 py-3 rounded-2xl font-bold text-white transition-all active:scale-95"
                  style={{ background: "linear-gradient(135deg,#6366F1,#818CF8)", boxShadow: "0 4px 16px rgba(99,102,241,0.4)" }}
                >
                  بعدی
                  <ChevronLeft size={16} className="inline-block mr-1" />
                </button>
              </div>
            </form>
          </div>
        )}

        {/* ── Step 3: Privacy ── */}
        {step === 3 && (
          <div style={card}>
            <div className="text-center mb-6">
              <div
                className="w-16 h-16 rounded-2xl flex items-center justify-center mx-auto mb-4"
                style={{ background: "rgba(16,185,129,0.15)" }}
              >
                <Eye size={28} style={{ color: "#10B981" }} />
              </div>
              <h2 className="text-xl font-bold text-white">حریم خصوصی</h2>
              <p className="text-sm mt-1" style={{ color: "rgba(255,255,255,0.5)" }}>
                کنترل کن چه کسی تو رو روی کره زمین ببینه
              </p>
            </div>

            <div className="space-y-3 mb-6">
              {[
                {
                  value: false,
                  icon: EyeOff,
                  title: "مخفی (پیشنهادی)",
                  desc: "روی نقشه دیده نمی‌شی — هر وقت خواستی فعال می‌کنی",
                  color: "#6366F1",
                },
                {
                  value: true,
                  icon: Eye,
                  title: "دیده‌شدنی روی نقشه",
                  desc: "در سطح منطقه (نه نقطه دقیق) نمایش داده می‌شی",
                  color: "#10B981",
                },
              ].map((opt) => {
                const Icon   = opt.icon;
                const active = privacyOnMap === opt.value;
                return (
                  <button
                    key={String(opt.value)}
                    onClick={() => setPrivacyOnMap(opt.value)}
                    className="w-full p-4 rounded-2xl text-right transition-all"
                    style={{
                      background: active ? `${opt.color}18` : "rgba(255,255,255,0.04)",
                      border:     `2px solid ${active ? opt.color : "rgba(255,255,255,0.07)"}`,
                    }}
                  >
                    <div className="flex items-center gap-3">
                      <div
                        className="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0"
                        style={{ background: `${opt.color}22` }}
                      >
                        <Icon size={18} style={{ color: opt.color }} />
                      </div>
                      <div className="flex-1 text-right">
                        <p
                          className="text-sm font-semibold"
                          style={{ color: active ? opt.color : "rgba(255,255,255,0.85)" }}
                        >
                          {opt.title}
                        </p>
                        <p className="text-xs mt-0.5" style={{ color: "rgba(255,255,255,0.4)" }}>
                          {opt.desc}
                        </p>
                      </div>
                      <div
                        className="w-5 h-5 rounded-full border-2 flex items-center justify-center flex-shrink-0"
                        style={{
                          borderColor: active ? opt.color : "rgba(255,255,255,0.25)",
                          background:  active ? opt.color : "transparent",
                        }}
                      >
                        {active && <Check size={12} className="text-white" />}
                      </div>
                    </div>
                  </button>
                );
              })}
            </div>

            <p className="text-xs text-center mb-5" style={{ color: "rgba(255,255,255,0.3)" }}>
              این تنظیم را هر زمان از پروفایل تغییر می‌توانی بدهی
            </p>

            <div className="flex gap-3">
              <button
                onClick={() => setStep(2)}
                className="flex-shrink-0 w-12 h-12 rounded-2xl flex items-center justify-center transition-all active:scale-95"
                style={{ background: "rgba(255,255,255,0.07)", border: "1px solid rgba(255,255,255,0.12)" }}
              >
                <ChevronRight size={20} style={{ color: "rgba(255,255,255,0.6)" }} />
              </button>
              <button
                onClick={onComplete}
                disabled={isLoading}
                className="flex-1 py-3 rounded-2xl font-bold text-white transition-all active:scale-95 disabled:opacity-60"
                style={{ background: "linear-gradient(135deg,#6366F1,#818CF8)", boxShadow: "0 4px 16px rgba(99,102,241,0.4)" }}
              >
                {isLoading ? "در حال ذخیره..." : "شروع کن!"}
              </button>
            </div>
          </div>
        )}

        {/* ── Step 4: Done ── */}
        {step === 4 && (
          <div style={{ ...card, textAlign: "center" }}>
            <div
              className="w-24 h-24 rounded-full flex items-center justify-center mx-auto mb-6"
              style={{ background: "rgba(16,185,129,0.2)", border: "2px solid #10B981" }}
            >
              <Check size={48} style={{ color: "#10B981" }} />
            </div>
            <h2 className="text-2xl font-bold text-white mb-2">همه چیز آماده‌ست! 🎉</h2>
            <p className="text-sm" style={{ color: "rgba(255,255,255,0.5)" }}>
              در حال انتقال به داشبورد...
            </p>
          </div>
        )}

      </div>
    </div>
  );
}
