"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { api, type PostOut, isAuthenticated } from "@/lib/api";

// خواندنِ فایل به data-URL (قرارداد رسانه‌ی بک‌اند: media آرایه‌ای از آبجکت‌ها).
function fileToDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result));
    r.onerror = () => reject(r.error);
    r.readAsDataURL(file);
  });
}

interface MediaItem {
  url: string;
  type: string;
}

export default function SocialPage() {
  const [posts, setPosts] = useState<PostOut[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [draft, setDraft] = useState("");
  const [media, setMedia] = useState<MediaItem[]>([]);
  const [publishing, setPublishing] = useState(false);
  const [commentFor, setCommentFor] = useState<string | null>(null);
  const [commentText, setCommentText] = useState("");
  const [authed, setAuthed] = useState(false);
  const fileRef = useRef<HTMLInputElement | null>(null);

  async function load() {
    setLoading(true);
    setError(null);
    try {
      setPosts(await api.social.feed());
    } catch {
      setError("بارگذاری فید ممکن نشد. اتصال به سرور را بررسی کنید.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    setAuthed(isAuthenticated());
    load();
  }, []);

  async function pickMedia(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (file) e.target.value = "";
    if (!file) return;
    try {
      const url = await fileToDataUrl(file);
      const type = file.type.startsWith("video") ? "video" : "image";
      setMedia((m) => [...m, { url, type }]);
    } catch {
      setError("خواندن فایل ممکن نشد.");
    }
  }

  async function publish() {
    const content = draft.trim();
    if (!content && media.length === 0) return;
    setPublishing(true);
    setError(null);
    try {
      const post_type = media.some((m) => m.type === "video")
        ? "video"
        : media.length > 0
          ? "image"
          : "text";
      const post = await api.social.createPost({ post_type, content: content || undefined, media });
      setPosts((p) => [post, ...p]);
      setDraft("");
      setMedia([]);
    } catch {
      setError("ارسال پست ناموفق بود. ابتدا وارد شوید.");
    } finally {
      setPublishing(false);
    }
  }

  async function like(postId: string) {
    try {
      const updated = await api.social.react(postId, "like");
      setPosts((p) => p.map((x) => (x.id === postId ? updated : x)));
    } catch {
      setError("ثبتِ واکنش ممکن نشد. ابتدا وارد شوید.");
    }
  }

  async function sendComment(postId: string) {
    const text = commentText.trim();
    if (!text) return;
    try {
      await api.social.comment(postId, text);
      setPosts((p) =>
        p.map((x) => (x.id === postId ? { ...x, comment_count: x.comment_count + 1 } : x)),
      );
      setCommentText("");
      setCommentFor(null);
    } catch {
      setError("ثبتِ نظر ممکن نشد. ابتدا وارد شوید.");
    }
  }

  function mediaUrlOf(item: unknown): string | null {
    if (item && typeof item === "object" && "url" in item) {
      const u = (item as { url?: unknown }).url;
      if (typeof u === "string") return u;
    }
    return null;
  }

  return (
    <main className="page">
      <div className="row-between">
        <Link href="/" className="link-btn">
          ← خانه
        </Link>
        <h1 style={{ fontSize: "1.2rem" }}>اجتماعی</h1>
      </div>
      <p className="muted">فید فعالیت‌ها: پست، رسانه، لایک و نظر</p>

      {authed ? (
        <div className="card">
          <textarea
            className="input"
            rows={3}
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            placeholder="چه خبر؟"
            aria-label="متن پست"
          />
          {media.length > 0 && (
            <div className="row" style={{ gap: 8, flexWrap: "wrap", marginTop: 8 }}>
              {media.map((m, i) => (
                <div key={i} style={{ position: "relative" }}>
                  {m.type === "video" ? (
                    <video src={m.url} style={{ width: 72, height: 72, borderRadius: 8, objectFit: "cover" }} />
                  ) : (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                      src={m.url}
                      alt="پیش‌نمایش"
                      style={{ width: 72, height: 72, borderRadius: 8, objectFit: "cover" }}
                    />
                  )}
                  <button
                    className="link-btn"
                    aria-label="حذفِ رسانه"
                    onClick={() => setMedia((arr) => arr.filter((_, j) => j !== i))}
                    style={{ position: "absolute", insetInlineEnd: 2, insetBlockStart: 2 }}
                  >
                    ✕
                  </button>
                </div>
              ))}
            </div>
          )}
          <input
            ref={fileRef}
            type="file"
            accept="image/*,video/*"
            hidden
            onChange={pickMedia}
          />
          <div className="row-between" style={{ marginTop: 8 }}>
            <button className="btn secondary" onClick={() => fileRef.current?.click()}>
              افزودنِ رسانه
            </button>
            <button className="btn" onClick={publish} disabled={publishing}>
              {publishing ? "…" : "انتشار"}
            </button>
          </div>
        </div>
      ) : (
        <div className="card danger">برای ارسالِ پست ابتدا وارد شوید.</div>
      )}

      {loading && <p className="muted">در حال بارگذاری…</p>}
      {error && <div className="card danger">{error}</div>}
      {!loading && !error && posts.length === 0 && (
        <div className="card">
          <p className="muted">هنوز پستی نیست.</p>
        </div>
      )}

      {posts.map((post) => {
        const mediaUrls = (post.media || []).map(mediaUrlOf).filter((u): u is string => u != null);
        return (
          <article key={post.id} className="card">
            <div className="row-between">
              <strong>{post.author_earth_id.slice(0, 8)}…</strong>
              <span className="muted">{post.post_type}</span>
            </div>
            {post.content && <p style={{ marginBlock: 8 }}>{post.content}</p>}
            {mediaUrls.map((u, i) => (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                key={i}
                src={u}
                alt="رسانه‌ی پست"
                style={{ width: "100%", borderRadius: 12, marginBlock: 6 }}
              />
            ))}
            <div className="row" style={{ gap: 16 }}>
              <button className="link-btn" onClick={() => like(post.id)}>
                👍 {post.reaction_counts?.like ?? 0}
              </button>
              <button
                className="link-btn"
                onClick={() => {
                  setCommentFor((c) => (c === post.id ? null : post.id));
                  setCommentText("");
                }}
              >
                💬 {post.comment_count}
              </button>
            </div>
            {commentFor === post.id && (
              <div className="row" style={{ gap: 8, marginTop: 8 }}>
                <input
                  className="input"
                  value={commentText}
                  onChange={(e) => setCommentText(e.target.value)}
                  placeholder="نظر خود را بنویسید…"
                  aria-label="متن نظر"
                />
                <button className="btn secondary" onClick={() => sendComment(post.id)}>
                  ارسال
                </button>
              </div>
            )}
          </article>
        );
      })}
    </main>
  );
}
