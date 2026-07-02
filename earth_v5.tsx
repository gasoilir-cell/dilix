"use client";

import { useEffect, useRef, useState, useCallback } from "react";
import { Search, Filter, Star, ShieldCheck, MessageCircle, Handshake, X } from "lucide-react";
import BottomNav from "@/components/layout/BottomNav";
import { cn } from "@/lib/utils";
import { useRouter } from "next/navigation";

// ─── Types ───────────────────────────────────────────────────
interface EarthUser {
  earth_id: string; name: string; role: string;
  lat: number; lng: number; rating: number;
  kyc_level: number; avatar_url?: string;
}

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

const DEMO_USERS: EarthUser[] = [
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

const ROLES = ["همه","driver","cargo_owner","freight_broker","insurance_agent","creator","user"] as const;

// ─── Helper: lat/lng → 3D point on sphere ────────────────────
function latLngToVec3(lat: number, lng: number, r = 1.02) {
  const phi   = (90 - lat)  * (Math.PI / 180);
  const theta = (lng + 180) * (Math.PI / 180);
  return {
    x:  r * Math.sin(phi) * Math.cos(theta),
    y:  r * Math.cos(phi),
    z: -r * Math.sin(phi) * Math.sin(theta),
  };
}

export default function EarthPage() {
  const router  = useRouter();
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const stateRef  = useRef<any>({});  // Three.js state

  const [ready,    setReady]    = useState(false);
  const [selected, setSelected] = useState<EarthUser|null>(null);
  const [search,   setSearch]   = useState("");
  const [roleFilter,setRole]    = useState("همه");
  const [showFilter,setFilter]  = useState(false);

  const filtered = DEMO_USERS.filter(u =>
    (roleFilter === "همه" || u.role === roleFilter) &&
    (search === "" ||
      u.name.toLowerCase().includes(search.toLowerCase()) ||
      u.earth_id.toLowerCase().includes(search.toLowerCase()))
  );

  // ─── Init Three.js ─────────────────────────────────────────
  const initThree = useCallback((THREE: any) => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const W = canvas.clientWidth;
    const H = canvas.clientHeight;

    // Scene
    const scene    = new THREE.Scene();
    const camera   = new THREE.PerspectiveCamera(45, W / H, 0.1, 1000);
    camera.position.z = 2.8;

    const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setSize(W, H);
    renderer.setClearColor(0x000510, 1);

    // ── Stars ──────────────────────────────────────────────
    const starGeo = new THREE.BufferGeometry();
    const starCount = 3000;
    const starPos = new Float32Array(starCount * 3);
    for (let i = 0; i < starCount * 3; i++) {
      starPos[i] = (Math.random() - 0.5) * 400;
    }
    starGeo.setAttribute("position", new THREE.BufferAttribute(starPos, 3));
    const starMat  = new THREE.PointsMaterial({ color: 0xffffff, size: 0.2, sizeAttenuation: true });
    scene.add(new THREE.Points(starGeo, starMat));

    // ── Earth ──────────────────────────────────────────────
    const loader   = new THREE.TextureLoader();
    const earthGeo = new THREE.SphereGeometry(1, 64, 64);

    // placeholder material (while textures load)
    const tempMat  = new THREE.MeshPhongMaterial({ color: 0x1a4a7a });
    const earth    = new THREE.Mesh(earthGeo, tempMat);
    scene.add(earth);

    // Load textures
    let loadedCount = 0;
    const onLoad = () => {
      loadedCount++;
      if (loadedCount >= 1) { // حداقل texture اصلی لود بشه
        setReady(true);
      }
    };

    loader.load("/libs/earth.jpg", (tex: any) => {
      tex.anisotropy = renderer.capabilities.getMaxAnisotropy();
      const mat = new THREE.MeshPhongMaterial({
        map: tex,
        specular: new THREE.Color(0x333333),
        shininess: 15,
      });
      loader.load("/libs/earth_bump.jpg", (bump: any) => {
        mat.bumpMap   = bump;
        mat.bumpScale = 0.05;
        loader.load("/libs/earth_clouds.png", (clouds: any) => {
          // لایه ابرها
          const cloudGeo = new THREE.SphereGeometry(1.008, 64, 64);
          const cloudMat = new THREE.MeshPhongMaterial({
            map:         clouds,
            transparent: true,
            opacity:     0.35,
            depthWrite:  false,
          });
          const cloudMesh = new THREE.Mesh(cloudGeo, cloudMat);
          scene.add(cloudMesh);
          stateRef.current.clouds = cloudMesh;
        });
      });
      earth.material = mat;
      onLoad();
    }, undefined, () => {
      // fallback اگه texture لود نشد
      onLoad();
    });

    // ── Atmosphere glow ────────────────────────────────────
    const atmGeo = new THREE.SphereGeometry(1.05, 64, 64);
    const atmMat = new THREE.MeshPhongMaterial({
      color:       0x4488ff,
      transparent: true,
      opacity:     0.08,
      side:        THREE.FrontSide,
    });
    const atm = new THREE.Mesh(atmGeo, atmMat);
    scene.add(atm);

    // ── Lighting ───────────────────────────────────────────
    const sun = new THREE.DirectionalLight(0xfff5e0, 1.8);
    sun.position.set(5, 3, 5);
    scene.add(sun);
    scene.add(new THREE.AmbientLight(0x223366, 0.8));

    // ── User Markers ───────────────────────────────────────
    const markerGeo = new THREE.SphereGeometry(0.018, 12, 12);

    DEMO_USERS.forEach(u => {
      const color  = new THREE.Color(rc(u.role));
      const mat    = new THREE.MeshBasicMaterial({ color });
      const mesh   = new THREE.Mesh(markerGeo, mat);
      const pos    = latLngToVec3(u.lat, u.lng, 1.03);
      mesh.position.set(pos.x, pos.y, pos.z);
      mesh.userData = { user: u };
      scene.add(mesh);

      // Glow ring
      const ringGeo = new THREE.RingGeometry(0.022, 0.030, 16);
      const ringMat = new THREE.MeshBasicMaterial({
        color, side: THREE.DoubleSide, transparent: true, opacity: 0.5
      });
      const ring = new THREE.Mesh(ringGeo, ringMat);
      ring.position.set(pos.x, pos.y, pos.z);
      // orient ring to face outward
      ring.lookAt(0, 0, 0);
      ring.userData = { user: u };
      scene.add(ring);
    });

    // ── Mouse / Touch controls ─────────────────────────────
    let isDragging = false;
    let prevMouse  = { x: 0, y: 0 };
    let rotVel     = { x: 0, y: 0 };
    let zoom = 2.8;

    const onMouseDown = (e: MouseEvent | TouchEvent) => {
      isDragging = true;
      rotVel     = { x: 0, y: 0 };
      const p    = "touches" in e ? e.touches[0] : e;
      prevMouse  = { x: p.clientX, y: p.clientY };
    };
    const onMouseMove = (e: MouseEvent | TouchEvent) => {
      if (!isDragging) return;
      const p  = "touches" in e ? e.touches[0] : e;
      const dx = (p.clientX - prevMouse.x) * 0.005;
      const dy = (p.clientY - prevMouse.y) * 0.005;
      earth.rotation.y += dx;
      earth.rotation.x  = Math.max(-Math.PI/2, Math.min(Math.PI/2, earth.rotation.x + dy));
      if (stateRef.current.clouds) {
        stateRef.current.clouds.rotation.y = earth.rotation.y + 0.05;
        stateRef.current.clouds.rotation.x = earth.rotation.x;
      }
      atm.rotation.copy(earth.rotation);
      rotVel = { x: dy * 0.6, y: dx * 0.6 };
      prevMouse = { x: p.clientX, y: p.clientY };
    };
    const onMouseUp   = () => { isDragging = false; };
    const onWheel     = (e: WheelEvent) => {
      e.preventDefault();
      zoom = Math.max(1.4, Math.min(5, zoom + e.deltaY * 0.003));
      camera.position.z = zoom;
    };

    // Raycasting برای کلیک روی marker
    const raycaster = new THREE.Raycaster();
    const mouse2d   = new THREE.Vector2();
    const onClick   = (e: MouseEvent) => {
      if (Math.abs(rotVel.x) > 0.005 || Math.abs(rotVel.y) > 0.005) return;
      const rect = canvas.getBoundingClientRect();
      mouse2d.x  =  ((e.clientX - rect.left) / rect.width)  * 2 - 1;
      mouse2d.y  = -((e.clientY - rect.top)  / rect.height) * 2 + 1;
      raycaster.setFromCamera(mouse2d, camera);
      const meshes = scene.children.filter((o: any) => o.userData?.user);
      const hits   = raycaster.intersectObjects(meshes);
      if (hits.length > 0) {
        setSelected(hits[0].object.userData.user);
      } else {
        setSelected(null);
      }
    };

    canvas.addEventListener("mousedown",  onMouseDown as any);
    canvas.addEventListener("mousemove",  onMouseMove as any);
    canvas.addEventListener("mouseup",    onMouseUp);
    canvas.addEventListener("mouseleave", onMouseUp);
    canvas.addEventListener("touchstart", onMouseDown as any, { passive: true });
    canvas.addEventListener("touchmove",  onMouseMove as any, { passive: true });
    canvas.addEventListener("touchend",   onMouseUp);
    canvas.addEventListener("wheel",      onWheel, { passive: false });
    canvas.addEventListener("click",      onClick);

    // ── Animate ───────────────────────────────────────────
    let animId: number;
    const tick = () => {
      animId = requestAnimationFrame(tick);

      // auto-rotate وقتی نمی‌کشیم
      if (!isDragging) {
        earth.rotation.y  += 0.001;
        rotVel.x *= 0.95;
        rotVel.y *= 0.95;
        earth.rotation.x  = Math.max(-Math.PI/3, Math.min(Math.PI/3, earth.rotation.x + rotVel.x));
        earth.rotation.y += rotVel.y;
      }
      if (stateRef.current.clouds) {
        stateRef.current.clouds.rotation.y = earth.rotation.y + 0.002 * performance.now() * 0.0002;
      }
      atm.rotation.copy(earth.rotation);
      renderer.render(scene, camera);
    };
    tick();

    // Resize
    const onResize = () => {
      const w = canvas.clientWidth;
      const h = canvas.clientHeight;
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
      renderer.setSize(w, h);
    };
    window.addEventListener("resize", onResize);

    stateRef.current = { ...stateRef.current, animId, renderer, scene, camera };

    return () => {
      cancelAnimationFrame(animId);
      renderer.dispose();
      window.removeEventListener("resize", onResize);
      canvas.removeEventListener("mousedown",  onMouseDown as any);
      canvas.removeEventListener("mousemove",  onMouseMove as any);
      canvas.removeEventListener("mouseup",    onMouseUp);
      canvas.removeEventListener("mouseleave", onMouseUp);
      canvas.removeEventListener("touchstart", onMouseDown as any);
      canvas.removeEventListener("touchmove",  onMouseMove as any);
      canvas.removeEventListener("touchend",   onMouseUp);
      canvas.removeEventListener("wheel",      onWheel);
      canvas.removeEventListener("click",      onClick);
    };
  }, []);

  // ─── Load Three.js script ──────────────────────────────────
  useEffect(() => {
    const win = window as any;
    if (win.THREE) { initThree(win.THREE); return; }

    const script  = document.createElement("script");
    script.src    = "/libs/three.min.js";
    script.async  = true;
    script.onload = () => initThree((window as any).THREE);
    document.head.appendChild(script);

    return () => { stateRef.current.animId && cancelAnimationFrame(stateRef.current.animId); };
  }, [initThree]);

  return (
    <div className="relative overflow-hidden bg-black" style={{ height:"100dvh" }}>

      {/* ─── Canvas ─── */}
      <canvas
        ref={canvasRef}
        className="absolute inset-0 w-full h-full"
        style={{ cursor: "grab" }}
      />

      {/* ─── Loading ─── */}
      {!ready && (
        <div className="absolute inset-0 flex flex-col items-center justify-center bg-[#000510]" style={{zIndex:20}}>
          <div className="relative w-20 h-20 mx-auto mb-5">
            <div className="absolute inset-0 rounded-full border-2 border-blue-500/20 animate-ping" />
            <div className="absolute inset-1 rounded-full border-2 border-blue-400/40 animate-pulse" />
            <div className="w-20 h-20 rounded-full flex items-center justify-center text-4xl">🌍</div>
          </div>
          <p className="text-blue-200 text-sm font-medium tracking-wide">در حال بارگذاری کره زمین...</p>
          <p className="text-blue-900 text-xs mt-1">Dilix Earth</p>
        </div>
      )}

      {/* ─── Top bar ─── */}
      <div className="absolute top-0 inset-x-0 p-3 pointer-events-none" style={{zIndex:30}}>
        <div className="flex items-center gap-2 pointer-events-auto">
          <div className="relative flex-1">
            <Search size={14} className="absolute right-3 top-1/2 -translate-y-1/2 text-blue-300/60" />
            <input
              value={search}
              onChange={e => setSearch(e.target.value)}
              placeholder="جستجوی نام یا Earth ID..."
              className="w-full bg-black/50 backdrop-blur-md border border-blue-900/60 rounded-xl pr-9 pl-4 py-2.5 text-sm text-blue-100 placeholder-blue-700 focus:outline-none focus:border-blue-500"
              style={{ direction:"rtl" }}
            />
          </div>
          <button
            onClick={() => setFilter(f => !f)}
            className={cn(
              "flex-shrink-0 p-2.5 rounded-xl border backdrop-blur-md transition-all",
              showFilter
                ? "bg-blue-600/80 border-blue-500 text-white"
                : "bg-black/50 border-blue-900/60 text-blue-300"
            )}
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
                className={cn(
                  "flex-shrink-0 text-xs px-3 py-1.5 rounded-full border transition-all whitespace-nowrap backdrop-blur-md",
                  roleFilter === r
                    ? "bg-blue-600/80 border-blue-500 text-white"
                    : "bg-black/50 border-blue-900/60 text-blue-300 hover:border-blue-600"
                )}
              >
                {r === "همه" ? `همه (${DEMO_USERS.length})` : `${rem(r)} ${rl(r)}`}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* ─── Selected card ─── */}
      {selected && (
        <div className="absolute inset-x-3 pointer-events-auto" style={{ bottom:"80px", zIndex:30 }}>
          <div className="bg-black/80 backdrop-blur-xl rounded-2xl border border-blue-900/60 p-4 shadow-2xl">
            <div className="flex items-start gap-3">
              <div
                className="w-12 h-12 rounded-full flex items-center justify-center text-2xl flex-shrink-0 border-2 overflow-hidden"
                style={{ borderColor:`${rc(selected.role)}80`, background:`${rc(selected.role)}18` }}
              >
                {selected.avatar_url
                  ? <img src={selected.avatar_url} className="w-full h-full object-cover" alt="" />
                  : rem(selected.role)}
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <p className="text-white font-bold text-sm">{selected.name}</p>
                  {selected.kyc_level >= 2 && <ShieldCheck size={13} className="text-green-400 flex-shrink-0" />}
                </div>
                <p className="text-blue-400/70 font-mono text-[11px]">{selected.earth_id}</p>
                <div className="flex items-center gap-2 mt-1">
                  <span className="text-xs px-2 py-0.5 rounded-full font-medium"
                    style={{ background:`${rc(selected.role)}25`, color:rc(selected.role) }}>
                    {rl(selected.role)}
                  </span>
                  <div className="flex items-center gap-0.5">
                    <Star size={11} className="text-amber-400 fill-amber-400" />
                    <span className="text-xs text-blue-300/70">{selected.rating}</span>
                  </div>
                </div>
              </div>
              <button onClick={() => setSelected(null)} className="p-1 text-blue-700 hover:text-white flex-shrink-0">
                <X size={18} />
              </button>
            </div>
            <div className="flex gap-2 mt-3">
              <button
                onClick={() => router.push(`/messages/${selected.earth_id}`)}
                className="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl text-white text-sm font-semibold transition-all hover:opacity-90 active:scale-95"
                style={{ background: rc(selected.role) }}
              >
                <MessageCircle size={15} />
                شروع گفتگو
              </button>
              <button
                onClick={() => router.push(`/messages/${selected.earth_id}?type=collaboration`)}
                className="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl text-sm font-semibold border transition-all hover:bg-white/10 active:scale-95"
                style={{ borderColor:`${rc(selected.role)}60`, color:rc(selected.role) }}
              >
                <Handshake size={15} />
                همکاری
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ─── Bottom strip ─── */}
      {!selected && (
        <div className="absolute inset-x-0 pointer-events-auto" style={{ bottom:"60px", zIndex:30 }}>
          <div className="flex gap-2 overflow-x-auto px-3 pb-2 no-scrollbar">
            {filtered.slice(0,14).map(u => (
              <button
                key={u.earth_id}
                onClick={() => setSelected(u)}
                className="flex-shrink-0 w-20 bg-black/70 backdrop-blur-md border border-blue-900/50 rounded-xl p-2 text-right hover:border-blue-600/70 active:scale-95 transition-all"
              >
                <div className="flex items-center gap-1.5 mb-1">
                  {u.avatar_url
                    ? <img src={u.avatar_url} className="w-5 h-5 rounded-full object-cover flex-shrink-0 border"
                        style={{borderColor:rc(u.role)}} alt="" />
                    : <div className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{backgroundColor:rc(u.role)}} />}
                  <p className="text-white text-[11px] font-semibold truncate">{u.name.split(" ")[0]}</p>
                </div>
                <p className="text-[9px] font-medium" style={{color:rc(u.role)}}>{rl(u.role)}</p>
                <div className="flex items-center gap-0.5 mt-0.5">
                  <Star size={8} className="text-amber-400 fill-amber-400" />
                  <p className="text-[9px] text-blue-300/60">{u.rating}</p>
                </div>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* ─── BottomNav ─── */}
      <div style={{ position:"absolute", bottom:0, left:0, right:0, zIndex:50 }}>
        <BottomNav />
      </div>
    </div>
  );
}
