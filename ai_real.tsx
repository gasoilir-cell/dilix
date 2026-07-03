"use client";

import { useState, useRef, useEffect, useCallback } from "react";
import { Send, Bot, Loader2, RefreshCw } from "lucide-react";
import BottomNav from "@/components/layout/BottomNav";
import api from "@/lib/api";
import { useAuthStore } from "@/store/auth";
import toast from "react-hot-toast";

interface Message {
  id: string;
  role: "user" | "assistant";
  content: string;
  created_at: string;
  pending?: boolean;
}

const SUGGESTIONS = [
  "قیمت باربری تهران به مشهد؟",
  "نرخ بیمه بار الکترونیک",
  "چطور بار ثبت کنم؟",
  "دیلیکس چیه؟",
];

function formatTime(iso: string): string {
  try {
    return new Date(iso).toLocaleTimeString("fa-IR", { hour: "2-digit", minute: "2-digit" });
  } catch { return ""; }
}

// Minimal markdown renderer for bold + lists
function renderMarkdown(text: string): React.ReactNode[] {
  const lines = text.split("\n");
  return lines.map((line, i) => {
    // bold **text**
    const parts = line.split(/\*\*(.*?)\*\*/g);
    const rendered = parts.map((p, j) =>
      j % 2 === 1 ? <strong key={j} className="text-white font-semibold">{p}</strong> : p
    );
    return (
      <span key={i}>
        {rendered}
        {i < lines.length - 1 && <br />}
      </span>
    );
  });
}

export default function AIPage() {
  const [messages,  setMessages]  = useState<Message[]>([]);
  const [input,     setInput]     = useState("");
  const [sending,   setSending]   = useState(false);
  const [loading,   setLoading]   = useState(true);
  const bottomRef   = useRef<HTMLDivElement>(null);
  const inputRef    = useRef<HTMLInputElement>(null);
  const user        = useAuthStore((s) => s.user);

  const scrollBottom = () =>
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });

  // Load history
  const loadHistory = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.get("/ai/history?limit=50");
      setMessages(res.data);
    } catch {
      // new chat
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { loadHistory(); }, [loadHistory]);
  useEffect(() => { scrollBottom(); }, [messages]);

  const send = async (text: string) => {
    const content = text.trim();
    if (!content || sending) return;
    setInput("");
    setSending(true);

    // optimistic user message
    const tmpId = "tmp-" + Date.now();
    const userMsg: Message = {
      id: tmpId,
      role: "user",
      content,
      created_at: new Date().toISOString(),
    };
    setMessages(prev => [...prev, userMsg]);

    // typing indicator
    const typingId = "typing-" + Date.now();
    setMessages(prev => [...prev, {
      id: typingId, role: "assistant",
      content: "...", created_at: new Date().toISOString(), pending: true,
    }]);

    try {
      const res = await api.post("/ai/chat", { message: content });
      const aiMsg: Message = res.data;
      setMessages(prev => prev.filter(m => m.id !== typingId).concat(aiMsg));
    } catch {
      setMessages(prev => prev.filter(m => m.id !== typingId));
      toast.error("خطا در ارسال پیام");
      setInput(content);
    } finally {
      setSending(false);
      setTimeout(scrollBottom, 100);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      send(input);
    }
  };

  const hasMessages = messages.length > 0;

  return (
    <div className="flex flex-col h-screen bg-[#0A0A0A]">
      {/* Header */}
      <div className="flex items-center gap-3 px-4 py-3 border-b border-white/8"
           style={{ background: "rgba(10,10,10,0.95)", backdropFilter: "blur(20px)" }}>
        <div className="w-9 h-9 rounded-xl bg-purple-600/20 flex items-center justify-center">
          <Bot size={20} className="text-purple-400" />
        </div>
        <div>
          <p className="text-white font-semibold text-sm">دستیار دیلیکس</p>
          <p className="text-white/40 text-xs">هوشمند · لجستیک · باربری</p>
        </div>
        <button onClick={loadHistory}
          className="mr-auto p-2 rounded-xl hover:bg-white/5 text-white/30 hover:text-white/60 transition-colors">
          <RefreshCw size={16} />
        </button>
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto px-4 py-4 space-y-4">
        {loading ? (
          <div className="flex justify-center pt-12">
            <Loader2 size={28} className="text-purple-400 animate-spin" />
          </div>
        ) : !hasMessages ? (
          /* Welcome screen */
          <div className="flex flex-col items-center justify-center h-full min-h-[50vh] gap-6 text-center">
            <div className="w-20 h-20 rounded-2xl bg-purple-600/15 border border-purple-500/20 flex items-center justify-center">
              <Bot size={40} className="text-purple-400" />
            </div>
            <div>
              <p className="text-white font-bold text-lg mb-1">دستیار هوشمند دیلیکس</p>
              <p className="text-white/40 text-sm">
                {user?.full_name ? `سلام ${user.full_name.split(" ")[0]}،` : "سلام،"} چطور کمکت کنم؟
              </p>
            </div>
            <div className="grid grid-cols-2 gap-2 w-full max-w-xs">
              {SUGGESTIONS.map((s) => (
                <button
                  key={s}
                  onClick={() => send(s)}
                  className="px-3 py-2.5 rounded-xl bg-[#1C1C1E] border border-white/8 text-xs text-white/70 hover:text-white hover:border-purple-500/40 transition-all text-right leading-relaxed"
                >
                  {s}
                </button>
              ))}
            </div>
          </div>
        ) : (
          messages.map((msg) => (
            <div key={msg.id} className={`flex gap-2.5 ${msg.role === "user" ? "justify-end" : "justify-start"}`}>
              {msg.role === "assistant" && (
                <div className="w-8 h-8 rounded-full bg-purple-600/20 flex items-center justify-center flex-shrink-0 mt-1">
                  <Bot size={15} className="text-purple-400" />
                </div>
              )}
              <div className={`max-w-[82%] ${msg.role === "user" ? "order-first" : ""}`}>
                <div className={`px-4 py-3 rounded-2xl text-sm leading-relaxed ${
                  msg.role === "user"
                    ? "bg-indigo-600 text-white rounded-br-sm"
                    : "bg-[#1C1C1E] text-white/85 rounded-bl-sm border border-white/8"
                }`}>
                  {msg.pending ? (
                    <div className="flex gap-1.5 items-center py-1">
                      {[0,1,2].map(i => (
                        <div key={i} className="w-1.5 h-1.5 rounded-full bg-white/40"
                          style={{ animation: `pulse 1.4s ease-in-out ${i*0.2}s infinite` }} />
                      ))}
                    </div>
                  ) : (
                    <div>{renderMarkdown(msg.content)}</div>
                  )}
                </div>
                {!msg.pending && (
                  <p className={`text-[10px] text-white/20 mt-1 ${msg.role === "user" ? "text-right" : "text-left"}`}>
                    {formatTime(msg.created_at)}
                  </p>
                )}
              </div>
            </div>
          ))
        )}
        <div ref={bottomRef} />
      </div>

      {/* Suggestions (only when has messages) */}
      {hasMessages && !loading && (
        <div className="px-3 pb-2 flex gap-2 overflow-x-auto no-scrollbar">
          {SUGGESTIONS.map((s) => (
            <button
              key={s}
              onClick={() => send(s)}
              className="flex-shrink-0 px-3 py-1.5 rounded-full bg-[#1C1C1E] border border-white/8 text-xs text-white/50 hover:text-white/80 hover:border-purple-500/30 transition-all"
            >
              {s}
            </button>
          ))}
        </div>
      )}

      {/* Input */}
      <div className="px-3 py-3 border-t border-white/8 bg-[#0A0A0A] pb-safe">
        <div className="flex items-center gap-2">
          <input
            ref={inputRef}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="سوالت را بپرس..."
            className="flex-1 bg-[#1C1C1E] border border-white/8 rounded-2xl px-4 py-3 text-white text-sm placeholder-white/25 focus:outline-none focus:border-purple-500/40 transition-colors"
            dir="rtl"
          />
          <button
            onClick={() => send(input)}
            disabled={!input.trim() || sending}
            className="w-11 h-11 rounded-2xl bg-purple-600 flex items-center justify-center disabled:opacity-40 hover:bg-purple-500 transition-colors flex-shrink-0"
          >
            {sending
              ? <Loader2 size={18} className="text-white animate-spin" />
              : <Send   size={18} className="text-white" />
            }
          </button>
        </div>
      </div>

      <BottomNav />

      <style jsx global>{`
        @keyframes pulse {
          0%, 60%, 100% { opacity: 0.3; transform: scale(0.8); }
          30% { opacity: 1; transform: scale(1); }
        }
      `}</style>
    </div>
  );
}
