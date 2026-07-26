"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import {
  Heart, MessageCircle, Share2, Bookmark, Trash2, Plus,
  Loader2, X, Send, ImagePlus, MapPin,
} from "lucide-react";
import toast from "react-hot-toast";
import { postsApi, getApiErrorMessage } from "@/lib/api";
import { useAuthStore } from "@/store/auth";
import MediaEditor from "@/components/chat/MediaEditor";

export interface Post {
  id: string;
  author_earth_id: string;
  author_name: string;
  author_avatar?: string | null;
  media_url: string;
  media_type: string;
  caption?: string | null;
  like_count: number;
  comment_count: number;
  liked_by_me: boolean;
  saved_by_me: boolean;
  is_mine: boolean;
  lat?: number | null;
  lng?: number | null;
  place_name?: string | null;
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

function ago(iso: string): string {
  const d = (Date.now() - new Date(iso).getTime()) / 1000;
  if (d < 60) return "همین حالا";
  if (d < 3600) return `${Math.floor(d / 60)} دقیقه پیش`;
  if (d < 86400) return `${Math.floor(d / 3600)} ساعت پیش`;
  if (d < 604800) return `${Math.floor(d / 86400)} روز پیش`;
  return new Date(iso).toLocaleDateString("fa-IR");
}

// ─── شیتِ کامنت‌ها ─────────────────────────────────────────
function CommentsSheet({ post, onClose, onAdded }: { post: Post; onClose: () => void; onAdded: () => void }) {
  const [items, setItems] = useState<Comment[]>([]);
  const [loading, setLoading] = useState(true);
  const [text, setText] = useState("");
  const [sending, setSending] = useState(false);

  const load = useCallback(async () => {
    try { const r = await postsApi.comments(post.id); setItems(r.data || []); }
    catch { /* silent */ } finally { setLoading(false); }
  }, [post.id]);
  useEffect(() => { load(); }, [load]);

  const send = async () => {
    const body = text.trim();
    if (!body || sending) return;
    setSending(true);
    try {
      const r = await postsApi.addComment(post.id, body);
      setItems((p) => [r.data, ...p]); setText(""); onAdded();
    } catch (e) { toast.error(getApiErrorMessage(e, "ارسالِ کامنت ناموفق بود")); }
    finally { setSending(false); }
  };
  const remove = async (c: Comment) => {
    try { await postsApi.removeComment(c.id); setItems((p) => p.filter((x) => x.id !== c.id)); }
    catch { toast.error("حذف ناموفق بود"); }
  };

  return (
    <div className="fixed inset-0 z-[90] flex flex-col justify-end" onClick={onClose}>
      <div className="absolute inset-0 bg-black/50" />
      <div className="relative bg-[#141414] rounded-t-2xl max-h-[70vh] flex flex-col" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between px-4 py-3 border-b border-white/10">
          <span className="text-white font-semibold text-sm">کامنت‌ها</span>
          <button onClick={onClose} className="text-white/60"><X size={20} /></button>
        </div>
        <div className="flex-1 overflow-y-auto px-4 py-3 space-y-4">
          {loading ? (
            <div className="flex justify-center py-8"><Loader2 className="animate-spin text-white/40" /></div>
          ) : items.length === 0 ? (
            <p className="text-center text-white/40 text-sm py-8">اولین کامنت را بگذارید</p>
          ) : items.map((c) => (
            <div key={c.id} className="flex items-start gap-2">
              <div className="w-8 h-8 rounded-full overflow-hidden bg-white/10 flex items-center justify-center text-xs shrink-0">
                {c.author_avatar ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={c.author_avatar} alt="" className="w-full h-full object-cover" />
                ) : (c.author_name?.[0] ?? "👤")}
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-[12px] text-white/60">{c.author_name} · {ago(c.created_at)}</p>
                <p className="text-[14px] text-white break-words">{c.body}</p>
              </div>
              {c.is_mine && (
                <button onClick={() => remove(c)} className="text-white/40 hover:text-rose-400"><Trash2 size={15} /></button>
              )}
            </div>
          ))}
        </div>
        <div className="flex items-center gap-2 p-3 border-t border-white/10">
          <input value={text} onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && send()}
            placeholder="کامنت بگذارید…"
            className="flex-1 bg-white/8 rounded-full px-4 py-2 text-sm text-white outline-none placeholder:text-white/35" />
          <button onClick={send} disabled={sending || !text.trim()}
            className="w-9 h-9 rounded-full bg-indigo-500 flex items-center justify-center text-white disabled:opacity-40">
            {sending ? <Loader2 size={16} className="animate-spin" /> : <Send size={16} />}
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── کارتِ پست ─────────────────────────────────────────────
function PostCard({ post, onLike, onSave, onComments, onDelete }: {
  post: Post;
  onLike: (p: Post) => void;
  onSave: (p: Post) => void;
  onComments: (p: Post) => void;
  onDelete: (p: Post) => void;
}) {
  const [burst, setBurst] = useState(false);
  const lastTap = useRef(0);
  const isVideo = post.media_type === "video";

  const onMediaTap = () => {
    const now = Date.now();
    if (now - lastTap.current < 280) {
      if (!post.liked_by_me) onLike(post);
      setBurst(true); setTimeout(() => setBurst(false), 700);
      lastTap.current = 0;
    } else lastTap.current = now;
  };

  return (
    <article className="bg-[#141414] rounded-2xl overflow-hidden border border-white/8 mb-4">
      {/* هدر */}
      <div className="flex items-center gap-2.5 px-3 py-2.5">
        <Link href={`/u/${post.author_earth_id}`} className="flex items-center gap-2.5 flex-1 min-w-0">
          <div className="w-9 h-9 rounded-full overflow-hidden bg-white/10 flex items-center justify-center text-sm ring-1 ring-white/15">
            {post.author_avatar ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={post.author_avatar} alt="" className="w-full h-full object-cover" />
            ) : (post.author_name?.[0] ?? "👤")}
          </div>
          <div className="min-w-0">
            <p className="text-sm font-semibold text-white truncate">{post.author_name}</p>
            <p className="text-[11px] text-white/45 flex items-center gap-1">
              {ago(post.created_at)}
              {post.lat != null && post.lng != null && (
                <span className="text-indigo-300/80 flex items-center gap-0.5 truncate">
                  · <MapPin size={10} />{post.place_name || "روی نقشه"}
                </span>
              )}
            </p>
          </div>
        </Link>
        {post.is_mine && (
          <button onClick={() => onDelete(post)} className="text-white/40 hover:text-rose-400 p-1"><Trash2 size={17} /></button>
        )}
      </div>

      {/* رسانه */}
      <div className="relative bg-black" onClick={onMediaTap}>
        {isVideo ? (
          <video src={post.media_url} className="w-full max-h-[70vh] object-contain" controls playsInline preload="metadata" />
        ) : (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={post.media_url} alt="" className="w-full max-h-[70vh] object-contain" />
        )}
        {burst && (
          <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
            <Heart size={110} className="text-white drop-shadow-lg animate-ping-once" fill="currentColor" />
          </div>
        )}
      </div>

      {/* اکشن‌ها */}
      <div className="flex items-center gap-4 px-3 pt-2.5">
        <button onClick={() => onLike(post)} className="flex items-center gap-1.5">
          <Heart size={24} className={post.liked_by_me ? "text-rose-500" : "text-white"} fill={post.liked_by_me ? "currentColor" : "none"} />
          <span className="text-sm text-white/80">{fmt(post.like_count)}</span>
        </button>
        <button onClick={() => onComments(post)} className="flex items-center gap-1.5">
          <MessageCircle size={23} className="text-white" />
          <span className="text-sm text-white/80">{fmt(post.comment_count)}</span>
        </button>
        <button
          onClick={() => {
            const url = typeof window !== "undefined" ? window.location.origin + "/u/" + post.author_earth_id : "";
            if (navigator.share) navigator.share({ title: "Dilix", url }).catch(() => {});
            else { navigator.clipboard?.writeText(url); toast.success("لینک کپی شد"); }
          }}
          className="text-white"
        ><Share2 size={22} /></button>
        <button onClick={() => onSave(post)} className="ms-auto text-white">
          <Bookmark size={22} className={post.saved_by_me ? "text-amber-400" : "text-white"} fill={post.saved_by_me ? "currentColor" : "none"} />
        </button>
      </div>

      {/* موقعیت (لحظه) */}
      {post.lat != null && post.lng != null && (
        <Link
          href={`/earth?focus=${post.lat},${post.lng}`}
          className="mx-3 mt-2 inline-flex items-center gap-1.5 bg-indigo-500/15 text-indigo-300 rounded-full px-3 py-1 text-[12px] hover:bg-indigo-500/25 transition-colors"
        >
          <MapPin size={13} /> {post.place_name || "دیدن روی کره"}
        </Link>
      )}

      {/* کپشن */}
      {post.caption && (
        <p className="px-3 py-2 text-[14px] text-white/90 leading-6 whitespace-pre-wrap break-words">
          <span className="font-semibold">{post.author_name} </span>{post.caption}
        </p>
      )}
      <div className="h-2" />
    </article>
  );
}

// ─── فیدِ اصلی ─────────────────────────────────────────────
export default function PostFeed({ mode = "feed", query = "", topic = "" }: { mode?: "feed" | "explore" | "interests" | "topic"; query?: string; topic?: string }) {
  const searchTerm = mode === "explore" ? query.trim() : "";
  const [posts, setPosts] = useState<Post[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(true);
  const [commentsFor, setCommentsFor] = useState<Post | null>(null);
  const [viewer, setViewer] = useState<Post | null>(null); // explore modal
  const [editorFile, setEditorFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [postLoc, setPostLoc] = useState<{ lat: number; lng: number } | null>(null);
  const [locBusy, setLocBusy] = useState(false);
  const fileRef = useRef<HTMLInputElement | null>(null);
  const fetchingRef = useRef(false);
  const sentinelRef = useRef<HTMLDivElement | null>(null);

  const fetchPage = useCallback(async (cur: string | null) => {
    if (fetchingRef.current) return;
    fetchingRef.current = true;
    try {
      const r = searchTerm
        ? await postsApi.search(searchTerm, cur ?? undefined)
        : mode === "topic" ? await postsApi.topicFeed(topic, cur ?? undefined)
        : mode === "interests" ? await postsApi.interests(cur ?? undefined)
        : mode === "explore" ? await postsApi.explore(cur ?? undefined)
        : await postsApi.feed(cur ?? undefined);
      const data = r.data || {};
      const items: Post[] = data.items || [];
      setPosts((prev) => {
        const ids = new Set(prev.map((x) => x.id));
        return [...prev, ...items.filter((x) => !ids.has(x.id))];
      });
      setCursor(data.next_cursor ?? null);
      setHasMore(Boolean(data.next_cursor) && items.length > 0);
    } catch { /* silent */ } finally { setLoading(false); fetchingRef.current = false; }
  }, [mode, searchTerm, topic]);

  useEffect(() => {
    setPosts([]); setCursor(null); setHasMore(true); setLoading(true);
    fetchPage(null);
  }, [mode, searchTerm, topic, fetchPage]);

  // بارگذاریِ بی‌نهایت
  useEffect(() => {
    const el = sentinelRef.current;
    if (!el) return;
    const io = new IntersectionObserver((ents) => {
      if (ents[0].isIntersecting && hasMore) fetchPage(cursor);
    }, { rootMargin: "400px" });
    io.observe(el);
    return () => io.disconnect();
  }, [cursor, hasMore, fetchPage]);

  const patch = (id: string, fn: (p: Post) => Post) =>
    setPosts((prev) => prev.map((x) => (x.id === id ? fn(x) : x)));

  const toggleLike = async (post: Post) => {
    patch(post.id, (x) => ({ ...x, liked_by_me: !x.liked_by_me, like_count: x.like_count + (x.liked_by_me ? -1 : 1) }));
    setViewer((v) => v && v.id === post.id ? { ...v, liked_by_me: !v.liked_by_me, like_count: v.like_count + (v.liked_by_me ? -1 : 1) } : v);
    try {
      const r = await postsApi.like(post.id);
      patch(post.id, (x) => ({ ...x, liked_by_me: r.data.liked, like_count: r.data.like_count }));
    } catch { patch(post.id, (x) => ({ ...x, liked_by_me: post.liked_by_me, like_count: post.like_count })); }
  };
  const toggleSave = async (post: Post) => {
    patch(post.id, (x) => ({ ...x, saved_by_me: !x.saved_by_me }));
    try { const r = await postsApi.save(post.id); patch(post.id, (x) => ({ ...x, saved_by_me: r.data.saved })); }
    catch { patch(post.id, (x) => ({ ...x, saved_by_me: post.saved_by_me })); }
  };
  const removePost = async (post: Post) => {
    if (!confirm("این پست حذف شود؟")) return;
    try { await postsApi.remove(post.id); setPosts((prev) => prev.filter((x) => x.id !== post.id)); setViewer(null); toast.success("پست حذف شد"); }
    catch { toast.error("حذف ناموفق بود"); }
  };

  const onPick = (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0]; e.target.value = "";
    if (!f) return;
    if (!f.type.startsWith("image/") && !f.type.startsWith("video/")) { toast.error("فقط عکس یا ویدیو"); return; }
    setEditorFile(f);
  };
  const toggleLoc = () => {
    if (postLoc) { setPostLoc(null); return; }
    if (!navigator.geolocation) { toast.error("مرورگرِ شما موقعیت را پشتیبانی نمی‌کند"); return; }
    setLocBusy(true);
    navigator.geolocation.getCurrentPosition(
      (pos) => { setPostLoc({ lat: pos.coords.latitude, lng: pos.coords.longitude }); setLocBusy(false); toast.success("موقعیت به پستِ بعدی افزوده شد 📍"); },
      () => { setLocBusy(false); toast.error("دسترسی به موقعیت داده نشد"); },
      { enableHighAccuracy: true, timeout: 10_000 },
    );
  };
  const publish = async (file: File) => {
    setEditorFile(null); setUploading(true);
    try {
      const r = await postsApi.create(file, undefined, file.name, postLoc ? { lat: postLoc.lat, lng: postLoc.lng } : undefined);
      setPosts((prev) => [r.data, ...prev]); setPostLoc(null);
      toast.success(postLoc ? "لحظهٔ شما روی کره ثبت شد 🌍" : "پستِ شما منتشر شد");
    }
    catch (e) { toast.error(getApiErrorMessage(e, "انتشار ناموفق بود")); }
    finally { setUploading(false); }
  };
  const bumpComment = (id: string) => patch(id, (x) => ({ ...x, comment_count: x.comment_count + 1 }));

  return (
    <div className="px-3">
      {/* کامپوزر (فقط فید) */}
      {mode === "feed" && (
        <div className="bg-[#141414] border border-white/8 rounded-2xl px-4 py-3 mb-4">
          <button onClick={() => fileRef.current?.click()} className="w-full flex items-center gap-3">
            <span className="w-9 h-9 rounded-full bg-indigo-500/20 flex items-center justify-center text-indigo-400">
              {uploading ? <Loader2 size={18} className="animate-spin" /> : <ImagePlus size={18} />}
            </span>
            <span className="text-sm text-white/55">چیزی به اشتراک بگذار…</span>
            <Plus size={18} className="ms-auto text-white/40" />
          </button>
          <button
            onClick={toggleLoc}
            className={`mt-2 inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-[12px] transition-colors ${
              postLoc ? "bg-indigo-500/20 text-indigo-300" : "bg-white/5 text-white/50 hover:text-white/70"
            }`}
          >
            {locBusy ? <Loader2 size={13} className="animate-spin" /> : <MapPin size={13} />}
            {postLoc ? "موقعیت افزوده شد — برای حذف بزنید" : "افزودنِ موقعیت (لحظه روی کره)"}
          </button>
        </div>
      )}

      {loading && posts.length === 0 ? (
        <div className="flex justify-center py-16"><Loader2 className="animate-spin text-white/40" size={28} /></div>
      ) : posts.length === 0 ? (
        <div className="flex flex-col items-center gap-3 py-16 text-white/50">
          <p>{
            searchTerm ? `پستی با «${searchTerm}» پیدا نشد`
            : mode === "feed" ? "فیدِ شما خالی است — کسانی را دنبال کن یا پست بگذار"
            : mode === "topic" ? `هنوز پستی با موضوعِ «${topic}» نیست`
            : mode === "interests" ? "هنوز علاقه‌ای نساخته‌ای — چند پست را لایک یا ذخیره کن تا اینجا پیشنهاد ببینی"
            : "هنوز پستی نیست"
          }</p>
        </div>
      ) : mode !== "feed" ? (
        <div className="grid grid-cols-3 gap-1">
          {posts.map((p) => (
            <button key={p.id} onClick={() => setViewer(p)} className="relative aspect-square bg-white/5 overflow-hidden">
              {p.media_type === "video" ? (
                <video src={p.media_url} className="w-full h-full object-cover" muted playsInline preload="metadata" />
              ) : (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={p.media_url} alt="" className="w-full h-full object-cover" />
              )}
              <span className="absolute bottom-1 left-1 flex items-center gap-1 text-white text-[11px] drop-shadow">
                <Heart size={12} fill="currentColor" /> {fmt(p.like_count)}
              </span>
            </button>
          ))}
        </div>
      ) : (
        posts.map((p) => (
          <PostCard key={p.id} post={p} onLike={toggleLike} onSave={toggleSave} onComments={setCommentsFor} onDelete={removePost} />
        ))
      )}

      <div ref={sentinelRef} className="h-8" />

      <input ref={fileRef} type="file" accept="image/*,video/*" className="hidden" onChange={onPick} />

      {editorFile && (
        <MediaEditor file={editorFile} kind={editorFile.type.startsWith("video/") ? "video" : "image"}
          onCancel={() => setEditorFile(null)} onDone={publish} />
      )}

      {/* مودالِ نمایشِ پست (کاوش) */}
      {viewer && (
        <div className="fixed inset-0 z-[85] bg-black/80 overflow-y-auto" onClick={() => setViewer(null)}>
          <div className="min-h-full flex items-start justify-center py-8 px-3" onClick={(e) => e.stopPropagation()}>
            <div className="w-full max-w-lg">
              <button onClick={() => setViewer(null)} className="mb-2 text-white/70"><X size={22} /></button>
              <PostCard post={posts.find((x) => x.id === viewer.id) || viewer}
                onLike={toggleLike} onSave={toggleSave} onComments={setCommentsFor} onDelete={removePost} />
            </div>
          </div>
        </div>
      )}

      {commentsFor && (
        <CommentsSheet post={commentsFor} onClose={() => setCommentsFor(null)} onAdded={() => bumpComment(commentsFor.id)} />
      )}
    </div>
  );
}
