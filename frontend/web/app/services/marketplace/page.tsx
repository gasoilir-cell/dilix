"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { api, type ListingOut, isAuthenticated } from "@/lib/api";

const STATUS_LABEL: Record<string, string> = {
  active: "فعال",
  paused: "متوقف",
  draft: "پیش‌نویس",
  archived: "بایگانی",
};

function formatPrice(minor: number, currency: string) {
  if (currency === "IRR") return `${(minor / 10).toLocaleString("fa-IR")} تومان`;
  return `${(minor / 100).toLocaleString("fa-IR")} ${currency}`;
}

export default function MarketplaceFeed() {
  const [listings, setListings] = useState<ListingOut[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
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

  useEffect(() => {
    load();
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

  return (
    <main className="page">
      <div className="row-between">
        <Link href="/services" className="link-btn">
          ← خدمات
        </Link>
        <h1 style={{ fontSize: "1.2rem" }}>بازارگاه</h1>
      </div>
      <p className="muted">خدمات و فریلنسری با کارمزدِ پایین</p>

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
      {error && <div className="card danger">{error}</div>}
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
        </div>
      ))}
    </main>
  );
}
