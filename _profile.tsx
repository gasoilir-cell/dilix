"use client";

import { useState, useRef, useEffect, useCallback } from "react";
import { useRouter } from "next/navigation";
import {
  User, Star, Shield, MapPin, Eye, EyeOff, LogOut,
  ChevronLeft, Edit2, Copy, Check, Camera, Loader2,
  Gift, Users, Link2, ChevronRight, X, Phone, Mail,
  Globe, Briefcase, Home, Heart, Trash2, UserPlus,
} from "lucide-react";
import { useAuthStore } from "@/store/auth";
import { authApi, storiesApi } from "@/lib/api";
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

const KYC_DESC: Record<number, string> = {
  0: "ثبت‌نامِ اولیه انجام شده",
  1: "شمارهٔ موبایل تأیید شده",
  2: "مدارکِ هویتی تأیید شده",
  3: "پروفایل و هویتِ کامل",
  4: "مدارکِ کسب‌وکار تأیید شده",
  5: "حسابِ سازمانی سطحِ بالا",
};

interface ReferralStats {
  code: string;
  link: string;
  total_referred: number;
  total_reward_toman: number;
  reward_per_referral: number;
}

type Aud = "public" | "followers" | "colleagues" | "family" | "friends";
type Circle = "colleagues" | "family" | "friends";

const AUDIENCE_OPTS: { key: Aud; label: string; desc: string; Icon: typeof Globe }[] = [
  { key: "public",     label: "عمومی",         desc: "همه می‌توانند ببینند",                 Icon: Globe },
  { key: "followers",  label: "دنبال‌کنندگان", desc: "فقط کسانی که شما را دنبال می‌کنند",   Icon: Users },
  { key: "colleagues", label: "همکاران",       desc: "فقط حلقهٔ همکاران",                    Icon: Briefcase },
  { key: "family",     label: "خانواده",       desc: "فقط حلقهٔ خانواده",                    Icon: Home },
  { key: "friends",    label: "دوستان",        desc: "فقط حلقهٔ دوستان",                     Icon: Heart },
];

const CIRCLES: { key: Circle; label: string; Icon: typeof Globe }[] = [
  { key: "colleagues", label: "همکاران",  Icon: Briefcase },
  { key: "family",     label: "خانواده", Icon: Home },
  { key: "friends",    label: "دوستان",  Icon: Heart },
];

interface CircleMember { earth_id: string; name: string; avatar_url?: string | null; }

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

  // پنجره‌های پروفایل: اطلاعات شخصی / ارتقای سطح تأیید / امنیت / مخاطبِ داستان
  const [modal, setModal] = useState<null | "info" | "kyc" | "security" | "story">(null);
  const [infoForm, setInfoForm] = useState({ full_name: "", username: "", bio: "" });
  const [savingInfo, setSavingInfo] = useState(false);

  // تنظیماتِ مخاطبِ داستان
  const [storyAud, setStoryAud] = useState<Aud>("public");
  const [storyLoading, setStoryLoading] = useState(false);
  const [savingAud, setSavingAud] = useState<Aud | null>(null);
  const [circleMembers, setCircleMembers] = useState<Record<Circle, CircleMember[]>>({ colleagues: [], family: [], friends: [] });
  const [addCircle, setAddCircle] = useState<Circle | null>(null);
  const [addEarthId, setAddEarthId] = useState("");
  const [addingMember, setAddingMember] = useState(false);

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

  const openInfo = () => {
    setInfoForm({
      full_name: user?.full_name || "",
      username: user?.username || "",
      bio: user?.bio || "",
    });
    setModal("info");
  };

  const saveInfo = async () => {
    setSavingInfo(true);
    try {
      const res = await authApi.updateProfile({
        full_name: infoForm.full_name.trim() || undefined,
        username: infoForm.username.trim() || undefined,
        bio: infoForm.bio.trim(),
      });
      updateUser(res.data);
      toast.success("اطلاعات ذخیره شد ✅");
      setModal(null);
    } catch (err) {
      const msg = (err as { response?: { data?: { detail?: string } } })?.response?.data?.detail;
      toast.error(msg || "خطا در ذخیرهٔ اطلاعات");
    } finally {
      setSavingInfo(false);
    }
  };

  const openStory = async () => {
    setModal("story");
    setStoryLoading(true);
    try {
      const [s, c] = await Promise.all([storiesApi.settings(), storiesApi.circles()]);
      setStoryAud((s.data?.default_audience as Aud) || "public");
      setCircleMembers({
        colleagues: c.data?.colleagues || [],
        family: c.data?.family || [],
        friends: c.data?.friends || [],
      });
    } catch {
      /* silent */
    } finally {
      setStoryLoading(false);
    }
  };

  const saveStoryAud = async (aud: Aud) => {
    setSavingAud(aud);
    try {
      await storiesApi.saveSettings(aud);
      setStoryAud(aud);
      toast.success("مخاطبِ پیش‌فرض ذخیره شد ✅");
    } catch {
      toast.error("خطا در ذخیرهٔ تنظیمات");
    } finally {
      setSavingAud(null);
    }
  };

  const addMember = async () => {
    if (!addCircle) return;
    const eid = addEarthId.trim();
    if (!eid) { toast.error("شناسهٔ کاربر را وارد کن"); return; }
    setAddingMember(true);
    try {
      const res = await storiesApi.addToCircle(addCircle, eid);
      const circle = addCircle;
      setCircleMembers((prev) => ({
        ...prev,
        [circle]: [res.data as CircleMember, ...prev[circle].filter((m) => m.earth_id !== res.data.earth_id)],
      }));
      setAddEarthId("");
      setAddCircle(null);
      toast.success("به حلقه اضافه شد ✅");
    } catch (err) {
      const msg = (err as { response?: { data?: { detail?: string } } })?.response?.data?.detail;
      toast.error(msg || "افزودن ناموفق بود");
    } finally {
      setAddingMember(false);
    }
  };

  const removeMember = async (circle: Circle, earthId: string) => {
    try {
      await storiesApi.removeFromCircle(circle, earthId);
      setCircleMembers((prev) => ({ ...prev, [circle]: prev[circle].filter((m) => m.earth_id !== earthId) }));
    } catch {
      toast.error("حذف ناموفق بود");
    }
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
              onClick={openInfo}
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
            <Button variant="outline" size="sm" fullWidth className="mt-3" onClick={() => setModal("kyc")}>
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

          <button onClick={openInfo} className="w-full flex items-center justify-between p-4 hover:bg-surface-800/30 transition-colors text-right">
            <div className="flex items-center gap-3">
              <User size={20} className="text-surface-400" />
              <p className="text-sm font-semibold text-white">اطلاعات شخصی</p>
            </div>
            <ChevronRight size={18} className="text-surface-500" />
          </button>

          <button onClick={openStory} className="w-full flex items-center justify-between p-4 hover:bg-surface-800/30 transition-colors text-right">
            <div className="flex items-center gap-3">
              <Globe size={20} className="text-surface-400" />
              <div>
                <p className="text-sm font-semibold text-white">مخاطبِ داستان</p>
                <p className="text-xs text-surface-400">تعیینِ مخاطبِ پیش‌فرض و حلقه‌ها</p>
              </div>
            </div>
            <ChevronRight size={18} className="text-surface-500" />
          </button>

          <button onClick={() => setModal("security")} className="w-full flex items-center justify-between p-4 hover:bg-surface-800/30 transition-colors text-right">
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

        {/* ─── Modals ─── */}
        {modal && (
          <div
            className="fixed inset-0 z-[80] flex items-end sm:items-center justify-center bg-black/70 backdrop-blur-sm sm:p-4"
            onClick={() => { if (!savingInfo) setModal(null); }}
          >
            <div
              dir="rtl"
              onClick={(e) => e.stopPropagation()}
              className="w-full sm:max-w-md bg-surface-900 border border-surface-800 rounded-t-3xl sm:rounded-3xl p-5 max-h-[88vh] overflow-y-auto"
              style={{ animation: "slideUp 0.22s ease-out" }}
            >
              <div className="flex items-center justify-between mb-4">
                <h2 className="text-white font-bold text-base">
                  {modal === "info" ? "اطلاعات شخصی" : modal === "kyc" ? "ارتقای سطح تأیید" : modal === "story" ? "مخاطبِ داستان" : "امنیت"}
                </h2>
                <button onClick={() => { if (!savingInfo) setModal(null); }} className="p-2 rounded-lg bg-surface-800 text-surface-300 hover:bg-surface-700">
                  <X size={18} />
                </button>
              </div>

              {/* اطلاعات شخصی */}
              {modal === "info" && (
                <div className="space-y-3">
                  <div>
                    <label className="text-xs text-surface-400 mb-1 block">نام و نام خانوادگی</label>
                    <input
                      value={infoForm.full_name}
                      onChange={(e) => setInfoForm((f) => ({ ...f, full_name: e.target.value }))}
                      maxLength={60}
                      placeholder="نامِ شما"
                      className="w-full bg-surface-800 border border-surface-700 rounded-xl px-3 py-2.5 text-white text-sm placeholder-surface-500 focus:outline-none focus:border-primary-500"
                    />
                  </div>
                  <div>
                    <label className="text-xs text-surface-400 mb-1 block">نام کاربری</label>
                    <div className="flex items-center bg-surface-800 border border-surface-700 rounded-xl px-3 focus-within:border-primary-500">
                      <span className="text-surface-500 text-sm">@</span>
                      <input
                        value={infoForm.username}
                        onChange={(e) => setInfoForm((f) => ({ ...f, username: e.target.value.replace(/[^a-zA-Z0-9_]/g, "") }))}
                        maxLength={30}
                        placeholder="username"
                        className="flex-1 bg-transparent py-2.5 pr-1 text-white text-sm placeholder-surface-500 focus:outline-none"
                        style={{ direction: "ltr" }}
                      />
                    </div>
                  </div>
                  <div>
                    <label className="text-xs text-surface-400 mb-1 block">دربارهٔ من</label>
                    <textarea
                      value={infoForm.bio}
                      onChange={(e) => setInfoForm((f) => ({ ...f, bio: e.target.value }))}
                      maxLength={160}
                      rows={3}
                      placeholder="یک توضیحِ کوتاه دربارهٔ خودت"
                      className="w-full bg-surface-800 border border-surface-700 rounded-xl px-3 py-2.5 text-white text-sm placeholder-surface-500 focus:outline-none focus:border-primary-500 resize-none"
                    />
                    <p className="text-[10px] text-surface-500 mt-1 text-left">{toPersianNum(infoForm.bio.length)}/۱۶۰</p>
                  </div>
                  <Button variant="primary" size="md" fullWidth onClick={saveInfo} disabled={savingInfo}>
                    {savingInfo ? <Loader2 size={18} className="animate-spin" /> : "ذخیرهٔ تغییرات"}
                  </Button>
                </div>
              )}

              {/* ارتقای سطح تأیید */}
              {modal === "kyc" && (
                <div className="space-y-3">
                  <p className="text-xs text-surface-400 leading-6">
                    هرچه سطحِ تأییدِ هویتِ تو بالاتر باشد، اعتماد و دسترسی‌های بیشتری در دیلیکس خواهی داشت.
                    سطحِ فعلی: <span className={kyc.color}>{kyc.label}</span>
                  </p>
                  <div className="space-y-2">
                    {[0, 1, 2, 3, 4, 5].map((lvl) => {
                      const info = KYC_LABELS[lvl];
                      const cur = user.kyc_level ?? 0;
                      const done = lvl <= cur;
                      const next = lvl === cur + 1;
                      return (
                        <div key={lvl} className={`flex items-center gap-3 rounded-xl p-3 border ${done ? "bg-primary-900/20 border-primary-500/30" : next ? "bg-surface-800/60 border-primary-500/40" : "bg-surface-800/30 border-surface-800"}`}>
                          <div className={`w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold shrink-0 ${done ? "bg-primary-500 text-white" : "bg-surface-700 text-surface-300"}`}>
                            {done ? <Check size={14} /> : toPersianNum(lvl)}
                          </div>
                          <div className="flex-1 min-w-0">
                            <p className="text-sm text-white">{info.label}</p>
                            <p className="text-[11px] text-surface-400">{KYC_DESC[lvl]}</p>
                          </div>
                          {next && <span className="text-[10px] text-primary-400 shrink-0">مرحلهٔ بعدی</span>}
                        </div>
                      );
                    })}
                  </div>
                  <div className="rounded-xl bg-surface-800/50 p-3 text-xs text-surface-300 leading-6">
                    برای ارتقا، ابتدا اطلاعاتِ شخصی‌ات را کامل کن. تأییدِ مدارکِ هویتی به‌زودی از همین بخش فعال می‌شود.
                  </div>
                  <Button variant="primary" size="md" fullWidth onClick={openInfo}>تکمیلِ اطلاعاتِ شخصی</Button>
                </div>
              )}

              {/* امنیت */}
              {modal === "security" && (
                <div className="space-y-3">
                  <div className="rounded-xl bg-surface-800/50 divide-y divide-surface-800 overflow-hidden">
                    <div className="flex items-center gap-3 p-3">
                      <Phone size={17} className="text-surface-400 shrink-0" />
                      <p className="text-sm text-white flex-1">شمارهٔ موبایل</p>
                      <span className={`text-xs ${user.phone ? "text-accent-400" : "text-surface-500"}`}>{user.phone ? "تأیید شده" : "ثبت نشده"}</span>
                    </div>
                    <div className="flex items-center gap-3 p-3">
                      <Mail size={17} className="text-surface-400 shrink-0" />
                      <p className="text-sm text-white flex-1">ایمیل</p>
                      <span className="text-xs text-surface-400 truncate max-w-[50%] ltr text-left">{user.email || "ثبت نشده"}</span>
                    </div>
                    <div className="flex items-center gap-3 p-3">
                      <Shield size={17} className="text-surface-400 shrink-0" />
                      <p className="text-sm text-white flex-1">سطحِ تأیید</p>
                      <span className={`text-xs ${kyc.color}`}>{kyc.label}</span>
                    </div>
                    <div className="flex items-center gap-3 p-3">
                      <Check size={17} className="text-surface-400 shrink-0" />
                      <p className="text-sm text-white flex-1">عضویت از</p>
                      <span className="text-xs text-surface-400">{user.created_at ? new Date(user.created_at).toLocaleDateString("fa-IR") : "—"}</span>
                    </div>
                  </div>
                  <div className="rounded-xl bg-surface-800/50 p-3 text-xs text-surface-300 leading-6">
                    برای تغییرِ رمز عبور یا گزارشِ فعالیتِ مشکوک روی حساب، با پشتیبانی در تماس باش.
                  </div>
                  <Button variant="outline" size="md" fullWidth onClick={() => { setModal(null); router.push("/support"); }}>تماس با پشتیبانی</Button>
                  <Button variant="danger" size="md" fullWidth onClick={handleLogout} leftIcon={<LogOut size={16} />}>خروج از حساب</Button>
                </div>
              )}

              {/* مخاطبِ داستان */}
              {modal === "story" && (
                <div className="space-y-4">
                  {storyLoading ? (
                    <div className="flex justify-center py-8">
                      <Loader2 size={22} className="text-primary-400 animate-spin" />
                    </div>
                  ) : (
                    <>
                      <div>
                        <p className="text-xs text-surface-400 mb-2 leading-6">
                          مخاطبِ پیش‌فرضِ داستان‌های شما. هنگامِ انتشار هم می‌توانید آن را تغییر دهید.
                        </p>
                        <div className="space-y-1.5">
                          {AUDIENCE_OPTS.map(({ key, label, desc, Icon }) => {
                            const active = storyAud === key;
                            return (
                              <button
                                key={key}
                                onClick={() => saveStoryAud(key)}
                                disabled={savingAud !== null}
                                className={`w-full flex items-center gap-3 rounded-2xl px-3.5 py-3 text-right transition ${
                                  active ? "bg-primary-500/15 ring-1 ring-primary-500" : "bg-surface-800/50 hover:bg-surface-800"
                                }`}
                              >
                                <span className={`shrink-0 w-9 h-9 rounded-full flex items-center justify-center ${active ? "bg-primary-500 text-white" : "bg-surface-700 text-surface-300"}`}>
                                  <Icon size={17} />
                                </span>
                                <span className="flex-1 min-w-0">
                                  <span className="block text-sm text-white">{label}</span>
                                  <span className="block text-[11px] text-surface-400 truncate">{desc}</span>
                                </span>
                                {savingAud === key ? (
                                  <Loader2 size={16} className="text-primary-400 animate-spin shrink-0" />
                                ) : active ? (
                                  <Check size={18} className="text-primary-400 shrink-0" />
                                ) : null}
                              </button>
                            );
                          })}
                        </div>
                      </div>

                      {/* حلقه‌های مخاطب */}
                      <div className="space-y-3 pt-1">
                        <p className="text-xs text-surface-400 leading-6">
                          حلقه‌های خصوصی: کاربران را با شناسهٔ کره‌زمین (Earth ID) به هر حلقه اضافه کنید تا داستان‌های مخصوصِ آن حلقه را ببینند.
                        </p>
                        {CIRCLES.map(({ key, label, Icon }) => (
                          <div key={key} className="rounded-2xl bg-surface-800/40 border border-surface-800 overflow-hidden">
                            <div className="flex items-center justify-between px-3.5 py-2.5">
                              <div className="flex items-center gap-2.5">
                                <Icon size={16} className="text-primary-400" />
                                <p className="text-sm text-white">{label}</p>
                                <span className="text-[11px] text-surface-500">({toPersianNum(circleMembers[key].length)})</span>
                              </div>
                              <button
                                onClick={() => { setAddCircle(addCircle === key ? null : key); setAddEarthId(""); }}
                                className="p-1.5 rounded-lg bg-surface-700/60 text-primary-300 hover:bg-surface-700"
                              >
                                <UserPlus size={15} />
                              </button>
                            </div>

                            {addCircle === key && (
                              <div className="flex items-center gap-2 px-3.5 pb-3">
                                <input
                                  value={addEarthId}
                                  onChange={(e) => setAddEarthId(e.target.value)}
                                  placeholder="شناسهٔ کاربر (Earth ID)"
                                  className="flex-1 bg-surface-900 border border-surface-700 rounded-xl px-3 py-2 text-white text-sm placeholder-surface-500 focus:outline-none focus:border-primary-500 ltr text-left"
                                />
                                <Button variant="primary" size="sm" onClick={addMember} disabled={addingMember}>
                                  {addingMember ? <Loader2 size={15} className="animate-spin" /> : "افزودن"}
                                </Button>
                              </div>
                            )}

                            {circleMembers[key].length > 0 && (
                              <div className="divide-y divide-surface-800/70">
                                {circleMembers[key].map((m) => (
                                  <div key={m.earth_id} className="flex items-center gap-2.5 px-3.5 py-2">
                                    <div className="w-8 h-8 rounded-full bg-surface-700 overflow-hidden flex items-center justify-center text-xs text-surface-300 shrink-0">
                                      {m.avatar_url ? <img src={m.avatar_url} alt="" className="w-full h-full object-cover" /> : (m.name?.[0] ?? "👤")}
                                    </div>
                                    <div className="flex-1 min-w-0">
                                      <p className="text-sm text-white truncate">{m.name}</p>
                                      <p className="text-[10px] text-surface-500 font-mono truncate ltr text-left">{m.earth_id}</p>
                                    </div>
                                    <button onClick={() => removeMember(key, m.earth_id)} className="p-1.5 rounded-lg text-rose-400 hover:bg-rose-500/10">
                                      <Trash2 size={15} />
                                    </button>
                                  </div>
                                ))}
                              </div>
                            )}
                          </div>
                        ))}
                      </div>
                    </>
                  )}
                </div>
              )}
            </div>
          </div>
        )}

      </div>
    </AppShell>
  );
}
