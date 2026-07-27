"use client";

import { useCallback, useEffect, useState } from "react";
import {
  BarChart3, Loader2, Megaphone, Pause, Play, Plus, Square,
} from "lucide-react";
import toast from "react-hot-toast";

import AppShell from "@/components/layout/AppShell";
import { Button } from "@/components/ui/Button";
import { adsApi, getApiErrorMessage } from "@/lib/api";
import { toPersianNum } from "@/lib/utils";
import { useTranslation } from "@/store/i18n";

function fmtToman(rial: number): string {
  return toPersianNum(Math.round((rial || 0) / 10).toLocaleString("en-US"));
}

function fmtNum(n: number): string {
  return toPersianNum((n || 0).toLocaleString("en-US"));
}

interface Campaign {
  id: string;
  title: string;
  body?: string | null;
  image_url?: string | null;
  target_url: string;
  cta?: string | null;
  placement: string;
  bid_cpc: number;
  budget_total: number;
  spent: number;
  escrow_locked: number;
  remaining: number;
  impressions: number;
  clicks: number;
  ctr: number;
  status: string;
  status_label: string;
  review_note?: string | null;
  target_countries: string[];
  target_locales: string[];
  ends_at?: string | null;
  created_at: string;
  can_activate: boolean;
  can_pause: boolean;
  can_edit: boolean;
}

interface StatPoint {
  day: string;
  impressions: number;
  clicks: number;
  spent: number;
}

interface Stats {
  impressions: number;
  clicks: number;
  ctr: number;
  spent: number;
  remaining: number;
  avg_cpc: number;
  series: StatPoint[];
}

const PLACEMENTS = ["feed", "explore", "story", "search"] as const;

const STATUS_STYLE: Record<string, string> = {
  draft: "bg-surface-700 text-surface-400",
  active: "bg-emerald-500/12 text-emerald-400",
  paused: "bg-amber-500/12 text-amber-400",
  completed: "bg-sky-500/12 text-sky-400",
  rejected: "bg-rose-500/12 text-rose-400",
};

// کمینه‌های سرور، به تومان — تا کاربر پیش از ارسال بداند مرز کجاست.
const BID_MIN_TOMAN = 100;
const BUDGET_MIN_TOMAN = 10_000;

export default function AdsPage() {
  const { t } = useTranslation();

  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [campaigns, setCampaigns] = useState<Campaign[]>([]);
  const [openStats, setOpenStats] = useState<string | null>(null);
  const [stats, setStats] = useState<Stats | null>(null);
  const [showForm, setShowForm] = useState(false);

  const [nTitle, setNTitle] = useState("");
  const [nBody, setNBody] = useState("");
  const [nUrl, setNUrl] = useState("");
  const [nCta, setNCta] = useState("");
  const [nPlacement, setNPlacement] = useState<string>("feed");
  const [nBid, setNBid] = useState("");
  const [nBudget, setNBudget] = useState("");
  const [nCountries, setNCountries] = useState("");
  const [creating, setCreating] = useState(false);

  const load = useCallback(async () => {
    try {
      const { data } = await adsApi.campaigns();
      setCampaigns(data || []);
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    }
  }, []);

  useEffect(() => {
    (async () => {
      setLoading(true);
      await load();
      setLoading(false);
    })();
  }, [load]);

  async function create() {
    const title = nTitle.trim();
    const url = nUrl.trim();
    const bid = Number(nBid.replace(/[^\d]/g, ""));
    const budget = Number(nBudget.replace(/[^\d]/g, ""));
    if (title.length < 2) return toast.error(t("ads.errTitle"));
    if (!/^https?:\/\/.+/i.test(url)) return toast.error(t("ads.errUrl"));
    if (!bid || bid < BID_MIN_TOMAN) return toast.error(t("ads.errBid"));
    if (!budget || budget < BUDGET_MIN_TOMAN) return toast.error(t("ads.errBudget"));
    if (budget < bid) return toast.error(t("ads.errBudgetLtBid"));
    const countries = nCountries
      .split(/[,،\s]+/).map((c) => c.trim().toUpperCase()).filter(Boolean);
    setCreating(true);
    try {
      await adsApi.create({
        title,
        target_url: url,
        body: nBody.trim() || null,
        cta: nCta.trim() || null,
        placement: nPlacement,
        bid_cpc: bid * 10,
        budget_total: budget * 10,
        target_countries: countries.length ? countries : null,
      });
      toast.success(t("ads.created"));
      setNTitle(""); setNBody(""); setNUrl(""); setNCta("");
      setNBid(""); setNBudget(""); setNCountries("");
      setShowForm(false);
      await load();
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setCreating(false);
    }
  }

  async function act(c: Campaign, action: "activate" | "pause" | "stop") {
    if (action === "activate" &&
        !confirm(`${t("ads.confirmActivate")}\n${fmtToman(c.remaining)} ${t("ads.toman")}`))
      return;
    if (action === "stop" && !confirm(t("ads.confirmStop"))) return;
    setBusy(c.id);
    try {
      if (action === "activate") await adsApi.activate(c.id);
      else if (action === "pause") await adsApi.pause(c.id);
      else await adsApi.stop(c.id);
      toast.success(t("ads.done"));
      await load();
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setBusy(null);
    }
  }

  async function toggleStats(c: Campaign) {
    if (openStats === c.id) {
      setOpenStats(null);
      setStats(null);
      return;
    }
    setBusy(c.id);
    try {
      const { data } = await adsApi.stats(c.id);
      setStats(data);
      setOpenStats(c.id);
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setBusy(null);
    }
  }

  if (loading) {
    return (
      <AppShell title={t("ads.title")}>
        <div className="page-inner flex justify-center py-20">
          <Loader2 className="w-6 h-6 animate-spin text-surface-400" />
        </div>
      </AppShell>
    );
  }

  const peak = Math.max(1, ...(stats?.series || []).map((p) => p.impressions));

  return (
    <AppShell title={t("ads.title")}>
      <div className="page-inner space-y-4">
        <div className="card p-4 flex items-start gap-3">
          <div className="w-10 h-10 rounded-2xl bg-primary/12 flex items-center justify-center shrink-0">
            <Megaphone className="w-5 h-5 text-primary" />
          </div>
          <div className="flex-1 min-w-0">
            <div className="font-semibold text-surface-50 text-sm">{t("ads.heroTitle")}</div>
            <p className="text-xs text-surface-400 mt-1 leading-5">{t("ads.heroBody")}</p>
          </div>
        </div>

        <Button onClick={() => setShowForm((v) => !v)} className="w-full">
          <Plus className="w-4 h-4" />{t("ads.newCampaign")}
        </Button>

        {showForm && (
          <div className="card p-4 space-y-3">
            <input
              value={nTitle}
              onChange={(e) => setNTitle(e.target.value)}
              placeholder={t("ads.titlePh")}
              className="w-full h-11 px-3 rounded-xl bg-surface-800 text-sm text-surface-100 outline-none"
            />
            <textarea
              value={nBody}
              onChange={(e) => setNBody(e.target.value)}
              rows={2}
              placeholder={t("ads.bodyPh")}
              className="w-full px-3 py-2.5 rounded-xl bg-surface-800 text-sm text-surface-100 outline-none resize-none"
            />
            <input
              value={nUrl}
              onChange={(e) => setNUrl(e.target.value)}
              dir="ltr"
              placeholder="https://example.com"
              className="w-full h-11 px-3 rounded-xl bg-surface-800 text-sm text-surface-100 outline-none"
            />
            <input
              value={nCta}
              onChange={(e) => setNCta(e.target.value)}
              placeholder={t("ads.ctaPh")}
              className="w-full h-11 px-3 rounded-xl bg-surface-800 text-sm text-surface-100 outline-none"
            />
            <select
              value={nPlacement}
              onChange={(e) => setNPlacement(e.target.value)}
              className="w-full h-11 px-3 rounded-xl bg-surface-800 text-sm text-surface-100 outline-none"
            >
              {PLACEMENTS.map((p) => (
                <option key={p} value={p}>{t(`ads.placement.${p}`)}</option>
              ))}
            </select>
            <div className="grid grid-cols-2 gap-2">
              <input
                value={nBid}
                onChange={(e) => setNBid(e.target.value)}
                inputMode="numeric"
                placeholder={t("ads.bidPh")}
                className="h-11 px-3 rounded-xl bg-surface-800 text-sm text-surface-100 outline-none"
              />
              <input
                value={nBudget}
                onChange={(e) => setNBudget(e.target.value)}
                inputMode="numeric"
                placeholder={t("ads.budgetPh")}
                className="h-11 px-3 rounded-xl bg-surface-800 text-sm text-surface-100 outline-none"
              />
            </div>
            <input
              value={nCountries}
              onChange={(e) => setNCountries(e.target.value)}
              dir="ltr"
              placeholder={t("ads.countriesPh")}
              className="w-full h-11 px-3 rounded-xl bg-surface-800 text-sm text-surface-100 outline-none"
            />
            <Button onClick={create} disabled={creating} className="w-full">
              {creating
                ? <Loader2 className="w-4 h-4 animate-spin" />
                : <Plus className="w-4 h-4" />}
              {t("ads.create")}
            </Button>
            <p className="text-[11px] text-surface-500 leading-5">{t("ads.formHint")}</p>
          </div>
        )}

        {campaigns.length === 0 && (
          <div className="card p-8 text-center text-surface-400 text-sm">
            {t("ads.empty")}
          </div>
        )}

        {campaigns.map((c) => (
          <div key={c.id} className="card p-4">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="font-semibold text-surface-50 truncate">{c.title}</span>
              <span className={`px-2 py-0.5 rounded-md text-[10px] ${
                STATUS_STYLE[c.status] || "bg-surface-700 text-surface-400"}`}>
                {c.status_label}
              </span>
              <span className="px-2 py-0.5 rounded-md bg-surface-800 text-surface-300 text-[10px]">
                {t(`ads.placement.${c.placement}`)}
              </span>
            </div>
            {c.body && (
              <p className="text-xs text-surface-300 mt-1.5 leading-5 line-clamp-2">{c.body}</p>
            )}
            <div className="text-xs text-surface-400 mt-1 truncate" dir="ltr">{c.target_url}</div>

            <div className="grid grid-cols-3 gap-2 mt-3">
              {([
                [t("ads.spent"), `${fmtToman(c.spent)}`],
                [t("ads.remaining"), `${fmtToman(c.remaining)}`],
                [t("ads.bid"), `${fmtToman(c.bid_cpc)}`],
                [t("ads.impressions"), fmtNum(c.impressions)],
                [t("ads.clicks"), fmtNum(c.clicks)],
                [t("ads.ctr"), `${toPersianNum(c.ctr)}٪`],
              ] as [string, string][]).map(([k, v]) => (
                <div key={k} className="rounded-xl bg-surface-800 p-2 text-center">
                  <div className="text-[10px] text-surface-500">{k}</div>
                  <div className="text-xs text-surface-100 mt-0.5 font-semibold">{v}</div>
                </div>
              ))}
            </div>

            {c.target_countries.length > 0 && (
              <div className="text-[11px] text-surface-500 mt-2" dir="ltr">
                {c.target_countries.join(" · ")}
              </div>
            )}
            {c.review_note && (
              <div className="text-[11px] text-rose-400 mt-1">
                {t("ads.reviewNote")}: {c.review_note}
              </div>
            )}

            <div className="flex gap-2 mt-3">
              {c.can_activate && (
                <Button size="sm" onClick={() => act(c, "activate")}
                        disabled={busy === c.id} className="flex-1">
                  <Play className="w-3.5 h-3.5" />{t("ads.activate")}
                </Button>
              )}
              {c.can_pause && (
                <Button size="sm" variant="ghost" onClick={() => act(c, "pause")}
                        disabled={busy === c.id} className="flex-1">
                  <Pause className="w-3.5 h-3.5" />{t("ads.pause")}
                </Button>
              )}
              {(c.status === "active" || c.status === "paused") && (
                <Button size="sm" variant="ghost" onClick={() => act(c, "stop")}
                        disabled={busy === c.id} className="flex-1">
                  <Square className="w-3.5 h-3.5" />{t("ads.stop")}
                </Button>
              )}
              <Button size="sm" variant="ghost" onClick={() => toggleStats(c)}
                      disabled={busy === c.id} className="flex-1">
                <BarChart3 className="w-3.5 h-3.5" />{t("ads.stats")}
              </Button>
            </div>

            {openStats === c.id && stats && (
              <div className="mt-3 pt-3 border-t border-surface-700">
                <div className="text-[11px] text-surface-500 mb-2">
                  {t("ads.last14")} · {t("ads.avgCpc")}: {fmtToman(stats.avg_cpc)} {t("ads.toman")}
                </div>
                <div className="flex items-end gap-1 h-20">
                  {stats.series.map((p) => (
                    <div key={p.day} className="flex-1 flex flex-col justify-end"
                         title={`${p.day} — ${fmtNum(p.impressions)}`}>
                      <div
                        className="w-full rounded-t bg-primary/60"
                        style={{ height: `${Math.round((p.impressions / peak) * 100)}%` }}
                      />
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        ))}
      </div>
    </AppShell>
  );
}
