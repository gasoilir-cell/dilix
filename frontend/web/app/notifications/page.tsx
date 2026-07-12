"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { api, isAuthenticated, type NotificationOut } from "@/lib/api";

function formatDate(iso: string): string {
  try {
    return new Date(iso).toLocaleDateString("fa-IR", {
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  } catch {
    return iso;
  }
}

export default function NotificationsPage() {
  const router = useRouter();
  const [items, setItems] = useState<NotificationOut[]>([]);
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const data = await api.notifications.list();
      setItems(data);
    } catch {
      setError("بارگذاری اعلان‌ها ممکن نشد.");
    }
  }, []);

  useEffect(() => {
    if (!isAuthenticated()) {
      router.replace("/login");
      return;
    }
    setReady(true);
    load();
  }, [router, load]);

  async function markRead(id: string) {
    try {
      await api.notifications.markRead(id);
      setItems((prev) => prev.map((n) => (n.id === id ? { ...n, read: true } : n)));
    } catch {
      setError("علامت‌گذاری به‌عنوان خوانده‌شده ممکن نشد.");
    }
  }

  async function markAllRead() {
    const unread = items.filter((n) => !n.read);
    await Promise.all(unread.map((n) => api.notifications.markRead(n.id).catch(() => null)));
    setItems((prev) => prev.map((n) => ({ ...n, read: true })));
  }

  if (!ready) return null;

  const unreadCount = items.filter((n) => !n.read).length;

  return (
    <main className="page">
      <div className="row-between">
        <h1>اعلان‌ها</h1>
        {unreadCount > 0 && (
          <button className="btn secondary" onClick={markAllRead}>
            خواندنِ همه ({unreadCount})
          </button>
        )}
      </div>

      {error && <div className="card danger">{error}</div>}

      {items.length === 0 ? (
        <div className="card">
          <p className="muted">اعلانی وجود ندارد.</p>
        </div>
      ) : (
        items.map((n) => (
          <div
            key={n.id}
            className={`card${n.read ? "" : " unread"}`}
            onClick={() => !n.read && markRead(n.id)}
          >
            <div className="row-between">
              <strong>{n.title}</strong>
              {!n.read && <span className="badge">جدید</span>}
            </div>
            {n.body && <p className="muted">{n.body}</p>}
            <div className="muted" style={{ fontSize: 12 }}>
              {formatDate(n.created_at)}
            </div>
          </div>
        ))
      )}
    </main>
  );
}
