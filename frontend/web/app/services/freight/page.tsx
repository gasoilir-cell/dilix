"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { api, type CargoPostOut, isAuthenticated } from "@/lib/api";

const STATUS_LABEL: Record<string, string> = {
  open: "باز",
  matched: "تطبیق‌یافته",
  in_transit: "در مسیر",
  delivered: "تحویل‌شده",
  settled: "تسویه‌شده",
  cancelled: "لغوشده",
};

export default function FreightFeed() {
  const [cargo, setCargo] = useState<CargoPostOut[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ title: "", origin: "", destination: "", weight_kg: "" });
  const authed = typeof window !== "undefined" && isAuthenticated();

  async function load() {
    setLoading(true);
    setError(null);
    try {
      setCargo(await api.freight.listCargo());
    } catch {
      setError("بارگذاری فهرستِ بار ممکن نشد.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
  }, []);

  async function submit() {
    const weight = Number(form.weight_kg);
    if (!form.title || !form.origin || !form.destination || !weight) return;
    try {
      const c = await api.freight.createCargo({
        title: form.title,
        origin: form.origin,
        destination: form.destination,
        weight_grams: Math.round(weight * 1000),
        currency: "IRR",
      });
      setCargo((prev) => [c, ...prev]);
      setShowForm(false);
      setForm({ title: "", origin: "", destination: "", weight_kg: "" });
    } catch {
      setError("ثبتِ بار ناموفق بود. ابتدا وارد شوید.");
    }
  }

  return (
    <main className="page">
      <div className="row-between">
        <Link href="/services" className="link-btn">
          ← خدمات
        </Link>
        <h1 style={{ fontSize: "1.2rem" }}>اسنپِ بار</h1>
      </div>
      <p className="muted">ثبتِ بار، تطبیقِ راننده، بارنامه (راهداری) و ردیابیِ زنده</p>

      {authed && (
        <button className="btn" onClick={() => setShowForm((v) => !v)}>
          {showForm ? "بستن" : "+ ثبتِ بار"}
        </button>
      )}

      {showForm && (
        <div className="card">
          <input className="input" placeholder="عنوانِ بار" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} />
          <input className="input" placeholder="مبدأ" value={form.origin} onChange={(e) => setForm({ ...form, origin: e.target.value })} />
          <input className="input" placeholder="مقصد" value={form.destination} onChange={(e) => setForm({ ...form, destination: e.target.value })} />
          <input className="input" type="number" placeholder="وزن (کیلوگرم)" value={form.weight_kg} onChange={(e) => setForm({ ...form, weight_kg: e.target.value })} />
          <button className="btn" style={{ marginTop: 8 }} onClick={submit}>
            ثبت
          </button>
        </div>
      )}

      {loading && <p className="muted">در حال بارگذاری…</p>}
      {error && <div className="card danger">{error}</div>}
      {!loading && !error && cargo.length === 0 && <p className="muted">باری ثبت نشده است.</p>}

      {cargo.map((c) => (
        <div key={c.id} className="card">
          <div className="row-between">
            <strong>{c.title}</strong>
            <span className="badge">{STATUS_LABEL[c.status] ?? c.status}</span>
          </div>
          <div className="muted">
            {c.origin} ← {c.destination} · {(c.weight_grams / 1000).toLocaleString("fa-IR")} کیلوگرم
          </div>
        </div>
      ))}
    </main>
  );
}
