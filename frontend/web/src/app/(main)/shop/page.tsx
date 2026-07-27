"use client";

import { useCallback, useEffect, useState } from "react";
import {
  Check, Loader2, Package, Plus, Search, ShoppingBag, ShoppingCart,
  Store, Trash2, Truck, X,
} from "lucide-react";
import toast from "react-hot-toast";

import AppShell from "@/components/layout/AppShell";
import { Button } from "@/components/ui/Button";
import { getApiErrorMessage, shopApi } from "@/lib/api";
import { toPersianNum } from "@/lib/utils";
import { useTranslation } from "@/store/i18n";

// سرور ریال می‌دهد و می‌گیرد؛ کاربرِ ایرانی تومان می‌خواند و می‌نویسد.
function fmtToman(rial: number): string {
  return toPersianNum(Math.round((rial || 0) / 10).toLocaleString("en-US"));
}

function fmtNum(n: number): string {
  return toPersianNum((n || 0).toLocaleString("en-US"));
}

function fmtDate(iso?: string | null): string {
  if (!iso) return "";
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

interface Product {
  id: string;
  seller_earth_id: string;
  seller_name?: string | null;
  title: string;
  description?: string | null;
  price: number;
  currency: string;
  stock: number;
  image_url?: string | null;
  is_active: boolean;
  sold_count: number;
  created_at: string;
}

interface Order {
  id: string;
  ref: string;
  product_id: string;
  seller_earth_id: string;
  seller_name?: string | null;
  buyer_earth_id: string;
  buyer_name?: string | null;
  title: string;
  unit_price: number;
  qty: number;
  total: number;
  commission: number;
  status: string;
  status_label: string;
  escrow_status: string;
  note?: string | null;
  address?: string | null;
  room_id?: string | null;
  created_at: string;
  shipped_at?: string | null;
  closed_at?: string | null;
  can_accept: boolean;
  can_ship: boolean;
  can_complete: boolean;
  can_cancel: boolean;
}

type Tab = "browse" | "mine" | "orders" | "sales";

const STATUS_STYLE: Record<string, string> = {
  pending: "bg-amber-500/12 text-amber-400",
  accepted: "bg-sky-500/12 text-sky-400",
  shipped: "bg-violet-500/12 text-violet-400",
  completed: "bg-emerald-500/12 text-emerald-400",
  cancelled: "bg-surface-700 text-surface-400",
};

export default function ShopPage() {
  const { t } = useTranslation();

  const [tab, setTab] = useState<Tab>("browse");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);

  const [catalog, setCatalog] = useState<Product[]>([]);
  const [query, setQuery] = useState("");
  const [mine, setMine] = useState<Product[]>([]);
  const [orders, setOrders] = useState<Order[]>([]);
  const [sales, setSales] = useState<Order[]>([]);

  // فرمِ افزودنِ کالا
  const [nTitle, setNTitle] = useState("");
  const [nPrice, setNPrice] = useState("");
  const [nStock, setNStock] = useState("");
  const [nDesc, setNDesc] = useState("");
  const [creating, setCreating] = useState(false);

  const loadCatalog = useCallback(async (q?: string) => {
    try {
      const { data } = await shopApi.products(q ? { q } : undefined);
      setCatalog(data || []);
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    }
  }, []);

  const loadMine = useCallback(async () => {
    try {
      const { data } = await shopApi.myProducts();
      setMine(data || []);
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    }
  }, []);

  const loadOrders = useCallback(async () => {
    try {
      const { data } = await shopApi.myOrders();
      setOrders(data || []);
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    }
  }, []);

  const loadSales = useCallback(async () => {
    try {
      const { data } = await shopApi.mySales();
      setSales(data || []);
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    }
  }, []);

  useEffect(() => {
    (async () => {
      setLoading(true);
      await loadCatalog();
      setLoading(false);
    })();
  }, [loadCatalog]);

  useEffect(() => {
    if (tab === "mine") loadMine();
    if (tab === "orders") loadOrders();
    if (tab === "sales") loadSales();
  }, [tab, loadMine, loadOrders, loadSales]);

  async function addProduct() {
    const title = nTitle.trim();
    const toman = Number(nPrice.replace(/[^\d]/g, ""));
    if (title.length < 2) return toast.error(t("shop.errTitle"));
    if (!toman || toman < 100) return toast.error(t("shop.errPrice"));
    const stockRaw = nStock.trim();
    // خالی یعنی نامحدود؛ سرور آن را با ‎-۱ می‌شناسد.
    const stock = stockRaw === "" ? -1 : Number(stockRaw.replace(/[^\d]/g, ""));
    setCreating(true);
    try {
      await shopApi.createProduct({
        title,
        price: toman * 10,
        stock,
        description: nDesc.trim() || null,
      });
      toast.success(t("shop.added"));
      setNTitle(""); setNPrice(""); setNStock(""); setNDesc("");
      await loadMine();
      await loadCatalog();
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setCreating(false);
    }
  }

  async function removeProduct(p: Product) {
    if (!confirm(t("shop.confirmRemove"))) return;
    setBusy(p.id);
    try {
      await shopApi.removeProduct(p.id);
      toast.success(t("shop.removed"));
      await loadMine();
      await loadCatalog();
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setBusy(null);
    }
  }

  async function buy(p: Product) {
    const raw = prompt(t("shop.askQty"), "1");
    if (raw === null) return;
    const qty = Math.max(1, Number(raw.replace(/[^\d]/g, "")) || 1);
    const total = fmtToman(p.price * qty);
    if (!confirm(`${t("shop.confirmBuy")}\n${p.title} × ${toPersianNum(qty)} = ${total} ${t("shop.toman")}`))
      return;
    const address = prompt(t("shop.askAddress")) || "";
    setBusy(p.id);
    try {
      await shopApi.createOrder({
        product_id: p.id,
        qty,
        address: address.trim() || null,
      });
      toast.success(t("shop.ordered"));
      setTab("orders");
      await loadOrders();
      await loadCatalog();
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setBusy(null);
    }
  }

  async function act(o: Order, kind: "accept" | "ship" | "complete" | "cancel") {
    const msg = {
      accept: t("shop.confirmAccept"),
      ship: t("shop.confirmShip"),
      complete: t("shop.confirmComplete"),
      cancel: t("shop.confirmCancel"),
    }[kind];
    if (!confirm(msg)) return;
    setBusy(o.id);
    try {
      await shopApi[kind](o.id);
      toast.success(t("shop.done"));
      await Promise.all([loadOrders(), loadSales()]);
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setBusy(null);
    }
  }

  function OrderCard({ o, side }: { o: Order; side: "buy" | "sell" }) {
    const peer = side === "buy"
      ? (o.seller_name || o.seller_earth_id)
      : (o.buyer_name || o.buyer_earth_id);
    return (
      <div className="card p-4">
        <div className="flex items-start gap-3">
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="font-semibold text-surface-50 truncate">{o.title}</span>
              <span className={`px-2 py-0.5 rounded-md text-[10px] ${
                STATUS_STYLE[o.status] || "bg-surface-700 text-surface-400"}`}>
                {o.status_label}
              </span>
              {o.escrow_status === "locked" && (
                <span className="px-2 py-0.5 rounded-md bg-amber-500/10 text-amber-400 text-[10px]">
                  {t("shop.escrowLocked")}
                </span>
              )}
            </div>
            <div className="text-xs text-surface-400 mt-1">
              {side === "buy" ? t("shop.seller") : t("shop.buyer")}: {peer}
            </div>
            <div className="text-xs text-surface-400 mt-0.5" dir="ltr">
              {o.ref}
            </div>
            <div className="text-sm text-surface-200 mt-1.5">
              {toPersianNum(o.qty)} × {fmtToman(o.unit_price)} ={" "}
              <span className="font-bold">{fmtToman(o.total)}</span> {t("shop.toman")}
            </div>
            {o.commission > 0 && (
              <div className="text-[11px] text-surface-500 mt-0.5">
                {t("shop.commission")}: {fmtToman(o.commission)} {t("shop.toman")}
              </div>
            )}
            {o.address && (
              <div className="text-[11px] text-surface-500 mt-0.5">
                {t("shop.address")}: {o.address}
              </div>
            )}
            <div className="text-[11px] text-surface-500 mt-0.5">
              {fmtDate(o.created_at)}
            </div>
          </div>
        </div>

        {(o.can_accept || o.can_ship || o.can_complete || o.can_cancel) && (
          <div className="flex gap-2 mt-3">
            {o.can_accept && (
              <Button size="sm" onClick={() => act(o, "accept")}
                      disabled={busy === o.id} className="flex-1">
                <Check className="w-3.5 h-3.5" />{t("shop.accept")}
              </Button>
            )}
            {o.can_ship && (
              <Button size="sm" onClick={() => act(o, "ship")}
                      disabled={busy === o.id} className="flex-1">
                <Truck className="w-3.5 h-3.5" />{t("shop.ship")}
              </Button>
            )}
            {o.can_complete && (
              <Button size="sm" onClick={() => act(o, "complete")}
                      disabled={busy === o.id} className="flex-1">
                <Check className="w-3.5 h-3.5" />{t("shop.complete")}
              </Button>
            )}
            {o.can_cancel && (
              <Button size="sm" variant="ghost" onClick={() => act(o, "cancel")}
                      disabled={busy === o.id} className="flex-1">
                <X className="w-3.5 h-3.5" />{t("shop.cancel")}
              </Button>
            )}
          </div>
        )}
      </div>
    );
  }

  if (loading) {
    return (
      <AppShell title={t("shop.title")}>
        <div className="page-inner flex justify-center py-20">
          <Loader2 className="w-6 h-6 animate-spin text-surface-400" />
        </div>
      </AppShell>
    );
  }

  return (
    <AppShell title={t("shop.title")}>
      <div className="page-inner space-y-4">
        <div className="flex gap-2 overflow-x-auto">
          {([
            ["browse", t("shop.tabBrowse"), <Store key="i" className="w-4 h-4" />],
            ["mine", t("shop.tabMine"), <Package key="i" className="w-4 h-4" />],
            ["orders", t("shop.tabOrders"), <ShoppingBag key="i" className="w-4 h-4" />],
            ["sales", t("shop.tabSales"), <ShoppingCart key="i" className="w-4 h-4" />],
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

        {/* ── کاتالوگ ───────────────────────────────────────────────────── */}
        {tab === "browse" && (
          <div className="space-y-3">
            <div className="card p-3 flex items-center gap-2">
              <Search className="w-4 h-4 text-surface-400 shrink-0" />
              <input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                onKeyDown={(e) => { if (e.key === "Enter") loadCatalog(query.trim()); }}
                placeholder={t("shop.searchPh")}
                className="bg-transparent flex-1 outline-none text-sm text-surface-100"
              />
              <Button size="sm" onClick={() => loadCatalog(query.trim())}>
                {t("shop.search")}
              </Button>
            </div>

            {catalog.length === 0 && (
              <div className="card p-8 text-center text-surface-400 text-sm">
                {t("shop.emptyCatalog")}
              </div>
            )}

            {catalog.map((p) => (
              <div key={p.id} className="card p-4">
                <div className="flex items-start gap-3">
                  <div className="w-12 h-12 rounded-2xl bg-primary/12 flex items-center justify-center shrink-0">
                    <Package className="w-5 h-5 text-primary" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="font-semibold text-surface-50 truncate">{p.title}</div>
                    <div className="text-xs text-surface-400 mt-0.5 truncate">
                      {p.seller_name || p.seller_earth_id}
                    </div>
                    {p.description && (
                      <p className="text-xs text-surface-300 mt-1.5 leading-5 line-clamp-2">
                        {p.description}
                      </p>
                    )}
                    <div className="text-sm font-bold text-surface-50 mt-1.5">
                      {fmtToman(p.price)} {t("shop.toman")}
                    </div>
                    <div className="text-[11px] text-surface-500 mt-0.5">
                      {p.stock === -1
                        ? t("shop.unlimited")
                        : `${t("shop.stock")}: ${fmtNum(p.stock)}`}
                      {p.sold_count > 0 && ` · ${t("shop.sold")}: ${fmtNum(p.sold_count)}`}
                    </div>
                  </div>
                </div>
                <Button
                  size="sm"
                  onClick={() => buy(p)}
                  disabled={busy === p.id}
                  className="w-full mt-3"
                >
                  {busy === p.id
                    ? <Loader2 className="w-4 h-4 animate-spin" />
                    : <ShoppingCart className="w-4 h-4" />}
                  {t("shop.buy")}
                </Button>
              </div>
            ))}

            <p className="text-[11px] text-surface-500 leading-5 px-1">
              {t("shop.escrowNote")}
            </p>
          </div>
        )}

        {/* ── کالاهای من ────────────────────────────────────────────────── */}
        {tab === "mine" && (
          <div className="space-y-3">
            <div className="card p-4 space-y-3">
              <div className="text-sm font-semibold text-surface-50">
                {t("shop.addProduct")}
              </div>
              <div>
                <label className="block text-xs text-surface-400 mb-1">
                  {t("shop.pTitle")}
                </label>
                <input
                  value={nTitle}
                  onChange={(e) => setNTitle(e.target.value)}
                  placeholder={t("shop.pTitlePh")}
                  className="input w-full"
                />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs text-surface-400 mb-1">
                    {t("shop.pPrice")}
                  </label>
                  <input
                    value={nPrice}
                    onChange={(e) => setNPrice(e.target.value)}
                    inputMode="numeric"
                    placeholder={t("shop.pPricePh")}
                    className="input w-full"
                    dir="ltr"
                  />
                </div>
                <div>
                  <label className="block text-xs text-surface-400 mb-1">
                    {t("shop.pStock")}
                  </label>
                  <input
                    value={nStock}
                    onChange={(e) => setNStock(e.target.value)}
                    inputMode="numeric"
                    placeholder={t("shop.pStockPh")}
                    className="input w-full"
                    dir="ltr"
                  />
                </div>
              </div>
              <div>
                <label className="block text-xs text-surface-400 mb-1">
                  {t("shop.pDesc")}
                </label>
                <textarea
                  value={nDesc}
                  onChange={(e) => setNDesc(e.target.value)}
                  rows={2}
                  placeholder={t("shop.pDescPh")}
                  className="input w-full resize-none"
                />
              </div>
              <Button onClick={addProduct} disabled={creating} className="w-full">
                {creating
                  ? <Loader2 className="w-4 h-4 animate-spin" />
                  : <Plus className="w-4 h-4" />}
                {t("shop.addProduct")}
              </Button>
            </div>

            {mine.length === 0 && (
              <div className="card p-8 text-center text-surface-400 text-sm">
                {t("shop.emptyMine")}
              </div>
            )}

            {mine.map((p) => (
              <div key={p.id} className="card p-4 flex items-start gap-3">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="font-semibold text-surface-50 truncate">
                      {p.title}
                    </span>
                    {!p.is_active && (
                      <span className="px-2 py-0.5 rounded-md bg-surface-700 text-surface-400 text-[10px]">
                        {t("shop.inactive")}
                      </span>
                    )}
                  </div>
                  <div className="text-xs text-surface-400 mt-0.5">
                    {fmtToman(p.price)} {t("shop.toman")} ·{" "}
                    {p.stock === -1 ? t("shop.unlimited") : `${t("shop.stock")}: ${fmtNum(p.stock)}`}
                    {` · ${t("shop.sold")}: ${fmtNum(p.sold_count)}`}
                  </div>
                </div>
                {p.is_active && (
                  <button
                    onClick={() => removeProduct(p)}
                    disabled={busy === p.id}
                    className="p-2 rounded-lg text-surface-400 hover:text-red-400 hover:bg-red-500/8 transition-colors shrink-0"
                    aria-label={t("shop.remove")}
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                )}
              </div>
            ))}
          </div>
        )}

        {/* ── خریدهای من ────────────────────────────────────────────────── */}
        {tab === "orders" && (
          <div className="space-y-3">
            {orders.length === 0 && (
              <div className="card p-8 text-center text-surface-400 text-sm">
                {t("shop.emptyOrders")}
              </div>
            )}
            {orders.map((o) => <OrderCard key={o.id} o={o} side="buy" />)}
          </div>
        )}

        {/* ── فروش‌های من ───────────────────────────────────────────────── */}
        {tab === "sales" && (
          <div className="space-y-3">
            {sales.length === 0 && (
              <div className="card p-8 text-center text-surface-400 text-sm">
                {t("shop.emptySales")}
              </div>
            )}
            {sales.map((o) => <OrderCard key={o.id} o={o} side="sell" />)}
          </div>
        )}
      </div>
    </AppShell>
  );
}
