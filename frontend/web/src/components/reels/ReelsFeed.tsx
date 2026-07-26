"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import {
  Heart, MessageCircle, Share2, Volume2, VolumeX, Trash2,
  Plus, Loader2, Play, X, Send,
} from "lucide-react";
import toast from "react-hot-toast";
import { reelsApi, getApiErrorMessage } from "@/lib/api";
import { useAuthStore } from "@/store/auth";
import MediaEditor from "@/components/chat/MediaEditor";

export interface Reel {
  id: string;
  author_earth_id: string;
  author_name: string;
  author_avatar?: string | null;
  media_url: string;
  media_type: string;
  caption?: string | null;
  view_count: number;
  like_count: number;
  comment_count: number;
  liked_by_me: boolean;
  is_mine: boolean;
  created_at: string;
}

interface Comment {
  id: string;
  author_earth_id: string;
  author_name: string;
  author_avatar?: string | null;
  body: string;
  is_mine: boolean;
  created_at: string;
}

function fmt(n: number): string {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1).replace(/\.0$/, "") + "M";
  if (n >= 1_000) return (n / 1_000).toFixed(1).replace(/\.0$/, "") + "K";
  return String(n);
}

// ─── یک آیتمِ ریلز ─────────────────────────────────────────
function ReelItem({
  reel, muted, onToggleMute, onLike, onOpenComments, onDelete, active,
}: {
  reel: Reel;
  muted: boolean;
  onToggleMute: () => void;
  onLike: (r: Reel) => void;
  onOpenComments: (r: Reel) => void;
  onDelete: (r: Reel) => void;
  active: boolean;
}) {
  const vref = useRef<HTMLVideoElement | null>(null);
  const [paused, setPaused] = useState(false);
  const [burst, setBurst] = useState(false);
  const lastTap = useRef(0);
  const isVideo = reel.media_type === "video";

  useEffect(() => {
    const v = vref.current;
    if (!v) return;
    if (active) {
      v.currentTime = v.currentTime; // keep
      const p = v.play();
      if (p && typeof p.catch === "function") p.catch(() => {});
      setPaused(false);
    } else {
      v.pause();
    }
  }, [active]);

  const togglePlay = () => {
    const v = vref.current;
    if (!v) return;
    if (v.paused) { v.play().catch(() => {}); setPaused(false); }
    else { v.pause(); setPaused(true); }
  };

  const doubleLike = () => {
    if (!reel.liked_by_me) onLike(reel);
    setBurst(true);
    setTimeout(() => setBurst(false), 700);
  };

  const onTap = () => {
    const now = Date.now();
    if (now - lastTap.current < 280) {
      doubleLike();
      lastTap.current = 0;
    } else {
      lastTap.current = now;
      setTimeout(() => {
        if (lastTap.current && Date.now() - lastTap.current >= 280) {
          if (isVideo) togglePlay();
          lastTap.current = 0;
        }
      }, 300);
    }
  };

  return (
    <div className="relative h-full w-full snap-start snap-always shrink-0 bg-[var(--color-bg)] overflow-hidden">
      {/* رسانه */}
      <div className="absolute inset-0 flex items-center justify-center" onClick={onTap}>
        {isVideo ? (
          <video
            ref={vref}
            src={reel.media_url}
            className="h-full w-full object-contain"
            loop
            muted={muted}
            playsInline
            preload="auto"
          />
        ) : (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={reel.media_url} alt="" className="h-full w-full object-contain" />
        )}
      </div>

      {/* آیکونِ pause */}
      {isVideo && paused && (
        <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
          <Play size={64} className="text-white/80" fill="currentColor" />
        </div>
      )}

      {/* برستِ قلب (double-tap) */}
      {burst && (
        <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
          <Heart size={120} className="text-white drop-shadow-lg animate-ping-once" fill="currentColor" />
        </div>
      )}

      {/* گرادیانِ پایین برای خوانایی */}
      <div className="absolute inset-x-0 bottom-0 h-52 bg-gradient-to-t from-black/70 to-transparent pointer-events-none" />

      {/* دکمهٔ صدا */}
      {isVideo && (
        <button
          onClick={onToggleMute}
          className="absolute top-4 left-4 z-20 w-9 h-9 rounded-full bg-black/45 backdrop-blur flex items-center justify-center text-white"
        >
          {muted ? <VolumeX size={18} /> : <Volume2 size={18} />}
        </button>
      )}

      {/* ریلِ اکشن‌ها (راست) */}
      <div className="absolute right-3 bottom-24 z-20 flex flex-col items-center gap-5">
        <button onClick={() => onLike(reel)} className="flex flex-col items-center gap-1">
          <Heart
            size={32}
            className={reel.liked_by_me ? "text-rose-500" : "text-white"}
            fill={reel.liked_by_me ? "currentColor" : "none"}
          />
          <span className="text-[11px] text-white font-medium">{fmt(reel.like_count)}</span>
        </button>
        <button onClick={() => onOpenComments(reel)} className="flex flex-col items-center gap-1">
          <MessageCircle size={31} className="text-white" />
          <span className="text-[11px] text-white font-medium">{fmt(reel.comment_count)}</span>
        </button>
        <button
          onClick={() => {
            const url = typeof window !== "undefined" ? window.location.href : "";
            if (navigator.share) navigator.share({ title: "Dilix Reels", url }).catch(() => {});
            else { navigator.clipboard?.writeText(url); toast.success("لینک کپی شد"); }
          }}
          className="flex flex-col items-center gap-1"
        >
          <Share2 size={30} className="text-white" />
          <span className="text-[11px] text-white font-medium">ارسال</span>
        </button>
        {reel.is_mine && (
          <button onClick={() => onDelete(reel)} className="flex flex-col items-center gap-1">
            <Trash2 size={27} className="text-white/90" />
          </button>
        )}
      </div>

      {/* اطلاعاتِ نویسنده (پایین چپ) */}
      <div className="absolute left-4 right-16 bottom-24 z-20 text-white">
        <Link href={`/u/${reel.author_earth_id}`} className="flex items-center gap-2 mb-2">
          <div className="w-9 h-9 rounded-full overflow-hidden bg-white/15 flex items-center justify-center text-sm ring-2 ring-white/60">
            {reel.author_avatar ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={reel.author_avatar} alt="" className="w-full h-full object-cover" />
            ) : (reel.author_name?.[0] ?? "👤")}
          </div>
          <span className="font-semibold text-sm drop-shadow">{reel.author_name}</span>
        </Link>
        {reel.caption && (
          <p className="text-[13px] leading-5 text-white/90 line-clamp-3 drop-shadow">{reel.caption}</p>
        )}
        <p className="text-[11px] text-white/55 mt-1">{fmt(reel.view_count)} بازدید</p>
      </div>
    </div>
  );
}

// ─── شیتِ کامنت‌ها ─────────────────────────────────────────
function CommentsSheet({
  reel, onClose, onAdded,
}: {
  reel: Reel;
  onClose: () => void;
  onAdded: () => void;
}) {
  const [items, setItems] = useState<Comment[]>([]);
  const [loading, setLoading] = useState(true);
  const [text, setText] = useState("");
  const [sending, setSending] = useState(false);

  const load = useCallback(async () => {
    try {
      const r = await reelsApi.comments(reel.id);
      setItems(r.data || []);
    } catch { /* silent */ } finally { setLoading(false); }
  }, [reel.id]);

  useEffect(() => { load(); }, [load]);

  const send = async () => {
    const body = text.trim();
    if (!body || sending) return;
    setSending(true);
    try {
      const r = await reelsApi.addComment(reel.id, body);
      setItems((p) => [r.data, ...p]);
      setText("");
      onAdded();
    } catch (e) {
      toast.error(getApiErrorMessage(e, "ارسالِ کامنت ناموفق بود"));
    } finally { setSending(false); }
  };

  const remove = async (c: Comment) => {
    try {
      await reelsApi.removeComment(c.id);
      setItems((p) => p.filter((x) => x.id !== c.id));
    } catch { toast.error("حذف ناموفق بود"); }
  };

  return (
    <div className="fixed inset-0 z-[90] flex flex-col justify-end" onClick={onClose}>
      <div className="absolute inset-0 bg-black/50" />
      <div
        className="relative bg-[#141414] rounded-t-2xl max-h-[70vh] flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between px-4 py-3 border-b border-white/10">
          <span className="text-white font-semibold text-sm">کامنت‌ها</span>
          <button onClick={onClose} className="text-white/60"><X size={20} /></button>
        </div>

        <div className="flex-1 overflow-y-auto px-4 py-3 space-y-4">
          {loading ? (
            <div className="flex justify-center py-8"><Loader2 className="animate-spin text-white/40" /></div>
          ) : items.length === 0 ? (
            <p className="text-center text-white/40 text-sm py-8">اولین کامنت را بگذارید</p>
          ) : (
            items.map((c) => (
              <div key={c.id} className="flex items-start gap-2">
                <div className="w-8 h-8 rounded-full overflow-hidden bg-white/10 flex items-center justify-center text-xs shrink-0">
                  {c.author_avatar ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={c.author_avatar} alt="" className="w-full h-full object-cover" />
                  ) : (c.author_name?.[0] ?? "👤")}
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-[12px] text-white/60">{c.author_name}</p>
                  <p className="text-[14px] text-white break-words">{c.body}</p>
                </div>
                {c.is_mine && (
                  <button onClick={() => remove(c)} className="text-white/40 hover:text-rose-400">
                    <Trash2 size={15} />
                  </button>
                )}
              </div>
            ))
          )}
        </div>

        <div className="flex items-center gap-2 p-3 border-t border-white/10 pb-[calc(var(--nav-height)+0.75rem)]">
          <input
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && send()}
            placeholder="کامنت بگذارید…"
            className="flex-1 bg-white/8 rounded-full px-4 py-2 text-sm text-white outline-none placeholder:text-white/35"
          />
          <button
            onClick={send}
            disabled={sending || !text.trim()}
            className="w-9 h-9 rounded-full bg-indigo-500 flex items-center justify-center text-white disabled:opacity-40"
          >
            {sending ? <Loader2 size={16} className="animate-spin" /> : <Send size={16} />}
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── فیدِ اصلی ─────────────────────────────────────────────
export default function ReelsFeed() {
  const me = useAuthStore((s) => s.user);
  const [reels, setReels] = useState<Reel[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(true);
  const [muted, setMuted] = useState(true);
  const [activeIdx, setActiveIdx] = useState(0);
  const [commentsFor, setCommentsFor] = useState<Reel | null>(null);
  const [editorFile, setEditorFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const fileRef = useRef<HTMLInputElement | null>(null);
  const scrollRef = useRef<HTMLDivElement | null>(null);
  const viewed = useRef<Set<string>>(new Set());
  const fetchingRef = useRef(false);

  const fetchPage = useCallback(async (cur: string | null) => {
    if (fetchingRef.current) return;
    fetchingRef.current = true;
    try {
      const r = await reelsApi.feed(cur ?? undefined);
      const data = r.data || {};
      const items: Reel[] = data.items || [];
      setReels((prev) => {
        const ids = new Set(prev.map((x) => x.id));
        return [...prev, ...items.filter((x) => !ids.has(x.id))];
      });
      setCursor(data.next_cursor ?? null);
      setHasMore(Boolean(data.next_cursor) && items.length > 0);
    } catch { /* silent */ } finally {
      setLoading(false);
      fetchingRef.current = false;
    }
  }, []);

  useEffect(() => { fetchPage(null); }, [fetchPage]);

  // ثبتِ بازدید هنگام فعال‌شدنِ آیتم
  useEffect(() => {
    const r = reels[activeIdx];
    if (r && !viewed.current.has(r.id)) {
      viewed.current.add(r.id);
      reelsApi.view(r.id).catch(() => {});
    }
    // بارگذاریِ صفحهٔ بعد نزدیکِ انتها
    if (hasMore && activeIdx >= reels.length - 3) fetchPage(cursor);
  }, [activeIdx, reels, hasMore, cursor, fetchPage]);

  const onScroll = () => {
    const el = scrollRef.current;
    if (!el) return;
    const idx = Math.round(el.scrollTop / el.clientHeight);
    if (idx !== activeIdx) setActiveIdx(idx);
  };

  const toggleLike = async (reel: Reel) => {
    // optimistic
    setReels((prev) => prev.map((x) => x.id === reel.id
      ? { ...x, liked_by_me: !x.liked_by_me, like_count: x.like_count + (x.liked_by_me ? -1 : 1) }
      : x));
    try {
      const r = await reelsApi.like(reel.id);
      setReels((prev) => prev.map((x) => x.id === reel.id
        ? { ...x, liked_by_me: r.data.liked, like_count: r.data.like_count } : x));
    } catch {
      // revert
      setReels((prev) => prev.map((x) => x.id === reel.id
        ? { ...x, liked_by_me: reel.liked_by_me, like_count: reel.like_count } : x));
    }
  };

  const removeReel = async (reel: Reel) => {
    if (!confirm("این ریلز حذف شود؟")) return;
    try {
      await reelsApi.remove(reel.id);
      setReels((prev) => prev.filter((x) => x.id !== reel.id));
      toast.success("ریلز حذف شد");
    } catch { toast.error("حذف ناموفق بود"); }
  };

  const onPick = (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0];
    e.target.value = "";
    if (!f) return;
    if (!f.type.startsWith("video/") && !f.type.startsWith("image/")) {
      toast.error("فقط ویدیو یا عکس");
      return;
    }
    setEditorFile(f);
  };

  const publish = async (file: File) => {
    setEditorFile(null);
    setUploading(true);
    try {
      const r = await reelsApi.create(file, undefined, file.name);
      setReels((prev) => [r.data, ...prev]);
      setActiveIdx(0);
      scrollRef.current?.scrollTo({ top: 0 });
      toast.success("ریلزِ شما منتشر شد");
    } catch (e) {
      toast.error(getApiErrorMessage(e, "انتشار ناموفق بود"));
    } finally { setUploading(false); }
  };

  const bumpComment = () => {
    if (!commentsFor) return;
    setReels((prev) => prev.map((x) => x.id === commentsFor.id
      ? { ...x, comment_count: x.comment_count + 1 } : x));
  };

  return (
    <div className="fixed inset-0 bg-[var(--color-bg)]">
      {/* هدرِ سبک */}
      <div className="absolute top-0 inset-x-0 z-30 flex items-center justify-between px-4 h-14 pointer-events-none">
        <span className="text-white font-black text-lg drop-shadow pointer-events-auto">ریلز</span>
      </div>

      {loading && reels.length === 0 ? (
        <div className="h-full flex items-center justify-center">
          <Loader2 className="animate-spin text-white/50" size={30} />
        </div>
      ) : reels.length === 0 ? (
        <div className="h-full flex flex-col items-center justify-center gap-3 text-white/60">
          <p>هنوز ریلزی نیست</p>
          <button
            onClick={() => fileRef.current?.click()}
            className="px-5 py-2.5 rounded-full bg-indigo-500 text-white text-sm font-medium"
          >
            اولین ریلز را بساز
          </button>
        </div>
      ) : (
        <div
          ref={scrollRef}
          onScroll={onScroll}
          className="h-full w-full overflow-y-auto snap-y snap-mandatory no-scrollbar"
          style={{ scrollBehavior: "smooth" }}
        >
          {reels.map((reel, i) => (
            <div key={reel.id} className="h-full w-full">
              <ReelItem
                reel={reel}
                active={i === activeIdx}
                muted={muted}
                onToggleMute={() => setMuted((m) => !m)}
                onLike={toggleLike}
                onOpenComments={setCommentsFor}
                onDelete={removeReel}
              />
            </div>
          ))}
        </div>
      )}

      {/* دکمهٔ ساختِ ریلز */}
      <button
        onClick={() => fileRef.current?.click()}
        className="absolute top-3 right-4 z-30 w-10 h-10 rounded-full bg-white/15 backdrop-blur flex items-center justify-center text-white"
        aria-label="ساختِ ریلز"
      >
        {uploading ? <Loader2 size={18} className="animate-spin" /> : <Plus size={22} />}
      </button>

      <input
        ref={fileRef}
        type="file"
        accept="video/*,image/*"
        className="hidden"
        onChange={onPick}
      />

      {editorFile && (
        <MediaEditor
          file={editorFile}
          kind={editorFile.type.startsWith("video/") ? "video" : "image"}
          onCancel={() => setEditorFile(null)}
          onDone={publish}
        />
      )}

      {commentsFor && (
        <CommentsSheet
          reel={commentsFor}
          onClose={() => setCommentsFor(null)}
          onAdded={bumpComment}
        />
      )}
    </div>
  );
}
