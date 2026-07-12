"use client";

import { useState } from "react";
import Link from "next/link";
import { api, type NearbyPerson, isAuthenticated } from "@/lib/api";

// bbox = min_lat,min_lon,max_lat,max_lon (پیش‌فرض: محدوده‌ی تهران)
const DEFAULT_BBOX = "35.5,51.2,35.85,51.6";

export default function DiscoveryFeed() {
  const [people, setPeople] = useState<NearbyPerson[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [bbox, setBbox] = useState(DEFAULT_BBOX);
  const [profession, setProfession] = useState("");
  const [sentTo, setSentTo] = useState<Record<string, boolean>>({});
  const authed = typeof window !== "undefined" && isAuthenticated();

  async function load() {
    if (!authed) {
      setError("برای جستجوی اطراف ابتدا وارد شوید.");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      setPeople(await api.discovery.nearby({ bbox, profession: profession || undefined }));
    } catch {
      setError("بارگذاری فهرستِ اطراف ممکن نشد.");
    } finally {
      setLoading(false);
    }
  }

  async function contact(earthId: string) {
    try {
      await api.discovery.contactRequest(earthId, "سلام، مایلم در ارتباط باشیم.");
      setSentTo((prev) => ({ ...prev, [earthId]: true }));
    } catch {
      setError("ارسالِ درخواستِ ارتباط ناموفق بود.");
    }
  }

  return (
    <main className="page">
      <div className="row-between">
        <Link href="/services" className="link-btn">
          ← خدمات
        </Link>
        <h1 style={{ fontSize: "1.2rem" }}>کشفِ اطراف</h1>
      </div>
      <p className="muted">یافتنِ افراد و کسب‌وکارهای نزدیک بر پایه‌ی موقعیت</p>

      {!authed && <div className="card danger">برای جستجوی اطراف ابتدا وارد شوید.</div>}

      <div className="card">
        <input className="input" placeholder="bbox: min_lat,min_lon,max_lat,max_lon" value={bbox} onChange={(e) => setBbox(e.target.value)} />
        <input className="input" placeholder="حرفه (اختیاری)" value={profession} onChange={(e) => setProfession(e.target.value)} />
        <button className="btn" style={{ marginTop: 8 }} disabled={!authed || loading} onClick={load}>
          جستجو
        </button>
      </div>

      {loading && <p className="muted">در حال بارگذاری…</p>}
      {error && <div className="card danger">{error}</div>}
      {!loading && !error && people.length === 0 && <p className="muted">کسی در این محدوده یافت نشد.</p>}

      {people.map((p) => (
        <div key={p.earth_id} className="card">
          <div className="row-between">
            <strong>{p.display_name ?? "کاربرِ ناشناس"}</strong>
            <span className="badge">{p.entity_type}</span>
          </div>
          <div className="muted">
            {p.profession ?? "—"}
            {p.age_range ? ` · ${p.age_range}` : ""}
            {p.languages?.length ? ` · ${p.languages.join("، ")}` : ""}
          </div>
          <button className="btn secondary" style={{ marginTop: 8 }} disabled={sentTo[p.earth_id]} onClick={() => contact(p.earth_id)}>
            {sentTo[p.earth_id] ? "درخواست ارسال شد" : "درخواستِ ارتباط"}
          </button>
        </div>
      ))}
    </main>
  );
}
