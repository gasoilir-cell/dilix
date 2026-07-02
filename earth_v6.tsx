"use client";

import { useEffect, useRef, useState, useCallback } from "react";
import { Search, Filter, Star, ShieldCheck, MessageCircle, Handshake, X } from "lucide-react";
import BottomNav from "@/components/layout/BottomNav";
import { cn } from "@/lib/utils";
import { useRouter } from "next/navigation";

interface EarthUser {
  earth_id: string; name: string; role: string;
  lat: number; lng: number; rating: number;
  kyc_level: number; avatar_url?: string;
}

const ROLE_COLOR: Record<string,string> = {
  driver:"#f59e0b", cargo_owner:"#06b6d4", freight_broker:"#a855f7",
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

const ROLES = ["همه","driver","cargo_owner","freight_broker","insurance_agent","creator","user"] as const;

// lat/lng → 3D position on unit sphere
function ll2v(lat: number, lng: number, r = 1.0) {
  const phi   = (90 - lat)  * (Math.PI / 180);
  const theta = (lng + 180) * (Math.PI / 180);
  return [
    r * Math.sin(phi) * Math.cos(theta),
    r * Math.cos(phi),
   -r * Math.sin(phi) * Math.sin(theta),
  ] as [number, number, number];
}

// CanvasTexture برای sprite marker (emoji + circle)
function makeMarkerTexture(THREE: any, color: string, emoji: string, avatarUrl?: string): Promise<any> {
  return new Promise((resolve) => {
    const SIZE = 128;
    const cv   = document.createElement("canvas");
    cv.width   = SIZE;
    cv.height  = SIZE;
    const ctx  = cv.getContext("2d")!;

    const draw = (imgSrc?: HTMLImageElement) => {
      // outer glow ring
      ctx.clearRect(0, 0, SIZE, SIZE);
      ctx.beginPath();
      ctx.arc(SIZE/2, SIZE/2, SIZE/2 - 2, 0, Math.PI*2);
      const grad = ctx.createRadialGradient(SIZE/2, SIZE/2, SIZE/3, SIZE/2, SIZE/2, SIZE/2);
      grad.addColorStop(0, color + "60");
      grad.addColorStop(1, color + "00");
      ctx.fillStyle = grad;
      ctx.fill();

      // circle bg
      ctx.beginPath();
      ctx.arc(SIZE/2, SIZE/2, SIZE/2 - 10, 0, Math.PI*2);
      ctx.fillStyle = color;
      ctx.fill();

      // white border
      ctx.beginPath();
      ctx.arc(SIZE/2, SIZE/2, SIZE/2 - 10, 0, Math.PI*2);
      ctx.strokeStyle = "rgba(255,255,255,0.9)";
      ctx.lineWidth = 5;
      ctx.stroke();

      if (imgSrc) {
        // clip به دایره و رسم avatar
        ctx.save();
        ctx.beginPath();
        ctx.arc(SIZE/2, SIZE/2, SIZE/2 - 13, 0, Math.PI*2);
        ctx.clip();
        ctx.drawImage(imgSrc, 10, 10, SIZE - 20, SIZE - 20);
        ctx.restore();
      } else {
        // emoji
        ctx.font      = `${SIZE * 0.42}px serif`;
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillText(emoji, SIZE/2, SIZE/2 + 2);
      }

      resolve(new THREE.CanvasTexture(cv));
    };

    if (avatarUrl) {
      const img = new Image();
      img.crossOrigin = "anonymous";
      img.onload  = () => draw(img);
      img.onerror = () => draw();
      img.src     = avatarUrl;
    } else {
      draw();
    }
  });
}

export default function EarthPage() {
  const router    = useRouter();
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const threeRef  = useRef<any>({});

  const [ready,     setReady]     = useState(false);
  const [selected,  setSelected]  = useState<EarthUser|null>(null);
  const [search,    setSearch]    = useState("");
  const [roleFilter,setRole]      = useState("همه");
  const [showFilter,setFilter]    = useState(false);

  const filtered = DEMO.filter(u =>
    (roleFilter === "همه" || u.role === roleFilter) &&
    (search === "" ||
      u.name.toLowerCase().includes(search.toLowerCase()) ||
      u.earth_id.toLowerCase().includes(search.toLowerCase()))
  );

  // نمایش/مخفی کردن markers هنگام فیلتر
  useEffect(() => {
    const sprites: any[] = threeRef.current.sprites ?? [];
    sprites.forEach((s: any) => {
      const u: EarthUser = s.userData.user;
      const show = (roleFilter === "همه" || u.role === roleFilter) &&
                   (search === "" ||
                    u.name.toLowerCase().includes(search.toLowerCase()) ||
                    u.earth_id.toLowerCase().includes(search.toLowerCase()));
      s.visible = show;
    });
  }, [search, roleFilter]);

  const initThree = useCallback((THREE: any) => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const W = canvas.clientWidth  || window.innerWidth;
    const H = canvas.clientHeight || window.innerHeight;

    // ── Renderer ─────────────────────────────────────────────
    const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setSize(W, H);
    renderer.setClearColor(0x000510);

    // ── Scene / Camera ────────────────────────────────────────
    const scene  = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(42, W / H, 0.1, 1000);
    camera.position.z = 2.6;

    // ── Stars ─────────────────────────────────────────────────
    const starBuf = new Float32Array(6000);
    for (let i = 0; i < 6000; i++) starBuf[i] = (Math.random() - 0.5) * 600;
    const starGeo = new THREE.BufferGeometry();
    starGeo.setAttribute("position", new THREE.BufferAttribute(starBuf, 3));
    scene.add(new THREE.Points(starGeo, new THREE.PointsMaterial({ color:0xffffff, size:0.3 })));

    // ── Earth GROUP (همه چیز داخل group چرخش می‌خورد) ────────
    const earthGroup = new THREE.Group();
    scene.add(earthGroup);

    // sphere
    const geo  = new THREE.SphereGeometry(1, 64, 64);
    const mat  = new THREE.MeshPhongMaterial({ color:0x2a6fa8 }); // placeholder
    const mesh = new THREE.Mesh(geo, mat);
    earthGroup.add(mesh);

    // ── Load textures ─────────────────────────────────────────
    const loader = new THREE.TextureLoader();
    loader.load("/libs/earth.jpg", (tex: any) => {
      tex.anisotropy = renderer.capabilities.getMaxAnisotropy();
      mat.map      = tex;
      mat.specular = new THREE.Color(0x555555);
      mat.shininess = 25;
      mat.needsUpdate = true;
      setReady(true);

      // bump
      loader.load("/libs/earth_bump.jpg", (bump: any) => {
        mat.bumpMap   = bump;
        mat.bumpScale = 0.06;
        mat.needsUpdate = true;
      });

      // clouds — layer روی کره
      loader.load("/libs/earth_clouds.png", (cl: any) => {
        const cGeo = new THREE.SphereGeometry(1.012, 64, 64);
        const cMat = new THREE.MeshPhongMaterial({
          map: cl, transparent: true, opacity: 0.45, depthWrite: false,
        });
        const clouds = new THREE.Mesh(cGeo, cMat);
        earthGroup.add(clouds);
        threeRef.current.clouds = clouds;
      });
    }, undefined, () => setReady(true));  // اگه texture fail شد باز نقشه نشون بده

    // ── Atmosphere ────────────────────────────────────────────
    const atmGeo = new THREE.SphereGeometry(1.06, 64, 64);
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
          float intensity = pow(0.65 - dot(vNormal, vec3(0,0,1.0)), 3.0);
          gl_FragColor = vec4(0.3, 0.6, 1.0, 1.0) * intensity;
        }`,
      blending: THREE.AdditiveBlending,
      side: THREE.FrontSide,
      transparent: true,
    });
    const atm = new THREE.Mesh(atmGeo, atmMat);
    scene.add(atm); // atmosphere در scene (نه group) تا همیشه ثابت باشه

    // ── Lighting ──────────────────────────────────────────────
    scene.add(new THREE.AmbientLight(0xffffff, 1.2));
    const sun = new THREE.DirectionalLight(0xfff8e0, 2.5);
    sun.position.set(6, 3, 5);
    scene.add(sun);
    // fill light از طرف دیگه
    const fill = new THREE.DirectionalLight(0x4488ff, 0.4);
    fill.position.set(-5, -2, -3);
    scene.add(fill);

    // ── Markers (sprites داخل earthGroup) ─────────────────────
    const sprites: any[] = [];
    threeRef.current.sprites = sprites;

    Promise.all(DEMO.map(async (u) => {
      const tex = await makeMarkerTexture(THREE, rc(u.role), rem(u.role), u.avatar_url);
      const mat = new THREE.SpriteMaterial({ map: tex, depthTest: false });
      const spr = new THREE.Sprite(mat);
      spr.scale.set(0.10, 0.10, 0.10);
      const [x, y, z] = ll2v(u.lat, u.lng, 1.08);
      spr.position.set(x, y, z);
      spr.userData = { user: u };
      earthGroup.add(spr);
      sprites.push(spr);
    }));

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
      earthGroup.rotation.x  = Math.max(-1.2, Math.min(1.2, earthGroup.rotation.x + dy));
      atm.rotation.copy(earthGroup.rotation);
      velX = dy * 0.5; velY = dx * 0.5;
      prevX = cx; prevY = cy;
    };
    const onUp = () => { isDrag = false; };

    // Raycasting برای کلیک روی sprite
    const raycaster = new THREE.Raycaster();
    const mouse     = new THREE.Vector2();
    const onClick   = (e: MouseEvent) => {
      if (moved) return;
      const rect = canvas.getBoundingClientRect();
      mouse.x    =  ((e.clientX - rect.left) / rect.width)  * 2 - 1;
      mouse.y    = -((e.clientY - rect.top)  / rect.height) * 2 + 1;
      raycaster.setFromCamera(mouse, camera);
      const hits = raycaster.intersectObjects(sprites, false);
      if (hits.length > 0) {
        setSelected(hits[0].object.userData.user);
      } else {
        // کلیک روی زمین → deselect
        const earthHit = raycaster.intersectObject(mesh, false);
        if (earthHit.length > 0) setSelected(null);
      }
    };

    canvas.addEventListener("mousedown",  (e) => onDown(e.clientX, e.clientY));
    canvas.addEventListener("mousemove",  (e) => onMove(e.clientX, e.clientY));
    canvas.addEventListener("mouseup",    onUp);
    canvas.addEventListener("mouseleave", onUp);
    canvas.addEventListener("click",      onClick);

    // touch
    canvas.addEventListener("touchstart", (e) => {
      if (e.touches.length === 1) onDown(e.touches[0].clientX, e.touches[0].clientY);
    }, { passive:true });
    canvas.addEventListener("touchmove",  (e) => {
      if (e.touches.length === 1) onMove(e.touches[0].clientX, e.touches[0].clientY);
      // pinch zoom
      if (e.touches.length === 2) {
        const d = Math.hypot(
          e.touches[0].clientX - e.touches[1].clientX,
          e.touches[0].clientY - e.touches[1].clientY
        );
        if (threeRef.current.lastPinch) {
          zoom = Math.max(1.3, Math.min(5, zoom - (d - threeRef.current.lastPinch) * 0.008));
          camera.position.z = zoom;
        }
        threeRef.current.lastPinch = d;
      }
    }, { passive:true });
    canvas.addEventListener("touchend",   () => { onUp(); threeRef.current.lastPinch = null; });

    // scroll zoom (desktop)
    canvas.addEventListener("wheel", (e) => {
      e.preventDefault();
      zoom = Math.max(1.3, Math.min(5, zoom + e.deltaY * 0.004));
      camera.position.z = zoom;
    }, { passive:false });

    // ── Animate ───────────────────────────────────────────────
    let animId = 0;
    const tick = () => {
      animId = requestAnimationFrame(tick);

      if (!isDrag) {
        // inertia + auto-rotate
        velX *= 0.95; velY *= 0.95;
        earthGroup.rotation.x = Math.max(-1.2, Math.min(1.2, earthGroup.rotation.x + velX));
        earthGroup.rotation.y += velY + 0.0008;
        atm.rotation.copy(earthGroup.rotation);
      }

      // clouds آهسته‌تر از زمین
      if (threeRef.current.clouds) {
        threeRef.current.clouds.rotation.y = earthGroup.rotation.y * 0.98 + 0.001;
        threeRef.current.clouds.rotation.x = earthGroup.rotation.x;
      }

      renderer.render(scene, camera);
    };
    tick();
    threeRef.current.animId = animId;

    // resize
    const onResize = () => {
      const w = canvas.clientWidth;
      const h = canvas.clientHeight;
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

  // ── Load Three.js ──────────────────────────────────────────
  useEffect(() => {
    const win = window as any;
    let cleanup: (() => void) | undefined;

    const init = () => {
      cleanup = initThree(win.THREE) ?? undefined;
    };

    if (win.THREE) { init(); return () => cleanup?.(); }

    const s  = document.createElement("script");
    s.src    = "/libs/three.min.js";
    s.async  = true;
    s.onload = init;
    document.head.appendChild(s);

    return () => {
      cleanup?.();
      if (threeRef.current.animId) cancelAnimationFrame(threeRef.current.animId);
    };
  }, [initThree]);

  return (
    <div className="relative overflow-hidden" style={{ height:"100dvh", background:"#000510" }}>

      {/* ─── Canvas ─── */}
      <canvas ref={canvasRef} className="absolute inset-0 w-full h-full" style={{ cursor:"grab" }} />

      {/* ─── Loading ─── */}
      {!ready && (
        <div className="absolute inset-0 flex flex-col items-center justify-center" style={{ zIndex:20, background:"#000510" }}>
          <div className="relative mb-6">
            <div className="absolute inset-0 rounded-full border-2 border-blue-400/20 animate-ping scale-125" />
            <div className="w-20 h-20 rounded-full border-2 border-blue-500/50 flex items-center justify-center text-5xl animate-pulse">
              🌍
            </div>
          </div>
          <p className="text-blue-200 text-sm font-semibold tracking-widest">DILIX EARTH</p>
          <p className="text-blue-800 text-xs mt-1">در حال بارگذاری...</p>
        </div>
      )}

      {/* ─── Top bar ─── */}
      <div className="absolute top-0 inset-x-0 p-3 pointer-events-none" style={{ zIndex:30 }}>
        <div className="flex items-center gap-2 pointer-events-auto">
          <div className="relative flex-1">
            <Search size={14} className="absolute right-3 top-1/2 -translate-y-1/2 text-blue-300/50" />
            <input
              value={search} onChange={e => setSearch(e.target.value)}
              placeholder="جستجوی نام یا Earth ID..."
              className="w-full rounded-xl pr-9 pl-4 py-2.5 text-sm text-white placeholder-blue-700 focus:outline-none"
              style={{ background:"rgba(0,10,30,0.7)", border:"1px solid rgba(100,150,255,0.2)", backdropFilter:"blur(12px)", direction:"rtl" }}
            />
          </div>
          <button onClick={() => setFilter(f => !f)}
            className="flex-shrink-0 p-2.5 rounded-xl transition-all"
            style={{ background: showFilter ? "#6366f1cc" : "rgba(0,10,30,0.7)", border:"1px solid rgba(100,150,255,0.2)", backdropFilter:"blur(12px)", color: showFilter ? "#fff" : "#93c5fd" }}>
            <Filter size={18} />
          </button>
        </div>

        {showFilter && (
          <div className="flex gap-2 mt-2 overflow-x-auto pb-1 no-scrollbar pointer-events-auto">
            {ROLES.map(r => (
              <button key={r} onClick={() => setRole(r)}
                className="flex-shrink-0 text-xs px-3 py-1.5 rounded-full border transition-all whitespace-nowrap"
                style={{
                  background: roleFilter === r ? "#6366f1cc" : "rgba(0,10,30,0.7)",
                  border: "1px solid " + (roleFilter === r ? "#818cf8" : "rgba(100,150,255,0.2)"),
                  color: roleFilter === r ? "#fff" : "#93c5fd",
                  backdropFilter:"blur(12px)",
                }}>
                {r === "همه" ? `همه (${DEMO.length})` : `${rem(r)} ${rl(r)}`}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* ─── Selected card ─── */}
      {selected && (
        <div className="absolute inset-x-3 pointer-events-auto" style={{ bottom:"76px", zIndex:30 }}>
          <div className="rounded-2xl p-4 shadow-2xl" style={{ background:"rgba(3,8,25,0.92)", border:"1px solid rgba(100,150,255,0.2)", backdropFilter:"blur(20px)" }}>
            <div className="flex items-start gap-3">
              <div className="w-12 h-12 rounded-full flex items-center justify-center text-2xl flex-shrink-0 border-2 overflow-hidden"
                style={{ borderColor:`${rc(selected.role)}80`, background:`${rc(selected.role)}25` }}>
                {selected.avatar_url
                  ? <img src={selected.avatar_url} className="w-full h-full object-cover" alt="" />
                  : rem(selected.role)}
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <p className="text-white font-bold text-sm truncate">{selected.name}</p>
                  {selected.kyc_level >= 2 && <ShieldCheck size={13} className="text-emerald-400 flex-shrink-0" />}
                </div>
                <p className="font-mono text-[11px] mt-0.5" style={{ color:"rgba(147,197,253,0.5)" }}>{selected.earth_id}</p>
                <div className="flex items-center gap-2 mt-1">
                  <span className="text-xs px-2 py-0.5 rounded-full font-medium"
                    style={{ background:`${rc(selected.role)}25`, color:rc(selected.role) }}>
                    {rl(selected.role)}
                  </span>
                  <div className="flex items-center gap-0.5">
                    <Star size={11} className="text-amber-400 fill-amber-400" />
                    <span className="text-xs" style={{ color:"rgba(147,197,253,0.7)" }}>{selected.rating}</span>
                  </div>
                </div>
              </div>
              <button onClick={() => setSelected(null)} className="p-1 flex-shrink-0" style={{ color:"rgba(147,197,253,0.4)" }}>
                <X size={18} />
              </button>
            </div>
            <div className="flex gap-2 mt-3">
              <button onClick={() => router.push(`/messages/${selected.earth_id}`)}
                className="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl text-white text-sm font-bold transition-all active:scale-95"
                style={{ background:`linear-gradient(135deg, ${rc(selected.role)}, ${rc(selected.role)}bb)` }}>
                <MessageCircle size={15} /> شروع گفتگو
              </button>
              <button onClick={() => router.push(`/messages/${selected.earth_id}?type=collaboration`)}
                className="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl text-sm font-bold border transition-all active:scale-95"
                style={{ borderColor:`${rc(selected.role)}60`, color:rc(selected.role), background:"rgba(255,255,255,0.05)" }}>
                <Handshake size={15} /> همکاری
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
              <button key={u.earth_id} onClick={() => setSelected(u)}
                className="flex-shrink-0 w-20 rounded-xl p-2 text-right active:scale-95 transition-all"
                style={{ background:"rgba(3,8,25,0.85)", border:"1px solid rgba(100,150,255,0.15)", backdropFilter:"blur(12px)" }}>
                <div className="flex items-center gap-1.5 mb-1">
                  {u.avatar_url
                    ? <img src={u.avatar_url} className="w-5 h-5 rounded-full object-cover flex-shrink-0"
                        style={{ border:`1.5px solid ${rc(u.role)}` }} alt="" />
                    : <div className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ background:rc(u.role) }} />}
                  <p className="text-white text-[11px] font-semibold truncate">{u.name.split(" ")[0]}</p>
                </div>
                <p className="text-[9px] font-medium" style={{ color:rc(u.role) }}>{rl(u.role)}</p>
                <div className="flex items-center gap-0.5 mt-0.5">
                  <Star size={8} className="text-amber-400 fill-amber-400" />
                  <p className="text-[9px]" style={{ color:"rgba(147,197,253,0.6)" }}>{u.rating}</p>
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
