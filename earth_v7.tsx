"use client";

import { useEffect, useRef, useState, useCallback } from "react";
import {
  Search, Filter, Star, ShieldCheck, MessageCircle,
  Handshake, X, Users, ChevronRight,
} from "lucide-react";
import BottomNav from "@/components/layout/BottomNav";
import { useRouter } from "next/navigation";
import { toPersianNum } from "@/lib/utils";

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

// ── Types ─────────────────────────────────────────────────────────────────────
interface EarthUser {
  earth_id: string; name: string; role: string;
  lat: number; lng: number; rating: number;
  kyc_level: number; avatar_url?: string;
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
  { earth_id:"DLX-DEMO001", name:"احمد رضایی",        role:"driver",          lat:35.69,  lng:51.39,  rating:4.8, kyc_level:2 },
  { earth_id:"DLX-DEMO002", name:"شرکت فراز لجستیک",  role:"cargo_owner",     lat:32.43,  lng:53.69,  rating:4.5, kyc_level:3 },
  { earth_id:"DLX-DEMO003", name:"محمد علوی",          role:"user",            lat:29.59,  lng:52.58,  rating:4.2, kyc_level:1 },
  { earth_id:"DLX-DEMO004", name:"سارا کریمی",         role:"driver",          lat:36.29,  lng:59.60,  rating:4.9, kyc_level:2 },
  { earth_id:"DLX-DEMO005", name:"نیلوفر صادقی",       role:"creator",         lat:33.34,  lng:44.40,  rating:4.6, kyc_level:1 },
  { earth_id:"DLX-DEMO006", name:"حسین محمدی",         role:"insurance_agent", lat:34.08,  lng:49.70,  rating:4.7, kyc_level:3 },
  { earth_id:"DLX-DEMO007", name:"زهرا موسوی",         role:"user",            lat:37.28,  lng:49.59,  rating:4.3, kyc_level:0 },
  { earth_id:"DLX-DEMO008", name:"مهدی تهرانی",        role:"freight_broker",  lat:31.32,  lng:48.67,  rating:4.4, kyc_level:2 },
  { earth_id:"DLX-DEMO010", name:"Ali Hassan",          role:"driver",          lat:25.20,  lng:55.27,  rating:4.7, kyc_level:2 },
  { earth_id:"DLX-DEMO011", name:"Mehmet Yilmaz",       role:"cargo_owner",     lat:41.01,  lng:28.97,  rating:4.5, kyc_level:1 },
  { earth_id:"DLX-DEMO012", name:"Sarah Klein",         role:"creator",         lat:52.52,  lng:13.40,  rating:4.9, kyc_level:3 },
  { earth_id:"DLX-DEMO013", name:"James Wilson",        role:"user",            lat:51.50,  lng:-0.12,  rating:4.3, kyc_level:1 },
  { earth_id:"DLX-DEMO014", name:"Kenji Tanaka",        role:"freight_broker",  lat:35.68,  lng:139.69, rating:4.8, kyc_level:3 },
  { earth_id:"DLX-DEMO015", name:"Raj Patel",           role:"user",            lat:19.08,  lng:72.88,  rating:4.1, kyc_level:1 },
  { earth_id:"DLX-DEMO016", name:"Carlos Mendez",       role:"driver",          lat:19.43,  lng:-99.13, rating:4.6, kyc_level:2 },
  { earth_id:"DLX-DEMO017", name:"Chen Wei",            role:"cargo_owner",     lat:31.23,  lng:121.47, rating:4.7, kyc_level:2 },
  { earth_id:"DLX-DEMO018", name:"Sofia Petrov",        role:"creator",         lat:55.75,  lng:37.62,  rating:4.5, kyc_level:1 },
  { earth_id:"DLX-DEMO019", name:"Nour Al-Rashid",      role:"insurance_agent", lat:24.69,  lng:46.72,  rating:4.4, kyc_level:2 },
  { earth_id:"DLX-DEMO020", name:"Amir Sultanov",       role:"driver",          lat:51.18,  lng:71.45,  rating:4.3, kyc_level:1 },
  { earth_id:"DLX-DEMO021", name:"Emma Johansson",      role:"user",            lat:59.33,  lng:18.07,  rating:4.6, kyc_level:1 },
  { earth_id:"DLX-DEMO022", name:"Lucas Dupont",        role:"freight_broker",  lat:48.86,  lng:2.35,   rating:4.5, kyc_level:2 },
  { earth_id:"DLX-DEMO023", name:"Amira Mansour",       role:"creator",         lat:30.04,  lng:31.24,  rating:4.7, kyc_level:1 },
  { earth_id:"DLX-DEMO024", name:"Park Jiwoo",          role:"user",            lat:37.57,  lng:126.98, rating:4.4, kyc_level:0 },
  { earth_id:"DLX-DEMO025", name:"Elena Kovacs",        role:"insurance_agent", lat:47.50,  lng:19.04,  rating:4.6, kyc_level:2 },
];

const ROLES = ["همه", "driver", "cargo_owner", "freight_broker", "insurance_agent", "creator", "user"] as const;

// ── Grid clustering ───────────────────────────────────────────────────────────
function buildClusters(users: EarthUser[], cellDeg = 22): Cluster[] {
  const cells = new Map<string, EarthUser[]>();
  for (const u of users) {
    const clat = Math.floor(u.lat / cellDeg) * cellDeg + cellDeg / 2;
    const clng = Math.floor(u.lng / cellDeg) * cellDeg + cellDeg / 2;
    const key  = `${clat.toFixed(1)},${clng.toFixed(1)}`;
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

// ── 3D coordinate ─────────────────────────────────────────────────────────────
function ll2v(lat: number, lng: number, r = 1.0): [number, number, number] {
  const phi   = (90 - lat)  * (Math.PI / 180);
  const theta = (lng + 180) * (Math.PI / 180);
  return [
    r * Math.sin(phi) * Math.cos(theta),
    r * Math.cos(phi),
   -r * Math.sin(phi) * Math.sin(theta),
  ];
}

// ── Canvas textures for markers ───────────────────────────────────────────────
function makeUserDot(THREE: any, color: string): any {
  const S = 64;
  const cv = document.createElement("canvas");
  cv.width = cv.height = S;
  const ctx = cv.getContext("2d")!;
  // glow halo
  const grd = ctx.createRadialGradient(S/2, S/2, 6, S/2, S/2, S/2 - 2);
  grd.addColorStop(0, color + "88");
  grd.addColorStop(1, color + "00");
  ctx.fillStyle = grd;
  ctx.fillRect(0, 0, S, S);
  // dot
  ctx.beginPath();
  ctx.arc(S/2, S/2, 11, 0, Math.PI * 2);
  ctx.fillStyle = color;
  ctx.fill();
  // white ring
  ctx.beginPath();
  ctx.arc(S/2, S/2, 11, 0, Math.PI * 2);
  ctx.strokeStyle = "#ffffff";
  ctx.lineWidth = 3.5;
  ctx.stroke();
  return new THREE.CanvasTexture(cv);
}

function makeClusterDot(THREE: any, color: string, count: number): any {
  const S = 96;
  const cv = document.createElement("canvas");
  cv.width = cv.height = S;
  const ctx = cv.getContext("2d")!;
  // outer glow
  const grd = ctx.createRadialGradient(S/2, S/2, 10, S/2, S/2, S/2 - 2);
  grd.addColorStop(0, color + "55");
  grd.addColorStop(1, color + "00");
  ctx.fillStyle = grd;
  ctx.fillRect(0, 0, S, S);
  // outer pulse ring
  ctx.beginPath();
  ctx.arc(S/2, S/2, 22, 0, Math.PI * 2);
  ctx.fillStyle = color + "30";
  ctx.fill();
  // main circle
  ctx.beginPath();
  ctx.arc(S/2, S/2, 16, 0, Math.PI * 2);
  ctx.fillStyle = color;
  ctx.fill();
  ctx.strokeStyle = "#ffffff";
  ctx.lineWidth = 3;
  ctx.stroke();
  // count label
  const label = count > 99 ? "99+" : String(count);
  ctx.fillStyle = "#ffffff";
  ctx.font = `bold ${label.length > 2 ? 10 : 12}px sans-serif`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(label, S/2, S/2);
  return new THREE.CanvasTexture(cv);
}

// ── Atlas texture from local GeoJSON ─────────────────────────────────────────
const ATLAS_PALETTE = [
  "#F5C06A","#7BC96F","#5BA8E0","#E07B7B","#A87BE0",
  "#7BE0D4","#E0A87B","#E0D87B","#7BA8E0","#D47BE0",
  "#EF8C5E","#5EB88A","#5E9CB8","#B85E5E","#8A5EB8",
  "#5EB8AE","#B88A5E","#B2B85E","#5E8AB8","#B85EA2",
  "#F0AB6A","#6AB87B","#6A9FD8","#D46A6A","#9A6AD4",
];

async function makeAtlasTexture(THREE: any): Promise<any> {
  const W = 2048, H = 1024;
  const cv = document.createElement("canvas");
  cv.width = W; cv.height = H;
  const ctx = cv.getContext("2d")!;

  // Ocean
  const oceanGrd = ctx.createLinearGradient(0, 0, 0, H);
  oceanGrd.addColorStop(0,   "#7AB8E0");
  oceanGrd.addColorStop(0.5, "#5A9FD0");
  oceanGrd.addColorStop(1,   "#3A7FB8");
  ctx.fillStyle = oceanGrd;
  ctx.fillRect(0, 0, W, H);

  // Subtle lat/lng grid
  ctx.strokeStyle = "rgba(255,255,255,0.07)";
  ctx.lineWidth = 0.5;
  for (let lat = -90; lat <= 90; lat += 30) {
    const y = (90 - lat) / 180 * H;
    ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(W, y); ctx.stroke();
  }
  for (let lng = -180; lng <= 180; lng += 30) {
    const x = (lng + 180) / 360 * W;
    ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, H); ctx.stroke();
  }

  // Load countries GeoJSON
  const res = await fetch("/libs/countries.geojson");
  const geo = await res.json();

  const toXY = (coord: number[]): [number, number] => [
    (coord[0] + 180) / 360 * W,
    (90 - coord[1]) / 180 * H,
  ];

  const tracePath = (coordinates: number[][][]) => {
    for (const ring of coordinates) {
      if (ring.length < 2) continue;
      ctx.moveTo(...toXY(ring[0]));
      for (let i = 1; i < ring.length; i++) ctx.lineTo(...toXY(ring[i]));
      ctx.closePath();
    }
  };

  // First pass — fills
  geo.features.forEach((feat: any, i: number) => {
    const color = ATLAS_PALETTE[i % ATLAS_PALETTE.length];
    ctx.beginPath();
    if (feat.geometry.type === "Polygon") {
      tracePath(feat.geometry.coordinates);
    } else if (feat.geometry.type === "MultiPolygon") {
      for (const poly of feat.geometry.coordinates) tracePath(poly);
    }
    ctx.fillStyle = color;
    ctx.fill("evenodd");
  });

  // Second pass — borders
  ctx.strokeStyle = "rgba(255,255,255,0.60)";
  ctx.lineWidth = 0.65;
  geo.features.forEach((feat: any) => {
    ctx.beginPath();
    if (feat.geometry.type === "Polygon") {
      tracePath(feat.geometry.coordinates);
    } else if (feat.geometry.type === "MultiPolygon") {
      for (const poly of feat.geometry.coordinates) tracePath(poly);
    }
    ctx.stroke();
  });

  return new THREE.CanvasTexture(cv);
}

// ── Component ─────────────────────────────────────────────────────────────────
export default function EarthPage() {
  const router    = useRouter();
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const threeRef  = useRef<any>({});

  const [ready,      setReady]      = useState(false);
  const [search,     setSearch]     = useState("");
  const [roleFilter, setRole]       = useState("همه");
  const [showFilter, setFilter]     = useState(false);
  const [drawer,     setDrawer]     = useState<DrawerState | null>(null);

  // Filter marker visibility when search/role changes
  useEffect(() => {
    const all: any[] = [
      ...(threeRef.current.userSprites ?? []),
      ...(threeRef.current.clusterSprites ?? []),
    ];
    all.forEach((s: any) => {
      const cluster: Cluster = s.userData.cluster;
      const hasMatch = cluster.members.some(u =>
        (roleFilter === "همه" || u.role === roleFilter) &&
        (search === "" ||
          u.name.toLowerCase().includes(search.toLowerCase()) ||
          u.earth_id.toLowerCase().includes(search.toLowerCase()))
      );
      s.visible = hasMatch;
    });
  }, [search, roleFilter]);

  const initThree = useCallback((THREE: any) => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const W = canvas.clientWidth  || window.innerWidth;
    const H = canvas.clientHeight || window.innerHeight;

    // ── Renderer ──────────────────────────────────────────────
    const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setSize(W, H);
    renderer.setClearColor(0x080F22);

    // ── Scene / Camera ────────────────────────────────────────
    const scene  = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(42, W / H, 0.1, 1000);
    camera.position.z = 2.6;

    // ── Stars ─────────────────────────────────────────────────
    const starPos = new Float32Array(9000);
    for (let i = 0; i < 9000; i++) starPos[i] = (Math.random() - 0.5) * 700;
    const starGeo = new THREE.BufferGeometry();
    starGeo.setAttribute("position", new THREE.BufferAttribute(starPos, 3));
    scene.add(new THREE.Points(
      starGeo,
      new THREE.PointsMaterial({ color: 0xffffff, size: 0.22, sizeAttenuation: true })
    ));

    // ── Earth group ────────────────────────────────────────────
    const earthGroup = new THREE.Group();
    scene.add(earthGroup);

    // Sphere (placeholder color while texture loads)
    const geo  = new THREE.SphereGeometry(1, 72, 72);
    const mat  = new THREE.MeshPhongMaterial({ color: 0x3A7FB8 });
    const mesh = new THREE.Mesh(geo, mat);
    earthGroup.add(mesh);

    // ── Atmosphere glow ────────────────────────────────────────
    const atmGeo = new THREE.SphereGeometry(1.055, 64, 64);
    const atmMat = new THREE.ShaderMaterial({
      vertexShader: `
        varying vec3 vNormal;
        void main(){
          vNormal = normalize(normalMatrix * normal);
          gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0);
        }`,
      fragmentShader: `
        varying vec3 vNormal;
        void main(){
          float intensity = pow(0.62 - dot(vNormal, vec3(0.0,0.0,1.0)), 3.0);
          gl_FragColor = vec4(0.25, 0.55, 1.0, 1.0) * intensity;
        }`,
      blending:     THREE.AdditiveBlending,
      side:         THREE.FrontSide,
      transparent:  true,
    });
    const atm = new THREE.Mesh(atmGeo, atmMat);
    scene.add(atm);

    // ── Lighting ──────────────────────────────────────────────
    scene.add(new THREE.AmbientLight(0xffffff, 0.9));
    const sun = new THREE.DirectionalLight(0xFFF5E0, 2.2);
    sun.position.set(5, 3, 5);
    scene.add(sun);
    const fill = new THREE.DirectionalLight(0x6699FF, 0.3);
    fill.position.set(-4, -2, -3);
    scene.add(fill);

    // ── Atlas texture ─────────────────────────────────────────
    makeAtlasTexture(THREE).then((tex: any) => {
      mat.map       = tex;
      mat.specular  = new THREE.Color(0x111111);
      mat.shininess = 8;
      mat.needsUpdate = true;
      setReady(true);
    }).catch(() => setReady(true));

    // ── Build markers from clusters ───────────────────────────
    const userSprites:    any[] = [];
    const clusterSprites: any[] = [];
    threeRef.current.userSprites    = userSprites;
    threeRef.current.clusterSprites = clusterSprites;

    const clusters = buildClusters(DEMO, 22);

    for (const cluster of clusters) {
      const isSingle = cluster.count === 1;
      const color    = rc(cluster.dominant_role);
      const tex = isSingle
        ? makeUserDot(THREE, color)
        : makeClusterDot(THREE, color, cluster.count);
      const spriteMat = new THREE.SpriteMaterial({ map: tex, depthTest: false });
      const spr       = new THREE.Sprite(spriteMat);
      const scale     = isSingle ? 0.065 : 0.10;
      spr.scale.set(scale, scale, scale);
      const [x, y, z] = ll2v(cluster.lat, cluster.lng, 1.05);
      spr.position.set(x, y, z);
      spr.userData = { cluster };
      earthGroup.add(spr);
      if (isSingle) userSprites.push(spr);
      else          clusterSprites.push(spr);
    }

    // ── Controls ──────────────────────────────────────────────
    let isDrag = false, moved = false;
    let prevX = 0, prevY = 0;
    let velX = 0, velY = 0;
    let zoom = 2.6;

    const onDown = (cx: number, cy: number) => {
      isDrag = true; moved = false;
      prevX = cx; prevY = cy;
      velX = velY = 0;
    };
    const onMove = (cx: number, cy: number) => {
      if (!isDrag) return;
      const dx = (cx - prevX) * 0.006;
      const dy = (cy - prevY) * 0.006;
      if (Math.abs(dx) > 0.001 || Math.abs(dy) > 0.001) moved = true;
      earthGroup.rotation.y += dx;
      earthGroup.rotation.x = Math.max(-1.2, Math.min(1.2, earthGroup.rotation.x + dy));
      atm.rotation.copy(earthGroup.rotation);
      velX = dy * 0.5; velY = dx * 0.5;
      prevX = cx; prevY = cy;
    };
    const onUp = () => { isDrag = false; };

    // Raycasting
    const raycaster = new THREE.Raycaster();
    const mouse     = new THREE.Vector2();
    const getAllSprites = () => [
      ...(threeRef.current.userSprites    ?? []),
      ...(threeRef.current.clusterSprites ?? []),
    ];

    const onClick = (e: MouseEvent) => {
      if (moved) return;
      const rect = canvas.getBoundingClientRect();
      mouse.x =  ((e.clientX - rect.left) / rect.width)  * 2 - 1;
      mouse.y = -((e.clientY - rect.top)  / rect.height) * 2 + 1;
      raycaster.setFromCamera(mouse, camera);
      const hits = raycaster.intersectObjects(getAllSprites(), false);
      if (hits.length > 0) {
        const cluster: Cluster = hits[0].object.userData.cluster;
        if (cluster.count === 1) {
          setDrawer({ type: "user", user: cluster.members[0] });
        } else {
          setDrawer({ type: "cluster", cluster });
        }
      } else {
        // click on globe body → close drawer
        const earthHit = raycaster.intersectObject(mesh, false);
        if (earthHit.length > 0) setDrawer(null);
      }
    };

    canvas.addEventListener("mousedown",  (e) => onDown(e.clientX, e.clientY));
    canvas.addEventListener("mousemove",  (e) => onMove(e.clientX, e.clientY));
    canvas.addEventListener("mouseup",    onUp);
    canvas.addEventListener("mouseleave", onUp);
    canvas.addEventListener("click",      onClick);

    canvas.addEventListener("touchstart", (e) => {
      if (e.touches.length === 1) onDown(e.touches[0].clientX, e.touches[0].clientY);
    }, { passive: true });
    canvas.addEventListener("touchmove", (e) => {
      if (e.touches.length === 1) onMove(e.touches[0].clientX, e.touches[0].clientY);
      if (e.touches.length === 2) {
        const d = Math.hypot(
          e.touches[0].clientX - e.touches[1].clientX,
          e.touches[0].clientY - e.touches[1].clientY,
        );
        if (threeRef.current.lastPinch) {
          zoom = Math.max(1.3, Math.min(5, zoom - (d - threeRef.current.lastPinch) * 0.008));
          camera.position.z = zoom;
        }
        threeRef.current.lastPinch = d;
      }
    }, { passive: true });
    canvas.addEventListener("touchend", () => { onUp(); threeRef.current.lastPinch = null; });
    canvas.addEventListener("wheel", (e) => {
      e.preventDefault();
      zoom = Math.max(1.3, Math.min(5, zoom + e.deltaY * 0.004));
      camera.position.z = zoom;
    }, { passive: false });

    // ── Animate ───────────────────────────────────────────────
    let animId = 0;
    const tick = () => {
      animId = requestAnimationFrame(tick);
      if (!isDrag) {
        velX *= 0.95; velY *= 0.95;
        earthGroup.rotation.x = Math.max(-1.2, Math.min(1.2, earthGroup.rotation.x + velX));
        earthGroup.rotation.y += velY + 0.0005;
        atm.rotation.copy(earthGroup.rotation);
      }
      renderer.render(scene, camera);
    };
    tick();
    threeRef.current.animId = animId;

    const onResize = () => {
      const w = canvas.clientWidth, h = canvas.clientHeight;
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
      renderer.setSize(w, h);
    };
    window.addEventListener("resize", onResize);

    return () => {
      cancelAnimationFrame(animId);
      renderer.dispose();
      window.removeEventListener("resize", onResize);
    };
  }, []);

  useEffect(() => {
    const win = window as any;
    let cleanup: (() => void) | undefined;
    const init = () => { cleanup = initThree(win.THREE) ?? undefined; };
    if (win.THREE) { init(); return () => cleanup?.(); }
    const s   = document.createElement("script");
    s.src     = "/libs/three.min.js";
    s.async   = true;
    s.onload  = init;
    document.head.appendChild(s);
    return () => {
      cleanup?.();
      if (threeRef.current.animId) cancelAnimationFrame(threeRef.current.animId);
    };
  }, [initThree]);

  // ── JSX ───────────────────────────────────────────────────────────────────
  return (
    <div className="relative overflow-hidden" style={{ height: "100dvh", background: "#080F22" }}>

      {/* Canvas */}
      <canvas
        ref={canvasRef}
        className="absolute inset-0 w-full h-full"
        style={{ cursor: "grab" }}
      />

      {/* ── Loading overlay ── */}
      {!ready && (
        <div
          className="absolute inset-0 flex flex-col items-center justify-center"
          style={{ zIndex: 20, background: "#080F22" }}
        >
          <div className="relative mb-6">
            <div className="absolute inset-0 rounded-full border-2 border-blue-400/20 animate-ping scale-150" />
            <div className="w-20 h-20 rounded-full border-2 border-blue-500/40 flex items-center justify-center text-5xl">
              🌍
            </div>
          </div>
          <p className="text-blue-200/80 text-sm font-semibold tracking-widest">DILIX EARTH</p>
          <p className="text-blue-800 text-xs mt-1">در حال رسم نقشه جهان...</p>
        </div>
      )}

      {/* ── Top bar ── */}
      <div
        className="absolute top-0 inset-x-0 p-3 pointer-events-none"
        style={{ zIndex: 30 }}
      >
        <div className="flex items-center gap-2 pointer-events-auto">
          <div className="relative flex-1">
            <Search
              size={14}
              className="absolute right-3 top-1/2 -translate-y-1/2"
              style={{ color: "rgba(147,197,253,0.45)" }}
            />
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
                {r === "همه" ? `همه (${DEMO.length})` : `${rem(r)} ${rl(r)}`}
              </button>
            ))}
          </div>
        )}
      </div>

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
              <div
                className="w-10 h-1 rounded-full"
                style={{ background: "rgba(255,255,255,0.15)" }}
              />
              <button
                onClick={() => setDrawer(null)}
                className="p-1"
                style={{ color: "rgba(147,197,253,0.4)" }}
              >
                <X size={18} />
              </button>
            </div>

            {drawer.type === "user" ? (
              /* ── Single user card ── */
              <div className="px-4 pb-4 pt-1">
                <div className="flex items-start gap-3 mb-3">
                  <div
                    className="w-14 h-14 rounded-full flex items-center justify-center text-2xl flex-shrink-0 border-2 overflow-hidden"
                    style={{
                      borderColor: rc(drawer.user.role) + "80",
                      background:  rc(drawer.user.role) + "25",
                    }}
                  >
                    {drawer.user.avatar_url
                      ? <img src={drawer.user.avatar_url} className="w-full h-full object-cover" alt="" />
                      : rem(drawer.user.role)}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-1.5">
                      <p className="text-white font-bold truncate">{drawer.user.name}</p>
                      {drawer.user.kyc_level >= 2 && (
                        <ShieldCheck size={14} className="text-emerald-400 flex-shrink-0" />
                      )}
                    </div>
                    <p
                      className="text-[11px] font-mono mt-0.5"
                      style={{ color: "rgba(147,197,253,0.5)" }}
                    >
                      {drawer.user.earth_id}
                    </p>
                    <div className="flex items-center gap-2 mt-1.5 flex-wrap">
                      <span
                        className="text-xs px-2 py-0.5 rounded-full font-medium"
                        style={{ background: rc(drawer.user.role) + "28", color: rc(drawer.user.role) }}
                      >
                        {rl(drawer.user.role)}
                      </span>
                      <div className="flex items-center gap-0.5">
                        <Star size={11} className="text-amber-400 fill-amber-400" />
                        <span className="text-xs" style={{ color: "rgba(147,197,253,0.75)" }}>
                          {drawer.user.rating}
                        </span>
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
                    style={{
                      borderColor: rc(drawer.user.role) + "55",
                      color:       rc(drawer.user.role),
                      background:  "rgba(255,255,255,0.04)",
                    }}
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
                    {toPersianNum(drawer.cluster.count)} نفر در این منطقه
                  </p>
                </div>
                <div className="space-y-1 max-h-56 overflow-y-auto no-scrollbar">
                  {drawer.cluster.members.map(u => (
                    <button
                      key={u.earth_id}
                      onClick={() => setDrawer({ type: "user", user: u })}
                      className="w-full flex items-center gap-3 p-2.5 rounded-xl active:scale-[0.99] transition-all text-right"
                      style={{
                        background: "rgba(255,255,255,0.04)",
                        border:     "1px solid rgba(255,255,255,0.07)",
                      }}
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
                      <div className="flex items-center gap-1 flex-shrink-0">
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
