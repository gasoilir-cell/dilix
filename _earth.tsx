"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  Search, Filter, Star, ShieldCheck, MessageCircle,
  Handshake, X, Users, ChevronRight, MapPin, Navigation,
} from "lucide-react";
import BottomNav from "@/components/layout/BottomNav";
import { useRouter } from "next/navigation";
import { toPersianNum } from "@/lib/utils";
import { earthApi } from "@/lib/api";
import toast from "react-hot-toast";

// ── Role metadata ──────────────────────────────────────────────────────────────
const ROLE_COLOR: Record<string, string> = {
  driver: "#F59E0B", cargo_owner: "#06B6D4", freight_broker: "#A855F7",
  insurance_agent: "#10B981", creator: "#F43F5E", admin: "#EC4899", user: "#6366F1",
};
const ROLE_LABEL: Record<string, string> = {
  driver: "راننده", cargo_owner: "صاحب بار", freight_broker: "کارگزار حمل",
  insurance_agent: "نماینده بیمه", creator: "بازاریاب / سازنده", admin: "مدیر", user: "کاربر",
};
const ROLE_EMOJI: Record<string, string> = {
  driver: "🚛", cargo_owner: "📦", freight_broker: "🤝",
  insurance_agent: "🛡️", creator: "📢", admin: "⚙️", user: "👤",
};
const rc  = (r: string) => ROLE_COLOR[r]  ?? "#6366F1";
const rl  = (r: string) => ROLE_LABEL[r] ?? "کاربر";
const rem = (r: string) => ROLE_EMOJI[r] ?? "👤";

// کلیدِ ذخیرهٔ تصمیمِ اتصالِ دائم در مرورگر
const GEO_CONSENT_KEY = "dilix_geo_consent";

// ── Types ─────────────────────────────────────────────────────────────────────
interface EarthUser {
  earth_id: string; name: string; role: string;
  lat: number; lng: number; rating: number;
  kyc_level: number; avatar_url?: string; online?: boolean; city?: string;
}
interface Cluster {
  id: string; lat: number; lng: number;
  count: number; members: EarthUser[]; dominant_role: string;
}
type DrawerState =
  | { type: "user";    user: EarthUser }
  | { type: "cluster"; cluster: Cluster };

// ── Demo data ─────────────────────────────────────────────────────────────────
const DEMO: EarthUser[] = [
  { earth_id:"DLX-DEMO001", name:"احمد رضایی",        role:"driver",          lat:35.69,  lng:51.39,  rating:4.8, kyc_level:2, online:true  },
  { earth_id:"DLX-DEMO002", name:"شرکت فراز لجستیک",  role:"cargo_owner",     lat:32.43,  lng:53.69,  rating:4.5, kyc_level:3, online:false },
  { earth_id:"DLX-DEMO003", name:"محمد علوی",          role:"user",            lat:29.59,  lng:52.58,  rating:4.2, kyc_level:1, online:true  },
  { earth_id:"DLX-DEMO004", name:"سارا کریمی",         role:"driver",          lat:36.29,  lng:59.60,  rating:4.9, kyc_level:2, online:true  },
  { earth_id:"DLX-DEMO005", name:"نیلوفر صادقی",       role:"creator",         lat:33.34,  lng:44.40,  rating:4.6, kyc_level:1, online:false },
  { earth_id:"DLX-DEMO006", name:"حسین محمدی",         role:"insurance_agent", lat:34.08,  lng:49.70,  rating:4.7, kyc_level:3, online:true  },
  { earth_id:"DLX-DEMO007", name:"زهرا موسوی",         role:"user",            lat:37.28,  lng:49.59,  rating:4.3, kyc_level:0, online:false },
  { earth_id:"DLX-DEMO008", name:"مهدی تهرانی",        role:"freight_broker",  lat:31.32,  lng:48.67,  rating:4.4, kyc_level:2, online:true  },
  { earth_id:"DLX-DEMO010", name:"Ali Hassan",          role:"driver",          lat:25.20,  lng:55.27,  rating:4.7, kyc_level:2, online:true  },
  { earth_id:"DLX-DEMO011", name:"Mehmet Yilmaz",       role:"cargo_owner",     lat:41.01,  lng:28.97,  rating:4.5, kyc_level:1, online:false },
  { earth_id:"DLX-DEMO012", name:"Sarah Klein",         role:"creator",         lat:52.52,  lng:13.40,  rating:4.9, kyc_level:3, online:true  },
  { earth_id:"DLX-DEMO013", name:"James Wilson",        role:"user",            lat:51.50,  lng:-0.12,  rating:4.3, kyc_level:1, online:false },
  { earth_id:"DLX-DEMO014", name:"Kenji Tanaka",        role:"freight_broker",  lat:35.68,  lng:139.69, rating:4.8, kyc_level:3, online:true  },
  { earth_id:"DLX-DEMO015", name:"Raj Patel",           role:"user",            lat:19.08,  lng:72.88,  rating:4.1, kyc_level:1, online:false },
  { earth_id:"DLX-DEMO016", name:"Carlos Mendez",       role:"driver",          lat:19.43,  lng:-99.13, rating:4.6, kyc_level:2, online:true  },
  { earth_id:"DLX-DEMO017", name:"Chen Wei",            role:"cargo_owner",     lat:31.23,  lng:121.47, rating:4.7, kyc_level:2, online:false },
  { earth_id:"DLX-DEMO018", name:"Sofia Petrov",        role:"creator",         lat:55.75,  lng:37.62,  rating:4.5, kyc_level:1, online:true  },
  { earth_id:"DLX-DEMO019", name:"Nour Al-Rashid",      role:"insurance_agent", lat:24.69,  lng:46.72,  rating:4.4, kyc_level:2, online:false },
  { earth_id:"DLX-DEMO020", name:"Amir Sultanov",       role:"driver",          lat:51.18,  lng:71.45,  rating:4.3, kyc_level:1, online:true  },
  { earth_id:"DLX-DEMO021", name:"Emma Johansson",      role:"user",            lat:59.33,  lng:18.07,  rating:4.6, kyc_level:1, online:false },
  { earth_id:"DLX-DEMO022", name:"Lucas Dupont",        role:"freight_broker",  lat:48.86,  lng:2.35,   rating:4.5, kyc_level:2, online:true  },
  { earth_id:"DLX-DEMO023", name:"Amira Mansour",       role:"creator",         lat:30.04,  lng:31.24,  rating:4.7, kyc_level:1, online:true  },
  { earth_id:"DLX-DEMO024", name:"Park Jiwoo",          role:"user",            lat:37.57,  lng:126.98, rating:4.4, kyc_level:0, online:false },
  { earth_id:"DLX-DEMO025", name:"Elena Kovacs",        role:"insurance_agent", lat:47.50,  lng:19.04,  rating:4.6, kyc_level:2, online:true  },
];

const ROLES = ["همه", "driver", "cargo_owner", "freight_broker", "insurance_agent", "creator", "user"] as const;

// حداقل تعداد برای نمایش به‌صورت خوشه؛ گروه‌های کوچک‌تر تک‌به‌تک نشان داده می‌شوند
const CLUSTER_MIN = 6;

// ── Grid clustering ───────────────────────────────────────────────────────────
function buildClusters(users: EarthUser[], cellDeg: number): Cluster[] {
  const cells = new Map<string, EarthUser[]>();
  for (const u of users) {
    const clat = Math.floor(u.lat / cellDeg) * cellDeg + cellDeg / 2;
    const clng = Math.floor(u.lng / cellDeg) * cellDeg + cellDeg / 2;
    const key  = `${clat.toFixed(3)},${clng.toFixed(3)}`;
    if (!cells.has(key)) cells.set(key, []);
    cells.get(key)!.push(u);
  }
  return Array.from(cells.entries()).map(([key, members]) => {
    const avgLat = members.reduce((s, u) => s + u.lat, 0) / members.length;
    const avgLng = members.reduce((s, u) => s + u.lng, 0) / members.length;
    const roleCounts: Record<string, number> = {};
    for (const u of members) roleCounts[u.role] = (roleCounts[u.role] ?? 0) + 1;
    const dominant_role = Object.entries(roleCounts).sort((a, b) => b[1] - a[1])[0][0];
    return { id: key, lat: avgLat, lng: avgLng, count: members.length, members, dominant_role };
  });
}

// اندازهٔ سلولِ خوشه‌بندی بر پایهٔ ارتفاع دوربین — پله‌ای (discrete) تا مارکرها
// در هر فریمِ زوم بازساخته نشوند و فقط هنگام عبور از مرزِ زوم تغییر کنند
function cellForAltitude(alt: number): number {
  if (alt > 1.6)   return 12;
  if (alt > 0.8)   return 4;
  if (alt > 0.4)   return 1.5;
  if (alt > 0.2)   return 0.5;
  if (alt > 0.1)   return 0.15;
  if (alt > 0.04)  return 0.05;
  if (alt > 0.015) return 0.015;
  return 0.005;
}

// جابه‌جایی قطعیِ ریز تا کاربرانِ دقیقاً هم‌مکان روی هم نیفتند
function spreadOffset(seed: string, index: number, total: number): [number, number] {
  if (total <= 1) return [0, 0];
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) >>> 0;
  const ang = (index / total) * Math.PI * 2 + ((h % 360) * Math.PI) / 180;
  const r = 0.05;
  return [Math.sin(ang) * r, Math.cos(ang) * r];
}

// ── Marker point ─────────────────────────────────────────────────────────────
interface GlobePoint {
  lat: number; lng: number;
  cluster: Cluster;
}

// ویژگی‌های ظاهریِ مارکر بر پایهٔ خوشه (رنگِ نور و آواتار)
function markerMeta(c: Cluster) {
  const isCluster = c.count > 1;
  const u = c.members[0];
  const online = isCluster ? c.members.some(m => m.online) : !!u.online;
  const glow = isCluster ? "#38BDF8" : (online ? "#22C55E" : "#9CA3AF");
  return { isCluster, u, glow };
}

// پایهٔ پرتو دقیقاً روی سطح (alt=0) تا با زوم دچار پارالاکس نشود و از نقطه جدا نیفتد
const MARKER_ALT = 0;

// ── Component ─────────────────────────────────────────────────────────────────
export default function EarthPage() {
  const router      = useRouter();
  const globeRef    = useRef<any>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const [GlobeComp, setGlobeComp] = useState<any>(null);
  const [size,      setSize]      = useState({ w: 0, h: 0 });
  const [users,     setUsers]     = useState<EarthUser[]>(DEMO);
  const [userCount, setUserCount] = useState(DEMO.length);
  const [search,    setSearch]    = useState("");
  const [roleFilter,setRole]      = useState("همه");
  const [showFilter,setFilter]    = useState(false);
  const [drawer,    setDrawer]    = useState<DrawerState | null>(null);
  const [altitude,  setAltitude]  = useState(2.2);

  // وضعیتِ اجازهٔ موقعیت: pending→ask→(permanent|temporary|dismissed)
  const [geoConsent, setGeoConsent] = useState<string>("pending");
  const [gpsOff,      setGpsOff]     = useState(false);
  const [geoBlocked,  setGeoBlocked] = useState(false);
  const watchIdRef    = useRef<number | null>(null);
  const lastAppliedRef = useRef<{ lat: number; lng: number } | null>(null);

  // نگاشتِ نقطه→گرهِ DOM برای جای‌گذاریِ مارکرها روی صفحه (لایهٔ اختصاصی)
  const markerNodes = useRef<Map<string, HTMLDivElement>>(new Map());
  const pointsRef   = useRef<GlobePoint[]>([]);

  // Lazy-load react-globe.gl (keeps Three.js out of SSR)
  useEffect(() => {
    let mounted = true;
    import("react-globe.gl").then((mod) => {
      if (mounted) setGlobeComp(() => mod.default);
    });
    return () => { mounted = false; };
  }, []);

  // Track container size for proper globe sizing
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const update = () => setSize({ w: el.clientWidth, h: el.clientHeight });
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, [GlobeComp]);

  // Fetch real users
  const fetchUsers = useCallback(() => {
    earthApi.getUsers({ limit: 500 })
      .then((res) => {
        const apiUsers: EarthUser[] = (res.data.users ?? []).map((u: any) => ({
          earth_id:  u.earth_id,
          name:      u.name,
          role:      u.role,
          lat:       u.lat,
          lng:       u.lng,
          rating:    u.rating ?? 0,
          kyc_level: u.kyc_level ?? 0,
          avatar_url: u.avatar_url ?? undefined,
          online:    u.online ?? false,
          city:      u.city ?? undefined,
        }));
        const merged = apiUsers.length > 0 ? apiUsers : DEMO;
        setUsers(merged);
        setUserCount(merged.length);
      })
      .catch(() => {});
  }, []);

  useEffect(() => { fetchUsers(); }, [fetchUsers]);

  // ثبتِ موقعیتِ کاربر روی سرور. recenter=true فقط برای اولین fix.
  const applyMyLocation = useCallback(
    (lat: number, lng: number, accuracy?: number, recenter = true) => {
      earthApi
        .updateLocation({ lat, lng, accuracy })
        .then(() => {
          fetchUsers();
          if (recenter) {
            const g = globeRef.current;
            if (g) {
              const c = g.controls?.();
              if (c) c.autoRotate = false;
              g.pointOfView({ lat, lng, altitude: 0.1 }, 1200);
            }
            toast.success("موقعیت شما روی نقشه ثبت شد");
          }
        })
        .catch(() => {
          if (recenter)
            toast.error("ثبت موقعیت ناموفق بود؛ اتصال یا ورود خود را بررسی کنید");
        });
    },
    [fetchUsers]
  );

  // موفقیتِ دریافتِ موقعیت: خاموش‌بودنِ GPS را پاک کن و در صورت جابه‌جاییِ
  // معنادار (~۳۰ متر) روی سرور ثبت کن؛ اولین‌بار کره را مرکز می‌کند.
  const handlePosition = useCallback(
    (pos: GeolocationPosition) => {
      setGpsOff(false);
      setGeoBlocked(false);
      const { latitude, longitude, accuracy } = pos.coords;
      const last = lastAppliedRef.current;
      const isFirst = last === null;
      if (last && Math.abs(last.lat - latitude) < 0.0003 && Math.abs(last.lng - longitude) < 0.0003) {
        return;
      }
      lastAppliedRef.current = { lat: latitude, lng: longitude };
      applyMyLocation(latitude, longitude, accuracy, isFirst);
    },
    [applyMyLocation]
  );

  // خطای موقعیت: رد دسترسی → کارتِ راهنمای فعال‌سازی (پایدار، بدون toastِ تکراری)؛
  // در دسترس نبودن/timeout → GPS خاموش
  const handleGeoError = useCallback((e: GeolocationPositionError) => {
    if (e.code === e.PERMISSION_DENIED) {
      setGpsOff(false);
      try { localStorage.removeItem(GEO_CONSENT_KEY); } catch {}
      // چند فراخوانی (getCurrentPosition + watch) هم‌زمان رد می‌شوند؛ به‌جای toastِ تکراری،
      // پنجرهٔ پرسش را ببند و کارتِ راهنمای «مسدود شده» را نشان بده.
      setGeoConsent("dismissed");
      setGeoBlocked(true);
    } else {
      setGpsOff(true);
    }
  }, []);

  // شروعِ ردیابی: یک fix سریع (با fallback کم‌دقت)؛ برای اتصالِ دائم watch مداوم
  const startTracking = useCallback(
    (permanent: boolean) => {
      if (typeof navigator === "undefined" || !navigator.geolocation) {
        toast.error("مرورگرِ شما از موقعیت مکانی پشتیبانی نمی‌کند");
        return;
      }
      navigator.geolocation.getCurrentPosition(
        handlePosition,
        () =>
          navigator.geolocation.getCurrentPosition(handlePosition, handleGeoError, {
            enableHighAccuracy: false,
            timeout: 12000,
            maximumAge: 60000,
          }),
        { enableHighAccuracy: true, timeout: 12000, maximumAge: 0 }
      );
      if (permanent) {
        if (watchIdRef.current != null) navigator.geolocation.clearWatch(watchIdRef.current);
        watchIdRef.current = navigator.geolocation.watchPosition(handlePosition, handleGeoError, {
          enableHighAccuracy: true,
          timeout: 20000,
          maximumAge: 15000,
        });
      }
    },
    [handlePosition, handleGeoError]
  );

  // خواندنِ تصمیمِ ذخیره‌شده در ورود: اگر دائم بود همان‌جا ردیابی را آغاز کن، وگرنه بپرس
  useEffect(() => {
    let saved: string | null = null;
    try { saved = localStorage.getItem(GEO_CONSENT_KEY); } catch {}
    if (saved === "permanent") {
      setGeoConsent("permanent");
      startTracking(true);
    } else {
      setGeoConsent("ask");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // فقط پاک‌سازیِ watch در خروج (شروعِ ردیابی داخلِ گسچرِ کاربر انجام می‌شود)
  useEffect(() => {
    return () => {
      if (watchIdRef.current != null && typeof navigator !== "undefined" && navigator.geolocation) {
        navigator.geolocation.clearWatch(watchIdRef.current);
        watchIdRef.current = null;
      }
    };
  }, []);

  // پذیرشِ دسترسی: درخواستِ موقعیت را در همان گسچرِ کاربر انجام بده تا مرورگر پرامپت را نشان دهد
  const acceptConsent = useCallback((permanent: boolean) => {
    try {
      if (permanent) localStorage.setItem(GEO_CONSENT_KEY, "permanent");
      else localStorage.removeItem(GEO_CONSENT_KEY);
    } catch {}
    lastAppliedRef.current = null;
    setGeoBlocked(false);
    setGeoConsent(permanent ? "permanent" : "temporary");
    startTracking(permanent);
  }, [startTracking]);

  const retryGps = useCallback(() => {
    setGpsOff(false);
    setGeoBlocked(false);
    startTracking(geoConsent === "permanent");
  }, [startTracking, geoConsent]);

  // تلاشِ مجدد پس از مسدود شدن: در همان گسچرِ کاربر دوباره درخواست بده
  const retryBlocked = useCallback(() => {
    setGeoBlocked(false);
    lastAppliedRef.current = null;
    startTracking(true);
  }, [startTracking]);

  // Build filtered users (memoized)
  const filteredUsers = useMemo(() =>
    users.filter(u =>
      (roleFilter === "همه" || u.role === roleFilter) &&
      (search === "" ||
        u.name.toLowerCase().includes(search.toLowerCase()) ||
        u.earth_id.toLowerCase().includes(search.toLowerCase()))
    ), [users, roleFilter, search]);

  // اندازهٔ سلولِ خوشه پله‌ای است → فقط هنگام عبور از مرزِ زوم عوض می‌شود
  const cellDeg = useMemo(() => cellForAltitude(altitude), [altitude]);

  // نقاطِ مارکر — خوشهٔ بزرگ فقط وقتی افراد زیادند، وگرنه تک‌تک
  const points = useMemo<GlobePoint[]>(() => {
    const out: GlobePoint[] = [];
    for (const cluster of buildClusters(filteredUsers, cellDeg)) {
      if (cluster.count > CLUSTER_MIN) {
        out.push({ lat: cluster.lat, lng: cluster.lng, cluster });
      } else {
        cluster.members.forEach((u, i) => {
          const [dlat, dlng] = spreadOffset(u.earth_id, i, cluster.members.length);
          out.push({
            lat: u.lat + dlat,
            lng: u.lng + dlng,
            cluster: { id: u.earth_id, lat: u.lat, lng: u.lng, count: 1, members: [u], dominant_role: u.role },
          });
        });
      }
    }
    return out;
  }, [filteredUsers, cellDeg]);

  pointsRef.current = points;

  const onPointClick = useCallback((c: Cluster) => {
    if (c.count === 1) setDrawer({ type: "user", user: c.members[0] });
    else               setDrawer({ type: "cluster", cluster: c });
  }, []);

  // لایهٔ اختصاصیِ مارکرها: مختصاتِ صفحه‌ای هر نقطه را از کره می‌گیرد و گره‌های DOM
  // را جای‌گذاری می‌کند. برای همگام‌ماندنِ کاملِ مارکرها با رندرِ WebGL (بدونِ لگِ
  // یک‌فریمی که هنگام زوم باعث جدا شدنِ پایه از لوکیشن می‌شد)، این تابع از رویدادِ
  // «change» ی OrbitControls صدا زده می‌شود که دقیقاً پیش از هر renderer.render اجرا می‌شود.
  const updateMarkers = useCallback(() => {
    const g = globeRef.current;
    if (!g || typeof g.getScreenCoords !== "function") return;
    const cam = g.camera();
    const cp = cam?.position;
    for (const p of pointsRef.current) {
      const node = markerNodes.current.get(p.cluster.id);
      if (!node) continue;
      const co = g.getCoords(p.lat, p.lng, MARKER_ALT);
      const sc = g.getScreenCoords(p.lat, p.lng, MARKER_ALT);
      // نیم‌کرهٔ روبه‌دوربین: dot(نرمالِ نقطه، بردار نقطه→دوربین) > 0
      const facing = cp
        ? co.x * (cp.x - co.x) + co.y * (cp.y - co.y) + co.z * (cp.z - co.z)
        : 1;
      if (sc && facing > 0) {
        node.style.display = "block";
        node.style.transform = `translate3d(${sc.x}px, ${sc.y}px, 0)`;
      } else {
        node.style.display = "none";
      }
    }
  }, [GlobeComp]);

  // پس از تغییرِ داده‌ها (نقاط) یا آماده‌شدنِ کره، یک‌بار پس از commit شدنِ DOM
  // مارکرها را جای‌گذاری کن تا حتی وقتی دوربین ساکن است هم درست بنشینند.
  useEffect(() => {
    if (!GlobeComp) return;
    const raf = requestAnimationFrame(updateMarkers);
    return () => cancelAnimationFrame(raf);
  }, [GlobeComp, points, updateMarkers]);

  const onGlobeReady = () => {
    const g = globeRef.current;
    if (!g) return;
    const controls = g.controls();
    controls.autoRotate      = true;
    controls.autoRotateSpeed = 0.4;
    controls.enableDamping   = true;
    controls.dampingFactor   = 0.1;
    controls.minDistance     = 100.15; // ≈ محله/خیابان (زوم عمیق‌تر از سطح شهر)
    controls.maxDistance     = 500;
    controls.addEventListener("start", () => { controls.autoRotate = false; });
    // مارکرها را دقیقاً هم‌فریم با رندرِ کره به‌روز کن تا پایه از لوکیشن جدا نشود
    controls.addEventListener("change", updateMarkers);
    g.pointOfView({ lat: 32, lng: 53, altitude: 2.2 }, 0);
    requestAnimationFrame(updateMarkers);
  };

  // ── JSX ───────────────────────────────────────────────────────────────────
  return (
    <div className="relative overflow-hidden" style={{ height: "calc(100dvh - 64px)", background: "#080F22" }}>

      {/* Globe container */}
      <div ref={containerRef} className="absolute inset-0">
        {GlobeComp && size.w > 0 ? (
          <>
            <GlobeComp
              ref={globeRef}
              width={size.w}
              height={size.h}
              onGlobeReady={onGlobeReady}
              backgroundColor="#080F22"
              globeImageUrl="/libs/earth.jpg"
              globeTileEngineUrl={(x: number, y: number, l: number) =>
                `/globe-tiles/${l}/${x}/${y}`
              }
              globeTileEngineMaxLevel={18}
              atmosphereColor="#3b82f6"
              atmosphereAltitude={0.18}
              onGlobeClick={() => setDrawer(null)}
              onZoom={(pov: { lat: number; lng: number; altitude: number }) => {
                const q = Math.round(pov.altitude * 1000) / 1000;
                setAltitude((prev) => (prev === q ? prev : q));
              }}
            />

            {/* لایهٔ اختصاصیِ مارکرها (پرتوِ نور + آواتار) روی کره */}
            <div className="absolute inset-0 pointer-events-none" style={{ zIndex: 20, overflow: "hidden" }}>
              {points.map((p) => {
                const { isCluster, u, glow } = markerMeta(p.cluster);
                return (
                  <div
                    key={p.cluster.id}
                    ref={(el) => {
                      if (el) markerNodes.current.set(p.cluster.id, el);
                      else markerNodes.current.delete(p.cluster.id);
                    }}
                    style={{ position: "absolute", left: 0, top: 0, display: "none", willChange: "transform" }}
                  >
                    {/* لنگرِ پایین-وسط روی نقطه؛ آواتار بالا، پرتو پایین */}
                    <div
                      onClick={(e) => { e.stopPropagation(); onPointClick(p.cluster); }}
                      style={{
                        position: "absolute", left: 0, top: 0,
                        transform: "translate(-50%,-100%)",
                        display: "flex", flexDirection: "column", alignItems: "center",
                        pointerEvents: "auto", cursor: "pointer",
                      }}
                    >
                      <div
                        style={{
                          width: 28, height: 28, borderRadius: "50%", overflow: "hidden",
                          border: `2px solid ${glow}`, background: `${glow}26`,
                          boxShadow: `0 0 10px ${glow}, 0 0 3px ${glow}`,
                          display: "flex", alignItems: "center", justifyContent: "center",
                          fontSize: 14, lineHeight: 1,
                        }}
                      >
                        {isCluster ? (
                          <span style={{ color: "#fff", fontWeight: 700, fontSize: 12 }}>
                            {toPersianNum(p.cluster.count)}
                          </span>
                        ) : u.avatar_url ? (
                          <img src={u.avatar_url} alt="" referrerPolicy="no-referrer"
                               style={{ width: "100%", height: "100%", objectFit: "cover" }} />
                        ) : (
                          <span>{rem(u.role)}</span>
                        )}
                      </div>
                      <div
                        style={{
                          width: 3, height: 26, marginTop: -1, borderRadius: 2,
                          background: `linear-gradient(to bottom, ${glow}, ${glow}00)`,
                          boxShadow: `0 0 8px ${glow}`,
                        }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </>
        ) : (
          <div className="absolute inset-0 flex flex-col items-center justify-center" style={{ background: "#080F22" }}>
            <div className="relative mb-6">
              <div className="absolute inset-0 rounded-full border-2 border-blue-400/20 animate-ping scale-150" />
              <div className="w-20 h-20 rounded-full border-2 border-blue-500/40 flex items-center justify-center text-5xl">🌍</div>
            </div>
            <p className="text-blue-200/80 text-sm font-semibold tracking-widest">DILIX EARTH</p>
            <p className="text-blue-800 text-xs mt-1">در حال بارگذاری...</p>
          </div>
        )}
      </div>

      {/* ── Top bar ── */}
      <div className="absolute top-0 inset-x-0 p-3 pointer-events-none" style={{ zIndex: 30 }}>
        <div className="flex items-center gap-2 pointer-events-auto">
          <div className="relative flex-1">
            <Search size={14} className="absolute right-3 top-1/2 -translate-y-1/2" style={{ color: "rgba(147,197,253,0.45)" }} />
            <input
              value={search}
              onChange={e => setSearch(e.target.value)}
              placeholder="جستجوی نام یا Earth ID..."
              className="w-full rounded-xl text-sm text-white focus:outline-none"
              style={{
                background:     "rgba(5,12,38,0.78)",
                border:         "1px solid rgba(100,150,255,0.18)",
                backdropFilter: "blur(18px)",
                padding:        "10px 36px 10px 16px",
                direction:      "rtl",
              }}
            />
          </div>
          <button
            onClick={() => setFilter(f => !f)}
            className="flex-shrink-0 p-2.5 rounded-xl transition-all"
            style={{
              background:     showFilter ? "#6366f1cc" : "rgba(5,12,38,0.78)",
              border:         "1px solid rgba(100,150,255,0.18)",
              backdropFilter: "blur(18px)",
              color:          showFilter ? "#fff" : "#93c5fd",
            }}
          >
            <Filter size={18} />
          </button>
        </div>

        {showFilter && (
          <div className="flex gap-2 mt-2 overflow-x-auto pb-1 no-scrollbar pointer-events-auto">
            {ROLES.map(r => (
              <button
                key={r}
                onClick={() => setRole(r)}
                className="flex-shrink-0 text-xs px-3 py-1.5 rounded-full transition-all whitespace-nowrap"
                style={{
                  background:     roleFilter === r ? "#6366f1cc" : "rgba(5,12,38,0.78)",
                  border:         "1px solid " + (roleFilter === r ? "#818cf8" : "rgba(100,150,255,0.18)"),
                  color:          roleFilter === r ? "#fff" : "#93c5fd",
                  backdropFilter: "blur(12px)",
                }}
              >
                {r === "همه" ? `همه (${toPersianNum(userCount)})` : `${rem(r)} ${rl(r)}`}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* ── نوارِ هشدارِ GPS خاموش ── */}
      {gpsOff && (geoConsent === "permanent" || geoConsent === "temporary") && (
        <div className="absolute inset-x-0 flex justify-center px-3 pointer-events-none" style={{ top: 60, zIndex: 35 }}>
          <div
            className="flex items-center gap-2 rounded-xl px-3 py-2 pointer-events-auto"
            dir="rtl"
            style={{ background: "rgba(120,25,25,0.92)", border: "1px solid rgba(255,120,120,0.4)", backdropFilter: "blur(12px)" }}
          >
            <MapPin size={15} className="text-red-200 flex-shrink-0" />
            <span className="text-xs text-white">GPS خاموش است — برای نمایش دقیق روشن کنید</span>
            <button
              onClick={retryGps}
              className="text-xs font-bold px-2.5 py-1 rounded-lg flex-shrink-0"
              style={{ background: "#fff", color: "#7f1d1d" }}
            >
              فعال‌سازی
            </button>
          </div>
        </div>
      )}

      {/* ── پنجرهٔ تاییدیهٔ دسترسی به موقعیت (دائم / موقت) ── */}
      {geoConsent === "ask" && (
        <div
          className="absolute inset-0 flex items-center justify-center p-6"
          style={{ zIndex: 60, background: "rgba(4,8,22,0.72)", backdropFilter: "blur(6px)" }}
        >
          <div
            className="w-full max-w-sm rounded-2xl p-5 shadow-2xl"
            dir="rtl"
            style={{ background: "rgba(8,16,40,0.98)", border: "1px solid rgba(100,150,255,0.2)", animation: "slideUp 0.24s ease-out" }}
          >
            <div className="flex items-center gap-3 mb-3">
              <div
                className="w-11 h-11 rounded-full flex items-center justify-center flex-shrink-0"
                style={{ background: "#22C55E22", border: "1px solid #22C55E55" }}
              >
                <Navigation size={20} className="text-emerald-400" />
              </div>
              <p className="text-white font-bold text-base">نمایش شما روی نقشه</p>
            </div>
            <p className="text-[13px] leading-6 mb-4" style={{ color: "rgba(147,197,253,0.82)" }}>
              برای نمایشِ دقیقِ شما روی کرهٔ زمین به موقعیت مکانی نیاز داریم.
              موقعیتِ دقیق فقط در سیستم ثبت می‌شود و برای کاربرانِ دیگر به‌صورتِ محدوده نشان داده می‌شود.
            </p>
            <div className="space-y-2">
              <button
                onClick={() => acceptConsent(true)}
                className="w-full py-3 rounded-xl text-white text-sm font-bold active:scale-95 transition-all"
                style={{ background: "linear-gradient(135deg,#22C55E,#16A34A)" }}
              >
                اتصالِ دائم — همیشه به‌روز بمانم
              </button>
              <button
                onClick={() => acceptConsent(false)}
                className="w-full py-3 rounded-xl text-sm font-bold active:scale-95 transition-all"
                style={{ border: "1px solid rgba(100,150,255,0.3)", color: "#93c5fd", background: "rgba(255,255,255,0.04)" }}
              >
                فقط همین بار (موقت)
              </button>
              <button
                onClick={() => setGeoConsent("dismissed")}
                className="w-full py-2 text-xs"
                style={{ color: "rgba(147,197,253,0.5)" }}
              >
                بعداً
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── کارتِ راهنما وقتی دسترسی در مرورگر «مسدود» شده ── */}
      {geoBlocked && (
        <div
          className="absolute inset-0 flex items-center justify-center p-6"
          style={{ zIndex: 60, background: "rgba(4,8,22,0.72)", backdropFilter: "blur(6px)" }}
        >
          <div
            className="w-full max-w-sm rounded-2xl p-5 shadow-2xl"
            dir="rtl"
            style={{ background: "rgba(8,16,40,0.98)", border: "1px solid rgba(255,120,120,0.25)", animation: "slideUp 0.24s ease-out" }}
          >
            <div className="flex items-center gap-3 mb-3">
              <div
                className="w-11 h-11 rounded-full flex items-center justify-center flex-shrink-0"
                style={{ background: "#EF444422", border: "1px solid #EF444455" }}
              >
                <MapPin size={20} className="text-red-400" />
              </div>
              <p className="text-white font-bold text-base">دسترسی به موقعیت مسدود است</p>
            </div>
            <p className="text-[13px] leading-6 mb-3" style={{ color: "rgba(147,197,253,0.82)" }}>
              مرورگر اجازهٔ موقعیت مکانی را برای این سایت مسدود کرده. برای فعال‌سازی:
            </p>
            <ol className="text-[13px] leading-7 mb-4 pr-4 list-decimal" style={{ color: "rgba(203,213,225,0.9)" }}>
              <li>روی آیکونِ 🔒 یا ⓘ کنارِ آدرسِ <b>dilix.ir</b> بزنید.</li>
              <li>گزینهٔ «Permissions / مجوزها» را باز کنید.</li>
              <li>«Location / موقعیت مکانی» را روی <b>Allow / مجاز</b> بگذارید.</li>
              <li>سپس دکمهٔ زیر را بزنید.</li>
            </ol>
            <div className="space-y-2">
              <button
                onClick={retryBlocked}
                className="w-full py-3 rounded-xl text-white text-sm font-bold active:scale-95 transition-all"
                style={{ background: "linear-gradient(135deg,#22C55E,#16A34A)" }}
              >
                تلاش مجدد
              </button>
              <button
                onClick={() => { setGeoBlocked(false); setGeoConsent("dismissed"); }}
                className="w-full py-2 text-xs"
                style={{ color: "rgba(147,197,253,0.5)" }}
              >
                بعداً
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Bottom Drawer ── */}
      {drawer && (
        <div
          className="absolute inset-x-0 pointer-events-auto"
          style={{ bottom: "60px", zIndex: 40, animation: "slideUp 0.22s ease-out" }}
        >
          <div
            className="mx-3 rounded-2xl shadow-2xl overflow-hidden"
            style={{
              background:     "rgba(5,12,35,0.96)",
              border:         "1px solid rgba(100,150,255,0.18)",
              backdropFilter: "blur(28px)",
            }}
          >
            {/* Handle row */}
            <div className="flex items-center justify-between px-4 pt-3 pb-1">
              <div style={{ width: 32 }} />
              <div className="w-10 h-1 rounded-full" style={{ background: "rgba(255,255,255,0.15)" }} />
              <button onClick={() => setDrawer(null)} className="p-1" style={{ color: "rgba(147,197,253,0.4)" }}>
                <X size={18} />
              </button>
            </div>

            {drawer.type === "user" ? (
              /* ── Single user card ── */
              <div className="px-4 pb-4 pt-1">
                <div className="flex items-start gap-3 mb-3">
                  <button
                    type="button"
                    onClick={() => router.push(`/u/${drawer.user.earth_id}`)}
                    className="w-14 h-14 rounded-full flex items-center justify-center text-2xl flex-shrink-0 border-2 overflow-hidden cursor-pointer active:scale-95 transition-transform"
                    style={{ borderColor: rc(drawer.user.role) + "80", background: rc(drawer.user.role) + "25" }}
                    title="مشاهده پروفایل"
                  >
                    {drawer.user.avatar_url
                      ? <img src={drawer.user.avatar_url} className="w-full h-full object-cover" alt="" />
                      : rem(drawer.user.role)}
                  </button>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-1.5">
                      <button type="button" onClick={() => router.push(`/u/${drawer.user.earth_id}`)} className="text-white font-bold truncate text-right hover:underline cursor-pointer">{drawer.user.name}</button>
                      {drawer.user.kyc_level >= 2 && (
                        <ShieldCheck size={14} className="text-emerald-400 flex-shrink-0" />
                      )}
                      <span
                        className="flex-shrink-0 w-2 h-2 rounded-full"
                        style={{ background: drawer.user.online ? "#22C55E" : "#6B7280" }}
                        title={drawer.user.online ? "آنلاین" : "آفلاین"}
                      />
                    </div>
                    <p className="text-[11px] font-mono mt-0.5" style={{ color: "rgba(147,197,253,0.5)" }}>
                      {drawer.user.earth_id}
                    </p>
                    {drawer.user.city && (
                      <p className="text-[11px] mt-0.5" style={{ color: "rgba(147,197,253,0.65)" }}>
                        📍 {drawer.user.city}
                      </p>
                    )}
                    <div className="flex items-center gap-2 mt-1.5 flex-wrap">
                      <span
                        className="text-xs px-2 py-0.5 rounded-full font-medium"
                        style={{ background: rc(drawer.user.role) + "28", color: rc(drawer.user.role) }}
                      >
                        {rl(drawer.user.role)}
                      </span>
                      <div className="flex items-center gap-0.5">
                        <Star size={11} className="text-amber-400 fill-amber-400" />
                        <span className="text-xs" style={{ color: "rgba(147,197,253,0.75)" }}>{drawer.user.rating}</span>
                      </div>
                    </div>
                  </div>
                </div>
                <div className="flex gap-2">
                  <button
                    onClick={() => router.push(`/messages/${drawer.user.earth_id}`)}
                    className="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl text-white text-sm font-bold active:scale-95 transition-all"
                    style={{ background: `linear-gradient(135deg, ${rc(drawer.user.role)}, ${rc(drawer.user.role)}bb)` }}
                  >
                    <MessageCircle size={15} /> گفتگو
                  </button>
                  <button
                    onClick={() => router.push(`/messages/${drawer.user.earth_id}?type=collaboration`)}
                    className="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl text-sm font-bold border active:scale-95 transition-all"
                    style={{ borderColor: rc(drawer.user.role) + "55", color: rc(drawer.user.role), background: "rgba(255,255,255,0.04)" }}
                  >
                    <Handshake size={15} /> همکاری
                  </button>
                </div>
              </div>
            ) : (
              /* ── Cluster list ── */
              <div className="px-3 pb-4 pt-1">
                <div className="flex items-center gap-2 px-1 mb-3">
                  <Users size={16} style={{ color: "rgba(147,197,253,0.65)" }} />
                  <p className="text-sm font-semibold text-white">
                    {toPersianNum(drawer.cluster.count)} نفر در این منطقه — برای دیدن تک‌تک زوم کنید
                  </p>
                </div>
                <div className="space-y-1 max-h-56 overflow-y-auto no-scrollbar">
                  {drawer.cluster.members.map(u => (
                    <button
                      key={u.earth_id}
                      onClick={() => setDrawer({ type: "user", user: u })}
                      className="w-full flex items-center gap-3 p-2.5 rounded-xl active:scale-[0.99] transition-all text-right"
                      style={{ background: "rgba(255,255,255,0.04)", border: "1px solid rgba(255,255,255,0.07)" }}
                    >
                      <div
                        className="w-9 h-9 rounded-full flex items-center justify-center text-base flex-shrink-0 border overflow-hidden"
                        style={{ borderColor: rc(u.role) + "55", background: rc(u.role) + "25" }}
                      >
                        {u.avatar_url
                          ? <img src={u.avatar_url} className="w-full h-full object-cover" alt="" />
                          : rem(u.role)}
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-white text-sm font-semibold truncate">{u.name}</p>
                        <p className="text-[11px]" style={{ color: rc(u.role) }}>{rl(u.role)}</p>
                      </div>
                      <div className="flex items-center gap-1.5 flex-shrink-0">
                        <span className="w-1.5 h-1.5 rounded-full" style={{ background: u.online ? "#22C55E" : "#6B7280" }} />
                        <Star size={11} className="text-amber-400 fill-amber-400" />
                        <span className="text-xs" style={{ color: "rgba(147,197,253,0.6)" }}>{u.rating}</span>
                        <ChevronRight size={14} style={{ color: "rgba(147,197,253,0.25)" }} />
                      </div>
                    </button>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {/* ── BottomNav ── */}
      <div style={{ position: "absolute", bottom: 0, left: 0, right: 0, zIndex: 50 }}>
        <BottomNav />
      </div>

      <style>{`
        @keyframes slideUp {
          from { opacity: 0; transform: translateY(18px); }
          to   { opacity: 1; transform: translateY(0); }
        }
      `}</style>
    </div>
  );
}
