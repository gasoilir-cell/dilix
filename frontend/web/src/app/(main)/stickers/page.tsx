"use client";

import { useCallback, useEffect, useState } from "react";
import {
  Check, Coins, Download, ImageIcon, Loader2, Plus, Search,
  ShoppingBag, Sticker, Store, Trash2, Wallet,
} from "lucide-react";
import toast from "react-hot-toast";

import AppShell from "@/components/layout/AppShell";
import { Button } from "@/components/ui/Button";
import { stickersApi, getApiErrorMessage } from "@/lib/api";
import { toPersianNum } from "@/lib/utils";
import { useTranslation } from "@/store/i18n";

// قیمت‌ها در سرور ریال‌اند؛ کاربر تومان می‌بیند و تومان وارد می‌کند.
const PRICE_MIN_TOMAN = 1_000;

const num = (n: number) => toPersianNum((n || 0).toLocaleString("en-US"));
const toman = (rial: number) => num(Math.round((rial || 0) / 10));

function fmtDate(iso: string | null): string {
  if (!iso) return "—";
  try {
    return toPersianNum(new Date(iso).toLocaleDateString("fa-IR"));
  } catch {
    return "—";
  }
}

interface Pack {
  id: string;
  title: string;
  description: string | null;
  cover_url: string | null;
  is_public: boolean;
  is_animated: boolean;
  is_mine: boolean;
  is_installed: boolean;
  install_count: number;
  sticker_count: number;
  owner_name: string | null;
  price: number;
  is_paid: boolean;
  is_purchased: boolean;
  can_install: boolean;
  sales_count: number;
  created_at: string;
}

interface Purchase {
  id: string;
  pack_id: string;
  pack_title: string;
  cover_url: string | null;
  price: number;
  fee: number;
  created_at: string;
}

interface Sales {
  sales_count: number;
  revenue_total: number;
  packs: Pack[];
}

type Tab = "market" | "mine" | "bought" | "sales";

function PackCover({ pack }: { pack: Pack }) {
  if (pack.cover_url) {
    return (
      // eslint-disable-next-line @next/next/no-img-element
      <img
        src={pack.cover_url}
        alt={pack.title}
        className="w-14 h-14 rounded-xl object-cover bg-surface-900 shrink-0"
      />
    );
  }
  return (
    <div className="w-14 h-14 rounded-xl bg-surface-900 border border-surface-700 flex items-center justify-center shrink-0">
      <ImageIcon size={20} className="text-surface-600" />
    </div>
  );
}

export default function StickersPage() {
  const { t } = useTranslation();

  const [tab, setTab] = useState<Tab>("market");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);

  const [market, setMarket] = useState<Pack[]>([]);
  const [q, setQ] = useState("");
  const [kind, setKind] = useState<"all" | "paid" | "free">("all");

  const [mine, setMine] = useState<Pack[]>([]);
  const [bought, setBought] = useState<Purchase[]>([]);
  const [sales, setSales] = useState<Sales | null>(null);

  const [showForm, setShowForm] = useState(false);
  const [nTitle, setNTitle] = useState("");
  const [nDesc, setNDesc] = useState("");
  const [nPublic, setNPublic] = useState(true);
  const [nPrice, setNPrice] = useState("");
  const [creating, setCreating] = useState(false);

  const loadMarket = useCallback(async () => {
    const { data } = await stickersApi.market({ q: q.trim() || undefined, kind });
    setMarket(data || []);
  }, [q, kind]);

  const loadTab = useCallback(async (which: Tab) => {
    setLoading(true);
    try {
      if (which === "market") await loadMarket();
      else if (which === "mine") setMine((await stickersApi.myPacks()).data || []);
      else if (which === "bought") setBought((await stickersApi.purchases()).data || []);
      else setSales((await stickersApi.sales()).data);
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setLoading(false);
    }
  }, [loadMarket]);

  useEffect(() => {
    loadTab(tab);
  }, [tab, loadTab]);

  async function buy(p: Pack) {
    setBusy(p.id);
    try {
      await stickersApi.purchase(p.id);
      toast.success(t("stk.bought"));
      await loadMarket();
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setBusy(null);
    }
  }

  async function install(p: Pack) {
    setBusy(p.id);
    try {
      if (p.is_installed) {
        await stickersApi.uninstall(p.id);
        toast.success(t("stk.uninstalled"));
      } else {
        await stickersApi.install(p.id);
        toast.success(t("stk.installed"));
      }
      await loadMarket();
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setBusy(null);
    }
  }

  async function createPack() {
    const title = nTitle.trim();
    if (title.length < 1) {
      toast.error(t("stk.errTitle"));
      return;
    }
    const priceToman = Number(nPrice || 0);
    if (priceToman > 0 && (!nPublic || priceToman < PRICE_MIN_TOMAN)) {
      toast.error(nPublic ? t("stk.errPrice") : t("stk.errPrivatePaid"));
      return;
    }
    setCreating(true);
    try {
      await stickersApi.createPack(title, nDesc.trim() || undefined, nPublic, priceToman * 10);
      toast.success(t("stk.packCreated"));
      setNTitle(""); setNDesc(""); setNPrice(""); setNPublic(true);
      setShowForm(false);
      await loadTab("mine");
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setCreating(false);
    }
  }

  async function repricePack(p: Pack) {
    const input = window.prompt(t("stk.newPricePrompt"), String(Math.round((p.price || 0) / 10)));
    if (input === null) return;
    const priceToman = Number(input);
    if (Number.isNaN(priceToman) || priceToman < 0) {
      toast.error(t("stk.errPrice"));
      return;
    }
    setBusy(p.id);
    try {
      await stickersApi.updatePack(p.id, { price: priceToman * 10 });
      toast.success(t("stk.priceUpdated"));
      await loadTab("mine");
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setBusy(null);
    }
  }

  async function removePack(p: Pack) {
    if (!window.confirm(t("stk.confirmDelete"))) return;
    setBusy(p.id);
    try {
      await stickersApi.deletePack(p.id);
      toast.success(t("stk.packDeleted"));
      await loadTab("mine");
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setBusy(null);
    }
  }

  const TABS: [Tab, string, React.ElementType][] = [
    ["market", t("stk.tabMarket"), Store],
    ["mine", t("stk.tabMine"), Sticker],
    ["bought", t("stk.tabBought"), ShoppingBag],
    ["sales", t("stk.tabSales"), Coins],
  ];

  return (
    <AppShell title={t("stk.title")}>
      <div className="page-inner space-y-4">

        <div className="grid grid-cols-4 gap-2">
          {TABS.map(([id, label, Icon]) => (
            <button
              key={id}
              onClick={() => setTab(id)}
              className={`flex flex-col items-center gap-1 rounded-xl px-2 py-2.5 text-[11px] transition-colors ${
                tab === id
                  ? "bg-primary-600 text-white"
                  : "bg-surface-800/60 border border-surface-700 text-surface-300"
              }`}
            >
              <Icon size={16} /> {label}
            </button>
          ))}
        </div>

        {loading ? (
          <div className="flex justify-center py-16">
            <Loader2 size={28} className="text-primary-400 animate-spin" />
          </div>
        ) : tab === "market" ? (
          <>
            <div className="flex gap-2">
              <div className="flex-1 flex items-center gap-2 rounded-xl bg-surface-900 border border-surface-700 px-3">
                <Search size={15} className="text-surface-500 shrink-0" />
                <input
                  value={q}
                  onChange={(e) => setQ(e.target.value)}
                  onKeyDown={(e) => { if (e.key === "Enter") loadMarket(); }}
                  placeholder={t("stk.searchPh")}
                  className="flex-1 bg-transparent py-2 text-sm text-white outline-none"
                />
              </div>
              <Button onClick={() => loadMarket()} className="px-3">
                <Search size={16} />
              </Button>
            </div>

            <div className="flex gap-2">
              {(["all", "paid", "free"] as const).map((k) => (
                <button
                  key={k}
                  onClick={() => setKind(k)}
                  className={`rounded-full px-3 py-1.5 text-xs transition-colors ${
                    kind === k
                      ? "bg-primary-600 text-white"
                      : "bg-surface-800/60 border border-surface-700 text-surface-400"
                  }`}
                >
                  {t(`stk.kind.${k}`)}
                </button>
              ))}
            </div>

            {market.length === 0 ? (
              <p className="text-surface-500 text-sm text-center py-12">{t("stk.marketEmpty")}</p>
            ) : (
              <div className="space-y-2">
                {market.map((p) => (
                  <div
                    key={p.id}
                    className="flex items-center gap-3 rounded-2xl bg-surface-800/60 border border-surface-700 p-3"
                  >
                    <PackCover pack={p} />
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <p className="text-sm font-semibold text-white truncate">{p.title}</p>
                        {p.is_paid && (
                          <span className="text-[10px] font-bold px-1.5 py-0.5 rounded-full bg-amber-500/15 text-amber-400 shrink-0">
                            {toman(p.price)} {t("stk.toman")}
                          </span>
                        )}
                      </div>
                      <p className="text-[11px] text-surface-500 truncate">
                        {p.owner_name} · {num(p.sticker_count)} {t("stk.stickers")}
                        {p.sales_count > 0 && ` · ${num(p.sales_count)} ${t("stk.sold")}`}
                      </p>
                    </div>
                    {p.is_mine ? (
                      <span className="text-[11px] text-surface-500 shrink-0">{t("stk.yours")}</span>
                    ) : p.is_paid && !p.is_purchased ? (
                      <Button
                        onClick={() => buy(p)}
                        disabled={busy === p.id}
                        className="gap-1.5 text-xs px-3 shrink-0"
                      >
                        {busy === p.id ? <Loader2 size={14} className="animate-spin" /> : <Wallet size={14} />}
                        {t("stk.buy")}
                      </Button>
                    ) : (
                      <Button
                        onClick={() => install(p)}
                        disabled={busy === p.id}
                        className={`gap-1.5 text-xs px-3 shrink-0 ${
                          p.is_installed ? "bg-surface-700 hover:bg-surface-600" : ""
                        }`}
                      >
                        {busy === p.id ? <Loader2 size={14} className="animate-spin" />
                          : p.is_installed ? <Check size={14} /> : <Download size={14} />}
                        {p.is_installed ? t("stk.installedShort") : t("stk.install")}
                      </Button>
                    )}
                  </div>
                ))}
              </div>
            )}
          </>
        ) : tab === "mine" ? (
          <>
            <Button onClick={() => setShowForm((s) => !s)} className="w-full gap-2">
              <Plus size={16} /> {t("stk.newPack")}
            </Button>

            {showForm && (
              <div className="rounded-2xl bg-surface-800/60 border border-surface-700 p-4 space-y-3">
                <input
                  value={nTitle}
                  onChange={(e) => setNTitle(e.target.value)}
                  placeholder={t("stk.titlePh")}
                  className="w-full rounded-xl bg-surface-900 border border-surface-700 px-3 py-2 text-white text-sm outline-none focus:border-primary-500"
                />
                <input
                  value={nDesc}
                  onChange={(e) => setNDesc(e.target.value)}
                  placeholder={t("stk.descPh")}
                  className="w-full rounded-xl bg-surface-900 border border-surface-700 px-3 py-2 text-white text-sm outline-none focus:border-primary-500"
                />
                <label className="flex items-center gap-2 text-sm text-surface-300">
                  <input
                    type="checkbox"
                    checked={nPublic}
                    onChange={(e) => setNPublic(e.target.checked)}
                    className="accent-primary-500"
                  />
                  {t("stk.publicLabel")}
                </label>
                <input
                  value={nPrice}
                  onChange={(e) => setNPrice(e.target.value.replace(/[^0-9]/g, ""))}
                  inputMode="numeric"
                  disabled={!nPublic}
                  placeholder={t("stk.pricePh")}
                  className="w-full rounded-xl bg-surface-900 border border-surface-700 px-3 py-2 text-white text-sm outline-none focus:border-primary-500 disabled:opacity-50 ltr text-left"
                />
                <p className="text-[11px] text-surface-500">{t("stk.formHint")}</p>
                <Button onClick={createPack} disabled={creating} className="w-full gap-2">
                  {creating ? <Loader2 size={16} className="animate-spin" /> : <Plus size={16} />}
                  {t("stk.create")}
                </Button>
              </div>
            )}

            {mine.length === 0 ? (
              <p className="text-surface-500 text-sm text-center py-12">{t("stk.mineEmpty")}</p>
            ) : (
              <div className="space-y-2">
                {mine.map((p) => (
                  <div
                    key={p.id}
                    className="flex items-center gap-3 rounded-2xl bg-surface-800/60 border border-surface-700 p-3"
                  >
                    <PackCover pack={p} />
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <p className="text-sm font-semibold text-white truncate">{p.title}</p>
                        <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded-full shrink-0 ${
                          p.is_public ? "bg-emerald-500/15 text-emerald-400" : "bg-surface-700 text-surface-400"
                        }`}>
                          {p.is_public ? t("stk.public") : t("stk.private")}
                        </span>
                      </div>
                      <p className="text-[11px] text-surface-500 truncate">
                        {num(p.sticker_count)} {t("stk.stickers")} · {num(p.install_count)} {t("stk.installs")}
                        {p.is_paid && ` · ${toman(p.price)} ${t("stk.toman")}`}
                      </p>
                    </div>
                    <div className="flex gap-1.5 shrink-0">
                      <Button
                        onClick={() => repricePack(p)}
                        disabled={busy === p.id || !p.is_public}
                        className="px-2.5 text-xs bg-surface-700 hover:bg-surface-600 disabled:opacity-40"
                      >
                        <Coins size={14} />
                      </Button>
                      <Button
                        onClick={() => removePack(p)}
                        disabled={busy === p.id}
                        className="px-2.5 text-xs bg-rose-600/80 hover:bg-rose-600"
                      >
                        <Trash2 size={14} />
                      </Button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </>
        ) : tab === "bought" ? (
          bought.length === 0 ? (
            <p className="text-surface-500 text-sm text-center py-12">{t("stk.boughtEmpty")}</p>
          ) : (
            <div className="space-y-2">
              {bought.map((b) => (
                <div
                  key={b.id}
                  className="flex items-center gap-3 rounded-2xl bg-surface-800/60 border border-surface-700 p-3"
                >
                  {b.cover_url ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={b.cover_url} alt={b.pack_title} className="w-12 h-12 rounded-xl object-cover bg-surface-900 shrink-0" />
                  ) : (
                    <div className="w-12 h-12 rounded-xl bg-surface-900 border border-surface-700 flex items-center justify-center shrink-0">
                      <ImageIcon size={18} className="text-surface-600" />
                    </div>
                  )}
                  <div className="flex-1 min-w-0">
                    <p className="text-sm text-white truncate">{b.pack_title}</p>
                    <p className="text-[11px] text-surface-500">{fmtDate(b.created_at)}</p>
                  </div>
                  <span className="text-sm font-bold text-amber-300 shrink-0">
                    {toman(b.price)} {t("stk.toman")}
                  </span>
                </div>
              ))}
            </div>
          )
        ) : (
          <>
            <div className="grid grid-cols-2 gap-3">
              <div className="rounded-2xl bg-surface-800/60 border border-surface-700 p-4">
                <div className="flex items-center gap-2 text-surface-400 text-xs mb-1">
                  <ShoppingBag size={14} /> {t("stk.salesCount")}
                </div>
                <div className="text-xl font-bold text-white">{num(sales?.sales_count || 0)}</div>
              </div>
              <div className="rounded-2xl bg-surface-800/60 border border-surface-700 p-4">
                <div className="flex items-center gap-2 text-surface-400 text-xs mb-1">
                  <Coins size={14} /> {t("stk.revenue")}
                </div>
                <div className="text-xl font-bold text-emerald-300">
                  {toman(sales?.revenue_total || 0)} <span className="text-xs font-normal">{t("stk.toman")}</span>
                </div>
              </div>
            </div>
            <p className="text-[11px] text-surface-500">{t("stk.feeNote")}</p>

            {(sales?.packs || []).length === 0 ? (
              <p className="text-surface-500 text-sm text-center py-12">{t("stk.salesEmpty")}</p>
            ) : (
              <div className="space-y-2">
                {sales!.packs.map((p) => (
                  <div
                    key={p.id}
                    className="flex items-center gap-3 rounded-2xl bg-surface-800/60 border border-surface-700 p-3"
                  >
                    <PackCover pack={p} />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm text-white truncate">{p.title}</p>
                      <p className="text-[11px] text-surface-500">
                        {toman(p.price)} {t("stk.toman")} · {num(p.sales_count)} {t("stk.sold")}
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </>
        )}
      </div>
    </AppShell>
  );
}
