"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { X, Trash2, Eye, Loader2, ChevronLeft, ChevronRight } from "@/lib/icons";
import toast from "@/lib/toast";
import { api, type StoryOut } from "@/lib/api";

export interface Ring {
  earth_id: string;
  name: string;
  avatar_url?: string | null;
  is_me?: boolean;
  has_unseen?: boolean;
}
type Story = StoryOut;
interface Viewer {
  viewer_earth_id: string;
  viewed_at: string;
}

const IMAGE_MS = 5000;

function timeAgo(iso: string): string {
  const t = new Date(iso).getTime();
  const diff = Math.max(0, Date.now() - t);
  const m = Math.floor(diff / 60000);
  if (m < 1) return "همین حالا";
  if (m < 60) return `${toFa(m)} دقیقه پیش`;
  const h = Math.floor(m / 60);
  return `${toFa(h)} ساعت پیش`;
}
function toFa(n: number | string): string { return String(n).replace(/[0-9]/g, (d) => "۰۱۲۳۴۵۶۷۸۹"[+d]); }
function shortId(id: string): string { return `${id.slice(0, 6)}…`; }

export default function StoryViewer({
  rings, startIndex, onClose, onViewed,
}: {
  rings: Ring[];
  startIndex: number;
  onClose: () => void;
  onViewed?: (earthId: string) => void;
}) {
  const [ui, setUi] = useState(startIndex);
  const [si, setSi] = useState(0);
  const [stories, setStories] = useState<Story[]>([]);
  const [loading, setLoading] = useState(true);
  const [progress, setProgress] = useState(0);
  const [paused, setPaused] = useState(false);
  const [viewers, setViewers] = useState<Viewer[] | null>(null);

  const ring = rings[ui];
  const story = stories[si];

  const elapsedRef = useRef(0);
  const lastTsRef = useRef<number | null>(null);
  const durRef = useRef(IMAGE_MS);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const downRef = useRef<{ t: number; x: number } | null>(null);

  const gotoUser = useCallback((dir: number) => {
    setUi((u) => {
      const n = u + dir;
      if (n < 0 || n >= rings.length) { onClose(); return u; }
      return n;
    });
  }, [rings.length, onClose]);

  // بارگذاریِ داستان‌های کاربرِ فعلی
  useEffect(() => {
    let cancelled = false;
    setLoading(true); setStories([]); setSi(0); setViewers(null);
    api.stories.userStories(ring.earth_id).then((arr) => {
      if (cancelled) return;
      if (!arr.length) { gotoUser(1); return; }
      setStories(arr); setLoading(false);
    }).catch(() => { if (!cancelled) gotoUser(1); });
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ui, ring.earth_id]);

  const next = useCallback(() => {
    setSi((s) => {
      if (s < stories.length - 1) return s + 1;
      gotoUser(1); return s;
    });
  }, [stories.length, gotoUser]);
  const prev = useCallback(() => {
    setSi((s) => { if (s > 0) return s - 1; gotoUser(-1); return s; });
  }, [gotoUser]);

  // ثبتِ بازدید + ریستِ تایمر هنگام تغییرِ داستان
  useEffect(() => {
    if (!story) return;
    elapsedRef.current = 0; lastTsRef.current = null; setProgress(0);
    durRef.current = story.media_type === "video" ? 15000 : IMAGE_MS;
    if (!story.is_mine && !story.viewed_by_me) api.stories.view(story.id).catch(() => {});
    onViewed?.(ring.earth_id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [story?.id]);

  // حلقهٔ پیشرفت (rAF)
  useEffect(() => {
    if (loading || !story) return;
    let raf = 0;
    const tick = (t: number) => {
      if (lastTsRef.current == null) lastTsRef.current = t;
      const dt = t - lastTsRef.current; lastTsRef.current = t;
      if (!paused) elapsedRef.current += dt;
      const p = Math.min(1, elapsedRef.current / durRef.current);
      setProgress(p);
      if (p >= 1) { next(); return; }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [loading, story?.id, si, paused, next]);

  // کنترلِ ویدیو با pause
  useEffect(() => {
    const v = videoRef.current; if (!v) return;
    if (paused) v.pause(); else v.play().catch(() => {});
  }, [paused, story?.id]);

  const onVideoMeta = () => { const v = videoRef.current; if (v && v.duration && isFinite(v.duration)) durRef.current = v.duration * 1000; };

  const handleDown = (e: React.PointerEvent) => { downRef.current = { t: Date.now(), x: e.clientX }; setPaused(true); };
  const handleUp = (e: React.PointerEvent) => {
    setPaused(false);
    const d = downRef.current; downRef.current = null;
    if (!d) return;
    if (Date.now() - d.t < 250) {
      const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
      const frac = (e.clientX - r.left) / r.width;
      if (frac < 0.33) prev(); else next();
    }
  };

  const deleteStory = async () => {
    if (!story) return;
    try {
      await api.stories.remove(story.id);
      toast.success("داستان حذف شد");
      setStories((prevArr) => {
        const arr = prevArr.filter((s) => s.id !== story.id);
        if (!arr.length) { onClose(); return prevArr; }
        setSi((s) => Math.max(0, Math.min(s, arr.length - 1)));
        return arr;
      });
    } catch { toast.error("حذف ناموفق بود"); }
  };

  const openViewers = async () => {
    if (!story) return;
    setPaused(true);
    try { setViewers(await api.stories.viewers(story.id)); }
    catch { toast.error("خطا در دریافتِ بازدیدکنندگان"); }
  };

  return (
    <div className="fixed inset-0 z-[80] bg-black flex flex-col select-none">
      {/* progress segments */}
      <div className="flex gap-1 px-2 pt-2 safe-top">
        {stories.map((s, i) => (
          <div key={s.id} className="flex-1 h-0.5 rounded-full bg-white/25 overflow-hidden">
            <div className="h-full bg-white rounded-full" style={{ width: `${i < si ? 100 : i === si ? progress * 100 : 0}%` }} />
          </div>
        ))}
      </div>

      {/* header */}
      <div className="flex items-center gap-2.5 px-3 py-2.5">
        <div className="w-9 h-9 rounded-full bg-white/10 overflow-hidden flex items-center justify-center text-sm shrink-0">
          {ring.avatar_url ? <img src={ring.avatar_url} alt="" className="w-full h-full object-cover" /> : (ring.name?.[0] ?? "👤")}
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-white text-sm font-semibold truncate">{ring.is_me ? "داستانِ شما" : ring.name}</p>
          {story && <p className="text-white/50 text-[11px]">{timeAgo(story.created_at)}</p>}
        </div>
        {story?.is_mine && (
          <button onClick={openViewers} className="flex items-center gap-1 text-white/80 text-xs px-2 py-1 rounded-lg bg-white/10">
            <Eye size={15} /> {toFa(story.view_count)}
          </button>
        )}
        {story?.is_mine && (
          <button onClick={deleteStory} className="p-2 rounded-lg bg-white/10 text-rose-300"><Trash2 size={16} /></button>
        )}
        <button onClick={onClose} className="p-2 rounded-lg bg-white/10 text-white/80"><X size={18} /></button>
      </div>

      {/* media */}
      <div className="flex-1 relative flex items-center justify-center overflow-hidden"
        onPointerDown={handleDown} onPointerUp={handleUp} onPointerCancel={() => setPaused(false)}
        style={{ touchAction: "none" }}>
        {loading || !story ? (
          <Loader2 size={30} className="text-white/50 animate-spin" />
        ) : story.media_type === "video" ? (
          <video ref={videoRef} src={story.media_url} autoPlay playsInline
            onLoadedMetadata={onVideoMeta} className="max-w-full max-h-full object-contain" />
        ) : (
          <img src={story.media_url} alt="" className="max-w-full max-h-full object-contain" />
        )}

        {/* nav hints (desktop) */}
        {ui > 0 || si > 0 ? (
          <button onClick={prev} className="hidden sm:flex absolute right-2 top-1/2 -translate-y-1/2 p-2 rounded-full bg-black/40 text-white/70"><ChevronRight size={20} /></button>
        ) : null}
        <button onClick={next} className="hidden sm:flex absolute left-2 top-1/2 -translate-y-1/2 p-2 rounded-full bg-black/40 text-white/70"><ChevronLeft size={20} /></button>

        {/* caption */}
        {story?.caption && (
          <div className="absolute bottom-6 inset-x-0 px-6 flex justify-center pointer-events-none">
            <p className="text-white text-sm bg-black/45 rounded-2xl px-4 py-2 max-w-md text-center leading-relaxed">{story.caption}</p>
          </div>
        )}
      </div>

      {/* viewers sheet */}
      {viewers !== null && (
        <div className="absolute inset-0 z-[90] flex flex-col justify-end" onClick={() => { setViewers(null); setPaused(false); }}>
          <div className="absolute inset-0 bg-black/60" />
          <div className="relative bg-[#141414] rounded-t-3xl max-h-[60vh] overflow-y-auto p-4" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center gap-2 mb-3 text-white">
              <Eye size={17} /><span className="text-sm font-semibold">بازدیدکنندگان ({toFa(viewers.length)})</span>
            </div>
            {viewers.length === 0 ? (
              <p className="text-white/40 text-sm text-center py-6">هنوز کسی این داستان را ندیده</p>
            ) : (
              <div className="space-y-1.5">
                {viewers.map((v) => (
                  <div key={v.viewer_earth_id} className="flex items-center gap-3 p-2 rounded-xl">
                    <div className="w-9 h-9 rounded-full bg-white/10 overflow-hidden flex items-center justify-center text-sm">
                      👤
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-white text-sm truncate">{shortId(v.viewer_earth_id)}</p>
                      <p className="text-white/40 text-[11px]">{timeAgo(v.viewed_at)}</p>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
