"use client";

import { useCallback, useEffect, useState } from "react";
import {
  BadgeCheck, BarChart3, Building2, Eye, Heart, Loader2, Plus, Star,
  Trash2, TrendingUp, Users, Wallet as WalletIcon,
} from "lucide-react";
import toast from "react-hot-toast";

import AppShell from "@/components/layout/AppShell";
import { Button } from "@/components/ui/Button";
import { businessApi, getApiErrorMessage, subscriptionsApi } from "@/lib/api";
import { toPersianNum } from "@/lib/utils";
import { useTranslation } from "@/store/i18n";

// سرور همیشه ریال می‌دهد؛ کاربرِ ایرانی تومان می‌خواند.
function fmtToman(rial: number): string {
  return toPersianNum(Math.round((rial || 0) / 10).toLocaleString("en-US"));
}

function fmtNum(n: number): string {
  return toPersianNum((n || 0).toLocaleString("en-US"));
}

function fmtDate(iso: string): string {
  try {
    return toPersianNum(
      new Date(iso).toLocaleDateString("fa-IR", {
        year: "numeric", month: "long", day: "numeric",
      })
    );
  } catch {
    return "";
  }
}

interface Category { key: string; label: string; emoji: string }
interface Kind { key: string; label: string; emoji: string; min_kyc: number }

interface Business {
  id: string;
  earth_id: string;
  kind: string;
  kind_label: string;
  kind_emoji: string;
  display_name: string;
  category: string;
  category_label: string;
  category_emoji: string;
  about?: string | null;
  website?: string | null;
  contact_phone?: string | null;
  contact_email?: string | null;
  address?: string | null;
  verified: boolean;
  follower_count: number;
  created_at: string;
}

interface DayPoint { day: string; value: number }

interface TopPost {
  id: string;
  media_url: string;
  caption?: string | null;
  like_count: number;
  comment_count: number;
  save_count: number;
  engagement: number;
  created_at: string;
}

interface Insights {
  followers_total: number;
  followers_7d: number;
  followers_30d: number;
  views_7d: number;
  views_30d: number;
  posts_total: number;
  likes_total: number;
  comments_total: number;
  saves_total: number;
  engagement_rate: number;
  subscribers_active: number;
  revenue_30d: number;
  views_series: DayPoint[];
  followers_series: DayPoint[];
  top_posts: TopPost[];
}

interface Tier {
  id: string;
  owner_earth_id: string;
  name: string;
  price: number;
  perks?: string | null;
  is_active: boolean;
  subscriber_count: number;
  created_at: string;
}

interface Sub {
  id: string;
  owner_earth_id: string;
  owner_name?: string | null;
  subscriber_earth_id: string;
  subscriber_name?: string | null;
  tier_id: string;
  tier_name: string;
  price: number;
  status: string;
  auto_renew: boolean;
  started_at: string;
  current_period_end: string;
  periods_paid: number;
  total_paid: number;
}

type Tab = "profile" | "insights" | "tiers" | "subs";

// نمودارِ ستونیِ سبک — بدون کتابخانهٔ اضافه، چون داده فقط ۳۰ نقطه است.
function MiniChart({ data, color }: { data: DayPoint[]; color: string }) {
  const max = Math.max(1, ...data.map((d) => d.value));
  return (
    <div className="flex items-end gap-[3px] h-24" dir="ltr">
      {data.map((d) => (
        <div
          key={d.day}
          title={`${d.day}: ${d.value}`}
          className={`flex-1 rounded-t-sm ${color} transition-all`}
          style={{ height: `${Math.max(3, (d.value / max) * 100)}%` }}
        />
      ))}
    </div>
  );
}

function StatCard({
  icon, label, value, hint,
}: { icon: React.ReactNode; label: string; value: string; hint?: string }) {
  return (
    <div className="card p-3.5">
      <div className="flex items-center gap-2 text-surface-400 text-xs mb-1.5">
        {icon}
        {label}
      </div>
      <div className="text-lg font-bold text-surface-50">{value}</div>
      {hint && <div className="text-[11px] text-surface-500 mt-0.5">{hint}</div>}
    </div>
  );
}

export default function BusinessPage() {
  const { t } = useTranslation();
  const [tab, setTab] = useState<Tab>("profile");

  const [cats, setCats] = useState<Category[]>([]);
  const [kinds, setKinds] = useState<Kind[]>([]);
  const [biz, setBiz] = useState<Business | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const [kind, setKind] = useState("business");
  const [displayName, setDisplayName] = useState("");
  const [category, setCategory] = useState("other");
  const [about, setAbout] = useState("");
  const [website, setWebsite] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [address, setAddress] = useState("");

  const [insights, setInsights] = useState<Insights | null>(null);
  const [tiers, setTiers] = useState<Tier[]>([]);
  const [subscribers, setSubscribers] = useState<Sub[]>([]);
  const [mySubs, setMySubs] = useState<Sub[]>([]);
  const [listLoading, setListLoading] = useState(false);

  const [newName, setNewName] = useState("");
  const [newPrice, setNewPrice] = useState("");
  const [newPerks, setNewPerks] = useState("");
  const [creatingTier, setCreatingTier] = useState(false);

  const fillForm = (b: Business) => {
    setKind(b.kind);
    setDisplayName(b.display_name);
    setCategory(b.category);
    setAbout(b.about || "");
    setWebsite(b.website || "");
    setPhone(b.contact_phone || "");
    setEmail(b.contact_email || "");
    setAddress(b.address || "");
  };

  useEffect(() => {
    Promise.all([businessApi.categories(), businessApi.kinds()])
      .then(([c, k]) => { setCats(c.data); setKinds(k.data); })
      .catch(() => {});
    businessApi.me()
      .then((r) => { setBiz(r.data); fillForm(r.data); })
      .catch(() => setBiz(null))
      .finally(() => setLoading(false));
  }, []);

  const loadInsights = useCallback(async () => {
    setListLoading(true);
    try {
      const r = await businessApi.insights();
      setInsights(r.data);
    } catch (e) {
      toast.error(getApiErrorMessage(e, t("biz.loadFailed")));
    } finally {
      setListLoading(false);
    }
  }, [t]);

  const loadTiers = useCallback(async () => {
    setListLoading(true);
    try {
      const [a, b] = await Promise.all([
        subscriptionsApi.myTiers(),
        subscriptionsApi.subscribers(),
      ]);
      setTiers(a.data);
      setSubscribers(b.data);
    } catch (e) {
      toast.error(getApiErrorMessage(e, t("biz.loadFailed")));
    } finally {
      setListLoading(false);
    }
  }, [t]);

  const loadMySubs = useCallback(async () => {
    setListLoading(true);
    try {
      const r = await subscriptionsApi.mine();
      setMySubs(r.data);
    } catch (e) {
      toast.error(getApiErrorMessage(e, t("biz.loadFailed")));
    } finally {
      setListLoading(false);
    }
  }, [t]);

  useEffect(() => {
    if (tab === "insights" && biz) loadInsights();
    if (tab === "tiers") loadTiers();
    if (tab === "subs") loadMySubs();
  }, [tab, biz, loadInsights, loadTiers, loadMySubs]);

  const save = async () => {
    if (displayName.trim().length < 2) {
      toast.error(t("biz.nameTooShort"));
      return;
    }
    setSaving(true);
    const body = {
      kind,
      display_name: displayName.trim(),
      category,
      about: about.trim() || null,
      website: website.trim() || null,
      contact_phone: phone.trim() || null,
      contact_email: email.trim() || null,
      address: address.trim() || null,
    };
    try {
      const r = biz
        ? await businessApi.update(body)
        : await businessApi.create(body);
      setBiz(r.data);
      fillForm(r.data);
      toast.success(biz ? t("biz.saved") : t("biz.created"));
    } catch (e) {
      toast.error(getApiErrorMessage(e, t("biz.saveFailed")));
    } finally {
      setSaving(false);
    }
  };

  const removeBiz = async () => {
    if (!confirm(t("biz.removeConfirm"))) return;
    setSaving(true);
    try {
      await businessApi.remove();
      setBiz(null);
      setInsights(null);
      toast.success(t("biz.removed"));
    } catch (e) {
      toast.error(getApiErrorMessage(e, t("biz.saveFailed")));
    } finally {
      setSaving(false);
    }
  };

  const addTier = async () => {
    // ورودی به تومان است و سرور ریال می‌خواهد.
    const toman = parseInt(newPrice.replace(/[^\d]/g, ""), 10);
    if (!newName.trim() || !toman) {
      toast.error(t("biz.tierIncomplete"));
      return;
    }
    setCreatingTier(true);
    try {
      await subscriptionsApi.createTier({
        name: newName.trim(),
        price: toman * 10,
        perks: newPerks.trim() || null,
      });
      setNewName(""); setNewPrice(""); setNewPerks("");
      toast.success(t("biz.tierCreated"));
      loadTiers();
    } catch (e) {
      toast.error(getApiErrorMessage(e, t("biz.tierFailed")));
    } finally {
      setCreatingTier(false);
    }
  };

  const deactivateTier = async (id: string) => {
    if (!confirm(t("biz.tierOffConfirm"))) return;
    try {
      await subscriptionsApi.deactivateTier(id);
      toast.success(t("biz.tierOff"));
      loadTiers();
    } catch (e) {
      toast.error(getApiErrorMessage(e, t("biz.tierFailed")));
    }
  };

  const cancelSub = async (id: string) => {
    if (!confirm(t("biz.cancelConfirm"))) return;
    try {
      await subscriptionsApi.cancel(id);
      toast.success(t("biz.cancelled"));
      loadMySubs();
    } catch (e) {
      toast.error(getApiErrorMessage(e, t("biz.cancelFailed")));
    }
  };

  const statusLabel = (s: string) =>
    s === "active" ? t("biz.stActive")
      : s === "cancelled" ? t("biz.stCancelled")
        : t("biz.stExpired");

  const statusClass = (s: string) =>
    s === "active" ? "bg-green-500/12 text-green-400"
      : s === "cancelled" ? "bg-surface-700 text-surface-300"
        : "bg-amber-500/12 text-amber-400";

  if (loading) {
    return (
      <AppShell title={t("biz.title")}>
        <div className="page-inner flex justify-center py-20">
          <Loader2 className="w-6 h-6 animate-spin text-surface-400" />
        </div>
      </AppShell>
    );
  }

  return (
    <AppShell title={t("biz.title")}>
      <div className="page-inner space-y-4">
        <div className="flex gap-2 overflow-x-auto">
          {([
            ["profile", t("biz.tabProfile"), <Building2 key="i" className="w-4 h-4" />],
            ["insights", t("biz.tabInsights"), <BarChart3 key="i" className="w-4 h-4" />],
            ["tiers", t("biz.tabTiers"), <Star key="i" className="w-4 h-4" />],
            ["subs", t("biz.tabSubs"), <Users key="i" className="w-4 h-4" />],
          ] as [Tab, string, React.ReactNode][]).map(([k, label, icon]) => (
            <button
              key={k}
              onClick={() => setTab(k)}
              className={`flex-1 min-w-[7rem] flex items-center justify-center gap-1.5 h-10 rounded-xl text-sm transition-colors ${
                tab === k
                  ? "bg-primary text-white"
                  : "bg-surface-800 text-surface-300 hover:bg-surface-700"
              }`}
            >
              {icon}
              {label}
            </button>
          ))}
        </div>

        {/* ── نمایه ─────────────────────────────────────────────────────── */}
        {tab === "profile" && (
          <div className="space-y-4">
            {biz && (
              <div className="card p-4 flex items-center gap-3">
                <div className="w-12 h-12 rounded-2xl bg-primary/12 flex items-center justify-center text-2xl">
                  {biz.kind_emoji}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-1.5">
                    <span className="font-bold text-surface-50 truncate">
                      {biz.display_name}
                    </span>
                    {biz.verified && (
                      <BadgeCheck className="w-4 h-4 text-sky-400 shrink-0" />
                    )}
                  </div>
                  <div className="text-xs text-surface-400">
                    {biz.category_emoji} {biz.category_label} · {biz.kind_label} ·{" "}
                    {fmtNum(biz.follower_count)} {t("biz.followers")}
                  </div>
                </div>
              </div>
            )}

            {!biz && (
              <div className="card p-4 text-sm text-surface-300">
                {t("biz.introText")}
              </div>
            )}

            <div className="card p-4 space-y-3">
              <div>
                <label className="block text-xs text-surface-400 mb-1.5">
                  {t("biz.kind")}
                </label>
                <div className="flex flex-wrap gap-2">
                  {kinds.map((k) => (
                    <button
                      key={k.key}
                      onClick={() => setKind(k.key)}
                      className={`px-3 h-9 rounded-xl text-xs transition-colors ${
                        kind === k.key
                          ? "bg-primary text-white"
                          : "bg-surface-800 text-surface-300 hover:bg-surface-700"
                      }`}
                    >
                      {k.emoji} {k.label}
                      {k.min_kyc > 0 && (
                        <span className="opacity-60">
                          {" "}· {t("biz.kycNeeded")} {toPersianNum(String(k.min_kyc))}
                        </span>
                      )}
                    </button>
                  ))}
                </div>
              </div>

              <div>
                <label className="block text-xs text-surface-400 mb-1">
                  {t("biz.displayName")}
                </label>
                <input
                  value={displayName}
                  onChange={(e) => setDisplayName(e.target.value)}
                  placeholder={t("biz.displayNamePh")}
                  className="input w-full"
                />
              </div>

              <div>
                <label className="block text-xs text-surface-400 mb-1.5">
                  {t("biz.category")}
                </label>
                <div className="flex flex-wrap gap-1.5">
                  {cats.map((c) => (
                    <button
                      key={c.key}
                      onClick={() => setCategory(c.key)}
                      className={`px-2.5 h-8 rounded-lg text-xs transition-colors ${
                        category === c.key
                          ? "bg-primary text-white"
                          : "bg-surface-800 text-surface-300 hover:bg-surface-700"
                      }`}
                    >
                      {c.emoji} {c.label}
                    </button>
                  ))}
                </div>
              </div>

              <div>
                <label className="block text-xs text-surface-400 mb-1">
                  {t("biz.about")}
                </label>
                <textarea
                  value={about}
                  onChange={(e) => setAbout(e.target.value)}
                  rows={3}
                  placeholder={t("biz.aboutPh")}
                  className="input w-full resize-none"
                />
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs text-surface-400 mb-1">
                    {t("biz.website")}
                  </label>
                  <input
                    value={website}
                    onChange={(e) => setWebsite(e.target.value)}
                    placeholder="https://…"
                    className="input w-full"
                    dir="ltr"
                  />
                </div>
                <div>
                  <label className="block text-xs text-surface-400 mb-1">
                    {t("biz.phone")}
                  </label>
                  <input
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                    inputMode="tel"
                    className="input w-full"
                    dir="ltr"
                  />
                </div>
                <div>
                  <label className="block text-xs text-surface-400 mb-1">
                    {t("biz.email")}
                  </label>
                  <input
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    inputMode="email"
                    className="input w-full"
                    dir="ltr"
                  />
                </div>
                <div>
                  <label className="block text-xs text-surface-400 mb-1">
                    {t("biz.address")}
                  </label>
                  <input
                    value={address}
                    onChange={(e) => setAddress(e.target.value)}
                    className="input w-full"
                  />
                </div>
              </div>

              <div className="flex gap-2 pt-1">
                <Button onClick={save} disabled={saving} className="flex-1">
                  {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : null}
                  {biz ? t("biz.save") : t("biz.create")}
                </Button>
                {biz && (
                  <Button
                    onClick={removeBiz}
                    disabled={saving}
                    variant="secondary"
                  >
                    <Trash2 className="w-4 h-4" />
                    {t("biz.remove")}
                  </Button>
                )}
              </div>

              {/* نشانِ تأیید خریدنی یا دستی نیست — به احراز هویت گره خورده. */}
              <p className="text-[11px] text-surface-500 leading-5">
                {t("biz.verifyNote")}
              </p>
            </div>
          </div>
        )}

        {/* ── Insights ──────────────────────────────────────────────────── */}
        {tab === "insights" && (
          <div className="space-y-4">
            {!biz ? (
              <div className="card p-6 text-center text-sm text-surface-400">
                {t("biz.needAccount")}
              </div>
            ) : listLoading && !insights ? (
              <div className="flex justify-center py-12">
                <Loader2 className="w-6 h-6 animate-spin text-surface-400" />
              </div>
            ) : insights ? (
              <>
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                  <StatCard
                    icon={<Users className="w-3.5 h-3.5" />}
                    label={t("biz.followers")}
                    value={fmtNum(insights.followers_total)}
                    hint={`+${fmtNum(insights.followers_7d)} ${t("biz.last7")}`}
                  />
                  <StatCard
                    icon={<Eye className="w-3.5 h-3.5" />}
                    label={t("biz.views30")}
                    value={fmtNum(insights.views_30d)}
                    hint={`${fmtNum(insights.views_7d)} ${t("biz.last7")}`}
                  />
                  <StatCard
                    icon={<TrendingUp className="w-3.5 h-3.5" />}
                    label={t("biz.engagement")}
                    value={`${toPersianNum(insights.engagement_rate.toFixed(1))}٪`}
                    hint={`${fmtNum(insights.posts_total)} ${t("biz.posts")}`}
                  />
                  <StatCard
                    icon={<WalletIcon className="w-3.5 h-3.5" />}
                    label={t("biz.revenue30")}
                    value={fmtToman(insights.revenue_30d)}
                    hint={`${fmtNum(insights.subscribers_active)} ${t("biz.activeSubs")}`}
                  />
                </div>

                <div className="grid grid-cols-1 lg:grid-cols-2 gap-3">
                  <div className="card p-4">
                    <div className="text-xs text-surface-400 mb-3">
                      {t("biz.viewsChart")}
                    </div>
                    <MiniChart data={insights.views_series} color="bg-cyan-500/70" />
                  </div>
                  <div className="card p-4">
                    <div className="text-xs text-surface-400 mb-3">
                      {t("biz.followersChart")}
                    </div>
                    <MiniChart data={insights.followers_series} color="bg-violet-500/70" />
                  </div>
                </div>

                <div className="grid grid-cols-3 gap-3">
                  <StatCard
                    icon={<Heart className="w-3.5 h-3.5" />}
                    label={t("biz.likes")}
                    value={fmtNum(insights.likes_total)}
                  />
                  <StatCard
                    icon={<Heart className="w-3.5 h-3.5" />}
                    label={t("biz.comments")}
                    value={fmtNum(insights.comments_total)}
                  />
                  <StatCard
                    icon={<Heart className="w-3.5 h-3.5" />}
                    label={t("biz.saves")}
                    value={fmtNum(insights.saves_total)}
                  />
                </div>

                {insights.top_posts.length > 0 && (
                  <div className="card p-4">
                    <div className="text-sm font-semibold text-surface-100 mb-3">
                      {t("biz.topPosts")}
                    </div>
                    <div className="space-y-2">
                      {insights.top_posts.map((p, i) => (
                        <div key={p.id} className="flex items-center gap-3">
                          <span className="w-5 text-center text-xs text-surface-500">
                            {toPersianNum(String(i + 1))}
                          </span>
                          <div className="flex-1 min-w-0">
                            <div className="text-sm text-surface-200 truncate">
                              {p.caption || t("biz.noCaption")}
                            </div>
                            <div className="text-[11px] text-surface-500">
                              ❤️ {fmtNum(p.like_count)} · 💬 {fmtNum(p.comment_count)} ·
                              {" "}🔖 {fmtNum(p.save_count)}
                            </div>
                          </div>
                          <span className="text-xs text-surface-400 shrink-0">
                            {fmtNum(p.engagement)}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </>
            ) : null}
          </div>
        )}

        {/* ── پلن‌های اشتراک ────────────────────────────────────────────── */}
        {tab === "tiers" && (
          <div className="space-y-4">
            <div className="card p-4 space-y-3">
              <div className="text-sm font-semibold text-surface-100">
                {t("biz.newTier")}
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs text-surface-400 mb-1">
                    {t("biz.tierName")}
                  </label>
                  <input
                    value={newName}
                    onChange={(e) => setNewName(e.target.value)}
                    placeholder={t("biz.tierNamePh")}
                    className="input w-full"
                  />
                </div>
                <div>
                  <label className="block text-xs text-surface-400 mb-1">
                    {t("biz.tierPrice")}
                  </label>
                  <input
                    value={newPrice}
                    onChange={(e) => setNewPrice(e.target.value)}
                    inputMode="numeric"
                    placeholder={t("biz.tierPricePh")}
                    className="input w-full"
                    dir="ltr"
                  />
                </div>
              </div>
              <div>
                <label className="block text-xs text-surface-400 mb-1">
                  {t("biz.tierPerks")}
                </label>
                <textarea
                  value={newPerks}
                  onChange={(e) => setNewPerks(e.target.value)}
                  rows={2}
                  placeholder={t("biz.tierPerksPh")}
                  className="input w-full resize-none"
                />
              </div>
              <Button onClick={addTier} disabled={creatingTier} className="w-full">
                {creatingTier
                  ? <Loader2 className="w-4 h-4 animate-spin" />
                  : <Plus className="w-4 h-4" />}
                {t("biz.addTier")}
              </Button>
            </div>

            {tiers.map((x) => (
              <div key={x.id} className="card p-4">
                <div className="flex items-start gap-3">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="font-semibold text-surface-50">{x.name}</span>
                      {!x.is_active && (
                        <span className="px-2 py-0.5 rounded-md bg-surface-700 text-surface-400 text-[10px]">
                          {t("biz.tierInactive")}
                        </span>
                      )}
                    </div>
                    <div className="text-xs text-surface-400 mt-0.5">
                      {fmtToman(x.price)} {t("biz.tomanPerMonth")} ·{" "}
                      {fmtNum(x.subscriber_count)} {t("biz.subscribers")}
                    </div>
                    {x.perks && (
                      <p className="text-xs text-surface-300 mt-1.5 leading-5">
                        {x.perks}
                      </p>
                    )}
                  </div>
                  {x.is_active && (
                    <button
                      onClick={() => deactivateTier(x.id)}
                      className="p-2 rounded-lg text-surface-400 hover:text-red-400 hover:bg-surface-800"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  )}
                </div>
              </div>
            ))}

            {!listLoading && tiers.length === 0 && (
              <div className="card p-6 text-center text-sm text-surface-400">
                {t("biz.noTiers")}
              </div>
            )}

            {subscribers.length > 0 && (
              <div className="card p-4">
                <div className="text-sm font-semibold text-surface-100 mb-3">
                  {t("biz.mySubscribers")}
                </div>
                <div className="space-y-2.5">
                  {subscribers.map((s) => (
                    <div key={s.id} className="flex items-center gap-3">
                      <div className="flex-1 min-w-0">
                        <div className="text-sm text-surface-200 truncate">
                          {s.subscriber_name || s.subscriber_earth_id}
                        </div>
                        <div className="text-[11px] text-surface-500">
                          {s.tier_name} · {fmtNum(s.periods_paid)} {t("biz.periods")} ·{" "}
                          {fmtToman(s.total_paid)} {t("biz.toman")}
                        </div>
                      </div>
                      <span className={`px-2 py-0.5 rounded-md text-[10px] shrink-0 ${statusClass(s.status)}`}>
                        {statusLabel(s.status)}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}

        {/* ── اشتراک‌های من ─────────────────────────────────────────────── */}
        {tab === "subs" && (
          <div className="space-y-3">
            {listLoading && mySubs.length === 0 ? (
              <div className="flex justify-center py-12">
                <Loader2 className="w-6 h-6 animate-spin text-surface-400" />
              </div>
            ) : mySubs.length === 0 ? (
              <div className="card p-6 text-center text-sm text-surface-400">
                {t("biz.noSubs")}
              </div>
            ) : (
              mySubs.map((s) => (
                <div key={s.id} className="card p-4">
                  <div className="flex items-start gap-3">
                    <div className="flex-1 min-w-0">
                      <div className="font-semibold text-surface-50 truncate">
                        {s.owner_name || s.owner_earth_id}
                      </div>
                      <div className="text-xs text-surface-400 mt-0.5">
                        {s.tier_name} · {fmtToman(s.price)} {t("biz.tomanPerMonth")}
                      </div>
                      <div className="text-[11px] text-surface-500 mt-1">
                        {t("biz.until")} {fmtDate(s.current_period_end)} ·{" "}
                        {fmtNum(s.periods_paid)} {t("biz.periods")} ·{" "}
                        {s.auto_renew ? t("biz.autoOn") : t("biz.autoOff")}
                      </div>
                    </div>
                    <div className="flex flex-col items-end gap-2 shrink-0">
                      <span className={`px-2 py-0.5 rounded-md text-[10px] ${statusClass(s.status)}`}>
                        {statusLabel(s.status)}
                      </span>
                      {s.status === "active" && (
                        <button
                          onClick={() => cancelSub(s.id)}
                          className="text-[11px] text-surface-400 hover:text-red-400"
                        >
                          {t("biz.cancel")}
                        </button>
                      )}
                    </div>
                  </div>
                </div>
              ))
            )}
          </div>
        )}
      </div>
    </AppShell>
  );
}
