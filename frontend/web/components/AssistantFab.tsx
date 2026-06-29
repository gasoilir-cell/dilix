"use client";

import { useState } from "react";
import { usePathname } from "next/navigation";
import { api } from "@/lib/api";

interface Turn {
  role: "user" | "assistant";
  text: string;
}

const HIDE_ON = ["/login"];

// دستیار هوشمندِ شناورِ سراسری (سند ۷ §۲) — روی همه‌ی صفحات در دسترس.
export default function AssistantFab() {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const [conversationId] = useState(() =>
    typeof crypto !== "undefined" && crypto.randomUUID ? crypto.randomUUID() : `c-${Date.now()}`,
  );
  const [turns, setTurns] = useState<Turn[]>([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);

  async function send() {
    const text = input.trim();
    if (!text || busy) return;
    setInput("");
    setTurns((t) => [...t, { role: "user", text }]);
    setBusy(true);
    try {
      const res = await api.ai.invoke(conversationId, text);
      setTurns((t) => [...t, { role: "assistant", text: res.reply }]);
    } catch {
      setTurns((t) => [
        ...t,
        { role: "assistant", text: "اتصال به دستیار برقرار نشد. لطفاً بعداً تلاش کنید." },
      ]);
    } finally {
      setBusy(false);
    }
  }

  if (HIDE_ON.some((p) => pathname === p || pathname.startsWith(`${p}/`))) return null;

  return (
    <>
      <button
        className="assistant-fab"
        aria-label="دستیار هوشمند"
        onClick={() => setOpen((v) => !v)}
      >
        {open ? "✕" : "✨"}
      </button>

      {open && (
        <div className="assistant-panel" role="dialog" aria-label="گفتگو با دستیار">
          <header>
            <strong>دستیار هوشمند</strong>
            <span className="muted">Dilix AI</span>
          </header>
          <div className="assistant-body">
            {turns.length === 0 && (
              <p className="muted">سلام! چطور می‌توانم کمک کنم؟ درباره‌ی بار، بیمه یا حسابتان بپرسید.</p>
            )}
            {turns.map((t, i) => (
              <div key={i} className={`bubble ${t.role}`}>
                {t.text}
              </div>
            ))}
            {busy && <div className="bubble assistant">در حال نوشتن…</div>}
          </div>
          <div className="assistant-input">
            <input
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && send()}
              placeholder="پیام…"
              aria-label="متن پیام"
            />
            <button className="btn" onClick={send} disabled={busy}>
              ارسال
            </button>
          </div>
        </div>
      )}
    </>
  );
}
