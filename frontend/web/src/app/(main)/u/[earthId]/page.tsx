"use client";

import { useCallback, useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import {
  ArrowRight, BadgeCheck, Loader2, MessageCircle, Globe, Phone, Mail, MapPin, Star,
  UserPlus, UserCheck, Users, QrCode, Share2, Copy, Check, X, Grid3X3, Heart, Play,
} from "lucide-react";
import {
  socialApi, messagesApi, postsApi, businessApi, subscriptionsApi, getApiErrorMessage,
} from "@/lib/api";
import { useAuthStore } from "@/store/auth";
import { Button } from "@/components/ui/Button";
import StoryHighlights from "@/components/chat/StoryHighlights";
import { toPersianNum } from "@/lib/utils";
import toast from "react-hot-toast";

interface Profile {
  earth_id: string;
  name: string;
  username?: string | null;
  avatar_url?: string | null;
  bio?: string | null;
  role?: string | null;
  kyc_level: number;
  followers_count: number;
  following_count: number;
  is_following: boolean;
  is_followed_by: boolean;
  is_me: boolean;
}

interface UserMini {
  earth_id: string;
  name: string;
  username?: string | null;
  avatar_url?: string | null;
  role?: string | null;
  kyc_level: number;
  is_following: boolean;
}

const ROLE_LABEL: Record<string, string> = {
  user: "کاربر",
  driver: "راننده",
  cargo_owner: "صاحب بار",
  freight_broker: "باربری",
  insurance_agent: "نماینده بیمه",
  creator: "تولیدکننده محتوا",
  admin: "مدیر",
  super_admin: "مدیر ارشد",
};

interface BusinessCard {
  earth_id: string;
  kind_label: string;
  kind_emoji: string;
  display_name: string;
  category_label: string;
  category_emoji: string;
  about?: string | null;
  website?: string | null;
  contact_phone?: string | null;
  contact_email?: string | null;
  address?: string | null;
  verified: boolean;
}

interface TierCard {
  id: string;
  name: string;
  price: number;          // ریال
  perks?: string | null;
  subscriber_count: number;
}

type Tab = "posts" | "followers" | "following";

export default function UserProfilePage() {
  const router = useRouter();
  const params = useParams();
  const earthId = decodeURIComponent(String(params?.earthId ?? ""));
  const me = useAuthStore((s) => s.user);

  const [profile, setProfile] = useState<Profile | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [tab, setTab] = useState<Tab>("posts");
  const [list, setList] = useState<UserMini[]>([]);
  const [listLoading, setListLoading] = useState(false);
  const [posts, setPosts] = useState<any[]>([]);
  const [postsLoading, setPostsLoading] = useState(false);
  const [msgBusy, setMsgBusy] = useState(false);
  const [showShare, setShowShare] = useState(false);
  const [copied, setCopied] = useState(false);
  const [biz, setBiz] = useState<BusinessCard | null>(null);
  const [tiers, setTiers] = useState<TierCard[]>([]);
  const [subscribedTo, setSubscribedTo] = useState<Set<string>>(new Set());
  const [subBusy, setSubBusy] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await socialApi.profile(earthId);
      setProfile(res.data);
    } catch (e) {
      toast.error(getApiErrorMessage(e, "پروفایل پیدا نشد"));
    } finally {
      setLoading(false);
    }
  }, [earthId]);

  const loadPosts = useCallback(async () => {
    setPostsLoading(true);
    try {
      const res = await postsApi.userPosts(earthId);
      setPosts(res.data ?? []);
    } catch {
      setPosts([]);
    } finally {
      setPostsLoading(false);
    }
  }, [earthId]);

  const loadList = useCallback(async (which: Tab) => {
    if (which === "posts") return;
    setListLoading(true);
    try {
      const res = which === "followers"
        ? await socialApi.followers(earthId)
        : await socialApi.following(earthId);
      setList(res.data ?? []);
    } catch {
      setList([]);
    } finally {
      setListLoading(false);
    }
  }, [earthId]);

  // نمایهٔ کسب‌وکار و پلن‌های اشتراک. ۴۰۴ یعنی این کاربر حسابِ کسب‌وکار ندارد،
  // که حالتی عادی است و نباید خطا نشان بدهد.
  const loadBusiness = useCallback(async () => {
    if (!earthId) return;
    try {
      const r = await businessApi.profile(earthId);
      setBiz(r.data);
      businessApi.view(earthId).catch(() => {});
    } catch {
      setBiz(null);
    }
    try {
      const r = await subscriptionsApi.tiersOf(earthId);
      setTiers(r.data ?? []);
    } catch {
      setTiers([]);
    }
    try {
      const r = await subscriptionsApi.mine();
      setSubscribedTo(new Set(
        (r.data ?? [])
          .filter((s: { status: string }) => s.status === "active")
          .map((s: { tier_id: string }) => s.tier_id)
      ));
    } catch {
      setSubscribedTo(new Set());
    }
  }, [earthId]);

  const subscribe = async (tier: TierCard) => {
    if (!confirm(`اشتراکِ «${tier.name}» با ${toPersianNum(Math.round(tier.price / 10).toLocaleString("en-US"))} تومان از کیفِ شما کسر می‌شود. ادامه؟`)) return;
    setSubBusy(tier.id);
    try {
      await subscriptionsApi.subscribe(tier.id);
      toast.success("اشتراک فعال شد");
      loadBusiness();
    } catch (e) {
      toast.error(getApiErrorMessage(e, "اشتراک فعال نشد"));
    } finally {
      setSubBusy(null);
    }
  };

  useEffect(() => { load(); }, [load]);
  useEffect(() => { loadBusiness(); }, [loadBusiness]);
  useEffect(() => { loadList(tab); }, [tab, loadList]);
  useEffect(() => { if (tab === "posts") loadPosts(); }, [tab, loadPosts]);

  const toggleFollow = async () => {
    if (!profile || profile.is_me || busy) return;
    setBusy(true);
    const next = !profile.is_following;
    // optimistic
    setProfile((p) => p && ({
      ...p,
      is_following: next,
      followers_count: p.followers_count + (next ? 1 : -1),
    }));
    try {
      if (next) await socialApi.follow(profile.earth_id);
      else await socialApi.unfollow(profile.earth_id);
    } catch (e) {
      // revert
      setProfile((p) => p && ({
        ...p,
        is_following: !next,
        followers_count: p.followers_count + (next ? -1 : 1),
      }));
      toast.error(getApiErrorMessage(e, "خطا در انجام عملیات"));
    } finally {
      setBusy(false);
    }
  };

  const startMessage = async () => {
    if (!profile || profile.is_me || msgBusy) return;
    setMsgBusy(true);
    try {
      await messagesApi.startRoom(profile.earth_id);
      router.push(`/messages/${profile.earth_id}`);
    } catch (e) {
      toast.error(getApiErrorMessage(e, "خطا در شروع گفت‌وگو"));
    } finally {
      setMsgBusy(false);
    }
  };

  const API = process.env.NEXT_PUBLIC_API_URL ?? "";
  const profileUrl =
    typeof window !== "undefined" && profile
      ? `${window.location.origin}/u/${profile.earth_id}`
      : "";

  const copyLink = async () => {
    try {
      await navigator.clipboard.writeText(profileUrl);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      toast.error("کپی نشد");
    }
  };

  const shareLink = async () => {
    if (typeof navigator !== "undefined" && (navigator as Navigator).share) {
      try {
        await (navigator as Navigator).share({ title: profile?.name ?? "Dilix", url: profileUrl });
      } catch { /* لغو شد */ }
    } else {
      copyLink();
    }
  };

  return (
    <div className="min-h-screen min-h-dvh" style={{ background: "var(--color-bg)" }}>
      <div className="relative mx-auto flex flex-col min-h-screen min-h-dvh w-full max-w-lg" style={{ background: "var(--color-bg)" }}>

        {/* Header */}
        <header
          className="app-header sticky top-0 z-40 flex items-center gap-3 px-4 h-14"
        >
          <button onClick={() => router.back()} className="p-1 -mr-1 text-surface-300 hover:text-white">
            <ArrowRight className="w-5 h-5" />
          </button>
          <h1 className="text-base font-bold text-white truncate">
            {profile?.username ? `@${profile.username}` : (profile?.name ?? "پروفایل")}
          </h1>
          {profile && (
            <button
              onClick={() => setShowShare(true)}
              className="ms-auto p-1 text-surface-300 hover:text-white"
              aria-label="اشتراک و QR"
            >
              <QrCode className="w-5 h-5" />
            </button>
          )}
        </header>

        {loading ? (
          <div className="flex-1 flex items-center justify-center py-24">
            <Loader2 className="w-6 h-6 animate-spin text-primary" />
          </div>
        ) : !profile ? (
          <div className="flex-1 flex items-center justify-center py-24 text-surface-400 text-sm">
            کاربر پیدا نشد
          </div>
        ) : (
          <div className="flex-1">
            {/* Profile card */}
            <div className="px-4 pt-5 pb-4">
              <div className="flex items-center gap-4">
                <div className="w-20 h-20 rounded-full overflow-hidden ring-2 ring-primary/40 bg-surface-800 flex items-center justify-center shrink-0">
                  {profile.avatar_url ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={profile.avatar_url} alt="avatar" className="w-full h-full object-cover" />
                  ) : (
                    <span className="text-2xl font-bold text-primary">{profile.name.charAt(0)}</span>
                  )}
                </div>

                {/* counts */}
                <div className="flex-1 grid grid-cols-2 gap-2 text-center">
                  <button onClick={() => setTab("followers")} className="py-1">
                    <div className="text-lg font-bold text-white">{toPersianNum(profile.followers_count)}</div>
                    <div className="text-xs text-surface-400">دنبال‌کننده</div>
                  </button>
                  <button onClick={() => setTab("following")} className="py-1">
                    <div className="text-lg font-bold text-white">{toPersianNum(profile.following_count)}</div>
                    <div className="text-xs text-surface-400">دنبال‌شده</div>
                  </button>
                </div>
              </div>

              {/* name + badges */}
              <div className="mt-3 flex items-center gap-1.5">
                <span className="text-base font-bold text-white">{profile.name}</span>
                {profile.kyc_level >= 2 && (
                  <BadgeCheck className="w-4 h-4 text-blue-400" aria-label="تأیید‌شده" />
                )}
              </div>
              <div className="text-xs text-surface-500 mt-0.5" dir="ltr">{profile.earth_id}</div>
              {profile.role && ROLE_LABEL[profile.role] && profile.role !== "user" && (
                <div className="inline-block mt-2 text-xs px-2 py-0.5 rounded-full bg-primary/15 text-primary">
                  {ROLE_LABEL[profile.role]}
                </div>
              )}
              {profile.bio && (
                <p className="mt-2 text-sm text-surface-300 whitespace-pre-wrap">{profile.bio}</p>
              )}

              {/* actions */}
              <div className="mt-4 flex gap-2">
                {profile.is_me ? (
                  <Button variant="ghost" fullWidth onClick={() => router.push("/profile")}>
                    ویرایش پروفایل
                  </Button>
                ) : (
                  <>
                    <Button
                      variant={profile.is_following ? "outline" : "primary"}
                      fullWidth
                      onClick={toggleFollow}
                      disabled={busy}
                    >
                      {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : profile.is_following ? (
                        <><UserCheck className="w-4 h-4" /> دنبال می‌کنید</>
                      ) : (
                        <><UserPlus className="w-4 h-4" /> {profile.is_followed_by ? "دنبال متقابل" : "دنبال کردن"}</>
                      )}
                    </Button>
                    <Button variant="secondary" onClick={startMessage} disabled={msgBusy}>
                      {msgBusy ? <Loader2 className="w-4 h-4 animate-spin" /> : <MessageCircle className="w-4 h-4" />}
                    </Button>
                  </>
                )}
              </div>
            </div>

            {/* کارتِ کسب‌وکار */}
            {biz && (
              <div className="mx-4 mt-4 rounded-2xl border border-surface-800 bg-surface-900/60 p-4">
                <div className="flex items-center gap-2">
                  <span className="text-xl">{biz.kind_emoji}</span>
                  <span className="font-bold text-surface-50">{biz.display_name}</span>
                  {biz.verified && <BadgeCheck className="w-4 h-4 text-sky-400" />}
                  <span className="text-xs text-surface-400">
                    · {biz.category_emoji} {biz.category_label}
                  </span>
                </div>
                {biz.about && (
                  <p className="mt-2 text-sm text-surface-300 whitespace-pre-wrap leading-6">
                    {biz.about}
                  </p>
                )}
                <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1.5 text-xs text-surface-400">
                  {biz.website && (
                    <a
                      href={biz.website}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="flex items-center gap-1 hover:text-primary"
                      dir="ltr"
                    >
                      <Globe className="w-3.5 h-3.5" /> {biz.website}
                    </a>
                  )}
                  {biz.contact_phone && (
                    <a href={`tel:${biz.contact_phone}`} className="flex items-center gap-1 hover:text-primary" dir="ltr">
                      <Phone className="w-3.5 h-3.5" /> {toPersianNum(biz.contact_phone)}
                    </a>
                  )}
                  {biz.contact_email && (
                    <a href={`mailto:${biz.contact_email}`} className="flex items-center gap-1 hover:text-primary" dir="ltr">
                      <Mail className="w-3.5 h-3.5" /> {biz.contact_email}
                    </a>
                  )}
                  {biz.address && (
                    <span className="flex items-center gap-1">
                      <MapPin className="w-3.5 h-3.5" /> {biz.address}
                    </span>
                  )}
                </div>
              </div>
            )}

            {/* پلن‌های اشتراک */}
            {!profile.is_me && tiers.length > 0 && (
              <div className="mx-4 mt-3 space-y-2">
                <div className="text-sm font-semibold text-surface-100 flex items-center gap-1.5">
                  <Star className="w-4 h-4 text-amber-400" />
                  حمایت با اشتراکِ ماهانه
                </div>
                {tiers.map((x) => {
                  const active = subscribedTo.has(x.id);
                  return (
                    <div
                      key={x.id}
                      className="rounded-2xl border border-surface-800 bg-surface-900/60 p-3.5 flex items-start gap-3"
                    >
                      <div className="flex-1 min-w-0">
                        <div className="font-semibold text-surface-50">{x.name}</div>
                        <div className="text-xs text-surface-400 mt-0.5">
                          {toPersianNum(Math.round(x.price / 10).toLocaleString("en-US"))} تومان ماهانه
                          {x.subscriber_count > 0 && (
                            <> · {toPersianNum(String(x.subscriber_count))} مشترک</>
                          )}
                        </div>
                        {x.perks && (
                          <p className="text-xs text-surface-300 mt-1.5 leading-5 whitespace-pre-wrap">
                            {x.perks}
                          </p>
                        )}
                      </div>
                      <Button
                        variant={active ? "outline" : "primary"}
                        onClick={() => subscribe(x)}
                        disabled={active || subBusy === x.id}
                        className="shrink-0"
                      >
                        {subBusy === x.id
                          ? <Loader2 className="w-4 h-4 animate-spin" />
                          : active ? "مشترک هستید" : "اشتراک"}
                      </Button>
                    </div>
                  );
                })}
              </div>
            )}

            {/* Highlights */}
            <StoryHighlights earthId={profile.earth_id} isMe={profile.is_me} />

            {/* Tabs */}
            <div className="flex border-t border-surface-800 sticky top-14 z-30" style={{ background: "var(--color-bg)" }}>
              {(["posts", "followers", "following"] as Tab[]).map((t) => (
                <button
                  key={t}
                  onClick={() => setTab(t)}
                  className={`flex-1 py-3 text-sm font-medium transition-colors flex items-center justify-center gap-1 ${
                    tab === t ? "text-white border-b-2 border-primary" : "text-surface-500"
                  }`}
                >
                  {t === "posts" ? (<><Grid3X3 className="w-4 h-4" /> پست‌ها</>)
                    : t === "followers" ? "دنبال‌کنندگان" : "دنبال‌شده‌ها"}
                </button>
              ))}
            </div>

            {/* Posts grid */}
            {tab === "posts" && (
              <div className="pb-24">
                {postsLoading ? (
                  <div className="flex items-center justify-center py-10">
                    <Loader2 className="w-5 h-5 animate-spin text-primary" />
                  </div>
                ) : posts.length === 0 ? (
                  <div className="flex flex-col items-center justify-center py-12 text-surface-500">
                    <Grid3X3 className="w-8 h-8 mb-2 opacity-40" />
                    <span className="text-sm">هنوز پستی ندارد</span>
                  </div>
                ) : (
                  <div className="grid grid-cols-3 gap-1">
                    {posts.map((p) => (
                      <button
                        key={p.id}
                        onClick={() => router.push(`/discover`)}
                        className="relative aspect-square bg-surface-900 overflow-hidden"
                      >
                        {p.media_type === "video" ? (
                          <>
                            <video src={p.media_url} className="w-full h-full object-cover" muted playsInline preload="metadata" />
                            <Play className="absolute top-1.5 right-1.5 w-4 h-4 text-white drop-shadow" fill="currentColor" />
                          </>
                        ) : (
                          // eslint-disable-next-line @next/next/no-img-element
                          <img src={p.media_url} alt="" className="w-full h-full object-cover" />
                        )}
                        <span className="absolute bottom-1 left-1 flex items-center gap-1 text-white text-[11px] drop-shadow">
                          <Heart className="w-3 h-3" fill="currentColor" /> {p.like_count}
                        </span>
                      </button>
                    ))}
                  </div>
                )}
              </div>
            )}

            {/* List */}
            {tab !== "posts" && (
            <div className="px-4 py-2 pb-24">
              {listLoading ? (
                <div className="flex items-center justify-center py-10">
                  <Loader2 className="w-5 h-5 animate-spin text-primary" />
                </div>
              ) : list.length === 0 ? (
                <div className="flex flex-col items-center justify-center py-12 text-surface-500">
                  <Users className="w-8 h-8 mb-2 opacity-40" />
                  <span className="text-sm">{tab === "followers" ? "هنوز دنبال‌کننده‌ای ندارد" : "هنوز کسی را دنبال نکرده"}</span>
                </div>
              ) : (
                list.map((u) => (
                  <button
                    key={u.earth_id}
                    onClick={() => router.push(`/u/${u.earth_id}`)}
                    className="w-full flex items-center gap-3 py-2.5 text-right"
                  >
                    <div className="w-11 h-11 rounded-full overflow-hidden bg-surface-800 flex items-center justify-center shrink-0">
                      {u.avatar_url ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img src={u.avatar_url} alt="" className="w-full h-full object-cover" />
                      ) : (
                        <span className="text-base font-bold text-primary">{u.name.charAt(0)}</span>
                      )}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-1">
                        <span className="text-sm font-medium text-white truncate">{u.name}</span>
                        {u.kyc_level >= 2 && <BadgeCheck className="w-3.5 h-3.5 text-blue-400 shrink-0" />}
                      </div>
                      {u.username && <div className="text-xs text-surface-500 truncate">@{u.username}</div>}
                    </div>
                    {u.is_following && (
                      <span className="text-xs text-surface-500 shrink-0">دنبال‌شده</span>
                    )}
                  </button>
                ))
              )}
            </div>
            )}
          </div>
        )}

        {/* Share / QR modal */}
        {profile && showShare && (
          <div
            className="fixed inset-0 z-50 flex items-center justify-center p-6"
            style={{ background: "rgba(0,0,0,0.72)", backdropFilter: "blur(4px)" }}
            onClick={() => setShowShare(false)}
          >
            <div
              className="w-full max-w-xs rounded-2xl p-5 bg-surface-900 border border-surface-800"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center justify-between mb-4">
                <span className="text-sm font-bold text-white">اشتراک پروفایل</span>
                <button onClick={() => setShowShare(false)} className="text-surface-400 hover:text-white">
                  <X className="w-4 h-4" />
                </button>
              </div>
              <div className="bg-white rounded-xl p-3 flex items-center justify-center">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={`${API}/api/v1/social/qr/${profile.earth_id}`} alt="QR" className="w-44 h-44" />
              </div>
              <div className="text-center mt-3">
                <div className="text-sm font-bold text-white">{profile.name}</div>
                <div className="text-xs text-surface-500" dir="ltr">{profile.earth_id}</div>
              </div>
              <p className="text-[11px] text-surface-500 text-center mt-2">
                این کد را اسکن کنید تا پروفایل باز شود
              </p>
              <div className="flex gap-2 mt-4">
                <Button variant="ghost" fullWidth onClick={copyLink}>
                  {copied ? <><Check className="w-4 h-4" /> کپی شد</> : <><Copy className="w-4 h-4" /> کپی لینک</>}
                </Button>
                <Button variant="primary" fullWidth onClick={shareLink}>
                  <Share2 className="w-4 h-4" /> اشتراک
                </Button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
