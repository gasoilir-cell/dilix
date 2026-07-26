"use client";

import { useState, useEffect, useCallback } from "react";
import AppShell from "@/components/layout/AppShell";
import {
  Users, Share2, Copy, Check, Loader2, AlertCircle,
  Network, Coins, Gift, UserPlus, TrendingUp, Layers,
} from "lucide-react";
import { Button } from "@/components/ui/Button";
import { toPersianNum } from "@/lib/utils";
import { referralApi, getApiErrorMessage } from "@/lib/api";
import { formatMoney } from "@/lib/currency";
import { useTranslation } from "@/store/i18n";
import toast from "react-hot-toast";

interface StatsResp {
  code: string;
  link: string;
  total_referred: number;
  total_network: number;
  earned: Record<string, number>;
  level_rates_bps: number[];
}
interface LevelRow { level: number; count: number; rate_bps: number; }
interface DirectRow { earth_id: string; name: string; joined_at: string | null; }
interface NetworkResp {
  levels: LevelRow[];
  total_network: number;
  direct: DirectRow[];
}
interface CommissionRow {
  id: string; level: number; amount: number; currency: string;
  rate_bps: number; source_type: string; created_at: string | null;
}
interface CommissionsResp {
  commissions: CommissionRow[];
  totals: Record<string, number>;
}

const pct = (bps: number) => toPersianNum((bps / 100).toLocaleString("en-US"));

function fmtDate(iso: string | null): string {
  if (!iso) return "—";
  try {
    return toPersianNum(new Date(iso).toLocaleDateString("fa-IR"));
  } catch {
    return "—";
  }
}

export default function ReferralPage() {
  const { t } = useTranslation();
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState<StatsResp | null>(null);
  const [net, setNet] = useState<NetworkResp | null>(null);
  const [comm, setComm] = useState<CommissionsResp | null>(null);
  const [copied, setCopied] = useState(false);
  const [refCode, setRefCode] = useState("");
  const [applying, setApplying] = useState(false);

  const load = useCallback(async () => {
    try {
      const [s, n, c] = await Promise.all([
        referralApi.stats(),
        referralApi.network(),
        referralApi.commissions(),
      ]);
      setStats(s.data);
      setNet(n.data);
      setComm(c.data);
    } catch {
      toast.error(t("ref.loadError"));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const copyLink = async () => {
    if (!stats?.link) return;
    try {
      await navigator.clipboard.writeText(stats.link);
      setCopied(true);
      toast.success(t("ref.copiedToast"));
      setTimeout(() => setCopied(false), 2000);
    } catch {
      toast.error(t("ref.copyFail"));
    }
  };

  const shareLink = async () => {
    if (!stats?.link) return;
    const data = {
      title: t("ref.shareTitle"),
      text: t("ref.shareText"),
      url: stats.link,
    };
    if (navigator.share) {
      try { await navigator.share(data); } catch { /* لغو کاربر */ }
    } else {
      copyLink();
    }
  };

  const applyRef = async () => {
    const code = refCode.trim().toUpperCase();
    if (!code.startsWith("DLX-")) {
      toast.error(t("ref.invalidCode"));
      return;
    }
    setApplying(true);
    try {
      await referralApi.apply(code);
      toast.success(t("ref.applied"));
      setRefCode("");
      await load();
    } catch (e) {
      toast.error(getApiErrorMessage(e, t("ref.applyFail")));
    } finally {
      setApplying(false);
    }
  };

  if (loading) {
    return (
      <AppShell title={t("ref.title")}>
        <div className="flex items-center justify-center h-48">
          <Loader2 size={32} className="text-primary-400 animate-spin" />
        </div>
      </AppShell>
    );
  }

  if (!stats) {
    return (
      <AppShell title={t("ref.title")}>
        <div className="page-inner flex flex-col items-center justify-center h-48 gap-3">
          <AlertCircle size={40} className="text-red-400" />
          <p className="text-surface-400">{t("ref.unavailable")}</p>
        </div>
      </AppShell>
    );
  }

  const earnedEntries = Object.entries(stats.earned || {});
  const rates = stats.level_rates_bps || [];

  return (
    <AppShell title={t("ref.title")}>
      <div className="page-inner space-y-4">
        {/* کارت کد دعوت */}
        <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-indigo-600 to-purple-700 p-5 text-white">
          <div className="flex items-center gap-2 mb-3 opacity-90">
            <Gift size={18} />
            <span className="text-sm">{t("ref.yourCode")}</span>
          </div>
          <div className="text-2xl font-bold tracking-wider mb-4 ltr text-left">
            {stats.code}
          </div>
          <div className="flex gap-2">
            <Button
              onClick={copyLink}
              className="flex-1 bg-white/15 hover:bg-white/25 border-0 gap-2"
            >
              {copied ? <Check size={16} /> : <Copy size={16} />}
              {copied ? t("ref.copied") : t("ref.copyLink")}
            </Button>
            <Button
              onClick={shareLink}
              className="flex-1 bg-white/15 hover:bg-white/25 border-0 gap-2"
            >
              <Share2 size={16} />
              {t("ref.share")}
            </Button>
          </div>
        </div>

        {/* آمار سریع */}
        <div className="grid grid-cols-2 gap-3">
          <div className="rounded-2xl bg-surface-800/60 border border-surface-700 p-4">
            <div className="flex items-center gap-2 text-surface-400 text-xs mb-1">
              <UserPlus size={14} /> {t("ref.directSubs")}
            </div>
            <div className="text-xl font-bold text-white">
              {toPersianNum(stats.total_referred.toLocaleString("en-US"))}
            </div>
          </div>
          <div className="rounded-2xl bg-surface-800/60 border border-surface-700 p-4">
            <div className="flex items-center gap-2 text-surface-400 text-xs mb-1">
              <Network size={14} /> {t("ref.totalNetwork")}
            </div>
            <div className="text-xl font-bold text-white">
              {toPersianNum(stats.total_network.toLocaleString("en-US"))}
            </div>
          </div>
        </div>

        {/* درآمد کسب‌شده */}
        <div className="rounded-2xl bg-surface-800/60 border border-surface-700 p-4">
          <div className="flex items-center gap-2 text-surface-300 text-sm mb-3">
            <TrendingUp size={16} className="text-emerald-400" /> {t("ref.income")}
          </div>
          {earnedEntries.length === 0 ? (
            <p className="text-surface-500 text-sm">{t("ref.noIncome")}</p>
          ) : (
            <div className="flex flex-wrap gap-2">
              {earnedEntries.map(([cur, amt]) => (
                <div
                  key={cur}
                  className="px-3 py-2 rounded-xl bg-emerald-500/10 border border-emerald-500/30"
                >
                  <span className="text-emerald-300 font-bold">
                    {formatMoney(amt, cur, "fa")}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* سطوح شبکه + نرخ کمیسیون */}
        <div className="rounded-2xl bg-surface-800/60 border border-surface-700 p-4">
          <div className="flex items-center gap-2 text-surface-300 text-sm mb-3">
            <Layers size={16} className="text-indigo-400" /> {t("ref.levelsTitle")}
          </div>
          <div className="space-y-2">
            {(net?.levels || []).map((lv) => (
              <div
                key={lv.level}
                className="flex items-center justify-between rounded-xl bg-surface-900/50 px-3 py-2"
              >
                <div className="flex items-center gap-2">
                  <span className="w-7 h-7 flex items-center justify-center rounded-full bg-indigo-500/20 text-indigo-300 text-xs font-bold">
                    {toPersianNum(String(lv.level))}
                  </span>
                  <span className="text-surface-300 text-sm">{t("ref.level")} {toPersianNum(String(lv.level))}</span>
                </div>
                <div className="flex items-center gap-3">
                  <span className="text-xs text-amber-300">
                    {pct(lv.rate_bps)}٪
                  </span>
                  <span className="text-sm text-white font-medium">
                    {toPersianNum(lv.count.toLocaleString("en-US"))} {t("ref.people")}
                  </span>
                </div>
              </div>
            ))}
          </div>
          {rates.length > 0 && (
            <p className="text-[11px] text-surface-500 mt-3">
              {t("ref.commissionNote")}
            </p>
          )}
        </div>

        {/* زیرمجموعهٔ مستقیم */}
        <div className="rounded-2xl bg-surface-800/60 border border-surface-700 p-4">
          <div className="flex items-center gap-2 text-surface-300 text-sm mb-3">
            <Users size={16} className="text-primary-400" /> {t("ref.directSubs")}
          </div>
          {(net?.direct || []).length === 0 ? (
            <p className="text-surface-500 text-sm">{t("ref.noInvites")}</p>
          ) : (
            <div className="space-y-2">
              {net!.direct.map((d) => (
                <div
                  key={d.earth_id}
                  className="flex items-center justify-between rounded-xl bg-surface-900/50 px-3 py-2"
                >
                  <div>
                    <div className="text-sm text-white">{d.name}</div>
                    <div className="text-[11px] text-surface-500 ltr text-left">{d.earth_id}</div>
                  </div>
                  <span className="text-[11px] text-surface-500">{fmtDate(d.joined_at)}</span>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* لِجِر کمیسیون */}
        <div className="rounded-2xl bg-surface-800/60 border border-surface-700 p-4">
          <div className="flex items-center gap-2 text-surface-300 text-sm mb-3">
            <Coins size={16} className="text-amber-400" /> {t("ref.commissionHistory")}
          </div>
          {(comm?.commissions || []).length === 0 ? (
            <p className="text-surface-500 text-sm">{t("ref.noCommission")}</p>
          ) : (
            <div className="space-y-2">
              {comm!.commissions.map((r) => (
                <div
                  key={r.id}
                  className="flex items-center justify-between rounded-xl bg-surface-900/50 px-3 py-2"
                >
                  <div className="flex items-center gap-2">
                    <span className="w-6 h-6 flex items-center justify-center rounded-full bg-amber-500/20 text-amber-300 text-[11px] font-bold">
                      {toPersianNum(String(r.level))}
                    </span>
                    <div>
                      <div className="text-xs text-surface-300">{t("ref.level")} {toPersianNum(String(r.level))} · {pct(r.rate_bps)}٪</div>
                      <div className="text-[11px] text-surface-500">{fmtDate(r.created_at)}</div>
                    </div>
                  </div>
                  <span className="text-sm font-bold text-emerald-300">
                    +{formatMoney(r.amount, r.currency, "fa")}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* ثبت معرف */}
        {stats.total_referred === 0 && (
          <div className="rounded-2xl bg-surface-800/60 border border-surface-700 p-4">
            <div className="flex items-center gap-2 text-surface-300 text-sm mb-3">
              <UserPlus size={16} className="text-primary-400" /> {t("ref.haveCode")}
            </div>
            <p className="text-[12px] text-surface-500 mb-3">
              {t("ref.haveCodeHint")}
            </p>
            <div className="flex gap-2">
              <input
                value={refCode}
                onChange={(e) => setRefCode(e.target.value)}
                placeholder="DLX-XXXXXXXX"
                className="flex-1 rounded-xl bg-surface-900 border border-surface-700 px-3 py-2 text-white text-sm ltr text-left outline-none focus:border-primary-500"
              />
              <Button onClick={applyRef} disabled={applying} className="gap-2">
                {applying ? <Loader2 size={16} className="animate-spin" /> : <Check size={16} />}
                {t("ref.submit")}
              </Button>
            </div>
          </div>
        )}
      </div>
    </AppShell>
  );
}
