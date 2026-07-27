"use client";

import { useCallback, useEffect, useState } from "react";
import {
  Award, CalendarCheck, Crown, Flame, History, Loader2, RefreshCw,
  Sparkles, Trophy,
} from "lucide-react";
import toast from "react-hot-toast";

import AppShell from "@/components/layout/AppShell";
import { Button } from "@/components/ui/Button";
import { gamificationApi, getApiErrorMessage } from "@/lib/api";
import { toPersianNum } from "@/lib/utils";
import { useTranslation } from "@/store/i18n";

const num = (n: number) => toPersianNum((n || 0).toLocaleString("en-US"));

function fmtDate(iso: string | null): string {
  if (!iso) return "—";
  try {
    return toPersianNum(new Date(iso).toLocaleDateString("fa-IR"));
  } catch {
    return "—";
  }
}

interface Badge {
  code: string;
  title: string;
  description: string;
  points: number;
  earned: boolean;
  progress: number;
  target: number;
  awarded_at: string | null;
}

interface Level {
  level: number;
  title: string;
  points: number;
  next_at: number | null;
  to_next: number;
  progress_pct: number;
}

interface Profile {
  points: number;
  level: Level;
  streak_days: number;
  longest_streak: number;
  checked_in_today: boolean;
  badges_earned: number;
  badges_total: number;
  rank: number | null;
  badges: Badge[];
}

interface PointEvent {
  id: string;
  kind: string;
  kind_label: string;
  ref: string;
  delta: number;
  note: string | null;
  created_at: string;
}

interface LeaderRow {
  rank: number;
  earth_id: string;
  name: string;
  avatar_url: string | null;
  points: number;
  level: number;
  is_me: boolean;
}

interface Leaderboard {
  period: string;
  rows: LeaderRow[];
  my_rank: number | null;
  my_points: number;
}

type Tab = "badges" | "board" | "history";

export default function RewardsPage() {
  const { t } = useTranslation();

  const [loading, setLoading] = useState(true);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [tab, setTab] = useState<Tab>("badges");
  const [board, setBoard] = useState<Leaderboard | null>(null);
  const [period, setPeriod] = useState<"all" | "week">("all");
  const [history, setHistory] = useState<PointEvent[]>([]);
  const [checking, setChecking] = useState(false);
  const [syncing, setSyncing] = useState(false);

  const loadProfile = useCallback(async () => {
    const { data } = await gamificationApi.me();
    setProfile(data);
  }, []);

  useEffect(() => {
    (async () => {
      try {
        await loadProfile();
      } catch (e) {
        toast.error(getApiErrorMessage(e));
      } finally {
        setLoading(false);
      }
    })();
  }, [loadProfile]);

  // تابلوی رتبه و تاریخچه فقط وقتی دیده می‌شوند بار می‌شوند.
  useEffect(() => {
    if (tab !== "board") return;
    (async () => {
      try {
        const { data } = await gamificationApi.leaderboard(period);
        setBoard(data);
      } catch (e) {
        toast.error(getApiErrorMessage(e));
      }
    })();
  }, [tab, period]);

  useEffect(() => {
    if (tab !== "history") return;
    (async () => {
      try {
        const { data } = await gamificationApi.history(60);
        setHistory(data || []);
      } catch (e) {
        toast.error(getApiErrorMessage(e));
      }
    })();
  }, [tab]);

  async function checkIn() {
    setChecking(true);
    try {
      const { data } = await gamificationApi.checkIn();
      if (data.already) toast(t("rw.alreadyIn"));
      else toast.success(`${t("rw.gained")} +${num(data.gained)}`);
      await loadProfile();
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setChecking(false);
    }
  }

  async function sync() {
    setSyncing(true);
    try {
      const { data } = await gamificationApi.sync();
      if (!data.awarded?.length) toast(t("rw.noNewBadge"));
      else toast.success(`${t("rw.newBadges")} ${num(data.awarded.length)} · +${num(data.gained)}`);
      await loadProfile();
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setSyncing(false);
    }
  }

  if (loading) {
    return (
      <AppShell title={t("rw.title")}>
        <div className="flex items-center justify-center h-48">
          <Loader2 size={32} className="text-primary-400 animate-spin" />
        </div>
      </AppShell>
    );
  }

  if (!profile) {
    return (
      <AppShell title={t("rw.title")}>
        <div className="page-inner text-center py-16 text-surface-400">{t("rw.unavailable")}</div>
      </AppShell>
    );
  }

  const lv = profile.level;

  return (
    <AppShell title={t("rw.title")}>
      <div className="page-inner space-y-4">

        {/* کارتِ سطح */}
        <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-amber-500 to-orange-600 p-5 text-white">
          <div className="flex items-start justify-between mb-3">
            <div>
              <div className="flex items-center gap-2 opacity-90 text-sm mb-1">
                <Sparkles size={16} />
                {t("rw.level")} {toPersianNum(String(lv.level))} · {lv.title}
              </div>
              <div className="text-3xl font-bold">{num(profile.points)}</div>
              <div className="text-xs opacity-80 mt-0.5">{t("rw.points")}</div>
            </div>
            {profile.rank !== null && (
              <div className="flex items-center gap-1.5 rounded-full bg-white/15 px-3 py-1.5 text-sm">
                <Trophy size={14} />
                {t("rw.rank")} {toPersianNum(String(profile.rank))}
              </div>
            )}
          </div>

          <div className="h-2 rounded-full bg-white/20 overflow-hidden">
            <div className="h-full bg-white/90" style={{ width: `${lv.progress_pct}%` }} />
          </div>
          <p className="text-[11px] opacity-85 mt-1.5">
            {lv.next_at === null
              ? t("rw.maxLevel")
              : `${t("rw.toNext")} ${num(lv.to_next)} ${t("rw.points")}`}
          </p>

          <div className="grid grid-cols-3 gap-2 mt-4">
            <div className="rounded-xl bg-white/12 px-3 py-2">
              <div className="flex items-center gap-1 text-[11px] opacity-85"><Flame size={12} /> {t("rw.streak")}</div>
              <div className="font-bold">{num(profile.streak_days)}</div>
            </div>
            <div className="rounded-xl bg-white/12 px-3 py-2">
              <div className="flex items-center gap-1 text-[11px] opacity-85"><Crown size={12} /> {t("rw.best")}</div>
              <div className="font-bold">{num(profile.longest_streak)}</div>
            </div>
            <div className="rounded-xl bg-white/12 px-3 py-2">
              <div className="flex items-center gap-1 text-[11px] opacity-85"><Award size={12} /> {t("rw.badges")}</div>
              <div className="font-bold">
                {num(profile.badges_earned)}<span className="opacity-70 text-xs">/{num(profile.badges_total)}</span>
              </div>
            </div>
          </div>

          <div className="flex gap-2 mt-4">
            <Button
              onClick={checkIn}
              disabled={checking || profile.checked_in_today}
              className="flex-1 bg-white/15 hover:bg-white/25 border-0 gap-2 disabled:opacity-60"
            >
              {checking ? <Loader2 size={16} className="animate-spin" /> : <CalendarCheck size={16} />}
              {profile.checked_in_today ? t("rw.checkedIn") : t("rw.checkIn")}
            </Button>
            <Button
              onClick={sync}
              disabled={syncing}
              className="bg-white/15 hover:bg-white/25 border-0 gap-2"
            >
              {syncing ? <Loader2 size={16} className="animate-spin" /> : <RefreshCw size={16} />}
              {t("rw.claim")}
            </Button>
          </div>
        </div>

        {/* تب‌ها */}
        <div className="flex gap-2">
          {([
            ["badges", t("rw.tabBadges"), Award],
            ["board", t("rw.tabBoard"), Trophy],
            ["history", t("rw.tabHistory"), History],
          ] as [Tab, string, React.ElementType][]).map(([id, label, Icon]) => (
            <button
              key={id}
              onClick={() => setTab(id)}
              className={`flex-1 flex items-center justify-center gap-1.5 rounded-xl px-3 py-2 text-sm transition-colors ${
                tab === id
                  ? "bg-primary-600 text-white"
                  : "bg-surface-800/60 border border-surface-700 text-surface-300"
              }`}
            >
              <Icon size={14} /> {label}
            </button>
          ))}
        </div>

        {/* نشان‌ها */}
        {tab === "badges" && (
          <div className="grid grid-cols-2 gap-2.5">
            {profile.badges.map((b) => {
              const pct = b.target > 0 ? Math.min(100, Math.round((b.progress / b.target) * 100)) : 0;
              return (
                <div
                  key={b.code}
                  className={`rounded-2xl border p-3.5 ${
                    b.earned
                      ? "bg-amber-500/10 border-amber-500/30"
                      : "bg-surface-800/60 border-surface-700"
                  }`}
                >
                  <div className="flex items-start justify-between mb-1.5">
                    <Award size={20} className={b.earned ? "text-amber-400" : "text-surface-500"} />
                    <span className={`text-[11px] font-bold ${b.earned ? "text-amber-300" : "text-surface-500"}`}>
                      +{num(b.points)}
                    </span>
                  </div>
                  <p className={`text-sm font-semibold ${b.earned ? "text-white" : "text-surface-300"}`}>
                    {b.title}
                  </p>
                  <p className="text-[11px] text-surface-500 mt-0.5 leading-relaxed">{b.description}</p>
                  {b.earned ? (
                    <p className="text-[10px] text-amber-400/80 mt-2">{fmtDate(b.awarded_at)}</p>
                  ) : (
                    <>
                      <div className="h-1.5 rounded-full bg-surface-900 mt-2.5 overflow-hidden">
                        <div className="h-full bg-primary-500" style={{ width: `${pct}%` }} />
                      </div>
                      <p className="text-[10px] text-surface-500 mt-1">
                        {num(b.progress)} / {num(b.target)}
                      </p>
                    </>
                  )}
                </div>
              );
            })}
          </div>
        )}

        {/* تابلوی رتبه */}
        {tab === "board" && (
          <div className="space-y-3">
            <div className="flex gap-2">
              {(["all", "week"] as const).map((p) => (
                <button
                  key={p}
                  onClick={() => setPeriod(p)}
                  className={`rounded-full px-3 py-1.5 text-xs transition-colors ${
                    period === p
                      ? "bg-primary-600 text-white"
                      : "bg-surface-800/60 border border-surface-700 text-surface-400"
                  }`}
                >
                  {p === "all" ? t("rw.allTime") : t("rw.thisWeek")}
                </button>
              ))}
            </div>

            {board === null ? (
              <div className="flex justify-center py-8">
                <Loader2 size={24} className="text-primary-400 animate-spin" />
              </div>
            ) : board.rows.length === 0 ? (
              <p className="text-surface-500 text-sm text-center py-8">{t("rw.boardEmpty")}</p>
            ) : (
              <div className="space-y-2">
                {board.rows.map((r) => (
                  <div
                    key={r.earth_id}
                    className={`flex items-center gap-3 rounded-2xl px-3 py-2.5 border ${
                      r.is_me
                        ? "bg-primary-600/10 border-primary-500/40"
                        : "bg-surface-800/60 border-surface-700"
                    }`}
                  >
                    <span className={`w-7 h-7 flex items-center justify-center rounded-full text-xs font-bold ${
                      r.rank === 1 ? "bg-amber-500/20 text-amber-300" :
                      r.rank === 2 ? "bg-surface-400/20 text-surface-200" :
                      r.rank === 3 ? "bg-orange-700/25 text-orange-300" :
                      "bg-surface-900 text-surface-400"
                    }`}>
                      {toPersianNum(String(r.rank))}
                    </span>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm text-white truncate">{r.name}</p>
                      <p className="text-[11px] text-surface-500">
                        {t("rw.level")} {toPersianNum(String(r.level))}
                      </p>
                    </div>
                    <span className="text-sm font-bold text-amber-300">{num(r.points)}</span>
                  </div>
                ))}
                {board.my_rank !== null && (
                  <p className="text-[11px] text-surface-500 text-center pt-1">
                    {t("rw.yourRank")} {toPersianNum(String(board.my_rank))} · {num(board.my_points)} {t("rw.points")}
                  </p>
                )}
              </div>
            )}
          </div>
        )}

        {/* تاریخچه */}
        {tab === "history" && (
          <div className="space-y-2">
            {history.length === 0 ? (
              <p className="text-surface-500 text-sm text-center py-8">{t("rw.historyEmpty")}</p>
            ) : (
              history.map((h) => (
                <div
                  key={h.id}
                  className="flex items-center justify-between rounded-2xl bg-surface-800/60 border border-surface-700 px-3 py-2.5"
                >
                  <div className="min-w-0">
                    <p className="text-sm text-white truncate">{h.note || h.kind_label}</p>
                    <p className="text-[11px] text-surface-500">
                      {h.kind_label} · {fmtDate(h.created_at)}
                    </p>
                  </div>
                  <span className="text-sm font-bold text-emerald-300 shrink-0">+{num(h.delta)}</span>
                </div>
              ))
            )}
          </div>
        )}
      </div>
    </AppShell>
  );
}
