"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Search, X, Loader2, UserPlus, UserCheck, BadgeCheck, Sparkles, Rss, Compass, Users, Flame, Hash } from "lucide-react";
import { socialApi, postsApi, getApiErrorMessage } from "@/lib/api";
import AppShell from "@/components/layout/AppShell";
import PostFeed from "@/components/feed/PostFeed";
import LiveBar from "@/components/live/LiveBar";
import { useTranslation } from "@/store/i18n";
import toast from "react-hot-toast";

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
  driver: "role.driver", cargo_owner: "role.cargo_owner", freight_broker: "role.freight_broker",
  insurance_agent: "role.insurance_agent", creator: "role.creator",
  admin: "role.admin", super_admin: "role.super_admin",
};

type Tab = "feed" | "explore" | "people";
const TABS: { key: Tab; label: string; icon: typeof Rss }[] = [
  { key: "feed", label: "disc.tab.feed", icon: Rss },
  { key: "explore", label: "disc.tab.explore", icon: Compass },
  { key: "people", label: "disc.tab.people", icon: Users },
];

export default function DiscoverPage() {
  const router = useRouter();
  const { t: tr } = useTranslation();
  const [tab, setTab] = useState<Tab>("feed");
  const [q, setQ] = useState("");
  const [contentQ, setContentQ] = useState("");
  const [contentTerm, setContentTerm] = useState("");
  const [results, setResults] = useState<UserMini[]>([]);
  const [suggestions, setSuggestions] = useState<UserMini[]>([]);
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState<Record<string, boolean>>({});
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // کاوش بر پایهٔ علاقه
  const [exploreView, setExploreView] = useState<"all" | "interests" | "topic">("all");
  const [activeTopic, setActiveTopic] = useState("");
  const [topics, setTopics] = useState<{ tag: string; post_count: number }[]>([]);
  const topicsLoadedRef = useRef(false);

  useEffect(() => {
    if (tab !== "explore" || topicsLoadedRef.current) return;
    topicsLoadedRef.current = true;
    postsApi.topics().then((r) => setTopics(r.data?.items ?? [])).catch(() => {});
  }, [tab]);

  const loadSuggestions = useCallback(async () => {
    try {
      const res = await socialApi.suggestions();
      setSuggestions(res.data ?? []);
    } catch {
      setSuggestions([]);
    }
  }, []);

  useEffect(() => { loadSuggestions(); }, [loadSuggestions]);

  // جستجوی debounce‌شده
  useEffect(() => {
    if (debounceRef.current) clearTimeout(debounceRef.current);
    const term = q.trim();
    if (!term) {
      setResults([]);
      setLoading(false);
      return;
    }
    setLoading(true);
    debounceRef.current = setTimeout(async () => {
      try {
        const res = await socialApi.search(term);
        setResults(res.data ?? []);
      } catch {
        setResults([]);
      } finally {
        setLoading(false);
      }
    }, 350);
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
  }, [q]);

  // جستجوی محتوا (کاوش) — debounce
  useEffect(() => {
    const id = setTimeout(() => setContentTerm(contentQ.trim()), 350);
    return () => clearTimeout(id);
  }, [contentQ]);

  const toggleFollow = async (u: UserMini) => {
    if (busy[u.earth_id]) return;
    setBusy((b) => ({ ...b, [u.earth_id]: true }));
    const next = !u.is_following;
    const patch = (list: UserMini[]) =>
      list.map((x) => (x.earth_id === u.earth_id ? { ...x, is_following: next } : x));
    setResults(patch);
    setSuggestions(patch);
    try {
      if (next) await socialApi.follow(u.earth_id);
      else await socialApi.unfollow(u.earth_id);
    } catch (e) {
      const revert = (list: UserMini[]) =>
        list.map((x) => (x.earth_id === u.earth_id ? { ...x, is_following: !next } : x));
      setResults(revert);
      setSuggestions(revert);
      toast.error(getApiErrorMessage(e, tr("disc.actionError")));
    } finally {
      setBusy((b) => ({ ...b, [u.earth_id]: false }));
    }
  };

  const Row = ({ u }: { u: UserMini }) => (
    <div className="flex items-center gap-3 py-2.5">
      <button
        onClick={() => router.push(`/u/${u.earth_id}`)}
        className="flex items-center gap-3 flex-1 min-w-0 text-right"
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
          <div className="text-xs text-surface-500 truncate">
            {u.username ? `@${u.username}` : u.earth_id}
            {u.role && ROLE_LABEL[u.role] ? ` · ${tr(ROLE_LABEL[u.role])}` : ""}
          </div>
        </div>
      </button>
      <button
        onClick={() => toggleFollow(u)}
        disabled={busy[u.earth_id]}
        className={`shrink-0 flex items-center gap-1 text-xs font-bold px-3 h-8 rounded-lg transition-colors ${
          u.is_following
            ? "bg-transparent border border-surface-700 text-surface-300"
            : "bg-primary text-white"
        }`}
      >
        {busy[u.earth_id] ? (
          <Loader2 className="w-3.5 h-3.5 animate-spin" />
        ) : u.is_following ? (
          <><UserCheck className="w-3.5 h-3.5" /> {tr("disc.following")}</>
        ) : (
          <><UserPlus className="w-3.5 h-3.5" /> {tr("disc.follow")}</>
        )}
      </button>
    </div>
  );

  const term = q.trim();

  return (
    <AppShell title={tr("disc.title")}>
      {/* نوارِ تب‌ها */}
      <div className="sticky top-14 z-30 flex border-b border-white/10 bg-[#0A0A0A]/95 backdrop-blur">
        {TABS.map((t) => {
          const Icon = t.icon;
          const active = tab === t.key;
          return (
            <button
              key={t.key}
              onClick={() => setTab(t.key)}
              className={`relative flex-1 flex items-center justify-center gap-1.5 py-3 text-sm font-medium transition-colors ${
                active ? "text-white" : "text-white/45"
              }`}
            >
              <Icon size={17} />
              {tr(t.label)}
              {active && <span className="absolute bottom-0 h-0.5 w-16 rounded-full bg-indigo-500" style={{ transform: "translateY(1px)" }} />}
            </button>
          );
        })}
      </div>

      <div className="pt-3 pb-24">
        {tab === "feed" && <><LiveBar /><PostFeed mode="feed" /></>}
        {tab === "explore" && (
          <>
            <div className="px-3 mb-2">
              <div className="relative">
                <Search className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-surface-500" />
                <input
                  value={contentQ}
                  onChange={(e) => setContentQ(e.target.value)}
                  placeholder={tr("disc.searchPosts")}
                  className="w-full h-11 pr-9 pl-9 rounded-xl bg-surface-900 border border-surface-800 text-sm text-white placeholder:text-surface-500 focus:outline-none focus:border-primary/60"
                />
                {contentQ && (
                  <button
                    onClick={() => setContentQ("")}
                    className="absolute left-3 top-1/2 -translate-y-1/2 text-surface-500 hover:text-white"
                  >
                    <X className="w-4 h-4" />
                  </button>
                )}
              </div>
            </div>

            {/* نوارِ موضوع‌ها / برای تو (وقتی جستجو خالی است) */}
            {!contentTerm && (
              <div className="flex gap-2 overflow-x-auto px-3 pb-3 no-scrollbar">
                <button
                  onClick={() => { setExploreView("interests"); setActiveTopic(""); }}
                  className={`shrink-0 flex items-center gap-1.5 h-8 px-3 rounded-full text-xs font-medium transition-colors ${
                    exploreView === "interests" ? "bg-indigo-500 text-white" : "bg-surface-800 text-white/70"
                  }`}
                >
                  <Sparkles size={14} /> {tr("disc.forYou")}
                </button>
                <button
                  onClick={() => { setExploreView("all"); setActiveTopic(""); }}
                  className={`shrink-0 flex items-center gap-1.5 h-8 px-3 rounded-full text-xs font-medium transition-colors ${
                    exploreView === "all" ? "bg-indigo-500 text-white" : "bg-surface-800 text-white/70"
                  }`}
                >
                  <Flame size={14} /> {tr("disc.all")}
                </button>
                {topics.map((t) => (
                  <button
                    key={t.tag}
                    onClick={() => { setActiveTopic(t.tag); setExploreView("topic"); }}
                    className={`shrink-0 flex items-center gap-1 h-8 px-3 rounded-full text-xs font-medium transition-colors ${
                      exploreView === "topic" && activeTopic === t.tag ? "bg-indigo-500 text-white" : "bg-surface-800 text-white/70"
                    }`}
                  >
                    <Hash size={13} />{t.tag}
                  </button>
                ))}
              </div>
            )}

            {contentTerm ? (
              <PostFeed mode="explore" query={contentTerm} />
            ) : exploreView === "interests" ? (
              <PostFeed mode="interests" />
            ) : exploreView === "topic" && activeTopic ? (
              <PostFeed mode="topic" topic={activeTopic} />
            ) : (
              <PostFeed mode="explore" />
            )}
          </>
        )}
        {tab === "people" && (
          <div className="px-4">
            {/* Search box */}
            <div className="relative mb-3">
              <Search className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-surface-500" />
              <input
                value={q}
                onChange={(e) => setQ(e.target.value)}
                placeholder={tr("disc.searchPeople")}
                className="w-full h-11 pr-9 pl-9 rounded-xl bg-surface-900 border border-surface-800 text-sm text-white placeholder:text-surface-500 focus:outline-none focus:border-primary/60"
              />
              {q && (
                <button
                  onClick={() => setQ("")}
                  className="absolute left-3 top-1/2 -translate-y-1/2 text-surface-500 hover:text-white"
                >
                  <X className="w-4 h-4" />
                </button>
              )}
            </div>

            {term ? (
              loading ? (
                <div className="flex items-center justify-center py-10">
                  <Loader2 className="w-5 h-5 animate-spin text-primary" />
                </div>
              ) : results.length === 0 ? (
                <div className="text-center py-12 text-surface-500 text-sm">
                  {tr("disc.noResultFor")} «{term}»
                </div>
              ) : (
                <div className="divide-y divide-surface-800/60">
                  {results.map((u) => <Row key={u.earth_id} u={u} />)}
                </div>
              )
            ) : (
              <>
                <div className="flex items-center gap-1.5 mb-1 text-surface-300">
                  <Sparkles className="w-4 h-4 text-primary" />
                  <span className="text-sm font-semibold">{tr("disc.suggested")}</span>
                </div>
                {suggestions.length === 0 ? (
                  <div className="text-center py-12 text-surface-500 text-sm">
                    {tr("disc.noSuggestions")}
                  </div>
                ) : (
                  <div className="divide-y divide-surface-800/60">
                    {suggestions.map((u) => <Row key={u.earth_id} u={u} />)}
                  </div>
                )}
              </>
            )}
          </div>
        )}
      </div>
    </AppShell>
  );
}
