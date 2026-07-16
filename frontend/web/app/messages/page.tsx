"use client";

import { useState } from "react";
import { api, type MessageOut, type RoomOut, isAuthenticated } from "@/lib/api";
import { requestCall, type CallMedia } from "@/lib/call-store";
import StoryBar from "@/components/StoryBar";
import StickerLibrary from "@/components/StickerLibrary";

// لیست/چتِ پیام‌رسان. پیام‌ها در محصولِ نهایی E2EE هستند (نشانِ قفل).
export default function Messenger() {
  const [room, setRoom] = useState<RoomOut | null>(null);
  const [messages, setMessages] = useState<MessageOut[]>([]);
  const [draft, setDraft] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [showStickers, setShowStickers] = useState(false);
  const authed = typeof window !== "undefined" && isAuthenticated();

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
          <p className="muted">هنوز گفتگویی باز نیست.</p>
          <button className="btn" onClick={startRoom} disabled={!authed}>
            شروع گفتگو
          </button>
        </div>
      ) : (
        <>
          <div className="card">
            <div className="row-between">
              <strong>{room.title ?? "گفتگو"}</strong>
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
