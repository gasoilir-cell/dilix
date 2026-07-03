"use client";

import { useState, useRef, useEffect, useCallback } from "react";
import { useRouter } from "next/navigation";
import {
  User, Star, Shield, MapPin, Eye, EyeOff, LogOut,
  ChevronLeft, Edit2, Copy, Check, Camera, Loader2,
  Gift, Users, Link2, ChevronRight,
} from "lucide-react";
import { useAuthStore } from "@/store/auth";
import { authApi } from "@/lib/api";
import api from "@/lib/api";
import { Button } from "@/components/ui/Button";
import AppShell from "@/components/layout/AppShell";
import { toPersianNum } from "@/lib/utils";
import toast from "react-hot-toast";

const KYC_LABELS: Record<number, { label: string; color: string }> = {
  0: { label: "تأیید نشده",         color: "text-surface-400" },
  1: { label: "تأیید شماره",        color: "text-yellow-400"  },
  2: { label: "تأیید هویت",         color: "text-blue-400"    },
  3: { label: "تأیید کامل",         color: "text-accent-400"  },
  4: { label: "کسب‌وکار تأیید شده", color: "text-primary-400" },
  5: { label: "Enterprise",          color: "text-ai-400"      },
};

interface ReferralStats {
  code: string;
  link: string;
  total_referred: number;
  total_reward_toman: number;
  reward_per_referral: number;
}

export default function ProfilePage() {
  const router = useRouter();
  const { user, logout } = useAuthStore();
  const updateUser = useAuthStore((s) => s.updateUser);

  const [copiedEarthId,   setCopiedEarthId]   = useState(false);
  const [copiedRefLink,   setCopiedRefLink]    = useState(false);
  const [privacyLoading,  setPrivacyLoading]  = useState(false);
  const [avatarUploading, setAvatarUploading] = useState(false);
  const [refStats,        setRefStats]         = useState<ReferralStats | null>(null);
  const [refLoading,      setRefLoading]       = useState(true);

  const fileInputRef = useRef<HTMLInputElement>(null);

  const loadReferral = useCallback(async () => {
    try {
      const res = await api.get("/referral/stats");
      setRefStats(res.data);
    } catch {
      // silent — referral is optional
    } finally {
      setRefLoading(false);
    }
  }, []);

  useEffect(() => {
    loadReferral();
  }, [loadReferral]);

  if (!user) return null;

  const kyc = KYC_LABELS[user.kyc_level ?? 0];

  const handleCopyEarthId = () => {
    navigator.clipboard.writeText(user.earth_id || "");
    setCopiedEarthId(true);
    setTimeout(() => setCopiedEarthId(false), 2000);
  };

  const handleCopyRefLink = () => {
    if (!refStats) return;
    navigator.clipboard.writeText(refStats.link);
    setCopiedRefLink(true);
    toast.success("لینک دعوت کپی شد");
    setTimeout(() => setCopiedRefLink(false), 2000);
  };

  const handleTogglePrivacy = async () => {
    setPrivacyLoading(true);
    try {
      const res = await authApi.updateProfile({ privacy_on_map: !user.privacy_on_map });
      updateUser(res.data);
      toast.success(!user.privacy_on_map ? "روی نقشه دیده می‌شی 🌍" : "از نقشه مخفی شدی");
    } catch {
      toast.error("خطا در تغییر تنظیمات");
    } finally {
      setPrivacyLoading(false);
    }
  };

  const handleAvatarChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    if (file.size > 5 * 1024 * 1024) {
      toast.error("حجم عکس نباید بیشتر از ۵ مگابایت باشد");
      return;
    }
    setAvatarUploading(true);
    try {
      const formData = new FormData();
      formData.append("file", file);
      const res = await api.post("/auth/me/avatar", formData, {
        headers: { "Content-Type": "multipart/form-data" },
      });
      updateUser({ avatar_url: res.data.avatar_url });
      toast.success("عکس پروفایل به‌روز شد ✅");
    } catch {
      toast.error("خطا در آپلود عکس");
    } finally {
      setAvatarUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  };

  const handleLogout = () => {
    logout();
    router.push("/login");
  };

  return (
    <AppShell title="پروفایل">
      <div className="page-inner pb-safe">

        {/* ─── Header Card ─── */}
        <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-primary-900/60 to-surface-900 border border-surface-800 p-6 mb-4">
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top_left,_var(--tw-gradient-stops))] from-primary-600/10 to-transparent" />

          <div className="relative flex items-start gap-4">
            {/* Avatar */}
            <div className="relative flex-shrink-0">
              <div className="w-20 h-20 rounded-full bg-primary-700/30 border-2 border-primary-500/50 flex items-center justify-center overflow-hidden">
                {user.avatar_url ? (
                  <img src={user.avatar_url} alt="avatar" className="w-full h-full object-cover" />
                ) : (
                  <User size={36} className="text-primary-400" />
                )}
                {avatarUploading && (
                  <div className="absolute inset-0 bg-black/60 flex items-center justify-center rounded-full">
                    <Loader2 size={20} className="text-white animate-spin" />
                  </div>
                )}
              </div>
              <button
                onClick={() => fileInputRef.current?.click()}
                disabled={avatarUploading}
                className="absolute -bottom-1 -left-1 w-7 h-7 rounded-full bg-primary-600 border-2 border-surface-900 flex items-center justify-center hover:bg-primary-500 transition-colors disabled:opacity-50"
              >
                <Camera size={13} className="text-white" />
              </button>
              <input
                ref={fileInputRef}
                type="file"
                accept="image/jpeg,image/png,image/webp"
                className="hidden"
                onChange={handleAvatarChange}
              />
            </div>

            <div className="flex-1 min-w-0">
              <h1 className="text-xl font-bold text-white truncate">
                {user.full_name || "بدون نام"}
              </h1>
              {user.username && (
                <p className="text-surface-400 text-sm">@{user.username}</p>
              )}
              <button
                onClick={handleCopyEarthId}
                className="flex items-center gap-2 mt-2 bg-surface-800/60 rounded-lg px-3 py-1.5 text-sm font-mono text-primary-300 hover:bg-surface-700/60 transition-colors"
              >
                <MapPin size={14} />
                {user.earth_id}
                {copiedEarthId
                  ? <Check size={14} className="text-accent-400" />
                  : <Copy size={14} className="text-surface-500" />}
              </button>
            </div>

            <button
              onClick={() => router.push("/profile/edit")}
              className="p-2 rounded-lg bg-surface-800/60 hover:bg-surface-700/60 transition-colors"
            >
              <Edit2 size={18} className="text-surface-300" />
            </button>
          </div>

          {/* Stats */}
          <div className="relative grid grid-cols-3 gap-3 mt-5">
            <div className="text-center bg-surface-800/40 rounded-xl p-3">
              <p className="text-xl font-bold text-white">{toPersianNum(user.total_trips ?? 0)}</p>
              <p className="text-xs text-surface-400 mt-0.5">سفر</p>
            </div>
            <div className="text-center bg-surface-800/40 rounded-xl p-3">
              <div className="flex items-center justify-center gap-1">
                <Star size={16} className="text-yellow-400 fill-yellow-400" />
                <p className="text-xl font-bold text-white">
                  {user.avg_rating ? toPersianNum(Number(user.avg_rating).toFixed(1)) : "—"}
                </p>
              </div>
              <p className="text-xs text-surface-400 mt-0.5">امتیاز</p>
            </div>
            <div className="text-center bg-surface-800/40 rounded-xl p-3">
              <p className="text-xl font-bold text-white">{toPersianNum(user.trust_score ?? 0)}</p>
              <p className="text-xs text-surface-400 mt-0.5">اعتماد</p>
            </div>
          </div>
        </div>

        {/* ─── KYC ─── */}
        <div className="card p-4 mb-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <Shield size={20} className="text-primary-400" />
              <div>
                <p className="text-sm font-semibold text-white">سطح تأیید هویت</p>
                <p className={`text-xs font-medium ${kyc.color}`}>{kyc.label}</p>
              </div>
            </div>
            <div className="flex items-center gap-1.5">
              {[0, 1, 2, 3, 4, 5].map((lvl) => (
                <div
                  key={lvl}
                  className={`w-2 h-4 rounded-full ${
                    lvl <= (user.kyc_level ?? 0) ? "bg-primary-500" : "bg-surface-700"
                  }`}
                />
              ))}
            </div>
          </div>
          {(user.kyc_level ?? 0) < 3 && (
            <Button variant="outline" size="sm" fullWidth className="mt-3">
              ارتقای سطح تأیید
              <ChevronLeft size={16} className="mr-1" />
            </Button>
          )}
        </div>

        {/* ─── Referral Card ─── */}
        <div className="card p-4 mb-4 bg-gradient-to-br from-violet-900/20 to-surface-900 border-violet-500/20">
          <div className="flex items-center gap-3 mb-3">
            <div className="w-9 h-9 rounded-xl bg-violet-500/15 flex items-center justify-center">
              <Gift size={18} className="text-violet-400" />
            </div>
            <div>
              <p className="text-sm font-semibold text-white">دعوت دوستان</p>
              <p className="text-xs text-surface-400">به‌ازای هر دعوت ۵۰,۰۰۰ تومان پاداش</p>
            </div>
          </div>

          {refLoading ? (
            <div className="flex justify-center py-2">
              <Loader2 size={20} className="text-violet-400 animate-spin" />
            </div>
          ) : refStats ? (
            <>
              {/* Stats row */}
              <div className="grid grid-cols-2 gap-3 mb-3">
                <div className="bg-surface-800/50 rounded-xl p-3 text-center">
                  <div className="flex items-center justify-center gap-1.5 mb-0.5">
                    <Users size={15} className="text-violet-400" />
                    <p className="text-lg font-bold text-white">{toPersianNum(refStats.total_referred)}</p>
                  </div>
                  <p className="text-xs text-surface-400">دعوت‌شده</p>
                </div>
                <div className="bg-surface-800/50 rounded-xl p-3 text-center">
                  <p className="text-lg font-bold text-accent-400">
                    {toPersianNum(refStats.total_reward_toman.toLocaleString())}
                  </p>
                  <p className="text-xs text-surface-400">تومان پاداش</p>
                </div>
              </div>

              {/* Referral link */}
              <button
                onClick={handleCopyRefLink}
                className="w-full flex items-center gap-2 bg-violet-500/10 border border-violet-500/20 rounded-xl p-3 hover:bg-violet-500/15 transition-colors text-right"
              >
                <Link2 size={16} className="text-violet-400 flex-shrink-0" />
                <span className="flex-1 text-xs text-violet-300 font-mono truncate ltr text-left">
                  {refStats.link}
                </span>
                {copiedRefLink
                  ? <Check size={16} className="text-accent-400 flex-shrink-0" />
                  : <Copy size={16} className="text-surface-400 flex-shrink-0" />}
              </button>
            </>
          ) : (
            <p className="text-xs text-surface-500 text-center py-2">خطا در بارگذاری اطلاعات رفرال</p>
          )}
        </div>

        {/* ─── Settings ─── */}
        <div className="card divide-y divide-surface-800 mb-4">
          {/* Privacy toggle */}
          <button
            onClick={handleTogglePrivacy}
            disabled={privacyLoading}
            className="w-full flex items-center justify-between p-4 hover:bg-surface-800/30 transition-colors text-right"
          >
            <div className="flex items-center gap-3">
              {user.privacy_on_map
                ? <Eye size={20} className="text-accent-400" />
                : <EyeOff size={20} className="text-surface-400" />}
              <div>
                <p className="text-sm font-semibold text-white">نمایش روی کره زمین</p>
                <p className="text-xs text-surface-400">
                  {user.privacy_on_map ? "در حال حاضر دیده می‌شی 🌍" : "مخفی هستی"}
                </p>
              </div>
            </div>
            {privacyLoading ? (
              <Loader2 size={18} className="text-surface-400 animate-spin" />
            ) : (
              <div
                className={`w-12 h-6 rounded-full transition-colors relative ${
                  user.privacy_on_map ? "bg-accent-500" : "bg-surface-700"
                }`}
              >
                <div
                  className={`absolute top-1 w-4 h-4 bg-white rounded-full shadow transition-all ${
                    user.privacy_on_map ? "right-1" : "left-1"
                  }`}
                />
              </div>
            )}
          </button>

          <button className="w-full flex items-center justify-between p-4 hover:bg-surface-800/30 transition-colors text-right">
            <div className="flex items-center gap-3">
              <User size={20} className="text-surface-400" />
              <p className="text-sm font-semibold text-white">اطلاعات شخصی</p>
            </div>
            <ChevronRight size={18} className="text-surface-500" />
          </button>

          <button className="w-full flex items-center justify-between p-4 hover:bg-surface-800/30 transition-colors text-right">
            <div className="flex items-center gap-3">
              <Shield size={20} className="text-surface-400" />
              <p className="text-sm font-semibold text-white">امنیت</p>
            </div>
            <ChevronRight size={18} className="text-surface-500" />
          </button>
        </div>

        {/* ─── Logout ─── */}
        <Button
          variant="danger"
          size="lg"
          fullWidth
          onClick={handleLogout}
          leftIcon={<LogOut size={18} />}
        >
          خروج از حساب
        </Button>

      </div>
    </AppShell>
  );
}
