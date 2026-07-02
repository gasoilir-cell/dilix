"use client";

import { useEffect, useRef, useState } from "react";
import { Filter, Search, X, Star, ShieldCheck, MessageCircle, Handshake, Loader2 } from "lucide-react";
import BottomNav from "@/components/layout/BottomNav";
import { cn } from "@/lib/utils";
import { useRouter } from "next/navigation";

// ─── Types ───────────────────────────────────────────────────
interface EarthUser {
  earth_id: string;
  name:     string;
  role:     string;
  country_code: string;
  lat:      number;
  lng:      number;
  rating:   number;
  kyc_level:number;
  avatar_url?: string;
}

// ─── Role helpers ─────────────────────────────────────────────
const ROLE_COLOR: Record<string,string> = {
  driver:"#f59e0b", cargo_owner:"#06b6d4", freight_broker:"#8b5cf6",
  insurance_agent:"#10b981", creator:"#f43f5e", admin:"#ec4899", user:"#6366f1",
};
const ROLE_LABEL: Record<string,string> = {
  driver:"راننده", cargo_owner:"صاحب بار", freight_broker:"کارگزار حمل",
  insurance_agent:"نماینده بیمه", creator:"بازاریاب / سازنده", admin:"مدیر", user:"کاربر",
};
const ROLE_EMOJI: Record<string,string> = {
  driver:"🚛", cargo_owner:"📦", freight_broker:"🤝",
  insurance_agent:"🛡️", creator:"📢", admin:"⚙️", user:"👤",
};
const rc  = (r:string) => ROLE_COLOR[r]  ?? "#6366f1";
const rl  = (r:string) => ROLE_LABEL[r] ?? "کاربر";
const rem = (r:string) => ROLE_EMOJI[r] ?? "👤";

// ─── Demo Users ───────────────────────────────────────────────
const DEMO_USERS: EarthUser[] = [
  { earth_id:"DLX-DEMO001", name:"احمد رضایی",          role:"driver",          country_code:"IRN", lat:35.69,  lng:51.39,  rating:4.8, kyc_level:2 },
  { earth_id:"DLX-DEMO002", name:"شرکت فراز لجستیک",    role:"cargo_owner",     country_code:"IRN", lat:32.43,  lng:53.69,  rating:4.5, kyc_level:3 },
  { earth_id:"DLX-DEMO003", name:"محمد علوی",            role:"user",            country_code:"IRN", lat:29.59,  lng:52.58,  rating:4.2, kyc_level:1 },
  { earth_id:"DLX-DEMO004", name:"سارا کریمی",           role:"driver",          country_code:"IRN", lat:36.29,  lng:59.60,  rating:4.9, kyc_level:2 },
  { earth_id:"DLX-DEMO005", name:"نیلوفر صادقی",         role:"creator",         country_code:"IRN", lat:33.34,  lng:44.40,  rating:4.6, kyc_level:1 },
  { earth_id:"DLX-DEMO006", name:"حسین محمدی",           role:"insurance_agent", country_code:"IRN", lat:34.08,  lng:49.70,  rating:4.7, kyc_level:3 },
  { earth_id:"DLX-DEMO007", name:"زهرا موسوی",           role:"user",            country_code:"IRN", lat:37.28,  lng:49.59,  rating:4.3, kyc_level:0 },
  { earth_id:"DLX-DEMO008", name:"مهدی تهرانی",          role:"freight_broker",  country_code:"IRN", lat:31.32,  lng:48.67,  rating:4.4, kyc_level:2 },
  { earth_id:"DLX-DEMO010", name:"Ali Hassan",            role:"driver",          country_code:"ARE", lat:25.20,  lng:55.27,  rating:4.7, kyc_level:2 },
  { earth_id:"DLX-DEMO011", name:"Mehmet Yilmaz",         role:"cargo_owner",     country_code:"TUR", lat:41.01,  lng:28.97,  rating:4.5, kyc_level:1 },
  { earth_id:"DLX-DEMO012", name:"Sarah Klein",           role:"creator",         country_code:"DEU", lat:52.52,  lng:13.40,  rating:4.9, kyc_level:3 },
  { earth_id:"DLX-DEMO013", name:"James Wilson",          role:"user",            country_code:"GBR", lat:51.50,  lng:-0.12,  rating:4.3, kyc_level:1 },
  { earth_id:"DLX-DEMO014", name:"Kenji Tanaka",          role:"freight_broker",  country_code:"JPN", lat:35.68,  lng:139.69, rating:4.8, kyc_level:3 },
  { earth_id:"DLX-DEMO015", name:"Raj Patel",             role:"user",            country_code:"IND", lat:19.08,  lng:72.88,  rating:4.1, kyc_level:1 },
  { earth_id:"DLX-DEMO016", name:"Carlos Mendez",         role:"driver",          country_code:"MEX", lat:19.43,  lng:-99.13, rating:4.6, kyc_level:2 },
  { earth_id:"DLX-DEMO017", name:"Chen Wei",              role:"cargo_owner",     country_code:"CHN", lat:31.23,  lng:121.47, rating:4.7, kyc_level:2 },
  { earth_id:"DLX-DEMO018", name:"Sofia Petrov",          role:"creator",         country_code:"RUS", lat:55.75,  lng:37.62,  rating:4.5, kyc_level:1 },
  { earth_id:"DLX-DEMO019", name:"Nour Al-Rashid",        role:"insurance_agent", country_code:"SAU", lat:24.69,  lng:46.72,  rating:4.4, kyc_level:2 },
  { earth_id:"DLX-DEMO020", name:"Amir Sultanov",         role:"driver",          country_code:"KAZ", lat:51.18,  lng:71.45,  rating:4.3, kyc_level:1 },
  { earth_id:"DLX-DEMO021", name:"Emma Johansson",        role:"user",            country_code:"SWE", lat:59.33,  lng:18.07,  rating:4.6, kyc_level:1 },
  { earth_id:"DLX-DEMO022", name:"Lucas Dupont",          role:"freight_broker",  country_code:"FRA", lat:48.86,  lng:2.35,   rating:4.5, kyc_level:2 },
  { earth_id:"DLX-DEMO023", name:"Amira Mansour",         role:"creator",         country_code:"EGY", lat:30.04,  lng:31.24,  rating:4.7, kyc_level:1 },
  { earth_id:"DLX-DEMO024", name:"Park Jiwoo",            role:"user",            country_code:"KOR", lat:37.57,  lng:126.98, rating:4.4, kyc_level:0 },
  { earth_id:"DLX-DEMO025", name:"Elena Kovacs",          role:"insurance_agent", country_code:"HUN", lat:47.50,  lng:19.04,  rating:4.6, kyc_level:2 },
];

const ROLES = ["همه","driver","cargo_owner","freight_broker","insurance_agent","creator","user"] as const;

export default function EarthPage() {
  const router   = useRouter();
  const mapRef   = useRef<HTMLDivElement>(null);
  const mapInst  = useRef<any>(null);
  const markersRef = useRef<any[]>([]);
  const markerEls  = useRef<Map<string,HTMLElement>>(new Map());

  const [mapReady,  setMapReady]  = useState(false);
  const [mapError,  setMapError]  = useState(false);
  const [selected,  setSelected]  = useState<EarthUser|null>(null);
  const [search,    setSearch]    = useState("");
  const [roleFilter,setRoleFilter]= useState("همه");
  const [showFilter,setShowFilter]= useState(false);

  const filtered = DEMO_USERS.filter(u =>
    (roleFilter === "همه" || u.role === roleFilter) &&
    (search === "" || u.name.toLowerCase().includes(search.toLowerCase()) || u.earth_id.toLowerCase().includes(search.toLowerCase()))
  );

  // ── به‌روزرسانی visibility markers ──────────────────────────
  useEffect(() => {
    markerEls.current.forEach((el) => { el.style.display = "none"; });
    filtered.forEach(u => {
      const el = markerEls.current.get(u.earth_id);
      if (el) el.style.display = "block";
    });
  }, [search, roleFilter]);

  const flyTo = (u: EarthUser) => {
    setSelected(u);
    mapInst.current?.flyTo({ center:[u.lng, u.lat], zoom: Math.max(mapInst.current.getZoom(), 5), duration: 1000 });
  };

  // ── Init MapLibre با Vector style (کاملاً offline) ──────────
  useEffect(() => {
    const win = window as any;

    const initMap = () => {
      if (!win.maplibregl || !mapRef.current) return;
      const mgl = win.maplibregl;

      // ── Style کاملاً offline (بدون tile/glyph خارجی) ───────
      const offlineStyle = {
        version: 8 as const,
        // بدون glyphs — از custom HTML برای labels استفاده می‌کنیم
        sources: {
          countries: {
            type: "geojson" as const,
            data: "/libs/countries.geojson",
          },
        },
        layers: [
          // فضا / پس‌زمینه
          { id: "background", type: "background" as const,
            paint: { "background-color": "#050d1a" } },
          // اقیانوس‌ها — با gradient
          { id: "ocean-deep", type: "background" as const,
            paint: { "background-color": "#071524" } },
          // کشورها
          { id: "countries-fill", type: "fill" as const,
            source: "countries",
            paint: {
              "fill-color": [
                "match", ["get","iso"],
                "IRN","#0f2035",  "TUR","#0d1e30", "ARE","#0e1f32",
                "SAU","#0e2030", "IND","#0d1f33", "CHN","#0c1e31",
                "RUS","#0d1d2e", "DEU","#0e2034", "GBR","#0d1e31",
                "FRA","#0e1f33", "JPN","#0d1e30", "KOR","#0c1d2f",
                "USA","#0e2035", "MEX","#0d1f32", "BRA","#0d1e31",
                "#111f30"  // default
              ] as any,
              "fill-opacity": 0.9,
            }
          },
          // مرزها
          { id: "countries-border", type: "line" as const,
            source: "countries",
            paint: {
              "line-color": "#1e3a5f",
              "line-width": 0.7,
              "line-opacity": 0.8,
            }
          },
          // highlight border برای hover
          { id: "countries-border-hover", type: "line" as const,
            source: "countries",
            paint: {
              "line-color": "#6366f1",
              "line-width": 1.5,
              "line-opacity": 0,
            }
          },
        ],
      };

      const map = new mgl.Map({
        container: mapRef.current,
        style: offlineStyle,
        center: [30, 30],
        zoom: 2,
        minZoom: 1,
        maxZoom: 16,
        projection: { type: "globe" },
        attributionControl: false,
        logoPosition: "bottom-right",
      });

      // fog — اتمسفر
      map.on("style.load", () => {
        map.setFog({
          color: "rgba(8,15,30,0.9)",
          "high-color": "rgba(3,8,20,0.95)",
          "horizon-blend": 0.03,
          "space-color": "#000510",
          "star-intensity": 0.6,
        });
        setMapReady(true);
        mapInst.current = map;
        addMarkers(mgl, map);
      });

      // Fallback — اگه style.load در ۵ ثانیه نیومد
      setTimeout(() => {
        if (!mapInst.current) {
          setMapReady(true);
          mapInst.current = map;
          addMarkers(mgl, map);
        }
      }, 5000);

      map.on("error", (e: any) => {
        console.warn("Map error:", e);
        // error در tile/glyph رو ignore می‌کنیم
      });

      return map;
    };

    const addMarkers = (mgl: any, map: any) => {
      // marker style
      const style = document.createElement("style");
      style.textContent = `
        .dlx-marker { cursor:pointer; transition:transform .15s; }
        .dlx-marker:hover { transform:scale(1.6) !important; }
        @keyframes dlx-pulse {
          0%,100%{ box-shadow:0 0 0 0 var(--mc,#6366f1); }
          50%{ box-shadow:0 0 0 5px transparent; }
        }
        .dlx-pulse { animation: dlx-pulse 2s infinite; }
      `;
      document.head.appendChild(style);

      DEMO_USERS.forEach(u => {
        const el = document.createElement("div");
        el.className = "dlx-marker dlx-pulse";
        const color = rc(u.role);
        el.style.cssText = `--mc:${color};`;

        if (u.avatar_url) {
          el.style.cssText += `
            width:22px; height:22px; border-radius:50%;
            border:2.5px solid ${color};
            box-shadow:0 0 8px ${color}99;
            overflow:hidden; background:#1e293b;
          `;
          const img = document.createElement("img");
          img.src = u.avatar_url;
          img.style.cssText = "width:100%;height:100%;object-fit:cover;border-radius:50%;";
          el.appendChild(img);
        } else {
          el.style.cssText += `
            width:12px; height:12px; border-radius:50%;
            background:${color};
            border:2px solid rgba(255,255,255,0.8);
            box-shadow:0 0 8px ${color}aa;
          `;
        }

        el.addEventListener("click", () => flyTo(u));

        const marker = new mgl.Marker({ element: el, anchor: "center" })
          .setLngLat([u.lng, u.lat])
          .addTo(map);

        markerEls.current.set(u.earth_id, el);
        markersRef.current.push(marker);
      });
    };

    // اگه MapLibre قبلاً لود شده
    if (win.maplibregl) {
      initMap();
      return;
    }

    // لود CSS
    const link = document.createElement("link");
    link.rel  = "stylesheet";
    link.href = "/libs/maplibre-gl.css";
    document.head.appendChild(link);

    // لود JS
    const script = document.createElement("script");
    script.src = "/libs/maplibre-gl.js";
    script.async = true;
    script.onload = () => initMap();
    script.onerror = () => setMapError(true);
    document.head.appendChild(script);

    return () => {
      markersRef.current.forEach(m => m.remove());
      markersRef.current = [];
      markerEls.current.clear();
      mapInst.current?.remove();
      mapInst.current = null;
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div className="relative overflow-hidden bg-black" style={{ height:"100dvh" }}>
      {/* ─── Map ─── */}
      <div ref={mapRef} className="absolute inset-0 w-full h-full" />

      {/* ─── Loading (BottomNav روی آن نمایش داده می‌شه) ─── */}
      {!mapReady && !mapError && (
        <div className="absolute inset-0 flex items-center justify-center bg-[#050d1a]" style={{zIndex:20}}>
          <div className="text-center">
            <div className="relative w-16 h-16 mx-auto mb-4">
              <div className="absolute inset-0 rounded-full border-2 border-primary-500/30 animate-ping" />
              <div className="w-16 h-16 rounded-full border-2 border-primary-500 flex items-center justify-center">
                <span className="text-2xl">🌍</span>
              </div>
            </div>
            <p className="text-surface-300 text-sm font-medium">در حال بارگذاری کره زمین...</p>
            <p className="text-surface-600 text-xs mt-1">منتظر باش</p>
          </div>
        </div>
      )}

      {/* ─── Error ─── */}
      {mapError && (
        <div className="absolute inset-0 flex items-center justify-center bg-[#050d1a]" style={{zIndex:20}}>
          <div className="text-center px-8">
            <p className="text-3xl mb-3">⚠️</p>
            <p className="text-white font-semibold">نقشه لود نشد</p>
            <p className="text-surface-400 text-xs mt-2">اتصال اینترنت را بررسی کنید</p>
            <button onClick={() => window.location.reload()}
              className="mt-4 px-4 py-2 rounded-xl bg-primary-600 text-white text-sm">
              تلاش مجدد
            </button>
          </div>
        </div>
      )}

      {/* ─── Top bar ─── */}
      <div className="absolute top-0 inset-x-0 p-3 pointer-events-none" style={{zIndex:30}}>
        <div className="flex items-center gap-2 pointer-events-auto">
          <div className="relative flex-1">
            <Search size={14} className="absolute right-3 top-1/2 -translate-y-1/2 text-surface-400" />
            <input
              value={search}
              onChange={e => setSearch(e.target.value)}
              placeholder="جستجوی نام یا Earth ID..."
              className="w-full bg-surface-950/90 backdrop-blur border border-surface-700/60 rounded-xl pr-9 pl-4 py-2.5 text-sm text-surface-100 placeholder-surface-500 focus:outline-none focus:border-primary-500"
              style={{ direction:"rtl" }}
            />
          </div>
          <button
            onClick={() => setShowFilter(f => !f)}
            className={cn(
              "flex-shrink-0 p-2.5 rounded-xl border backdrop-blur transition-all",
              showFilter
                ? "bg-primary-600 border-primary-500 text-white"
                : "bg-surface-950/90 border-surface-700/60 text-surface-400"
            )}
          >
            <Filter size={18} />
          </button>
        </div>

        {/* فیلتر نقش */}
        {showFilter && (
          <div className="flex gap-2 mt-2 overflow-x-auto pb-1 no-scrollbar">
            {ROLES.map(r => (
              <button
                key={r}
                onClick={() => setRoleFilter(r)}
                className={cn(
                  "flex-shrink-0 text-xs px-3 py-1.5 rounded-full border transition-all whitespace-nowrap",
                  roleFilter === r
                    ? "bg-primary-600 border-primary-500 text-white"
                    : "bg-surface-950/80 border-surface-700 text-surface-400 hover:border-surface-500"
                )}
              >
                {r === "همه" ? `همه (${DEMO_USERS.length})` : `${rem(r)} ${rl(r)}`}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* ─── User card (selected) ─── */}
      {selected && (
        <div className="absolute inset-x-3 pointer-events-auto" style={{ bottom:"80px", zIndex:30 }}>
          <div className="bg-surface-900/95 backdrop-blur-md rounded-2xl border border-surface-700/60 p-4 shadow-2xl">
            <div className="flex items-start gap-3">
              <div className="w-12 h-12 rounded-full flex items-center justify-center text-2xl flex-shrink-0 border-2 overflow-hidden"
                style={{ borderColor:`${rc(selected.role)}60`, background:`${rc(selected.role)}18` }}>
                {selected.avatar_url
                  ? <img src={selected.avatar_url} className="w-full h-full object-cover" alt={selected.name} />
                  : rem(selected.role)}
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 flex-wrap">
                  <p className="text-white font-bold text-sm truncate">{selected.name}</p>
                  {selected.kyc_level >= 2 && <ShieldCheck size={14} className="text-accent-400 flex-shrink-0" />}
                </div>
                <p className="text-surface-500 font-mono text-[11px]">{selected.earth_id}</p>
                <div className="flex items-center gap-2 mt-1 flex-wrap">
                  <span className="text-xs px-2 py-0.5 rounded-full font-medium"
                    style={{ background:`${rc(selected.role)}20`, color:rc(selected.role) }}>
                    {rl(selected.role)}
                  </span>
                  <div className="flex items-center gap-1">
                    <Star size={11} className="text-amber-400 fill-amber-400" />
                    <span className="text-xs text-surface-400">{selected.rating}</span>
                  </div>
                </div>
              </div>
              <button onClick={() => setSelected(null)} className="p-1 text-surface-500 hover:text-white flex-shrink-0">
                <X size={18} />
              </button>
            </div>
            <div className="flex gap-2 mt-3">
              <button
                onClick={() => router.push(`/messages/${selected.earth_id}`)}
                className="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl text-white text-sm font-semibold transition-all hover:opacity-90 active:scale-95"
                style={{ background: rc(selected.role) }}
              >
                <MessageCircle size={16} />
                شروع گفتگو
              </button>
              <button
                onClick={() => router.push(`/messages/${selected.earth_id}?type=collaboration`)}
                className="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl text-sm font-semibold border transition-all hover:bg-surface-800 active:scale-95"
                style={{ borderColor:`${rc(selected.role)}50`, color:rc(selected.role) }}
              >
                <Handshake size={16} />
                همکاری
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ─── User list (bottom strip) ─── */}
      {!selected && (
        <div className="absolute inset-x-0 pointer-events-auto" style={{ bottom:"60px", zIndex:30 }}>
          <div className="flex gap-2 overflow-x-auto px-3 pb-2 no-scrollbar">
            {filtered.slice(0, 12).map(u => (
              <button
                key={u.earth_id}
                onClick={() => flyTo(u)}
                className="flex-shrink-0 w-24 bg-surface-900/90 backdrop-blur border border-surface-700/50 rounded-xl p-2 text-right hover:border-surface-500 active:scale-95 transition-all"
              >
                <div className="flex items-center gap-1.5 mb-1">
                  {u.avatar_url
                    ? <img src={u.avatar_url} className="w-5 h-5 rounded-full object-cover flex-shrink-0 border"
                        style={{borderColor:rc(u.role)}} alt={u.name} />
                    : <div className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{backgroundColor:rc(u.role)}} />}
                  <p className="text-white text-[11px] font-semibold truncate">{u.name.split(" ")[0]}</p>
                </div>
                <p className="text-[9px] font-medium" style={{color:rc(u.role)}}>{rl(u.role)}</p>
                <div className="flex items-center gap-0.5 mt-0.5">
                  <Star size={8} className="text-amber-400 fill-amber-400" />
                  <p className="text-[9px] text-surface-400">{u.rating}</p>
                </div>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* ─── BottomNav (همیشه روی همه چیز) ─── */}
      <div style={{ position:"absolute", bottom:0, left:0, right:0, zIndex:50 }}>
        <BottomNav />
      </div>
    </div>
  );
}
