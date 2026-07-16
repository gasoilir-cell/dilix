"use client";

import { useEffect, useRef, useState } from "react";
import { api, isAuthenticated, type AiConversationOut, type AiMessageOut } from "@/lib/api";

type AgentType = "personal" | "freight" | "insurance" | "financial" | "matchmaking" | "travel" | "business";

const AGENTS: { value: AgentType; label: string }[] = [
  { value: "personal", label: "شخصی" },
  { value: "freight", label: "حمل‌ونقل" },
  { value: "insurance", label: "بیمه" },
  { value: "financial", label: "مالی" },
  { value: "business", label: "کسب‌وکار" },
];

function titleFor(agent: string): string {
  return AGENTS.find((a) => a.value === agent)?.label ?? agent;
}

export default function AssistantPanel({ compact = false }: { compact?: boolean }) {
  const [authed, setAuthed] = useState(false);
  const [conversations, setConversations] = useState<AiConversationOut[]>([]);
  const [active, setActive] = useState<AiConversationOut | null>(null);
  const [messages, setMessages] = useState<AiMessageOut[]>([]);
  const [agent, setAgent] = useState<AgentType>("personal");
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const bodyRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setAuthed(isAuthenticated());
  }, []);

  useEffect(() => {
    bodyRef.current?.scrollTo({ top: bodyRef.current.scrollHeight });
  }, [messages, sending]);

  async function load() {
    if (!isAuthenticated()) return;
    setLoading(true);
    setError(null);
    try {
      const list = await api.ai.conversations();
      setConversations(list);
      if (list[0]) {
        setActive(list[0]);
        setAgent((list[0].agent_type as AgentType) || "personal");
        setMessages(await api.ai.history(list[0].id));
      }
    } catch {
      setError("بارگذاری تاریخچه دستیار ممکن نشد.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { load(); }, []);

  async function selectConversation(conv: AiConversationOut) {
    setActive(conv);
    setAgent((conv.agent_type as AgentType) || "personal");
    setLoading(true);
    setError(null);
    try {
      setMessages(await api.ai.history(conv.id));
    } catch {
      setError("دریافت پیام‌های مکالمه ممکن نشد.");
    } finally {
      setLoading(false);
    }
  }

  async function newConversation(nextAgent = agent) {
    setLoading(true);
    setError(null);
    try {
      const conv = await api.ai.createConversation({ agent_type: nextAgent, title: `دستیار ${titleFor(nextAgent)}` });
      setConversations((prev) => [conv, ...prev]);
      setActive(conv);
      setAgent(nextAgent);
      setMessages([]);
      return conv;
    } catch {
      setError("ساخت مکالمه جدید ممکن نشد.");
      return null;
    } finally {
      setLoading(false);
    }
  }

  async function send() {
    const text = input.trim();
    if (!text || sending) return;
    setInput("");
    setError(null);
    let conv = active;
    if (!conv) conv = await newConversation(agent);
    if (!conv) return;
    const optimistic: AiMessageOut = {
      id: `local-${Date.now()}`,
      conversation_id: conv.id,
      role: "user",
      content: text,
      tool_calls: [],
      sent_at: new Date().toISOString(),
    };
    setMessages((prev) => [...prev, optimistic]);
    setSending(true);
    try {
      const reply = await api.ai.chat(conv.id, text);
      setMessages((prev) => [...prev, reply]);
    } catch {
      setError("ارسال پیام به دستیار ناموفق بود.");
      setMessages((prev) => prev.filter((m) => m.id !== optimistic.id));
    } finally {
      setSending(false);
    }
  }

  if (!authed) {
    return <div className="card muted">برای استفاده از دستیار هوشمند ابتدا وارد حساب شوید.</div>;
  }

  return (
    <section className={compact ? "assistant-full compact" : "assistant-full"}>
      <div className="assistant-sidebar card">
        <div className="row-between">
          <strong>مکالمه‌ها</strong>
          <button className="btn secondary" onClick={() => newConversation()} disabled={loading}>جدید</button>
        </div>
        <select className="input" value={agent} onChange={(e) => setAgent(e.target.value as AgentType)} aria-label="نوع دستیار">
          {AGENTS.map((a) => <option key={a.value} value={a.value}>{a.label}</option>)}
        </select>
        <div className="plain-list">
          {conversations.map((conv) => (
            <button
              key={conv.id}
              className={`conversation-chip${active?.id === conv.id ? " active" : ""}`}
              onClick={() => selectConversation(conv)}
            >
              {conv.title || `دستیار ${titleFor(conv.agent_type)}`}
            </button>
          ))}
        </div>
      </div>

      <div className="assistant-chat card">
        <div className="row-between">
          <strong>{active?.title || `دستیار ${titleFor(agent)}`}</strong>
          {loading && <span className="muted">در حال بارگذاری…</span>}
        </div>
        {error && <div className="card danger">{error}</div>}
        <div className="assistant-body" ref={bodyRef}>
          {messages.length === 0 && !loading && <p className="muted">یک پیام بنویسید تا مکالمه شروع شود.</p>}
          {messages.map((m) => (
            <div key={m.id} className={`bubble ${m.role === "user" ? "user" : "assistant"}`}>{m.content}</div>
          ))}
          {sending && <div className="bubble assistant">در حال پاسخ…</div>}
        </div>
        <div className="assistant-input">
          <input
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && send()}
            placeholder="پیام به دستیار…"
            aria-label="پیام به دستیار"
          />
          <button className="btn" onClick={send} disabled={sending || loading}>ارسال</button>
        </div>
      </div>
    </section>
  );
}
