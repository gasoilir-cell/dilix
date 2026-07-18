"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { api, type PostOut, isAuthenticated } from "@/lib/api";

// استخراجِ اولین ویدیوی پست از آرایه‌ی media (قرارداد: آبجکت با کلیدِ url/media_url).
function videoUrlOf(post: PostOut): string | null {
  for (const item of post.media || []) {
    if (item && typeof item === "object") {
      const o = item as { url?: unknown; media_url?: unknown; type?: unknown; media_type?: unknown };
      const url = typeof o.url === "string" ? o.url : typeof o.media_url === "string" ? o.media_url : null;
      const kind = typeof o.type === "string" ? o.type : typeof o.media_type === "string" ? o.media_type : "";
      if (url && (kind === "" || kind.startsWith("video"))) return url;
    }
  }
  return null;
}

// یک ریلِ تکی؛ با ورود به دیدِ کاربر پخش و با خروج، مکث می‌شود.
function Reel({
  post,
  onLike,
  onComment,
}: {
  post: PostOut;
  onLike: (id: string) => void;
  onComment: (id: string, text: string) => Promise<void>;
}) {
  const ref = useRef<HTMLVideoElement | null>(null);
  const [paused, setPaused] = useState(false);
  const [commenting, setCommenting] = useState(false);
  const [text, setText] = useState("");
  const url = videoUrlOf(post);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (e.isIntersecting && e.intersectionRatio > 0.6) {
            el.play().then(() => setPaused(false)).catch(() => {});
          } else {
            el.pause();
          }
        }
      },
      { threshold: [0, 0.6, 1] },
    );
    io.observe(el);
    return () => io.disconnect();
  }, []);

  function toggle() {
    const el = ref.current;
    if (!el) return;
    if (el.paused) {
      el.play().then(() => setPaused(false)).catch(() => {});
    } else {
      el.pause();
      setPaused(true);
    }
  }

  async function submit() {
    const t = text.trim();
    if (!t) return;
    await onComment(post.id, t);
    setText("");
    setCommenting(false);
  }

  return (
    <section className="reel">
      {url ? (
        <video
          ref={ref}
          className="reel-video"
          src={url}
          loop
          muted
          playsInline
          onClick={toggle}
        />
      ) : (
        <div className="reel-video reel-empty" onClick={toggle}>
          <span className="muted">این ریل ویدیویی ندارد</span>
        </div>
      )}

      {paused && <div className="reel-play" aria-hidden>▶</div>}

      <div className="reel-overlay">
        <div className="reel-meta">
          <strong>{post.author_earth_id.slice(0, 8)}…</strong>
          {post.content && <p>{post.content}</p>}
        </div>
        <div className="reel-actions">
          <button className="reel-btn" onClick={() => onLike(post.id)} aria-label="پسندیدن">
            👍
            <span>{post.reaction_counts?.like ?? 0}</span>
          </button>
          <button
            className="reel-btn"
            onClick={() => setCommenting((c) => !c)}
            aria-label="نظر"
          >
            💬
            <span>{post.comment_count}</span>
          </button>
        </div>
      </div>

      {commenting && (
        <div className="reel-comment">
          <input
            className="input"
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder="نظر خود را بنویسید…"
            aria-label="متن نظر"
          />
          <button className="btn secondary" onClick={submit}>
            ارسال
          </button>
        </div>
      )}
    </section>
  );
}

export default function ReelsPage() {
  const [posts, setPosts] = useState<PostOut[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [authed, setAuthed] = useState(false);

  async function load() {
    setLoading(true);
    setError(null);
    try {
      setPosts(await api.social.feed(30, "reel"));
    } catch {
      setError("بارگذاری ریلز ممکن نشد. اتصال به سرور را بررسی کنید.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    setAuthed(isAuthenticated());
    load();
  }, []);

  async function like(postId: string) {
    if (!authed) {
      setError("برای واکنش ابتدا وارد شوید.");
      return;
    }
    try {
      const updated = await api.social.react(postId, "like");
      setPosts((p) => p.map((x) => (x.id === postId ? updated : x)));
    } catch {
      setError("ثبتِ واکنش ممکن نشد.");
    }
  }

  async function comment(postId: string, text: string) {
    try {
      await api.social.comment(postId, text);
      setPosts((p) =>
        p.map((x) => (x.id === postId ? { ...x, comment_count: x.comment_count + 1 } : x)),
      );
    } catch {
      setError("ثبتِ نظر ممکن نشد. ابتدا وارد شوید.");
    }
  }

  return (
    <main className="reels">
      <div className="reels-top">
        <Link href="/" className="link-btn">
          ← خانه
        </Link>
        <h1>ریلز</h1>
      </div>

      {loading && <p className="muted reels-msg">در حال بارگذاری…</p>}
      {error && <div className="card danger reels-msg">{error}</div>}
      {!loading && !error && posts.length === 0 && (
        <p className="muted reels-msg">هنوز ریلی نیست. اولین ویدیوی کوتاه را منتشر کنید.</p>
      )}

      <div className="reels-scroll">
        {posts.map((post) => (
          <Reel key={post.id} post={post} onLike={like} onComment={comment} />
        ))}
      </div>
    </main>
  );
}
