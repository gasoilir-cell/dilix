"use client";

import { useState } from "react";
import { api, type NearbyPerson } from "@/lib/api";
import { t } from "@/lib/i18n";

// نقشه‌ی کره‌ی 3D امضای محصول است (CesiumJS/Mapbox) و به‌صورت تنبل بارگذاری می‌شود.
// این صفحه نمای فهرستیِ کشف opt-in را با حریم خصوصی (fuzzed) ارائه می‌دهد.
const DEFAULT_BBOX = "50.5,35.0,52.0,36.5"; // محدوده‌ی تهران (نمونه)

export default function EarthDiscovery() {
  const tr = t("fa");
  const [people, setPeople] = useState<NearbyPerson[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [entityType, setEntityType] = useState("");
  const [profession, setProfession] = useState("");

  async function search() {
    setLoading(true);
    setError(null);
    try {
      setPeople(
        await api.discovery.nearby({
          bbox: DEFAULT_BBOX,
          entity_type: entityType || undefined,
          profession: profession || undefined,
          limit: 50,
        }),
      );
    } catch {
      setError("جست‌وجو ممکن نشد. اتصال به سرور را بررسی کنید.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="page">
      <h1>{tr.earth_title}</h1>
      <p className="muted">{tr.earth_privacy}</p>

      <div className="globe-placeholder card" aria-hidden>
        🌍
        <span className="muted">کره‌ی سه‌بعدی هنگام اجرا بارگذاری می‌شود</span>
      </div>

      <div className="card">
        <div className="row" style={{ gap: 8, flexWrap: "wrap" }}>
          <select className="input" value={entityType} onChange={(e) => setEntityType(e.target.value)}>
            <option value="">همه</option>
            <option value="individual">افراد</option>
            <option value="business">کسب‌وکار</option>
          </select>
          <input
            className="input"
            value={profession}
            onChange={(e) => setProfession(e.target.value)}
            placeholder="شغل (اختیاری)"
            aria-label="فیلتر شغل"
          />
          <button className="btn" onClick={search} disabled={loading}>
            جست‌وجو
          </button>
        </div>
      </div>

      {loading && <p className="muted">در حال بارگذاری…</p>}
      {error && <div className="card danger">{error}</div>}
      {!loading && !error && people.length === 0 && (
        <p className="muted">برای دیدن کاربرانِ opt-in، جست‌وجو کنید.</p>
      )}

      {people.map((p) => (
        <div key={p.earth_id} className="card row-between">
          <div>
            <strong>{p.display_name ?? "کاربر"}</strong>
            <div className="muted">
              {p.profession ?? "—"} · دقت موقعیت: {p.geo_precision}
            </div>
          </div>
          <button className="btn secondary" onClick={() => api.discovery.contactRequest(p.earth_id, "سلام")}>
            گفتگو
          </button>
        </div>
      ))}
    </main>
  );
}
