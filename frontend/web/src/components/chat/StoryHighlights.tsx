"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Plus, X, Trash2, Loader2, Check, Play } from "lucide-react";
import toast from "react-hot-toast";
import { highlightsApi, storiesApi } from "@/lib/api";

interface Highlight {
  id: string;
  title: string;
  cover_url?: string | null;
  item_count: number;
  is_mine: boolean;
  updated_at: string;
}
interface HItem {
  id: string;
  story_id?: string | null;
  media_url: string;
  media_type: string;
  caption?: string | null;
  sort_order: number;
}
interface HDetail {
  id: string;
  title: string;
  cover_url?: string | null;
  is_mine: boolean;
  owner_earth_id: string;
  owner_name: string;
  items: HItem[];
}
interface MyStory {
  id: string;
  media_url: string;
  media_type: string;
  caption?: string | null;
  created_at: string;
}

const IMAGE_MS = 5000;
const toFa = (n: number | string) => String(n).replace(/[0-9]/g, (d) => "۰۱۲۳۴۵۶۷۸۹"[+d]);

function Cover({ url, type, size }: { url?: string | null; type?: string; size: string }) {
  if (url && type !== "video") {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={url} alt="" className={`${size} object-cover`} />;
  }
  if (url && type === "video") {
    return (
      <div className={`${size} relative bg-black`}>
        <video src={url} className="w-full h-full object-cover" muted playsInline preload="metadata" />
        <Play className="absolute inset-0 m-auto w-4 h-4 text-white/90" fill="currentColor" />
      </div>
    );
  }
  return <div className={`${size} bg-surface-800`} />;
}

export default function StoryHighlights({ earthId, isMe }: { earthId: string; isMe: boolean }) {
  const [items, setItems] = useState<Highlight[]>([]);
  const [loading, setLoading] = useState(true);
  const [viewing, setViewing] = useState<HDetail | null>(null);
  const [picker, setPicker] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const r = await highlightsApi.list(earthId);
      setItems(r.data || []);
    } catch {
      setItems([]);
    } finally {
      setLoading(false);
    }
  }, [earthId]);

  useEffect(() => { load(); }, [load]);

  const openHighlight = async (id: string) => {
    try {
      const r = await highlightsApi.get(id);
      setViewing(r.data);
    } catch {
      toast.error("خطا در بازکردنِ هایلایت");
    }
  };

  const deleteHighlight = async (id: string) => {
    if (!window.confirm("این هایلایت حذف شود؟")) return;
    try {
      await highlightsApi.remove(id);
      setItems((p) => p.filter((h) => h.id !== id));
      toast.success("هایلایت حذف شد");
    } catch {
      toast.error("حذف ناموفق بود");
    }
  };

  if (loading) {
    return <div className="px-4 py-3"><div className="h-16 flex items-center"><Loader2 className="w-4 h-4 animate-spin text-surface-500" /></div></div>;
  }
  if (items.length === 0 && !isMe) return null;

  return (
    <div className="px-4 py-3 border-t border-surface-800/70">
      <div className="flex gap-4 overflow-x-auto no-scrollbar">
        {isMe && (
          <button onClick={() => setPicker(true)} className="flex flex-col items-center gap-1.5 shrink-0 w-16">
            <span className="w-16 h-16 rounded-full border-2 border-dashed border-surface-600 flex items-center justify-center text-surface-400">
              <Plus size={22} />
            </span>
            <span className="text-[11px] text-surface-400 truncate w-full text-center">جدید</span>
          </button>
        )}
        {items.map((h) => (
          <div key={h.id} className="relative shrink-0 w-16">
            <button onClick={() => openHighlight(h.id)} className="flex flex-col items-center gap-1.5 w-full">
              <span className="w-16 h-16 rounded-full overflow-hidden ring-2 ring-surface-600 flex items-center justify-center bg-surface-800">
                <Cover url={h.cover_url} type={undefined} size="w-full h-full" />
              </span>
              <span className="text-[11px] text-surface-200 truncate w-full text-center">{h.title}</span>
            </button>
            {isMe && (
              <button
                onClick={() => deleteHighlight(h.id)}
                className="absolute -top-1 -right-1 w-5 h-5 rounded-full bg-surface-900 border border-surface-700 flex items-center justify-center text-rose-300"
                aria-label="حذف"
              >
                <X size={12} />
              </button>
            )}
          </div>
        ))}
      </div>

      {viewing && (
        <HighlightViewer
          detail={viewing}
          onClose={() => setViewing(null)}
          onChanged={load}
        />
      )}

      {picker && (
        <CreateHighlight
          myEarthId={earthId}
          onClose={() => setPicker(false)}
          onCreated={() => { setPicker(false); load(); }}
        />
      )}
    </div>
  );
}

// ─── Full-screen highlight viewer ───────────────────────────────
function HighlightViewer({ detail, onClose, onChanged }: { detail: HDetail; onClose: () => void; onChanged: () => void; }) {
  const [items, setItems] = useState<HItem[]>(detail.items);
  const [si, setSi] = useState(0);
  const [progress, setProgress] = useState(0);
  const [paused, setPaused] = useState(false);

  const it = items[si];
  const elapsedRef = useRef(0);
  const lastTsRef = useRef<number | null>(null);
  const durRef = useRef(IMAGE_MS);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const downRef = useRef<{ t: number; x: number } | null>(null);

  const next = useCallback(() => {
    setSi((s) => { if (s < items.length - 1) return s + 1; onClose(); return s; });
  }, [items.length, onClose]);
  const prev = useCallback(() => { setSi((s) => (s > 0 ? s - 1 : s)); }, []);

  useEffect(() => {
    if (!it) return;
    elapsedRef.current = 0; lastTsRef.current = null; setProgress(0);
    durRef.current = it.media_type === "video" ? 15000 : IMAGE_MS;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [it?.id]);

  useEffect(() => {
    if (!it) return;
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
  }, [it?.id, si, paused, next]);

  useEffect(() => {
    const v = videoRef.current; if (!v) return;
    if (paused) v.pause(); else v.play().catch(() => {});
  }, [paused, it?.id]);

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

  const removeItem = async () => {
    if (!it) return;
    setPaused(true);
    if (!window.confirm("این آیتم از هایلایت حذف شود؟")) { setPaused(false); return; }
    try {
      await highlightsApi.removeItem(detail.id, it.id);
      const arr = items.filter((x) => x.id !== it.id);
      onChanged();
      if (!arr.length) { onClose(); return; }
      setItems(arr);
      setSi((s) => Math.max(0, Math.min(s, arr.length - 1)));
      toast.success("حذف شد");
    } catch { toast.error("حذف ناموفق بود"); }
    finally { setPaused(false); }
  };

  return (
    <div className="fixed inset-0 z-[85] bg-black flex flex-col select-none">
      <div className="flex gap-1 px-2 pt-2 safe-top">
        {items.map((s, i) => (
          <div key={s.id} className="flex-1 h-0.5 rounded-full bg-white/25 overflow-hidden">
            <div className="h-full bg-white rounded-full" style={{ width: `${i < si ? 100 : i === si ? progress * 100 : 0}%` }} />
          </div>
        ))}
      </div>

      <div className="flex items-center gap-2.5 px-3 py-2.5">
        <div className="flex-1 min-w-0">
          <p className="text-white text-sm font-semibold truncate">{detail.title}</p>
          <p className="text-white/50 text-[11px]">{toFa(si + 1)}/{toFa(items.length)}</p>
        </div>
        {detail.is_mine && (
          <button onClick={removeItem} className="p-2 rounded-lg bg-white/10 text-rose-300"><Trash2 size={16} /></button>
        )}
        <button onClick={onClose} className="p-2 rounded-lg bg-white/10 text-white/80"><X size={18} /></button>
      </div>

      <div className="flex-1 relative flex items-center justify-center overflow-hidden"
        onPointerDown={handleDown} onPointerUp={handleUp} onPointerCancel={() => setPaused(false)}
        style={{ touchAction: "none" }}>
        {!it ? (
          <Loader2 size={30} className="text-white/50 animate-spin" />
        ) : it.media_type === "video" ? (
          <video ref={videoRef} src={it.media_url} autoPlay playsInline onLoadedMetadata={onVideoMeta} className="max-w-full max-h-full object-contain" />
        ) : (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={it.media_url} alt="" className="max-w-full max-h-full object-contain" />
        )}
        {it?.caption && (
          <div className="absolute bottom-6 inset-x-0 px-6 flex justify-center pointer-events-none">
            <p className="text-white text-sm bg-black/45 rounded-2xl px-4 py-2 max-w-md text-center leading-relaxed">{it.caption}</p>
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Create highlight (pick from my active stories) ─────────────
function CreateHighlight({ myEarthId, onClose, onCreated }: { myEarthId: string; onClose: () => void; onCreated: () => void; }) {
  const [stories, setStories] = useState<MyStory[]>([]);
  const [loading, setLoading] = useState(true);
  const [sel, setSel] = useState<string[]>([]);
  const [title, setTitle] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    let cancelled = false;
    storiesApi.userStories(myEarthId).then((r) => {
      if (!cancelled) setStories(r.data || []);
    }).catch(() => { if (!cancelled) setStories([]); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [myEarthId]);

  const toggle = (id: string) => setSel((p) => (p.includes(id) ? p.filter((x) => x !== id) : [...p, id]));

  const create = async () => {
    if (sel.length === 0) { toast.error("حداقل یک داستان انتخاب کن"); return; }
    setSaving(true);
    try {
      await highlightsApi.create(title.trim() || "هایلایت", sel);
      toast.success("هایلایت ساخته شد ✅");
      onCreated();
    } catch {
      toast.error("ساختِ هایلایت ناموفق بود");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 z-[85] flex items-end sm:items-center justify-center bg-black/70 backdrop-blur-sm sm:p-4" onClick={() => { if (!saving) onClose(); }}>
      <div dir="rtl" onClick={(e) => e.stopPropagation()} className="w-full sm:max-w-md bg-surface-900 border border-surface-800 rounded-t-3xl sm:rounded-3xl p-5 max-h-[88vh] overflow-y-auto">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-white font-bold text-base">هایلایتِ جدید</h2>
          <button onClick={() => { if (!saving) onClose(); }} className="p-2 rounded-lg bg-surface-800 text-surface-300 hover:bg-surface-700"><X size={18} /></button>
        </div>

        <input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          maxLength={60}
          placeholder="عنوانِ هایلایت (مثلاً سفرها)"
          className="w-full bg-surface-800 border border-surface-700 rounded-xl px-3 py-2.5 text-white text-sm placeholder-surface-500 focus:outline-none focus:border-primary-500 mb-3"
        />

        <p className="text-xs text-surface-400 mb-2 leading-6">از داستان‌های فعالِ خودت انتخاب کن (داستان‌ها پس از ۲۴ساعت منقضی می‌شوند ولی در هایلایت ماندگار می‌مانند).</p>

        {loading ? (
          <div className="flex justify-center py-10"><Loader2 size={22} className="text-primary-400 animate-spin" /></div>
        ) : stories.length === 0 ? (
          <p className="text-center text-surface-500 text-sm py-10">داستانِ فعالی نداری. اول یک داستان بگذار.</p>
        ) : (
          <div className="grid grid-cols-3 gap-2 mb-4">
            {stories.map((s) => {
              const active = sel.includes(s.id);
              return (
                <button key={s.id} onClick={() => toggle(s.id)} className={`relative aspect-square rounded-xl overflow-hidden border-2 ${active ? "border-primary-500" : "border-transparent"}`}>
                  {s.media_type === "video" ? (
                    <video src={s.media_url} className="w-full h-full object-cover" muted playsInline preload="metadata" />
                  ) : (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={s.media_url} alt="" className="w-full h-full object-cover" />
                  )}
                  {active && (
                    <span className="absolute inset-0 bg-primary-500/30 flex items-center justify-center">
                      <span className="w-6 h-6 rounded-full bg-primary-500 flex items-center justify-center"><Check size={14} className="text-white" /></span>
                    </span>
                  )}
                </button>
              );
            })}
          </div>
        )}

        <button
          onClick={create}
          disabled={saving || sel.length === 0}
          className="w-full rounded-xl bg-primary-600 hover:bg-primary-500 disabled:opacity-50 text-white text-sm font-semibold py-3 flex items-center justify-center gap-2"
        >
          {saving ? <Loader2 size={18} className="animate-spin" /> : `ساختنِ هایلایت${sel.length ? ` (${toFa(sel.length)})` : ""}`}
        </button>
      </div>
    </div>
  );
}
