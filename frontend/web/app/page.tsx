"use client";

import { useEffect, useState } from "react";
import { api, type PostOut, isAuthenticated } from "@/lib/api";

export default function HomeFeed() {
  const [posts, setPosts] = useState<PostOut[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [draft, setDraft] = useState("");
  const [authed, setAuthed] = useState(false);

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

  async function publish() {
    const content = draft.trim();
    if (!content) return;
    try {
      const post = await api.social.createPost({ content });
      setPosts((p) => [post, ...p]);
      setDraft("");
    } catch {
      setError("ارسال پست ناموفق بود. ابتدا وارد شوید.");
    }
  }

  return (
    <main className="page">
      <h1>خانه</h1>
      <p className="muted">فید فعالیت‌ها و کسب‌وکارها</p>

      {authed && (
        <div className="card">
          <textarea
            className="input"
            rows={3}
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            placeholder="چه خبر؟"
            aria-label="متن پست"
          />
          <div style={{ marginTop: 8, textAlign: "start" }}>
            <button className="btn" onClick={publish}>
              انتشار
            </button>
          </div>
        </div>
      )}

      {loading && <p className="muted">در حال بارگذاری…</p>}
      {error && <div className="card danger">{error}</div>}
      {!loading && !error && posts.length === 0 && (
        <div className="card">
          <p className="muted">هنوز پستی نیست.</p>
        </div>
      )}

      {posts.map((post) => (
        <article key={post.id} className="card">
          <div className="row-between">
            <strong>{post.author_earth_id.slice(0, 8)}…</strong>
            <span className="muted">{post.post_type}</span>
          </div>
          {post.content && <p style={{ marginBlock: 8 }}>{post.content}</p>}
          <div className="row" style={{ gap: 16 }}>
            <button className="link-btn" onClick={() => api.social.react(post.id, "like").then(load)}>
              👍 {post.reaction_counts?.like ?? 0}
            </button>
            <span className="muted">💬 {post.comment_count}</span>
          </div>
        </article>
      ))}
    </main>
  );
}
