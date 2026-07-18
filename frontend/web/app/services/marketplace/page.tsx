"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { api, type ListingOut, type OrderOut, type Identity, isAuthenticated } from "@/lib/api";

const STATUS_LABEL: Record<string, string> = {
  active: "فعال",
  paused: "متوقف",
  draft: "پیش‌نویس",
  archived: "بایگانی",
};

const ORDER_STATUS_LABEL: Record<string, string> = {
  pending: "در انتظارِ پذیرش",
  accepted: "پذیرفته‌شده",
  in_progress: "در حالِ انجام",
  delivered: "تحویل‌شده",
  completed: "تکمیل‌شده",
  cancelled: "لغوشده",
  disputed: "مورد اختلاف",
};

function formatPrice(minor: number, currency: string) {
  if (currency === "IRR") return `${(minor / 10).toLocaleString("fa-IR")} تومان`;
  return `${(minor / 100).toLocaleString("fa-IR")} ${currency}`;
}

export default function MarketplaceFeed() {
  const [listings, setListings] = useState<ListingOut[]>([]);
  const [orders, setOrders] = useState<OrderOut[]>([]);
  const [myEarthId, setMyEarthId] = useState<string | null>(null);
  const [tab, setTab] = useState<"listings" | "orders">("listings");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [keyword, setKeyword] = useState("");
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ title: "", description: "", category: "", base_price: "", delivery_days: "7" });
  const authed = typeof window !== "undefined" && isAuthenticated();

  async function load(kw?: string) {
    setLoading(true);
    setError(null);
    try {
      setListings(await api.marketplace.listListings(kw ? { keyword: kw } : {}));
    } catch {
      setError("بارگذاری فهرستِ خدمات ممکن نشد. ابتدا وارد شوید.");
    } finally {
      setLoading(false);
    }
  }

  async function loadOrders() {
    if (!authed) return;
    try {
      const [ords, me] = await Promise.all([
        api.marketplace.listOrders(),
        api.identity.me() as Promise<Identity>,
      ]);
      setOrders(ords);
      setMyEarthId(me.earth_id);
    } catch {
      // بی‌صدا: کاربر مهمان سفارشی ندارد
    }
  }

  useEffect(() => {
    load();
    loadOrders();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function submit() {
    const price = Number(form.base_price);
    const days = Number(form.delivery_days);
    if (!form.title || !form.description || !form.category || !price) return;
    try {
      const item = await api.marketplace.createListing({
        title: form.title,
        description: form.description,
        category: form.category,
        base_price_minor: Math.round(price * 10),
        currency: "IRR",
        delivery_days: days || 7,
      });
      setListings((prev) => [item, ...prev]);
      setShowForm(false);
      setForm({ title: "", description: "", category: "", base_price: "", delivery_days: "7" });
    } catch {
      setError("ثبتِ خدمت ناموفق بود. ابتدا وارد شوید.");
    }
  }

  async function order(l: ListingOut) {
    if (!authed) {
      setError("برای سفارش ابتدا وارد شوید.");
      return;
    }
    try {
      const o = await api.marketplace.placeOrder({
        listing_id: l.id,
        agreed_price_minor: l.base_price_minor,
        currency: l.currency,
      });
      setOrders((prev) => [o, ...prev.filter((x) => x.id !== o.id)]);
      setNotice("سفارش ثبت شد؛ مبلغ در امانت (escrow) نگه داشته شد.");
      setTab("orders");
    } catch {
      setError("ثبتِ سفارش ناموفق بود (نمی‌توانید از آگهیِ خودتان سفارش دهید).");
    }
  }

  async function act(o: OrderOut, action: "accept" | "deliver" | "complete") {
    setError(null);
    try {
      const fn =
        action === "accept"
          ? api.marketplace.acceptOrder
          : action === "deliver"
            ? api.marketplace.deliverOrder
            : api.marketplace.completeOrder;
      const updated = await fn(o.id);
      setOrders((prev) => prev.map((x) => (x.id === updated.id ? updated : x)));
    } catch {
      setError("انجامِ این عملیات ممکن نشد.");
    }
  }

  function orderActions(o: OrderOut) {
    const isProvider = myEarthId != null && o.provider_earth_id === myEarthId;
    const isBuyer = myEarthId != null && o.buyer_earth_id === myEarthId;
    const btns: React.ReactNode[] = [];
    if (isProvider && o.status === "pending")
      btns.push(<button key="a" className="btn secondary" onClick={() => act(o, "accept")}>پذیرش</button>);
    if (isProvider && (o.status === "accepted" || o.status === "in_progress"))
      btns.push(<button key="d" className="btn secondary" onClick={() => act(o, "deliver")}>تحویل</button>);
    if (isBuyer && o.status === "delivered")
      btns.push(<button key="c" className="btn" onClick={() => act(o, "complete")}>تأیید و تکمیل</button>);
    return btns;
  }

  return (
    <main className="page">
      <div className="row-between">
        <Link href="/services" className="link-btn">
          ← خدمات
        </Link>
        <h1 style={{ fontSize: "1.2rem" }}>بازارگاه</h1>
      </div>
      <p className="muted">خدمات و فریلنسری با کارمزدِ پایین</p>

      {authed && (
        <div className="row" style={{ gap: 8 }}>
          <button
            className={tab === "listings" ? "btn" : "btn secondary"}
            onClick={() => setTab("listings")}
          >
            خدمات
          </button>
          <button
            className={tab === "orders" ? "btn" : "btn secondary"}
            onClick={() => {
              setTab("orders");
              loadOrders();
            }}
          >
            سفارش‌های من
          </button>
        </div>
      )}

      {notice && <div className="card">{notice}</div>}
      {error && <div className="card danger">{error}</div>}

      {tab === "listings" && (
        <>
          <div className="row">
            <input
              className="input"
              placeholder="جستجوی خدمت…"
              value={keyword}
              onChange={(e) => setKeyword(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && load(keyword)}
            />
            <button className="btn secondary" onClick={() => load(keyword)}>
              جستجو
            </button>
          </div>

          {authed && (
            <button className="btn" onClick={() => setShowForm((v) => !v)}>
              {showForm ? "بستن" : "+ ثبتِ خدمت"}
            </button>
          )}

          {showForm && (
            <div className="card">
              <input className="input" placeholder="عنوانِ خدمت" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} />
              <input className="input" placeholder="توضیحات" value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
              <input className="input" placeholder="دسته (مثلاً طراحی)" value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })} />
              <input className="input" type="number" placeholder="قیمتِ پایه (تومان)" value={form.base_price} onChange={(e) => setForm({ ...form, base_price: e.target.value })} />
              <input className="input" type="number" placeholder="روزِ تحویل" value={form.delivery_days} onChange={(e) => setForm({ ...form, delivery_days: e.target.value })} />
              <button className="btn" style={{ marginTop: 8 }} onClick={submit}>
                ثبت
              </button>
            </div>
          )}

          {loading && <p className="muted">در حال بارگذاری…</p>}
          {!loading && !error && listings.length === 0 && <p className="muted">خدمتی ثبت نشده است.</p>}

          {listings.map((l) => (
            <div key={l.id} className="card">
              <div className="row-between">
                <strong>{l.title}</strong>
                <span className="badge">{STATUS_LABEL[l.status] ?? l.status}</span>
              </div>
              <p className="muted">{l.description}</p>
              <div className="row-between">
                <span className="muted">{l.category} · تحویل {l.delivery_days.toLocaleString("fa-IR")} روز</span>
                <strong>{formatPrice(l.base_price_minor, l.currency)}</strong>
              </div>
              {authed && (
                <button className="btn" style={{ marginTop: 8 }} onClick={() => order(l)}>
                  سفارش
                </button>
              )}
            </div>
          ))}
        </>
      )}

      {tab === "orders" && (
        <>
          {orders.length === 0 && <p className="muted">هنوز سفارشی ندارید.</p>}
          {orders.map((o) => {
            const role = myEarthId === o.provider_earth_id ? "فروشنده" : "خریدار";
            return (
              <div key={o.id} className="card">
                <div className="row-between">
                  <strong>سفارش #{o.id.slice(0, 8)}…</strong>
                  <span className="badge">{ORDER_STATUS_LABEL[o.status] ?? o.status}</span>
                </div>
                <div className="row-between">
                  <span className="muted">نقشِ شما: {role}</span>
                  <strong>{formatPrice(o.agreed_price_minor, o.currency)}</strong>
                </div>
                <div className="row" style={{ gap: 8, marginTop: 8 }}>
                  {orderActions(o)}
                </div>
              </div>
            );
          })}
        </>
      )}
    </main>
  );
}
