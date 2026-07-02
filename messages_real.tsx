"use client";

import { useState, useEffect, useRef, useCallback, Suspense } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Search, MessageCircle, Send, ArrowRight, Loader2, Users } from "lucide-react";
import AppShell from "@/components/layout/AppShell";
import { messagesApi } from "@/lib/api";
import { useAuthStore } from "@/store/auth";
import { toPersianNum } from "@/lib/utils";
import toast from "react-hot-toast";

const ROLE_EMOJI: Record<string, string> = {
  driver: "🚛", cargo_owner: "📦", freight_broker: "🤝",
  insurance_agent: "🛡️", creator: "📢", admin: "⚙️", user: "👤",
};
const ROLE_LABEL: Record<string, string> = {
  driver: "راننده", cargo_owner: "صاحب بار", freight_broker: "کارگزار",
  insurance_agent: "نماینده بیمه", creator: "بازاریاب", admin: "سیستم", user: "کاربر",
};

interface Room {
  id: string; type: string; name: string | null;
  partner_name: string | null; partner_earth_id: string | null;
  partner_role: string | null; partner_avatar: string | null;
  last_message: string | null; last_message_at: string | null;
  unread_count: number; created_at: string;
}

interface Message {
  id: string; sender_id: string; sender_name: string | null;
  sender_earth_id: string | null; content: string;
  is_mine: boolean; created_at: string;
}

function formatTime(iso: string | null): string {
  if (!iso) return "";
  try {
    const d = new Date(iso);
    const now = new Date();
    const diff = now.getTime() - d.getTime();
    if (diff < 86400000) return d.toLocaleTimeString("fa-IR", { hour: "2-digit", minute: "2-digit" });
    if (diff < 604800000) {
      const days = ["یکشنبه","دوشنبه","سه‌شنبه","چهارشنبه","پنجشنبه","جمعه","شنبه"];
      return days[d.getDay()];
    }
    return d.toLocaleDateString("fa-IR", { month: "short", day: "numeric" });
  } catch { return ""; }
}

// ── Chat View ─────────────────────────────────────────────────
function ChatView({ room, onBack }: { room: Room; onBack: () => void }) {
  const [messages, setMessages] = useState<Message[]>([]);
  const [loading,  setLoading]  = useState(true);
  const [text,     setText]     = useState("");
  const [sending,  setSending]  = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);
  const me = useAuthStore((s) => s.user);

  const load = useCallback(async () => {
    try {
      const res = await messagesApi.getMessages(room.id, 50);
      setMessages(res.data);
    } catch {
      toast.error("خطا در بارگذاری پیام‌ها");
    } finally {
      setLoading(false);
    }
  }, [room.id]);

  useEffect(() => { load(); }, [load]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  // poll every 5s for new messages
  useEffect(() => {
    const t = setInterval(load, 5000);
    return () => clearInterval(t);
  }, [load]);

  const send = async () => {
    if (!text.trim() || sending) return;
    const content = text.trim();
    setText("");
    setSending(true);

    // optimistic update
    const tmp: Message = {
      id: "tmp-" + Date.now(),
      sender_id: me?.id ?? "",
      sender_name: me?.full_name ?? "",
      sender_earth_id: me?.earth_id ?? "",
      content,
      is_mine: true,
      created_at: new Date().toISOString(),
    };
    setMessages(prev => [...prev, tmp]);

    try {
      const res = await messagesApi.send(room.id, content);
      setMessages(prev => prev.map(m => m.id === tmp.id ? res.data : m));
    } catch {
      setMessages(prev => prev.filter(m => m.id !== tmp.id));
      setText(content);
      toast.error("ارسال پیام ناموفق بود");
    } finally {
      setSending(false);
    }
  };

  const partnerName = room.partner_name ?? room.name ?? "مکالمه";
  const partnerRole = room.partner_role ?? "user";

  return (
    <div className="flex flex-col h-screen bg-[#0A0A0A]">
      {/* Header */}
      <div className="flex items-center gap-3 px-4 py-3 bg-[rgba(10,10,10,0.95)] border-b border-white/8 safe-top">
        <button onClick={onBack} className="p-2 rounded-xl hover:bg-white/5 text-white/70">
          <ArrowRight size={20} />
        </button>
        <div className="w-10 h-10 rounded-full bg-[#2C2C2E] flex items-center justify-center text-lg flex-shrink-0">
          {ROLE_EMOJI[partnerRole] ?? "👤"}
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-white font-semibold truncate">{partnerName}</p>
          <p className="text-white/40 text-xs">{ROLE_LABEL[partnerRole] ?? "کاربر"}</p>
        </div>
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto px-4 py-4 space-y-3">
        {loading ? (
          <div className="flex justify-center pt-10">
            <Loader2 size={28} className="text-indigo-400 animate-spin" />
          </div>
        ) : messages.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-40 gap-2">
            <MessageCircle size={32} className="text-white/20" />
            <p className="text-white/30 text-sm">اولین نفری باش که پیام می‌فرستی</p>
          </div>
        ) : (
          messages.map((msg) => (
            <div key={msg.id} className={`flex ${msg.is_mine ? "justify-end" : "justify-start"}`}>
              <div className={`max-w-[78%] px-4 py-2.5 rounded-2xl text-sm leading-relaxed ${
                msg.is_mine
                  ? "bg-indigo-600 text-white rounded-br-sm"
                  : "bg-[#2C2C2E] text-white/90 rounded-bl-sm"
              }`}>
                <p>{msg.content}</p>
                <p className={`text-[10px] mt-1 ${msg.is_mine ? "text-indigo-200/60" : "text-white/30"} text-left`}>
                  {formatTime(msg.created_at)}
                </p>
              </div>
            </div>
          ))
        )}
        <div ref={bottomRef} />
      </div>

      {/* Input */}
      <div className="px-3 py-3 border-t border-white/8 bg-[#0A0A0A] pb-safe">
        <div className="flex items-end gap-2">
          <input
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && !e.shiftKey && (e.preventDefault(), send())}
            placeholder="پیام..."
            className="flex-1 bg-[#1C1C1E] border border-white/8 rounded-2xl px-4 py-3 text-white text-sm placeholder-white/30 focus:outline-none focus:border-indigo-500/50 resize-none"
          />
          <button
            onClick={send}
            disabled={!text.trim() || sending}
            className="w-11 h-11 rounded-2xl bg-indigo-600 flex items-center justify-center disabled:opacity-40 hover:bg-indigo-500 transition-colors flex-shrink-0"
          >
            {sending
              ? <Loader2 size={18} className="text-white animate-spin" />
              : <Send size={18} className="text-white" />
            }
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Rooms List ────────────────────────────────────────────────
function MessagesInner() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [rooms,    setRooms]    = useState<Room[]>([]);
  const [loading,  setLoading]  = useState(true);
  const [search,   setSearch]   = useState("");
  const [activeRoom, setActiveRoom] = useState<Room | null>(null);
  const [starting, setStarting] = useState(false);
  const [newTarget, setNewTarget] = useState("");
  const [showNew,  setShowNew]  = useState(false);

  const loadRooms = useCallback(async () => {
    try {
      const res = await messagesApi.listRooms();
      setRooms(res.data);
    } catch {
      // not authenticated or error — ignore
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { loadRooms(); }, [loadRooms]);

  // URL param: ?to=EARTH_ID → start room directly
  useEffect(() => {
    const to = searchParams.get("to");
    if (to) {
      handleStartRoom(to);
    }
  }, []); // eslint-disable-line

  const handleStartRoom = async (earthId: string) => {
    if (!earthId) return;
    setStarting(true);
    try {
      const res = await messagesApi.startRoom(earthId);
      const room: Room = res.data;
      await loadRooms();
      setActiveRoom(room);
      setShowNew(false);
      setNewTarget("");
    } catch (e: any) {
      toast.error(e?.response?.data?.detail || "کاربر پیدا نشد");
    } finally {
      setStarting(false);
    }
  };

  if (activeRoom) {
    return (
      <ChatView
        room={activeRoom}
        onBack={() => { setActiveRoom(null); loadRooms(); }}
      />
    );
  }

  const filtered = rooms.filter((r) => {
    const q = search.toLowerCase();
    return (
      (r.partner_name ?? "").toLowerCase().includes(q) ||
      (r.partner_earth_id ?? "").toLowerCase().includes(q) ||
      (r.last_message ?? "").toLowerCase().includes(q)
    );
  });

  const totalUnread = rooms.reduce((s, r) => s + r.unread_count, 0);

  return (
    <AppShell title={totalUnread > 0 ? `پیام‌ها (${toPersianNum(totalUnread)})` : "پیام‌ها"}>
      <div className="page-inner">
        {/* Search + New */}
        <div className="flex gap-2 mb-4">
          <div className="relative flex-1">
            <Search size={16} className="absolute right-3 top-1/2 -translate-y-1/2 text-white/30" />
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="جستجو..."
              className="w-full bg-[#1C1C1E] border border-white/8 rounded-xl py-2.5 pr-9 pl-3 text-sm text-white placeholder-white/30 focus:outline-none focus:border-indigo-500/50"
            />
          </div>
          <button
            onClick={() => setShowNew(!showNew)}
            className="w-10 h-10 rounded-xl bg-indigo-600 flex items-center justify-center hover:bg-indigo-500 transition-colors flex-shrink-0"
          >
            <Users size={18} className="text-white" />
          </button>
        </div>

        {/* New conversation input */}
        {showNew && (
          <div className="mb-4 bg-[#1C1C1E] border border-white/8 rounded-xl p-4">
            <p className="text-white/60 text-xs mb-2">شروع مکالمه با Earth ID</p>
            <div className="flex gap-2">
              <input
                value={newTarget}
                onChange={(e) => setNewTarget(e.target.value.toUpperCase())}
                placeholder="DLX-XXXXXXXX"
                className="flex-1 bg-[#262626] border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white placeholder-white/30 focus:outline-none focus:border-indigo-500 font-mono"
                dir="ltr"
              />
              <button
                onClick={() => handleStartRoom(newTarget)}
                disabled={!newTarget.startsWith("DLX-") || starting}
                className="px-4 rounded-xl bg-indigo-600 text-white text-sm font-medium disabled:opacity-40 hover:bg-indigo-500 transition-colors"
              >
                {starting ? <Loader2 size={16} className="animate-spin" /> : "شروع"}
              </button>
            </div>
          </div>
        )}

        {loading ? (
          <div className="flex justify-center pt-12">
            <Loader2 size={28} className="text-indigo-400 animate-spin" />
          </div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 gap-3">
            <MessageCircle size={48} className="text-white/15" />
            <p className="text-white/30 text-sm">
              {search ? "نتیجه‌ای پیدا نشد" : "هنوز مکالمه‌ای نداری"}
            </p>
            {!search && (
              <p className="text-white/20 text-xs">روی 🌍 کره زمین کاربری را پیدا کن و پیام بده</p>
            )}
          </div>
        ) : (
          <div className="space-y-1">
            {filtered.map((room) => {
              const name = room.partner_name ?? room.name ?? "مکالمه";
              const role = room.partner_role ?? "user";
              return (
                <button
                  key={room.id}
                  onClick={() => setActiveRoom(room)}
                  className="w-full flex items-center gap-3 p-3.5 rounded-xl hover:bg-[#1C1C1E] transition-colors text-right"
                >
                  <div className="w-12 h-12 rounded-full bg-[#2C2C2E] flex items-center justify-center text-xl flex-shrink-0 relative">
                    {room.partner_avatar
                      ? <img src={room.partner_avatar} className="w-full h-full object-cover rounded-full" alt="" />
                      : ROLE_EMOJI[role] ?? "👤"
                    }
                    {room.unread_count > 0 && (
                      <span className="absolute -top-1 -left-1 w-5 h-5 bg-indigo-500 text-white text-[10px] font-bold rounded-full flex items-center justify-center">
                        {toPersianNum(room.unread_count)}
                      </span>
                    )}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between mb-0.5">
                      <p className="text-sm font-semibold text-white truncate">{name}</p>
                      <p className="text-xs text-white/30 flex-shrink-0 mr-2">{formatTime(room.last_message_at)}</p>
                    </div>
                    <p className="text-xs text-white/40 truncate">
                      {room.last_message || "مکالمه را شروع کن"}
                    </p>
                  </div>
                </button>
              );
            })}
          </div>
        )}
      </div>
    </AppShell>
  );
}
export default function MessagesPage() {
  return (
    <Suspense fallback={
      <div className="flex items-center justify-center h-screen bg-[#0A0A0A]">
        <Loader2 size={28} className="text-indigo-400 animate-spin" />
      </div>
    }>
      <MessagesInner />
    </Suspense>
  );
}
