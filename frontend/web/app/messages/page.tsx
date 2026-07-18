"use client";

import { useEffect, useState } from "react";
import { api, type MessageOut, type RoomOut, isAuthenticated } from "@/lib/api";
import { requestCall, type CallMedia } from "@/lib/call-store";
import StoryBar from "@/components/StoryBar";
import StickerLibrary from "@/components/StickerLibrary";

// لیست/چتِ پیام‌رسان. پیام‌ها در محصولِ نهایی E2EE هستند (نشانِ قفل).
export default function Messenger() {
  const [room, setRoom] = useState<RoomOut | null>(null);
  const [rooms, setRooms] = useState<RoomOut[]>([]);
  const [roomsLoading, setRoomsLoading] = useState(true);
  const [messages, setMessages] = useState<MessageOut[]>([]);
  const [draft, setDraft] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [showStickers, setShowStickers] = useState(false);
  const authed = typeof window !== "undefined" && isAuthenticated();

  async function loadRooms() {
    try {
      setRooms(await api.messaging.listRooms());
    } catch {
      /* بی‌صدا؛ لیستِ خالی می‌ماند */
    } finally {
      setRoomsLoading(false);
    }
  }

  useEffect(() => {
    if (!authed) {
      setRoomsLoading(false);
      return;
    }
    loadRooms();
    const t = setInterval(loadRooms, 10000); /*rt-poll*/
    return () => clearInterval(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [authed]);

  async function openRoom(r: RoomOut) {
    setError(null);
    setRoom(r);
    try {
      setMessages(await api.messaging.messages(r.id));
    } catch {
      setError("بارگذاری پیام‌ها ممکن نشد.");
    }
  }

  async function sendSticker(stickerId: string) {
    if (!room) return;
    try {
      const m = await api.messaging.send(room.id, `[sticker:${stickerId}]`);
      setMessages((prev) => [...prev, m]);
    } catch {
      setError("ارسال استیکر ناموفق بود.");
    }
  }

  async function startRoom() {
    setError(null);
    try {
      const r = await api.messaging.createRoom({ room_type: "group", title: "گفتگوی جدید" });
      setRoom(r);
      setMessages(await api.messaging.messages(r.id));
      loadRooms();
    } catch {
      setError("ساخت گفتگو ممکن نشد. ابتدا وارد شوید.");
    }
  }

  function startCall(media: CallMedia) {
    const peer = window.prompt("Earth ID مخاطب برای تماس را وارد کنید");
    if (!peer?.trim()) return;
    requestCall({ earthId: peer.trim(), name: peer.trim(), media });
  }

  async function send() {
    const content = draft.trim();
    if (!content || !room) return;
    setDraft("");
    try {
      const m = await api.messaging.send(room.id, content);
      setMessages((prev) => [...prev, m]);
    } catch {
      setError("ارسال پیام ناموفق بود.");
    }
  }

  return (
    <main className="page">
      <h1>پیام‌ها</h1>
      <p className="muted">
        گفتگوهای رمزنگاری‌شده‌ی سرتاسری <span aria-hidden>🔒</span>
      </p>

      {authed && <StoryBar />}

      {!authed && <div className="card muted">برای استفاده از پیام‌رسان ابتدا از بخش «من» وارد شوید.</div>}
      {error && <div className="card danger">{error}</div>}

      {!room ? (
        <div className="card">
          {authed && roomsLoading && <p className="muted">در حال بارگذاری گفتگوها…</p>}
          {authed && !roomsLoading && rooms.length > 0 && (
            <ul className="list" style={{ marginBottom: 12 }}>
              {rooms.map((r) => (
                <li key={r.id}>
                  <button
                    className="btn secondary"
                    style={{ width: "100%", justifyContent: "space-between" }}
                    onClick={() => openRoom(r)}
                  >
                    <span>{r.title ?? `${r.id.slice(0, 8)}…`}</span>
                    <span aria-hidden>{r.is_e2ee ? "🔒" : "💬"}</span>
                  </button>
                </li>
              ))}
            </ul>
          )}
          {authed && !roomsLoading && rooms.length === 0 && (
            <p className="muted">هنوز گفتگویی ندارید.</p>
          )}
          <button className="btn" onClick={startRoom} disabled={!authed}>
            شروع گفتگوی جدید
          </button>
        </div>
      ) : (
        <>
          <div className="card">
            <div className="row-between">
              <div className="row" style={{ gap: 8 }}>
                <button
                  className="btn secondary"
                  onClick={() => { setRoom(null); loadRooms(); }}
                  aria-label="بازگشت به فهرست گفتگوها"
                >
                  ←
                </button>
                <strong>{room.title ?? "گفتگو"}</strong>
              </div>
              <div className="row" style={{ gap: 8 }}>
                <button className="btn secondary" onClick={() => startCall("audio")} aria-label="شروع تماس صوتی">
                  تماس صوتی
                </button>
                <button className="btn secondary" onClick={() => startCall("video")} aria-label="شروع تماس تصویری">
                  تماس تصویری
                </button>
                {room.is_e2ee && <span className="badge">E2EE 🔒</span>}
              </div>
            </div>
          </div>

          <div className="chat">
            {messages.length === 0 && <p className="muted">پیامی نیست؛ اولین پیام را بفرستید.</p>}
            {messages.map((m) => (
              <div key={m.id} className="bubble user">
                {m.content}
              </div>
            ))}
          </div>

          <div className="assistant-input">
            <button className="btn secondary" onClick={() => setShowStickers(true)} aria-label="استیکرها">
              <span aria-hidden>🙂</span>
            </button>
            <input
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && send()}
              placeholder="پیام…"
              aria-label="متن پیام"
            />
            <button className="btn" onClick={send}>
              ارسال
            </button>
          </div>
        </>
      )}

      {showStickers && (
        <StickerLibrary
          onClose={() => setShowStickers(false)}
          onSendSticker={sendSticker}
        />
      )}
    </main>
  );
}
