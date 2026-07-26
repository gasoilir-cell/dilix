"use client";

import { useState, useRef, useEffect, useCallback } from "react";
import { useRouter } from "next/navigation";
import {
  User, Star, Shield, MapPin, Eye, EyeOff, LogOut,
  ChevronLeft, Edit2, Copy, Check, Camera, Loader2,
  Gift, Users, Link2, ChevronRight, X, Phone, Mail,
  Globe, Briefcase, Home, Heart, Trash2, UserPlus,
  Upload, Clock, CheckCircle2, AlertTriangle,
} from "lucide-react";
import { useAuthStore } from "@/store/auth";
import { authApi, storiesApi, getApiErrorMessage } from "@/lib/api";
import api from "@/lib/api";
import { Button } from "@/components/ui/Button";
import AppShell from "@/components/layout/AppShell";
import StoryHighlights from "@/components/chat/StoryHighlights";
import LanguageSwitcher from "@/components/shared/LanguageSwitcher";
import ThemeToggle from "@/components/shared/ThemeToggle";
import { useTranslation } from "@/store/i18n";
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

// نقش‌های خودسرویس (هم‌راستا با onboarding و بک‌اندِ SELF_SERVICE_ROLES).
// نقش‌های ممتاز (admin/super_admin) این‌جا نیستند و قابلِ خوداعطا نیستند.
const SELF_SERVICE_ROLES: { id: string; label: string; desc: string; emoji: string }[] = [
  { id: "user",            label: "کاربر عادی",       desc: "پیام و ارتباط — مثل واتساپ",   emoji: "👤" },
  { id: "driver",          label: "راننده",           desc: "حمل بار و ارائه ظرفیت",        emoji: "🚛" },
  { id: "cargo_owner",     label: "صاحب بار / تاجر",  desc: "ارسال و دریافت محموله",        emoji: "📦" },
  { id: "freight_broker",  label: "کارگزار / شرکت حمل", desc: "واسطه و هماهنگی بار",        emoji: "🤝" },
  { id: "insurance_agent", label: "نماینده بیمه",     desc: "صدور و پشتیبانی بیمه",         emoji: "🛡️" },
  { id: "banker",          label: "بانکدار",          desc: "خدمات و تراکنش‌های مالی",      emoji: "🏦" },
  { id: "creator",         label: "شرکت / سازمان",    desc: "شخصیت حقوقی",                  emoji: "📢" },
];

export default function ProfilePage() {
  const router = useRouter();
  const { t } = useTranslation();
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
  const [modal, setModal] = useState<null | "info" | "kyc" | "security" | "story" | "role">(null);
  const [infoForm, setInfoForm] = useState({ full_name: "", username: "", bio: "" });
  const [savingInfo, setSavingInfo] = useState(false);
  const [roleSwitching, setRoleSwitching] = useState<string | null>(null);

  // تنظیماتِ مخاطبِ داستان
  const [storyAud, setStoryAud] = useState<Aud>("public");
  const [storyLoading, setStoryLoading] = useState(false);
  const [savingAud, setSavingAud] = useState<Aud | null>(null);
  const [circleMembers, setCircleMembers] = useState<Record<Circle, CircleMember[]>>({ colleagues: [], family: [], friends: [] });
  const [addCircle, setAddCircle] = useState<Circle | null>(null);
  const [addEarthId, setAddEarthId] = useState("");
  const [addingMember, setAddingMember] = useState(false);

  // تأیید هویت (KYC — سطحِ ۲)
  const [kycInfo, setKycInfo] = useState<{ status: string; review_note?: string | null } | null>(null);
  const [kycLoading, setKycLoading] = useState(false);
  const [kycForm, setKycForm] = useState({ national_id: "", full_name: "", date_of_birth: "" });
  const [kycFront, setKycFront] = useState<File | null>(null);
  const [kycSelfie, setKycSelfie] = useState<File | null>(null);
  const [submittingKyc, setSubmittingKyc] = useState(false);
  const kycFrontRef = useRef<HTMLInputElement>(null);
  const kycSelfieRef = useRef<HTMLInputElement>(null);

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
    toast.success(t("profile.toast.linkCopied"));
    setTimeout(() => setCopiedRefLink(false), 2000);
  };

  const handleTogglePrivacy = async () => {
    setPrivacyLoading(true);
    try {
      const res = await authApi.updateProfile({ privacy_on_map: !user.privacy_on_map });
      updateUser(res.data);
      toast.success(!user.privacy_on_map ? "روی نقشه دیده می‌شی 🌍" : "از نقشه مخفی شدی");
    } catch {
      toast.error(t("profile.toast.settingsError"));
    } finally {
      setPrivacyLoading(false);
    }
  };

  const handleAvatarChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    if (file.size > 5 * 1024 * 1024) {
      toast.error(t("profile.toast.photoTooLarge5"));
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
      toast.success(t("profile.toast.photoUpdated"));
    } catch {
      toast.error(t("profile.toast.photoUploadError"));
    } finally {
      setAvatarUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  };

  const handleLogout = () => {
    logout();
    router.push("/login");
  };

  const handleRoleChange = async (roleId: string) => {
    if (roleId === user.role || roleSwitching) return;
    setRoleSwitching(roleId);
    try {
      const res = await authApi.updateProfile({ role: roleId });
      updateUser(res.data);
      const meta = SELF_SERVICE_ROLES.find((r) => r.id === roleId);
      toast.success(`نقشِ تو به «${meta?.label ?? roleId}» تغییر کرد ✅`);
      setModal(null);
    } catch {
      toast.error(t("profile.toast.roleChangeFailed"));
    } finally {
      setRoleSwitching(null);
    }
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
      toast.success(t("profile.toast.infoSaved"));
      setModal(null);
    } catch (err) {
      const msg = (err as { response?: { data?: { detail?: string } } })?.response?.data?.detail;
      toast.error(msg || "خطا در ذخیرهٔ اطلاعات");
    } finally {
      setSavingInfo(false);
    }
  };

  const openKyc = async () => {
    setModal("kyc");
    setKycForm({ national_id: "", full_name: user?.full_name || "", date_of_birth: "" });
    setKycFront(null);
    setKycSelfie(null);
    setKycLoading(true);
    try {
      const res = await authApi.kycStatus();
      setKycInfo(res.data);
    } catch {
      setKycInfo({ status: "none" });
    } finally {
      setKycLoading(false);
    }
  };

  const pickKycFile = (e: React.ChangeEvent<HTMLInputElement>, set: (f: File | null) => void) => {
    const f = e.target.files?.[0];
    if (!f) return;
    if (f.size > 8 * 1024 * 1024) { toast.error(t("profile.toast.imageTooLarge8")); return; }
    set(f);
  };

  const submitKyc = async () => {
    const nid = kycForm.national_id.trim();
    if (!/^\d{10}$/.test(nid)) { toast.error(t("profile.toast.nidInvalid")); return; }
    if (kycForm.full_name.trim().length < 3) { toast.error(t("profile.toast.fullNameRequired")); return; }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(kycForm.date_of_birth.trim())) {
      toast.error(t("profile.toast.birthDateFormat")); return;
    }
    if (!kycFront) { toast.error(t("profile.toast.idImageRequired")); return; }
    if (!kycSelfie) { toast.error(t("profile.toast.selfieRequired")); return; }
    setSubmittingKyc(true);
    try {
      const res = await authApi.submitKyc({
        national_id: nid,
        full_name: kycForm.full_name.trim(),
        date_of_birth: kycForm.date_of_birth.trim(),
        front: kycFront,
        selfie: kycSelfie,
      });
      setKycInfo({ status: "pending" });
      updateUser({ kyc_status: "pending", national_id_set: true });
      toast.success(res.data?.message || "مدارکِ شما ثبت شد و در حالِ بررسی است ✅");
    } catch (err) {
      toast.error(getApiErrorMessage(err, "ثبتِ مدارک ناموفق بود"));
    } finally {
      setSubmittingKyc(false);
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
      toast.success(t("profile.toast.defaultContactSaved"));
    } catch {
      toast.error(t("profile.toast.settingsError"));
    } finally {
      setSavingAud(null);
    }
  };

  const addMember = async () => {
    if (!addCircle) return;
    const eid = addEarthId.trim();
    if (!eid) { toast.error(t("profile.toast.userIdRequired")); return; }
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
      toast.success(t("profile.toast.addedToCircle"));
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
      toast.error(t("profile.toast.deleteFailed"));
    }
  };

  return (
    <AppShell title={t("profile.title")}>
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
                {user.full_name || t("profile.noname")}
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
              <p className="text-xs text-surface-400 mt-0.5">{t("profile.stat.trips")}</p>
            </div>
            <div className="text-center bg-surface-800/40 rounded-xl p-3">
              <div className="flex items-center justify-center gap-1">
                <Star size={16} className="text-yellow-400 fill-yellow-400" />
                <p className="text-xl font-bold text-white">
                  {user.avg_rating ? toPersianNum(Number(user.avg_rating).toFixed(1)) : "—"}
                </p>
              </div>
              <p className="text-xs text-surface-400 mt-0.5">{t("profile.stat.rating")}</p>
            </div>
            <div className="text-center bg-surface-800/40 rounded-xl p-3">
              <p className="text-xl font-bold text-white">{toPersianNum(user.trust_score ?? 0)}</p>
              <p className="text-xs text-surface-400 mt-0.5">{t("profile.stat.trust")}</p>
            </div>
          </div>
        </div>

        {/* ─── Story Highlights ─── */}
        {user.earth_id && (
          <div className="mb-4">
            <StoryHighlights earthId={user.earth_id} isMe={true} />
          </div>
        )}

        {/* ─── KYC ─── */}
        <div className="card p-4 mb-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <Shield size={20} className="text-primary-400" />
              <div>
                <p className="text-sm font-semibold text-white">{t("profile.kyc.title")}</p>
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
            <Button variant="outline" size="sm" fullWidth className="mt-3" onClick={openKyc}>
              {t("profile.kyc.upgrade")}
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
              <p className="text-sm font-semibold text-white">{t("profile.referral.title")}</p>
              <p className="text-xs text-surface-400">{t("profile.referral.subtitle")}</p>
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
                  <p className="text-xs text-surface-400">{t("profile.referral.invited")}</p>
                </div>
                <div className="bg-surface-800/50 rounded-xl p-3 text-center">
                  <p className="text-lg font-bold text-accent-400">
                    {toPersianNum(refStats.total_reward_toman.toLocaleString())}
                  </p>
                  <p className="text-xs text-surface-400">{t("profile.referral.reward")}</p>
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

              {/* مشاهدهٔ شبکه و کمیسیون‌ها */}
              <button
                onClick={() => router.push("/referral")}
                className="w-full mt-2 flex items-center justify-center gap-2 bg-violet-600/80 hover:bg-violet-600 rounded-xl p-2.5 transition-colors"
              >
                <Users size={16} className="text-white" />
                <span className="text-sm font-medium text-white">{t("profile.referral.viewNetwork")}</span>
              </button>
            </>
          ) : (
            <p className="text-xs text-surface-500 text-center py-2">{t("profile.referral.loadError")}</p>
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
                <p className="text-sm font-semibold text-white">{t("profile.settings.mapVisibility")}</p>
                <p className="text-xs text-surface-400">
                  {user.privacy_on_map ? t("profile.settings.visible") : t("profile.settings.hidden")}
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

          <button onClick={() => setModal("role")} className="w-full flex items-center justify-between p-4 hover:bg-surface-800/30 transition-colors text-right">
            <div className="flex items-center gap-3">
              <Briefcase size={20} className="text-surface-400" />
              <div>
                <p className="text-sm font-semibold text-white">{t("profile.settings.role")}</p>
                <p className="text-xs text-surface-400">
                  {SELF_SERVICE_ROLES.find((r) => r.id === user.role)?.label ?? t("profile.settings.roleDefault")} — {t("profile.settings.roleHint")}
                </p>
              </div>
            </div>
            <ChevronRight size={18} className="text-surface-500" />
          </button>

          <button onClick={openInfo} className="w-full flex items-center justify-between p-4 hover:bg-surface-800/30 transition-colors text-right">
            <div className="flex items-center gap-3">
              <User size={20} className="text-surface-400" />
              <p className="text-sm font-semibold text-white">{t("profile.settings.personalInfo")}</p>
            </div>
            <ChevronRight size={18} className="text-surface-500" />
          </button>

          {/* زبانِ برنامه (جهانی‌سازی) */}
          <LanguageSwitcher />

          {/* پوستهٔ روشن/تیره */}
          <ThemeToggle />

          <button onClick={openStory} className="w-full flex items-center justify-between p-4 hover:bg-surface-800/30 transition-colors text-right">
            <div className="flex items-center gap-3">
              <Globe size={20} className="text-surface-400" />
              <div>
                <p className="text-sm font-semibold text-white">{t("profile.settings.storyAudience")}</p>
                <p className="text-xs text-surface-400">{t("profile.settings.storyAudienceSub")}</p>
              </div>
            </div>
            <ChevronRight size={18} className="text-surface-500" />
          </button>

          <button onClick={() => setModal("security")} className="w-full flex items-center justify-between p-4 hover:bg-surface-800/30 transition-colors text-right">
            <div className="flex items-center gap-3">
              <Shield size={20} className="text-surface-400" />
              <p className="text-sm font-semibold text-white">{t("profile.settings.security")}</p>
            </div>
            <ChevronRight size={18} className="text-surface-500" />
          </button>

          {(user.role === "admin" || user.role === "super_admin") && (
            <button onClick={() => router.push("/admin/kyc")} className="w-full flex items-center justify-between p-4 hover:bg-surface-800/30 transition-colors text-right">
              <div className="flex items-center gap-3">
                <Shield size={20} className="text-primary-400" />
                <div>
                  <p className="text-sm font-semibold text-white">{t("profile.settings.kycReview")}</p>
                  <p className="text-xs text-surface-400">{t("profile.settings.kycReviewSub")}</p>
                </div>
              </div>
              <ChevronRight size={18} className="text-surface-500" />
            </button>
          )}
        </div>

        {/* ─── Logout ─── */}
        <Button
          variant="danger"
          size="lg"
          fullWidth
          onClick={handleLogout}
          leftIcon={<LogOut size={18} />}
        >
          {t("profile.logout")}
        </Button>

        {/* ─── Modals ─── */}
        {modal && (
          <div
            className="fixed inset-0 z-[80] flex items-end sm:items-center justify-center bg-black/70 backdrop-blur-sm sm:p-4"
            onClick={() => { if (!savingInfo && !submittingKyc) setModal(null); }}
          >
            <div
              dir="rtl"
              onClick={(e) => e.stopPropagation()}
              className="w-full sm:max-w-md bg-surface-900 border border-surface-800 rounded-t-3xl sm:rounded-3xl p-5 max-h-[88vh] overflow-y-auto"
              style={{ animation: "slideUp 0.22s ease-out" }}
            >
              <div className="flex items-center justify-between mb-4">
                <h2 className="text-white font-bold text-base">
                  {modal === "info" ? "اطلاعات شخصی" : modal === "kyc" ? "ارتقای سطح تأیید" : modal === "story" ? "مخاطبِ داستان" : modal === "role" ? "تغییرِ نقش" : "امنیت"}
                </h2>
                <button onClick={() => { if (!savingInfo && !submittingKyc) setModal(null); }} className="p-2 rounded-lg bg-surface-800 text-surface-300 hover:bg-surface-700">
                  <X size={18} />
                </button>
              </div>

              {/* تغییرِ نقش */}
              {modal === "role" && (
                <div className="space-y-2">
                  <p className="text-xs text-surface-400 mb-1">
                    نقش، پنل و ابزارهایی که در داشبورد می‌بینی را تعیین می‌کند. هر زمان می‌توانی جابجا شوی.
                  </p>
                  {SELF_SERVICE_ROLES.map((r) => {
                    const active = user.role === r.id;
                    return (
                      <button
                        key={r.id}
                        onClick={() => handleRoleChange(r.id)}
                        disabled={active || roleSwitching !== null}
                        className={`w-full flex items-center gap-3 p-3 rounded-2xl border text-right transition-colors ${
                          active
                            ? "border-accent-500 bg-accent-500/10"
                            : "border-surface-800 hover:bg-surface-800/40"
                        } disabled:opacity-60`}
                      >
                        <span className="text-2xl leading-none">{r.emoji}</span>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-semibold text-white">{r.label}</p>
                          <p className="text-xs text-surface-400 truncate">{r.desc}</p>
                        </div>
                        {roleSwitching === r.id ? (
                          <Loader2 size={18} className="text-surface-300 animate-spin" />
                        ) : active ? (
                          <Check size={18} className="text-accent-400" />
                        ) : null}
                      </button>
                    );
                  })}
                </div>
              )}

              {/* اطلاعات شخصی */}
              {modal === "info" && (
                <div className="space-y-3">
                  <div>
                    <label className="text-xs text-surface-400 mb-1 block">نام و نام خانوادگی</label>
                    <input
                      value={infoForm.full_name}
                      onChange={(e) => setInfoForm((f) => ({ ...f, full_name: e.target.value }))}
                      maxLength={60}
                      placeholder={t("profile.ph.yourName")}
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
                      placeholder={t("profile.ph.bio")}
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

                  {/* نردبانِ سطوح */}
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

                  {/* بخشِ تأییدِ مدارکِ هویتی (سطحِ ۲) */}
                  {kycLoading ? (
                    <div className="flex justify-center py-6">
                      <Loader2 size={22} className="text-primary-400 animate-spin" />
                    </div>
                  ) : (user.kyc_level ?? 0) >= 2 || kycInfo?.status === "approved" ? (
                    <div className="rounded-xl bg-accent-500/10 border border-accent-500/30 p-3 flex items-center gap-3">
                      <CheckCircle2 size={20} className="text-accent-400 shrink-0" />
                      <p className="text-xs text-accent-300 leading-6">هویتِ شما تأیید شده است. ممنون که اعتمادِ حسابت را بالا بردی.</p>
                    </div>
                  ) : kycInfo?.status === "pending" ? (
                    <div className="rounded-xl bg-yellow-500/10 border border-yellow-500/30 p-3 flex items-center gap-3">
                      <Clock size={20} className="text-yellow-400 shrink-0" />
                      <p className="text-xs text-yellow-200 leading-6">مدارکِ شما ثبت شده و در حالِ بررسی است. نتیجه به‌زودی اعلام می‌شود.</p>
                    </div>
                  ) : (
                    <div className="space-y-3 pt-1">
                      {kycInfo?.status === "rejected" && (
                        <div className="rounded-xl bg-rose-500/10 border border-rose-500/30 p-3 flex items-start gap-3">
                          <AlertTriangle size={18} className="text-rose-400 shrink-0 mt-0.5" />
                          <div className="text-xs text-rose-200 leading-6">
                            درخواستِ قبلی تأیید نشد. لطفاً دوباره با مدارکِ درست ارسال کن.
                            {kycInfo.review_note ? <span className="block text-rose-300/80 mt-1">دلیل: {kycInfo.review_note}</span> : null}
                          </div>
                        </div>
                      )}

                      <div className="rounded-xl bg-surface-800/50 p-3 text-xs text-surface-300 leading-6">
                        برای تأییدِ هویت (سطحِ ۲)، کدِ ملی، نام و تاریخِ تولدت را وارد کن و تصویرِ کارتِ ملی/شناسنامه به‌همراه یک عکسِ سلفی از خودت (که مدرک را کنارِ صورتت گرفته‌ای) بارگذاری کن.
                      </div>

                      <div>
                        <label className="text-xs text-surface-400 mb-1 block">کدِ ملی (۱۰ رقم)</label>
                        <input
                          value={kycForm.national_id}
                          onChange={(e) => setKycForm((f) => ({ ...f, national_id: e.target.value.replace(/[^0-9]/g, "").slice(0, 10) }))}
                          inputMode="numeric"
                          placeholder="۰۰۱۲۳۴۵۶۷۸"
                          className="w-full bg-surface-800 border border-surface-700 rounded-xl px-3 py-2.5 text-white text-sm placeholder-surface-500 focus:outline-none focus:border-primary-500 ltr text-left tracking-widest"
                        />
                      </div>

                      <div>
                        <label className="text-xs text-surface-400 mb-1 block">نام و نام خانوادگی (مطابقِ مدرک)</label>
                        <input
                          value={kycForm.full_name}
                          onChange={(e) => setKycForm((f) => ({ ...f, full_name: e.target.value }))}
                          maxLength={60}
                          placeholder={t("profile.ph.fullName")}
                          className="w-full bg-surface-800 border border-surface-700 rounded-xl px-3 py-2.5 text-white text-sm placeholder-surface-500 focus:outline-none focus:border-primary-500"
                        />
                      </div>

                      <div>
                        <label className="text-xs text-surface-400 mb-1 block">تاریخِ تولد (میلادی — YYYY-MM-DD)</label>
                        <input
                          value={kycForm.date_of_birth}
                          onChange={(e) => setKycForm((f) => ({ ...f, date_of_birth: e.target.value.replace(/[^0-9-]/g, "").slice(0, 10) }))}
                          placeholder="1990-05-12"
                          className="w-full bg-surface-800 border border-surface-700 rounded-xl px-3 py-2.5 text-white text-sm placeholder-surface-500 focus:outline-none focus:border-primary-500 ltr text-left"
                        />
                      </div>

                      <div className="grid grid-cols-2 gap-2">
                        <button
                          type="button"
                          onClick={() => kycFrontRef.current?.click()}
                          className={`flex flex-col items-center justify-center gap-1.5 rounded-xl border border-dashed p-4 text-center transition ${kycFront ? "border-accent-500/50 bg-accent-500/5" : "border-surface-700 bg-surface-800/40 hover:bg-surface-800"}`}
                        >
                          {kycFront ? <CheckCircle2 size={20} className="text-accent-400" /> : <Upload size={20} className="text-surface-400" />}
                          <span className="text-[11px] text-surface-300 leading-5">{kycFront ? "کارتِ ملی ✓" : "کارتِ ملی / شناسنامه"}</span>
                        </button>
                        <button
                          type="button"
                          onClick={() => kycSelfieRef.current?.click()}
                          className={`flex flex-col items-center justify-center gap-1.5 rounded-xl border border-dashed p-4 text-center transition ${kycSelfie ? "border-accent-500/50 bg-accent-500/5" : "border-surface-700 bg-surface-800/40 hover:bg-surface-800"}`}
                        >
                          {kycSelfie ? <CheckCircle2 size={20} className="text-accent-400" /> : <Camera size={20} className="text-surface-400" />}
                          <span className="text-[11px] text-surface-300 leading-5">{kycSelfie ? "سلفی ✓" : "سلفی با مدرک"}</span>
                        </button>
                      </div>
                      <input ref={kycFrontRef} type="file" accept="image/jpeg,image/png,image/webp" className="hidden" onChange={(e) => pickKycFile(e, setKycFront)} />
                      <input ref={kycSelfieRef} type="file" accept="image/jpeg,image/png,image/webp" className="hidden" onChange={(e) => pickKycFile(e, setKycSelfie)} />

                      <Button variant="primary" size="md" fullWidth onClick={submitKyc} disabled={submittingKyc}>
                        {submittingKyc ? <Loader2 size={18} className="animate-spin" /> : "ارسالِ مدارک برای تأیید"}
                      </Button>
                      <p className="text-[10px] text-surface-500 text-center leading-5">اطلاعاتِ هویتیِ شما محرمانه نگهداری و فقط برای احرازِ هویت استفاده می‌شود.</p>
                    </div>
                  )}
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
                                  placeholder={t("profile.ph.earthId")}
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
