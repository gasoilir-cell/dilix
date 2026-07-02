"use client";

import { useState, useRef, useEffect, Suspense } from "react";
import { useParams, useSearchParams, useRouter } from "next/navigation";
import { motion, AnimatePresence } from "framer-motion";
import {
  ArrowRight, Send, Phone, Video,
  Check, CheckCheck, Handshake, MoreVertical,
  Image as ImageIcon, Smile,
} from "lucide-react";

const ROLE_AVATAR: Record<string, string> = {
  driver: "🚛",
  cargo_owner: "📦",
  freight_broker: "🤝",
  insurance_agent: "🛡️",
  creator: "📢",
  admin: "⚙️",
  user: "👤",
};

const ROLE_COLOR: Record<string, string> = {
  driver: "#f59e0b",
  cargo_owner: "#06b6d4",
  freight_broker: "#8b5cf6",
  insurance_agent: "#10b981",
  creator: "#f43f5e",
  admin: "#ec4899",
  user: "#6366f1",
};

const ROLE_LABEL: Record<string, string> = {
  driver: "راننده",
  cargo_owner: "صاحب بار",
  freight_broker: "کارگزار حمل",
  insurance_agent: "نماینده بیمه",
  creator: "بازاریاب / سازنده",
  admin: "مدیر",
  user: "کاربر",
};

// جدول mock کاربران — در پروداکشن از API می‌آد
const MOCK_USERS: Record<string, { name: string; role: string; avatar_url?: string; online: boolean }> = {
  "DLX-DEMO001": { name: "احمد رضایی",       role: "driver",          online: true  },
  "DLX-DEMO002": { name: "شرکت فراز لجستیک", role: "cargo_owner",     online: false },
  "DLX-DEMO003": { name: "محمد علوی",         role: "user",            online: false },
  "DLX-DEMO004": { name: "سارا کریمی",        role: "driver",          online: true  },
  "DLX-DEMO005": { name: "نیلوفر صادقی",      role: "creator",         online: false },
  "DLX-DEMO006": { name: "حسین محمدی",        role: "insurance_agent", online: true  },
  "DLX-DEMO007": { name: "زهرا موسوی",        role: "user",            online: false },
  "DLX-DEMO008": { name: "مهدی تهرانی",       role: "freight_broker",  online: true  },
  "DLX-DEMO010": { name: "Ali Hassan",         role: "driver",          online: true  },
  "DLX-DEMO011": { name: "Mehmet Yilmaz",      role: "cargo_owner",     online: false },
  "DLX-DEMO012": { name: "Sarah Klein",        role: "creator",         online: true  },
  "DLX-DEMO013": { name: "James Wilson",       role: "user",            online: false },
  "DLX-DEMO014": { name: "Kenji Tanaka",       role: "freight_broker",  online: true  },
  "DLX-DEMO015": { name: "Raj Patel",          role: "user",            online: false },
  "DLX-DEMO016": { name: "Carlos Mendez",      role: "driver",          online: false },
  "DLX-DEMO017": { name: "Chen Wei",           role: "cargo_owner",     online: true  },
  "DLX-DEMO018": { name: "Sofia Petrov",       role: "creator",         online: false },
  "DLX-DEMO019": { name: "Nour Al-Rashid",     role: "insurance_agent", online: false },
  "DLX-DEMO020": { name: "Amir Sultanov",      role: "driver",          online: false },
  "DLX-DEMO021": { name: "Emma Johansson",     role: "user",            online: true  },
  "DLX-DEMO022": { name: "Lucas Dupont",       role: "freight_broker",  online: false },
  "DLX-DEMO023": { name: "Amira Mansour",      role: "creator",         online: false },
  "DLX-DEMO024": { name: "Park Jiwoo",         role: "user",            online: true  },
  "DLX-DEMO025": { name: "Elena Kovacs",       role: "insurance_agent", online: false },
  "DLX-SYS00001":{ name: "سیستم دیلیکس",     role: "admin",           online: true  },
};

type Message = {
  id: string;
  text: string;
  mine: boolean;
  time: string;
  read: boolean;
  isSystem?: boolean;
};

function now() {
  return new Date().toLocaleTimeString("fa-IR", { hour: "2-digit", minute: "2-digit" });
}

function ChatContent() {
  const params = useParams();
  const searchParams = useSearchParams();
  const router = useRouter();

  const earthId = params.id as string;
  const isCollaboration = searchParams.get("type") === "collaboration";

  const person = MOCK_USERS[earthId] ?? { name: earthId, role: "user", online: false };
  const color = ROLE_COLOR[person.role] ?? "#6366f1";

  const [messages, setMessages] = useState<Message[]>([]);
  const [text, setText] = useState("");
  const [sending, setSending] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  // پیام خوش‌آمد بر اساس نوع (همکاری / گفتگو)
  useEffect(() => {
    const welcome: Message = {
      id: "sys-welcome",
      text: isCollaboration
        ? `درخواست همکاری برای ${person.name} ارسال شد.\nمنتظر پاسخ بمان 🤝`
        : `شروع مکالمه با ${person.name}`,
      mine: false,
      time: now(),
      read: true,
      isSystem: true,
    };
    setMessages([welcome]);
    if (isCollaboration) {
      setText("سلام، می‌خوام در مورد یه همکاری باهاتون صحبت کنم 🤝");
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const sendMessage = () => {
    if (!text.trim() || sending) return;
    const trimmed = text.trim();
    setText("");
    setSending(true);

    const newMsg: Message = {
      id: Date.now().toString(),
      text: trimmed,
      mine: true,
      time: now(),
      read: false,
    };
    setMessages(prev => [...prev, newMsg]);

    // شبیه‌سازی تیک خوانده‌شدن بعد از ۱.۵ ثانیه
    setTimeout(() => {
      setMessages(prev =>
        prev.map(m => m.id === newMsg.id ? { ...m, read: true } : m)
      );
      setSending(false);
    }, 1500);

    // شبیه‌سازی پاسخ طرف مقابل
    const replies = [
      "ممنون از پیامت، بررسی می‌کنم",
      "باشه، قبوله 👍",
      "چشم، به‌زودی خبر می‌دم",
      "اطلاعات بیشتری بده تا بتونم کمک کنم",
      "در دسترسم، بفرما",
    ];
    setTimeout(() => {
      setMessages(prev => [...prev, {
        id: (Date.now() + 1).toString(),
        text: replies[Math.floor(Math.random() * replies.length)],
        mine: false,
        time: now(),
        read: true,
      }]);
    }, 2500 + Math.random() * 1500);
  };

  const handleKey = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  };

  return (
    <div className="flex flex-col h-dvh bg-surface-950">
      {/* ─── Header ─── */}
      <div className="flex items-center gap-3 px-4 py-3 border-b border-surface-800 bg-surface-950/95 backdrop-blur-md sticky top-0 z-10">
        <button
          onClick={() => router.back()}
          className="p-2 rounded-xl hover:bg-surface-800 text-surface-400 transition-colors flex-shrink-0"
        >
          <ArrowRight size={20} />
        </button>

        <button
          onClick={() => {/* پروفایل کاربر */}}
          className="relative flex-shrink-0"
        >
          <div
            className="w-10 h-10 rounded-full flex items-center justify-center text-xl border-2"
            style={{ borderColor: `${color}60`, background: `${color}15` }}
          >
            {person.avatar_url
              ? <img src={person.avatar_url} className="w-full h-full rounded-full object-cover" alt={person.name} />
              : (ROLE_AVATAR[person.role] ?? "👤")}
          </div>
          {person.online && (
            <span className="absolute bottom-0 right-0 w-2.5 h-2.5 bg-emerald-500 rounded-full border-2 border-surface-950" />
          )}
        </button>

        <div className="flex-1 min-w-0">
          <p className="text-sm font-bold text-white truncate">{person.name}</p>
          <p className="text-[11px] text-surface-500 font-mono">{earthId}</p>
        </div>

        <div className="flex items-center gap-1 flex-shrink-0">
          <button className="p-2 rounded-xl hover:bg-surface-800 text-surface-400 transition-colors">
            <Phone size={18} />
          </button>
          <button className="p-2 rounded-xl hover:bg-surface-800 text-surface-400 transition-colors">
            <Video size={18} />
          </button>
          <button className="p-2 rounded-xl hover:bg-surface-800 text-surface-400 transition-colors">
            <MoreVertical size={18} />
          </button>
        </div>
      </div>

      {/* همکاری badge */}
      {isCollaboration && (
        <div
          className="mx-4 mt-3 flex items-center gap-2 rounded-xl px-3 py-2.5 text-sm font-semibold"
          style={{ background: `${color}18`, color }}
        >
          <Handshake size={16} />
          <span>درخواست همکاری — {ROLE_LABEL[person.role] ?? "کاربر"}</span>
        </div>
      )}

      {/* ─── Messages ─── */}
      <div className="flex-1 overflow-y-auto px-4 py-4 space-y-2">
        {messages.length === 1 && messages[0].isSystem && (
          <div className="flex flex-col items-center justify-center pt-16 pb-8 text-center">
            <div
              className="w-20 h-20 rounded-full flex items-center justify-center text-4xl mb-4 border-2"
              style={{ borderColor: `${color}50`, background: `${color}15` }}
            >
              {person.avatar_url
                ? <img src={person.avatar_url} className="w-full h-full rounded-full object-cover" alt={person.name} />
                : (ROLE_AVATAR[person.role] ?? "👤")}
            </div>
            <p className="text-white font-bold text-lg">{person.name}</p>
            <p className="text-surface-500 text-sm mt-1">{earthId}</p>
            <span
              className="inline-block mt-2 text-xs font-medium px-3 py-1 rounded-full"
              style={{ background: `${color}20`, color }}
            >
              {ROLE_LABEL[person.role] ?? "کاربر"}
            </span>
            {person.online ? (
              <p className="text-emerald-400 text-xs mt-3 flex items-center gap-1">
                <span className="w-1.5 h-1.5 bg-emerald-400 rounded-full inline-block" />
                آنلاین
              </p>
            ) : (
              <p className="text-surface-600 text-xs mt-3">آفلاین</p>
            )}
          </div>
        )}

        <AnimatePresence initial={false}>
          {messages.map((msg) => {
            if (msg.isSystem) return (
              <motion.div
                key={msg.id}
                initial={{ opacity: 0, scale: 0.95 }}
                animate={{ opacity: 1, scale: 1 }}
                className="flex justify-center"
              >
                <div className="bg-surface-800/60 rounded-2xl px-4 py-2 text-center max-w-[85%]">
                  <p className="text-surface-400 text-xs leading-relaxed whitespace-pre-line">{msg.text}</p>
                </div>
              </motion.div>
            );

            return (
              <motion.div
                key={msg.id}
                initial={{ opacity: 0, y: 8, scale: 0.97 }}
                animate={{ opacity: 1, y: 0, scale: 1 }}
                className={`flex ${msg.mine ? "justify-start" : "justify-end"}`}
              >
                <div
                  className={`max-w-[78%] rounded-2xl px-4 py-2.5 ${
                    msg.mine
                      ? "text-white rounded-br-sm"
                      : "bg-surface-800 text-surface-100 rounded-bl-sm"
                  }`}
                  style={msg.mine ? { background: color } : {}}
                >
                  <p className="text-sm leading-relaxed">{msg.text}</p>
                  <div className={`flex items-center gap-1 mt-1 ${msg.mine ? "justify-start" : "justify-end"}`}>
                    <span className="text-[10px] opacity-60">{msg.time}</span>
                    {msg.mine && (
                      msg.read
                        ? <CheckCheck size={11} className="opacity-60" />
                        : <Check size={11} className="opacity-60" />
                    )}
                  </div>
                </div>
              </motion.div>
            );
          })}
        </AnimatePresence>
        <div ref={bottomRef} />
      </div>

      {/* ─── Input ─── */}
      <div className="px-4 pb-6 pt-3 border-t border-surface-800 bg-surface-950 safe-bottom">
        <div className="flex items-end gap-2">
          <button className="p-2.5 rounded-xl text-surface-500 hover:text-surface-300 hover:bg-surface-800 transition-colors flex-shrink-0">
            <ImageIcon size={20} />
          </button>
          <button className="p-2.5 rounded-xl text-surface-500 hover:text-surface-300 hover:bg-surface-800 transition-colors flex-shrink-0">
            <Smile size={20} />
          </button>

          <div className="flex-1">
            <textarea
              ref={inputRef}
              value={text}
              onChange={(e) => setText(e.target.value)}
              onKeyDown={handleKey}
              placeholder="پیام بنویس..."
              rows={1}
              className="w-full bg-surface-800 border border-surface-700 rounded-2xl px-4 py-3 text-sm text-surface-100 placeholder-surface-500 focus:outline-none focus:border-primary-500 resize-none"
              style={{ direction: "rtl", maxHeight: "120px", overflowY: "auto" }}
            />
          </div>

          <motion.button
            whileTap={{ scale: 0.92 }}
            onClick={sendMessage}
            disabled={!text.trim()}
            className="w-11 h-11 rounded-2xl text-white flex items-center justify-center transition-all flex-shrink-0 disabled:opacity-40 disabled:cursor-not-allowed"
            style={{ background: text.trim() ? color : "#334155" }}
          >
            <Send size={18} />
          </motion.button>
        </div>
      </div>
    </div>
  );
}

export default function ChatPage() {
  return (
    <Suspense fallback={
      <div className="flex items-center justify-center h-dvh bg-surface-950 text-surface-400 text-sm">
        در حال بارگذاری...
      </div>
    }>
      <ChatContent />
    </Suspense>
  );
}
