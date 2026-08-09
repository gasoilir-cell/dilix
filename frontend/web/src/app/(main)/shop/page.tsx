"use client";

import { useCallback, useEffect, useState } from "react";
import {
  Check, Layers, Loader2, Package, Plus, Search, Send, ShoppingBag, ShoppingCart,
  Star, Store, Tag, Trash2, Truck, X,
} from "lucide-react";
import toast from "react-hot-toast";

import AppShell from "@/components/layout/AppShell";
import { Button } from "@/components/ui/Button";
import { getApiErrorMessage, messagesApi, shopApi } from "@/lib/api";
import { toPersianNum } from "@/lib/utils";
import { useTranslation } from "@/store/i18n";

// سرور ریال می‌دهد و می‌گیرد؛ کاربرِ ایرانی تومان می‌خواند و می‌نویسد.
function fmtToman(rial: number): string {
  return toPersianNum(Math.round((rial || 0) / 10).toLocaleString("en-US"));
}

function fmtNum(n: number): string {
  return toPersianNum((n || 0).toLocaleString("en-US"));
}

function fmtRating(avg: number): string {
  return toPersianNum(avg.toFixed(1));
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

const CART_KEY = "dilix_shop_cart_v1";

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
  images?: string[];
  is_active: boolean;
  sold_count: number;
  created_at: string;
  rating_avg?: number | null;
  rating_count: number;
  has_variants: boolean;
}

interface Variant {
  id: string;
  product_id: string;
  name: string;
  price?: number | null;
  stock: number;
  image_url?: string | null;
  is_active: boolean;
}

interface OrderItem {
  product_id: string;
  variant_id?: string | null;
  title: string;
  unit_price: number;
  qty: number;
  subtotal: number;
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
  discount: number;
  coupon_code?: string | null;
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
  items: OrderItem[];
  can_accept: boolean;
  can_ship: boolean;
  can_complete: boolean;
  can_cancel: boolean;
}

interface Review {
  id: string;
  product_id: string;
  order_id: string;
  reviewer_earth_id: string;
  reviewer_name?: string | null;
  rating: number;
  comment?: string | null;
  created_at: string;
}

interface Coupon {
  id: string;
  code: string;
  discount_type: string;
  discount_value: number;
  product_id?: string | null;
  max_uses?: number | null;
  used_count: number;
  min_order_total: number;
  expires_at?: string | null;
  is_active: boolean;
  created_at: string;
}

interface CartLine {
  product_id: string;
  title: string;
  price: number; // واحدِ ریال؛ اگر گونه انتخاب شده باشد، قیمتِ گونه
  variant_id?: string | null;
  qty: number;
  seller_earth_id: string;
}

/** فقط چیزی که برای انتخابِ گفتگو لازم است — نه کلِ شکلِ اتاق. */
interface ChatRoomLite {
  id: string;
  name?: string | null;
  partner_name?: string | null;
  partner_earth_id?: string | null;
}

type Tab = "browse" | "mine" | "orders" | "sales" | "cart";

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
  const [nImages, setNImages] = useState("");
  const [creating, setCreating] = useState(false);

  // سبدِ خرید — در localStorage نگه داشته می‌شود تا با ناوبری از دست نرود.
  const [cart, setCart] = useState<CartLine[]>([]);
  const [cartCoupon, setCartCoupon] = useState("");
  const [cartAddress, setCartAddress] = useState("");
  const [cartBusy, setCartBusy] = useState(false);

  useEffect(() => {
    try {
      const raw = localStorage.getItem(CART_KEY);
      if (raw) setCart(JSON.parse(raw));
    } catch {
      /* سبدِ خراب را نادیده بگیر */
    }
  }, []);

  useEffect(() => {
    try {
      localStorage.setItem(CART_KEY, JSON.stringify(cart));
    } catch {
      /* فضای ذخیره‌سازی پر یا غیرقابلِ‌دسترس — بی‌اهمیت برای این قابلیت */
    }
  }, [cart]);

  // انتخابِ گونه پیش از خرید/افزودن به سبد — یک مودالِ عمومی که با Promise جواب می‌دهد.
  const [variantModal, setVariantModal] = useState<{
    product: Product;
    variants: Variant[];
    resolve: (v: Variant | null) => void;
  } | null>(null);

  async function chooseVariant(p: Product): Promise<Variant | null | "cancel"> {
    if (!p.has_variants) return null;
    try {
      const { data } = await shopApi.listVariants(p.id);
      const list: Variant[] = (data || []).filter((v: Variant) => v.is_active);
      if (list.length === 0) {
        toast.error(t("shop.noVariants"));
        return "cancel";
      }
      return await new Promise<Variant | null>((resolve) => {
        setVariantModal({
          product: p, variants: list,
          resolve: (v) => { setVariantModal(null); resolve(v); },
        });
      });
    } catch (e) {
      toast.error(getApiErrorMessage(e));
      return "cancel";
    }
  }

  // نظراتِ یک کالا (نمایشِ فهرست)
  const [reviewsFor, setReviewsFor] = useState<Product | null>(null);
  const [reviewsList, setReviewsList] = useState<Review[] | null>(null);

  async function openReviews(p: Product) {
    setReviewsFor(p);
    setReviewsList(null);
    try {
      const { data } = await shopApi.listReviews(p.id);
      setReviewsList(data || []);
    } catch (e) {
      toast.error(getApiErrorMessage(e));
      setReviewsFor(null);
    }
  }

  // ثبتِ نظر روی یک سفارشِ تکمیل‌شده
  const [reviewFor, setReviewFor] = useState<Order | null>(null);
  const [reviewPid, setReviewPid] = useState("");
  const [reviewRating, setReviewRating] = useState(5);
  const [reviewComment, setReviewComment] = useState("");
  const [reviewBusy, setReviewBusy] = useState(false);

  function openReview(o: Order) {
    setReviewFor(o);
    setReviewPid((o.items && o.items[0]?.product_id) || o.product_id);
    setReviewRating(5);
    setReviewComment("");
  }

  async function submitReview() {
    if (!reviewFor) return;
    setReviewBusy(true);
    try {
      await shopApi.reviewOrder(reviewFor.id, {
        product_id: reviewPid,
        rating: reviewRating,
        comment: reviewComment.trim() || null,
      });
      toast.success(t("shop.reviewSubmitted"));
      setReviewFor(null);
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setReviewBusy(false);
    }
  }

  // مدیریتِ گونه‌های یک کالا (فروشنده)
  const [variantManage, setVariantManage] = useState<{ product: Product; variants: Variant[] | null } | null>(null);
  const [vName, setVName] = useState("");
  const [vPrice, setVPrice] = useState("");
  const [vStock, setVStock] = useState("");
  const [vBusy, setVBusy] = useState(false);

  async function openVariantManage(p: Product) {
    setVariantManage({ product: p, variants: null });
    setVName(""); setVPrice(""); setVStock("");
    try {
      const { data } = await shopApi.listVariants(p.id);
      setVariantManage({ product: p, variants: (data || []).filter((v: Variant) => v.is_active) });
    } catch (e) {
      toast.error(getApiErrorMessage(e));
      setVariantManage(null);
    }
  }

  async function submitVariant() {
    if (!variantManage) return;
    const name = vName.trim();
    if (name.length < 1) return toast.error(t("shop.errTitle"));
    const priceToman = vPrice.trim() ? Number(vPrice.replace(/[^\d]/g, "")) : 0;
    const stockRaw = vStock.trim();
    const stock = stockRaw === "" ? 0 : Number(stockRaw.replace(/[^\d]/g, ""));
    setVBusy(true);
    try {
      const { data } = await shopApi.addVariant(variantManage.product.id, {
        name,
        price: priceToman > 0 ? priceToman * 10 : null,
        stock,
      });
      toast.success(t("shop.variantAdded"));
      setVName(""); setVPrice(""); setVStock("");
      setVariantManage((cur) => cur && { ...cur, variants: [...(cur.variants || []), data] });
      await loadMine();
      await loadCatalog();
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setVBusy(false);
    }
  }

  async function removeVariant(v: Variant) {
    if (!variantManage) return;
    if (!confirm(t("shop.confirmRemoveVariant"))) return;
    try {
      await shopApi.deactivateVariant(variantManage.product.id, v.id);
      toast.success(t("shop.variantRemoved"));
      setVariantManage((cur) => cur && { ...cur, variants: (cur.variants || []).filter((x) => x.id !== v.id) });
      await loadMine();
      await loadCatalog();
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    }
  }

  // مدیریتِ کدهای تخفیفِ یک کالا (فروشنده)
  const [couponManage, setCouponManage] = useState<{ product: Product; coupons: Coupon[] | null } | null>(null);
  const [cCode, setCCode] = useState("");
  const [cType, setCType] = useState<"percent" | "fixed">("percent");
  const [cValue, setCValue] = useState("");
  const [cMaxUses, setCMaxUses] = useState("");
  const [cScope, setCScope] = useState<"product" | "all">("product");
  const [cBusy, setCBusy] = useState(false);

  async function openCouponManage(p: Product) {
    setCouponManage({ product: p, coupons: null });
    setCCode(""); setCType("percent"); setCValue(""); setCMaxUses(""); setCScope("product");
    try {
      const { data } = await shopApi.myCoupons();
      setCouponManage({
        product: p,
        coupons: (data || []).filter((c: Coupon) => c.is_active && c.product_id === p.id),
      });
    } catch (e) {
      toast.error(getApiErrorMessage(e));
      setCouponManage(null);
    }
  }

  async function submitCoupon() {
    if (!couponManage) return;
    const code = cCode.trim().toUpperCase();
    if (code.length < 3) return toast.error(t("shop.errTitle"));
    const value = Number(cValue.replace(/[^\d]/g, ""));
    if (!value || value <= 0) return toast.error(t("shop.errPrice"));
    const maxUses = cMaxUses.trim() ? Number(cMaxUses.replace(/[^\d]/g, "")) : null;
    setCBusy(true);
    try {
      const { data } = await shopApi.createCoupon({
        code,
        product_id: cScope === "product" ? couponManage.product.id : null,
        discount_type: cType,
        discount_value: cType === "fixed" ? value * 10 : value,
        max_uses: maxUses,
      });
      toast.success(t("shop.couponAdded"));
      setCCode(""); setCValue(""); setCMaxUses("");
      if (data.product_id === couponManage.product.id) {
        setCouponManage((cur) => cur && { ...cur, coupons: [...(cur.coupons || []), data] });
      }
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setCBusy(false);
    }
  }

  async function removeCoupon(c: Coupon) {
    if (!couponManage) return;
    if (!confirm(t("shop.confirmRemoveCoupon"))) return;
    try {
      await shopApi.deactivateCoupon(c.id);
      toast.success(t("shop.couponRemoved"));
      setCouponManage((cur) => cur && { ...cur, coupons: (cur.coupons || []).filter((x) => x.id !== c.id) });
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    }
  }

  // انتخابِ گفتگو برای فرستادنِ کارتِ کالا. فهرستِ گفتگوها فقط وقتی گرفته
  // می‌شود که کاربر دکمه را بزند؛ صفحهٔ فروشگاه نباید برای قابلیتی که شاید
  // هرگز لمس نشود یک درخواستِ اضافه بزند.
  const [shareFor, setShareFor] = useState<Product | null>(null);
  const [shareRooms, setShareRooms] = useState<ChatRoomLite[] | null>(null);

  async function openShare(p: Product) {
    setShareFor(p);
    setShareRooms(null);
    try {
      const { data } = await messagesApi.listRooms();
      setShareRooms(data || []);
    } catch (e) {
      toast.error(getApiErrorMessage(e));
      setShareFor(null);
    }
  }

  async function doShare(roomId: string) {
    if (!shareFor) return;
    const p = shareFor;
    setShareFor(null);
    try {
      await shopApi.shareProduct(p.id, roomId);
      toast.success(t("shop.sharedToChat"));
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    }
  }

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
    const images = nImages.split("\n").map((s) => s.trim()).filter(Boolean).slice(0, 8);
    setCreating(true);
    try {
      await shopApi.createProduct({
        title,
        price: toman * 10,
        stock,
        description: nDesc.trim() || null,
        images: images.length ? images : null,
      });
      toast.success(t("shop.added"));
      setNTitle(""); setNPrice(""); setNStock(""); setNDesc(""); setNImages("");
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
    const variant = await chooseVariant(p);
    if (variant === "cancel") return;
    const raw = prompt(t("shop.askQty"), "1");
    if (raw === null) return;
    const qty = Math.max(1, Number(raw.replace(/[^\d]/g, "")) || 1);
    const unitPrice = variant && variant.price != null ? variant.price : p.price;
    const total = fmtToman(unitPrice * qty);
    if (!confirm(`${t("shop.confirmBuy")}\n${p.title} × ${toPersianNum(qty)} = ${total} ${t("shop.toman")}`))
      return;
    const address = prompt(t("shop.askAddress")) || "";
    const coupon = prompt(t("shop.cartCouponPh")) || "";
    setBusy(p.id);
    try {
      await shopApi.createOrder({
        product_id: p.id,
        variant_id: variant ? variant.id : null,
        qty,
        address: address.trim() || null,
        coupon_code: coupon.trim() || null,
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

  async function addToCartFlow(p: Product) {
    const variant = await chooseVariant(p);
    if (variant === "cancel") return;
    setCart((prev) => {
      const idx = prev.findIndex(
        (l) => l.product_id === p.id && (l.variant_id || null) === (variant ? variant.id : null)
      );
      if (idx >= 0) {
        const copy = [...prev];
        copy[idx] = { ...copy[idx], qty: copy[idx].qty + 1 };
        return copy;
      }
      return [
        ...prev,
        {
          product_id: p.id,
          title: variant ? `${p.title} (${variant.name})` : p.title,
          price: variant && variant.price != null ? variant.price : p.price,
          variant_id: variant ? variant.id : null,
          qty: 1,
          seller_earth_id: p.seller_earth_id,
        },
      ];
    });
    toast.success(t("shop.addedToCart"));
  }

  function removeFromCart(idx: number) {
    setCart((prev) => prev.filter((_, i) => i !== idx));
  }

  function setCartQty(idx: number, qty: number) {
    setCart((prev) => prev.map((l, i) => (i === idx ? { ...l, qty: Math.max(1, qty) } : l)));
  }

  const cartTotal = cart.reduce((sum, l) => sum + l.price * l.qty, 0);

  async function checkoutCart() {
    if (cart.length === 0) return;
    setCartBusy(true);
    try {
      const code = cartCoupon.trim() || null;
      await shopApi.cartCheckout({
        items: cart.map((l) => ({
          product_id: l.product_id,
          variant_id: l.variant_id || null,
          qty: l.qty,
          coupon_code: code,
        })),
        address: cartAddress.trim() || null,
      });
      toast.success(t("shop.cartCheckedOut"));
      setCart([]);
      setCartCoupon(""); setCartAddress("");
      setTab("orders");
      await loadOrders();
      await loadCatalog();
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setCartBusy(false);
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

            {o.items && o.items.length > 1 ? (
              <div className="mt-1.5 space-y-0.5">
                {o.items.map((it, i) => (
                  <div key={i} className="text-xs text-surface-300">
                    {it.title} — {toPersianNum(it.qty)} × {fmtToman(it.unit_price)} {t("shop.toman")}
                  </div>
                ))}
              </div>
            ) : (
              <div className="text-sm text-surface-200 mt-1.5">
                {toPersianNum(o.qty)} × {fmtToman(o.unit_price)} {t("shop.toman")}
              </div>
            )}

            {o.discount > 0 && (
              <div className="text-[11px] text-emerald-400 mt-0.5">
                {t("shop.discountLabel")}{o.coupon_code ? ` (${o.coupon_code})` : ""}: -{fmtToman(o.discount)} {t("shop.toman")}
              </div>
            )}
            <div className="text-sm text-surface-50 mt-1">
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

        {(o.can_accept || o.can_ship || o.can_complete || o.can_cancel || (side === "buy" && o.status === "completed")) && (
          <div className="flex gap-2 mt-3 flex-wrap">
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
            {side === "buy" && o.status === "completed" && (
              <Button size="sm" variant="outline" onClick={() => openReview(o)} className="flex-1">
                <Star className="w-3.5 h-3.5" />{t("shop.writeReview")}
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
            ["cart", `${t("shop.tabCart")}${cart.length ? ` (${toPersianNum(cart.length)})` : ""}`, <ShoppingCart key="i" className="w-4 h-4" />],
            ["orders", t("shop.tabOrders"), <ShoppingBag key="i" className="w-4 h-4" />],
            ["sales", t("shop.tabSales"), <Tag key="i" className="w-4 h-4" />],
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

            {catalog.map((p) => {
              const cover = p.images?.[0] || p.image_url || null;
              return (
                <div key={p.id} className="card p-4">
                  <div className="flex items-start gap-3">
                    {cover ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={cover} alt="" className="w-12 h-12 rounded-2xl object-cover shrink-0 bg-surface-800" />
                    ) : (
                      <div className="w-12 h-12 rounded-2xl bg-primary/12 flex items-center justify-center shrink-0">
                        <Package className="w-5 h-5 text-primary" />
                      </div>
                    )}
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
                        {p.has_variants && (
                          <span className="ms-1.5 text-[10px] font-normal px-1.5 py-0.5 rounded-md bg-surface-700 text-surface-300">
                            {t("shop.manageVariants")}
                          </span>
                        )}
                      </div>
                      <div className="text-[11px] text-surface-500 mt-0.5">
                        {p.stock === -1
                          ? t("shop.unlimited")
                          : `${t("shop.stock")}: ${fmtNum(p.stock)}`}
                        {p.sold_count > 0 && ` · ${t("shop.sold")}: ${fmtNum(p.sold_count)}`}
                      </div>
                      <button
                        onClick={() => openReviews(p)}
                        className="flex items-center gap-1 mt-1 text-[11px] text-amber-400 hover:underline"
                      >
                        <Star className="w-3 h-3 fill-amber-400" />
                        {p.rating_count > 0
                          ? `${fmtRating(p.rating_avg || 0)} (${fmtNum(p.rating_count)})`
                          : t("shop.reviews")}
                      </button>
                    </div>
                  </div>
                  <div className="flex gap-2 mt-3">
                    <Button
                      size="sm"
                      onClick={() => buy(p)}
                      disabled={busy === p.id}
                      className="flex-1"
                    >
                      {busy === p.id
                        ? <Loader2 className="w-4 h-4 animate-spin" />
                        : <ShoppingCart className="w-4 h-4" />}
                      {t("shop.buy")}
                    </Button>
                    <button
                      onClick={() => addToCartFlow(p)}
                      title={t("shop.addToCart")}
                      aria-label={t("shop.addToCart")}
                      className="px-3 rounded-xl bg-surface-800 text-surface-300 hover:text-surface-50"
                    >
                      <Plus className="w-4 h-4" />
                    </button>
                    <button
                      onClick={() => openShare(p)}
                      title={t("shop.shareToChat")}
                      aria-label={t("shop.shareToChat")}
                      className="px-3 rounded-xl bg-surface-800 text-surface-300 hover:text-surface-50"
                    >
                      <Send className="w-4 h-4" />
                    </button>
                  </div>
                </div>
              );
            })}

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
              <div>
                <label className="block text-xs text-surface-400 mb-1">
                  {t("shop.pImages")}
                </label>
                <textarea
                  value={nImages}
                  onChange={(e) => setNImages(e.target.value)}
                  rows={2}
                  placeholder={t("shop.pImagesPh")}
                  className="input w-full resize-none"
                  dir="ltr"
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

            {mine.map((p) => {
              const cover = p.images?.[0] || p.image_url || null;
              return (
                <div key={p.id} className="card p-4 flex items-start gap-3">
                  {cover ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={cover} alt="" className="w-10 h-10 rounded-xl object-cover shrink-0 bg-surface-800" />
                  ) : null}
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
                    {p.rating_count > 0 && (
                      <div className="flex items-center gap-1 mt-0.5 text-[11px] text-amber-400">
                        <Star className="w-3 h-3 fill-amber-400" />
                        {fmtRating(p.rating_avg || 0)} ({fmtNum(p.rating_count)})
                      </div>
                    )}
                  </div>
                  {p.is_active && (
                    <div className="flex flex-col gap-1 shrink-0">
                      <div className="flex gap-1">
                        <button
                          onClick={() => openVariantManage(p)}
                          className="p-2 rounded-lg text-surface-400 hover:text-primary hover:bg-primary/8 transition-colors"
                          aria-label={t("shop.manageVariants")}
                          title={t("shop.manageVariants")}
                        >
                          <Layers className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() => openCouponManage(p)}
                          className="p-2 rounded-lg text-surface-400 hover:text-primary hover:bg-primary/8 transition-colors"
                          aria-label={t("shop.manageCoupons")}
                          title={t("shop.manageCoupons")}
                        >
                          <Tag className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() => openShare(p)}
                          className="p-2 rounded-lg text-surface-400 hover:text-primary hover:bg-primary/8 transition-colors"
                          aria-label={t("shop.shareToChat")}
                          title={t("shop.shareToChat")}
                        >
                          <Send className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() => removeProduct(p)}
                          disabled={busy === p.id}
                          className="p-2 rounded-lg text-surface-400 hover:text-red-400 hover:bg-red-500/8 transition-colors"
                          aria-label={t("shop.remove")}
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}

        {/* ── سبدِ خرید ─────────────────────────────────────────────────── */}
        {tab === "cart" && (
          <div className="space-y-3">
            {cart.length === 0 ? (
              <div className="card p-8 text-center text-surface-400 text-sm">
                {t("shop.cartEmpty")}
              </div>
            ) : (
              <>
                {cart.map((l, idx) => (
                  <div key={`${l.product_id}-${l.variant_id || ""}`} className="card p-4 flex items-center gap-3">
                    <div className="flex-1 min-w-0">
                      <div className="font-semibold text-surface-50 truncate">{l.title}</div>
                      <div className="text-xs text-surface-400 mt-0.5">
                        {fmtToman(l.price)} {t("shop.toman")}
                      </div>
                    </div>
                    <input
                      type="number"
                      min={1}
                      value={l.qty}
                      onChange={(e) => setCartQty(idx, Number(e.target.value) || 1)}
                      className="input w-16 text-center"
                      dir="ltr"
                    />
                    <button
                      onClick={() => removeFromCart(idx)}
                      className="p-2 rounded-lg text-surface-400 hover:text-red-400 hover:bg-red-500/8 transition-colors shrink-0"
                      aria-label={t("shop.remove")}
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                ))}

                <div className="card p-4 space-y-3">
                  <input
                    value={cartCoupon}
                    onChange={(e) => setCartCoupon(e.target.value)}
                    placeholder={t("shop.cartCouponPh")}
                    className="input w-full"
                    dir="ltr"
                  />
                  <input
                    value={cartAddress}
                    onChange={(e) => setCartAddress(e.target.value)}
                    placeholder={t("shop.askAddress")}
                    className="input w-full"
                  />
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-surface-400">{t("shop.cartTotal")}</span>
                    <span className="font-bold text-surface-50">{fmtToman(cartTotal)} {t("shop.toman")}</span>
                  </div>
                  <Button onClick={checkoutCart} disabled={cartBusy} className="w-full">
                    {cartBusy ? <Loader2 className="w-4 h-4 animate-spin" /> : <ShoppingCart className="w-4 h-4" />}
                    {t("shop.cartCheckout")}
                  </Button>
                </div>
              </>
            )}
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

        {/* ── انتخابِ گفتگو برای فرستادنِ کارتِ کالا ─────────────────────── */}
        {shareFor && (
          <div
            className="fixed inset-0 z-50 bg-black/60 flex items-end sm:items-center justify-center p-0 sm:p-4"
            onClick={() => setShareFor(null)}
          >
            <div
              className="w-full sm:max-w-sm max-h-[70vh] overflow-y-auto rounded-t-3xl sm:rounded-3xl bg-surface-900 p-4 space-y-2"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center justify-between">
                <span className="text-sm font-semibold text-surface-50">
                  {t("shop.shareToChat")}
                </span>
                <button onClick={() => setShareFor(null)} aria-label={t("chat.close")}>
                  <X className="w-4 h-4 text-surface-400" />
                </button>
              </div>
              <div className="text-xs text-surface-400 truncate">{shareFor.title}</div>

              {shareRooms === null ? (
                <div className="py-8 flex justify-center">
                  <Loader2 className="w-5 h-5 animate-spin text-surface-500" />
                </div>
              ) : shareRooms.length === 0 ? (
                <div className="py-8 text-center text-surface-400 text-sm">
                  {t("shop.noChats")}
                </div>
              ) : (
                shareRooms.map((r) => (
                  <button
                    key={r.id}
                    onClick={() => doShare(r.id)}
                    className="w-full text-start px-3 py-2.5 rounded-xl bg-surface-800 hover:bg-surface-700 text-surface-100 text-sm truncate"
                  >
                    {r.name || r.partner_name || r.partner_earth_id || r.id}
                  </button>
                ))
              )}
            </div>
          </div>
        )}

        {/* ── انتخابِ گونه پیش از خرید/افزودن به سبد ──────────────────────── */}
        {variantModal && (
          <div
            className="fixed inset-0 z-50 bg-black/60 flex items-end sm:items-center justify-center p-0 sm:p-4"
            onClick={() => variantModal.resolve(null)}
          >
            <div
              className="w-full sm:max-w-sm max-h-[70vh] overflow-y-auto rounded-t-3xl sm:rounded-3xl bg-surface-900 p-4 space-y-2"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center justify-between">
                <span className="text-sm font-semibold text-surface-50">{t("shop.selectVariant")}</span>
                <button onClick={() => variantModal.resolve(null)} aria-label={t("chat.close")}>
                  <X className="w-4 h-4 text-surface-400" />
                </button>
              </div>
              {variantModal.variants.map((v) => (
                <button
                  key={v.id}
                  onClick={() => variantModal.resolve(v)}
                  disabled={v.stock === 0}
                  className="w-full text-start px-3 py-2.5 rounded-xl bg-surface-800 hover:bg-surface-700 disabled:opacity-40 text-surface-100 text-sm flex items-center justify-between gap-2"
                >
                  <span className="truncate">{v.name}</span>
                  <span className="text-xs text-surface-400 shrink-0">
                    {fmtToman(v.price != null ? v.price : variantModal.product.price)} {t("shop.toman")}
                    {v.stock !== -1 && ` · ${fmtNum(v.stock)}`}
                  </span>
                </button>
              ))}
            </div>
          </div>
        )}

        {/* ── فهرستِ نظراتِ یک کالا ────────────────────────────────────────── */}
        {reviewsFor && (
          <div
            className="fixed inset-0 z-50 bg-black/60 flex items-end sm:items-center justify-center p-0 sm:p-4"
            onClick={() => setReviewsFor(null)}
          >
            <div
              className="w-full sm:max-w-sm max-h-[70vh] overflow-y-auto rounded-t-3xl sm:rounded-3xl bg-surface-900 p-4 space-y-2"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center justify-between">
                <span className="text-sm font-semibold text-surface-50">{t("shop.reviewsTitle")}</span>
                <button onClick={() => setReviewsFor(null)} aria-label={t("chat.close")}>
                  <X className="w-4 h-4 text-surface-400" />
                </button>
              </div>
              {reviewsList === null ? (
                <div className="py-8 flex justify-center">
                  <Loader2 className="w-5 h-5 animate-spin text-surface-500" />
                </div>
              ) : reviewsList.length === 0 ? (
                <div className="py-8 text-center text-surface-400 text-sm">
                  {t("shop.noReviews")}
                </div>
              ) : (
                reviewsList.map((r) => (
                  <div key={r.id} className="px-3 py-2.5 rounded-xl bg-surface-800">
                    <div className="flex items-center justify-between">
                      <span className="text-sm text-surface-100">{r.reviewer_name || r.reviewer_earth_id}</span>
                      <span className="flex items-center gap-0.5 text-amber-400 text-xs">
                        <Star className="w-3 h-3 fill-amber-400" />{toPersianNum(r.rating)}
                      </span>
                    </div>
                    {r.comment && (
                      <p className="text-xs text-surface-300 mt-1 leading-5">{r.comment}</p>
                    )}
                    <div className="text-[10px] text-surface-500 mt-1">{fmtDate(r.created_at)}</div>
                  </div>
                ))
              )}
            </div>
          </div>
        )}

        {/* ── ثبتِ نظر روی سفارشِ تکمیل‌شده ───────────────────────────────── */}
        {reviewFor && (
          <div
            className="fixed inset-0 z-50 bg-black/60 flex items-end sm:items-center justify-center p-0 sm:p-4"
            onClick={() => setReviewFor(null)}
          >
            <div
              className="w-full sm:max-w-sm rounded-t-3xl sm:rounded-3xl bg-surface-900 p-4 space-y-3"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center justify-between">
                <span className="text-sm font-semibold text-surface-50">{t("shop.writeReview")}</span>
                <button onClick={() => setReviewFor(null)} aria-label={t("chat.close")}>
                  <X className="w-4 h-4 text-surface-400" />
                </button>
              </div>
              {reviewFor.items && reviewFor.items.length > 1 && (
                <select
                  value={reviewPid}
                  onChange={(e) => setReviewPid(e.target.value)}
                  className="input w-full"
                >
                  {reviewFor.items.map((it) => (
                    <option key={it.product_id} value={it.product_id}>{it.title}</option>
                  ))}
                </select>
              )}
              <div>
                <label className="block text-xs text-surface-400 mb-1">{t("shop.reviewRatingLabel")}</label>
                <div className="flex gap-1">
                  {[1, 2, 3, 4, 5].map((n) => (
                    <button key={n} onClick={() => setReviewRating(n)} aria-label={String(n)}>
                      <Star className={`w-6 h-6 ${n <= reviewRating ? "fill-amber-400 text-amber-400" : "text-surface-600"}`} />
                    </button>
                  ))}
                </div>
              </div>
              <textarea
                value={reviewComment}
                onChange={(e) => setReviewComment(e.target.value)}
                rows={3}
                placeholder={t("shop.reviewCommentPh")}
                className="input w-full resize-none"
              />
              <Button onClick={submitReview} disabled={reviewBusy} className="w-full">
                {reviewBusy ? <Loader2 className="w-4 h-4 animate-spin" /> : <Star className="w-4 h-4" />}
                {t("shop.writeReview")}
              </Button>
            </div>
          </div>
        )}

        {/* ── مدیریتِ گونه‌های کالا ────────────────────────────────────────── */}
        {variantManage && (
          <div
            className="fixed inset-0 z-50 bg-black/60 flex items-end sm:items-center justify-center p-0 sm:p-4"
            onClick={() => setVariantManage(null)}
          >
            <div
              className="w-full sm:max-w-sm max-h-[85vh] overflow-y-auto rounded-t-3xl sm:rounded-3xl bg-surface-900 p-4 space-y-3"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center justify-between">
                <span className="text-sm font-semibold text-surface-50">{t("shop.variantsTitle")}</span>
                <button onClick={() => setVariantManage(null)} aria-label={t("chat.close")}>
                  <X className="w-4 h-4 text-surface-400" />
                </button>
              </div>
              <div className="text-xs text-surface-400 truncate">{variantManage.product.title}</div>

              {variantManage.variants === null ? (
                <div className="py-8 flex justify-center">
                  <Loader2 className="w-5 h-5 animate-spin text-surface-500" />
                </div>
              ) : (
                variantManage.variants.map((v) => (
                  <div key={v.id} className="px-3 py-2.5 rounded-xl bg-surface-800 flex items-center justify-between gap-2">
                    <div className="min-w-0">
                      <div className="text-sm text-surface-100 truncate">{v.name}</div>
                      <div className="text-[11px] text-surface-400">
                        {fmtToman(v.price != null ? v.price : variantManage.product.price)} {t("shop.toman")}
                        {" · "}{v.stock === -1 ? t("shop.unlimited") : `${t("shop.stock")}: ${fmtNum(v.stock)}`}
                      </div>
                    </div>
                    <button
                      onClick={() => removeVariant(v)}
                      className="p-2 rounded-lg text-surface-400 hover:text-red-400 hover:bg-red-500/8 transition-colors shrink-0"
                      aria-label={t("shop.remove")}
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                ))
              )}

              <div className="border-t border-surface-800 pt-3 space-y-2">
                <input
                  value={vName}
                  onChange={(e) => setVName(e.target.value)}
                  placeholder={t("shop.variantNamePh")}
                  className="input w-full"
                />
                <input
                  value={vPrice}
                  onChange={(e) => setVPrice(e.target.value)}
                  inputMode="numeric"
                  placeholder={t("shop.variantPriceHint")}
                  className="input w-full"
                  dir="ltr"
                />
                <input
                  value={vStock}
                  onChange={(e) => setVStock(e.target.value)}
                  inputMode="numeric"
                  placeholder={t("shop.pStockPh")}
                  className="input w-full"
                  dir="ltr"
                />
                <Button onClick={submitVariant} disabled={vBusy} className="w-full">
                  {vBusy ? <Loader2 className="w-4 h-4 animate-spin" /> : <Plus className="w-4 h-4" />}
                  {t("shop.manageVariants")}
                </Button>
              </div>
            </div>
          </div>
        )}

        {/* ── مدیریتِ کدهای تخفیفِ کالا ────────────────────────────────────── */}
        {couponManage && (
          <div
            className="fixed inset-0 z-50 bg-black/60 flex items-end sm:items-center justify-center p-0 sm:p-4"
            onClick={() => setCouponManage(null)}
          >
            <div
              className="w-full sm:max-w-sm max-h-[85vh] overflow-y-auto rounded-t-3xl sm:rounded-3xl bg-surface-900 p-4 space-y-3"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center justify-between">
                <span className="text-sm font-semibold text-surface-50">{t("shop.couponsTitle")}</span>
                <button onClick={() => setCouponManage(null)} aria-label={t("chat.close")}>
                  <X className="w-4 h-4 text-surface-400" />
                </button>
              </div>
              <div className="text-xs text-surface-400 truncate">{couponManage.product.title}</div>

              {couponManage.coupons === null ? (
                <div className="py-8 flex justify-center">
                  <Loader2 className="w-5 h-5 animate-spin text-surface-500" />
                </div>
              ) : couponManage.coupons.length === 0 ? (
                <div className="py-4 text-center text-surface-400 text-sm">{t("shop.noCoupons")}</div>
              ) : (
                couponManage.coupons.map((c) => (
                  <div key={c.id} className="px-3 py-2.5 rounded-xl bg-surface-800 flex items-center justify-between gap-2">
                    <div className="min-w-0">
                      <div className="text-sm text-surface-100 truncate" dir="ltr">{c.code}</div>
                      <div className="text-[11px] text-surface-400">
                        {c.discount_type === "percent"
                          ? `${toPersianNum(c.discount_value)}٪`
                          : `${fmtToman(c.discount_value)} ${t("shop.toman")}`}
                        {" · "}{fmtNum(c.used_count)}{c.max_uses ? `/${fmtNum(c.max_uses)}` : ""}
                      </div>
                    </div>
                    <button
                      onClick={() => removeCoupon(c)}
                      className="p-2 rounded-lg text-surface-400 hover:text-red-400 hover:bg-red-500/8 transition-colors shrink-0"
                      aria-label={t("shop.remove")}
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                ))
              )}

              <div className="border-t border-surface-800 pt-3 space-y-2">
                <input
                  value={cCode}
                  onChange={(e) => setCCode(e.target.value)}
                  placeholder={t("shop.couponCodePh")}
                  className="input w-full"
                  dir="ltr"
                />
                <div className="grid grid-cols-2 gap-2">
                  <select
                    value={cType}
                    onChange={(e) => setCType(e.target.value as "percent" | "fixed")}
                    className="input w-full"
                  >
                    <option value="percent">{t("shop.percentOpt")}</option>
                    <option value="fixed">{t("shop.fixedOpt")}</option>
                  </select>
                  <input
                    value={cValue}
                    onChange={(e) => setCValue(e.target.value)}
                    inputMode="numeric"
                    placeholder={t("shop.couponValue")}
                    className="input w-full"
                    dir="ltr"
                  />
                </div>
                <input
                  value={cMaxUses}
                  onChange={(e) => setCMaxUses(e.target.value)}
                  inputMode="numeric"
                  placeholder={t("shop.couponMaxUsesPh")}
                  className="input w-full"
                  dir="ltr"
                />
                <select
                  value={cScope}
                  onChange={(e) => setCScope(e.target.value as "product" | "all")}
                  className="input w-full"
                >
                  <option value="product">{t("shop.scopeThisProduct")}</option>
                  <option value="all">{t("shop.scopeAllProducts")}</option>
                </select>
                <Button onClick={submitCoupon} disabled={cBusy} className="w-full">
                  {cBusy ? <Loader2 className="w-4 h-4 animate-spin" /> : <Plus className="w-4 h-4" />}
                  {t("shop.addCoupon")}
                </Button>
              </div>
            </div>
          </div>
        )}
      </div>
    </AppShell>
  );
}
