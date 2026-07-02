"use client";

import { useState, useRef, useEffect, Suspense } from "react";
import { useParams, useSearchParams, useRouter } from "next/navigation";
import { motion, AnimatePresence } from "framer-motion";
import {
  ArrowRight, Send, Phone, Video,
  Check, CheckCheck, Handshake, MoreVertical,
  Image as ImageIcon, Smile, X, UserCircle2, Info,
  PhoneOff, VideoOff, Mic, MicOff, Volume2,
} from "lucide-react";
import BottomNav from "@/components/layout/BottomNav";

// ─── Data ────────────────────────────────────────────────────
const ROLE_AVATAR: Record<string, string> = {
  driver: "🚛", cargo_owner: "📦", freight_broker: "🤝",
  insurance_agent: "🛡️", creator: "📢", admin: "⚙️", user: "👤",
};
const ROLE_COLOR: Record<string, string> = {
  driver: "#f59e0b", cargo_owner: "#06b6d4", freight_broker: "#8b5cf6",
  insurance_agent: "#10b981", creator: "#f43f5e", admin: "#ec4899", user: "#6366f1",
};
const ROLE_LABEL: Record<string, string> = {
  driver: "راننده", cargo_owner: "صاحب بار", freight_broker: "کارگزار حمل",
  insurance_agent: "نماینده بیمه", creator: "بازاریاب / سازنده", admin: "مدیر", user: "کاربر",
};

const MOCK_USERS: Record<string, { name: string; role: string; avatar_url?: string; online: boolean; bio?: string; country?: string }> = {
  "DLX-DEMO001": { name:"احمد رضایی",          role:"driver",          online:true,  bio:"راننده حرفه‌ای با ۸ سال تجربه", country:"🇮🇷 ایران" },
  "DLX-DEMO002": { name:"شرکت فراز لجستیک",    role:"cargo_owner",     online:false, bio:"ارائه خدمات حمل‌ونقل کالا", country:"🇮🇷 ایران" },
  "DLX-DEMO003": { name:"محمد علوی",            role:"user",            online:false, country:"🇮🇷 ایران" },
  "DLX-DEMO004": { name:"سارا کریمی",           role:"driver",          online:true,  country:"🇮🇷 ایران" },
  "DLX-DEMO005": { name:"نیلوفر صادقی",         role:"creator",         online:false, country:"🇮🇷 ایران" },
  "DLX-DEMO006": { name:"حسین محمدی",           role:"insurance_agent", online:true,  country:"🇮🇷 ایران" },
  "DLX-DEMO010": { name:"Ali Hassan",            role:"driver",          online:true,  bio:"Professional driver, Dubai–Tehran route", country:"🇦🇪 UAE" },
  "DLX-DEMO012": { name:"Sarah Klein",           role:"creator",         online:true,  bio:"Marketing consultant & content creator", country:"🇩🇪 Germany" },
  "DLX-DEMO014": { name:"Kenji Tanaka",          role:"freight_broker",  online:true,  country:"🇯🇵 Japan" },
  "DLX-DEMO017": { name:"Chen Wei",              role:"cargo_owner",     online:true,  country:"🇨🇳 China" },
  "DLX-DEMO024": { name:"Park Jiwoo",            role:"user",            online:true,  country:"🇰🇷 Korea" },
  "DLX-SYS00001":{ name:"سیستم دیلیکس",        role:"admin",           online:true,  bio:"پشتیبانی رسمی دیلیکس" },
};

type Message = { id: string; text: string; mine: boolean; time: string; read: boolean; isSystem?: boolean };

function nowTime() {
  return new Date().toLocaleTimeString("fa-IR", { hour: "2-digit", minute: "2-digit" });
}

// ─── Modal‌های آیکن‌ها ────────────────────────────────────────
type ModalType = null | "call" | "video" | "profile" | "menu";

function CallModal({ person, color, onEnd }: { person: typeof MOCK_USERS[string]; color: string; onEnd: () => void }) {
  const [muted, setMuted] = useState(false);
  const [speaker, setSpeaker] = useState(true);
  const [sec, setSec] = useState(0);

  useEffect(() => {
    const t = setInterval(() => setSec(s => s + 1), 1000);
    return () => clearInterval(t);
  }, []);

  const fmt = (s: number) => `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;

  return (
    <motion.div
      initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
      className="fixed inset-0 z-[100] flex flex-col items-center justify-between py-16 px-8"
      style={{ background: `linear-gradient(135deg, ${color}33 0%, #080f1e 60%)` }}
    >
      <div className="flex flex-col items-center gap-4">
        <div className="w-24 h-24 rounded-full border-4 flex items-center justify-center text-5xl"
          style={{ borderColor: color, background: `${color}20` }}>
          {person.avatar_url
            ? <img src={person.avatar_url} className="w-full h-full rounded-full object-cover" alt="" />
            : ROLE_AVATAR[person.role]}
        </div>
        <p className="text-white text-2xl font-bold">{person.name}</p>
        <p className="text-surface-400 text-sm font-mono">{fmt(sec)}</p>
        <p className="text-surface-500 text-xs">تماس صوتی در حال اجرا...</p>
      </div>

      <div className="flex items-center gap-6">
        <button onClick={() => setMuted(m => !m)}
          className={`w-14 h-14 rounded-full flex items-center justify-center transition-colors ${muted ? "bg-surface-700" : "bg-surface-800"}`}>
          {muted ? <MicOff size={22} className="text-white" /> : <Mic size={22} className="text-white" />}
        </button>
        <button onClick={onEnd}
          className="w-16 h-16 rounded-full bg-red-600 hover:bg-red-500 flex items-center justify-center transition-colors">
          <PhoneOff size={26} className="text-white" />
        </button>
        <button onClick={() => setSpeaker(s => !s)}
          className={`w-14 h-14 rounded-full flex items-center justify-center transition-colors ${speaker ? "bg-surface-800" : "bg-surface-700"}`}>
          <Volume2 size={22} className={speaker ? "text-white" : "text-surface-500"} />
        </button>
      </div>
    </motion.div>
  );
}

function VideoModal({ person, color, onEnd }: { person: typeof MOCK_USERS[string]; color: string; onEnd: () => void }) {
  const [muted, setMuted] = useState(false);
  const [camOff, setCamOff] = useState(false);

  return (
    <motion.div
      initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
      className="fixed inset-0 z-[100] bg-black flex flex-col"
    >
      {/* ویدیو شبیه‌سازی‌شده */}
      <div className="flex-1 relative flex items-center justify-center"
        style={{ background: `linear-gradient(135deg, ${color}22, #000)` }}>
        <div className="text-center">
          <div className="w-32 h-32 rounded-full border-4 flex items-center justify-center text-6xl mx-auto mb-4"
            style={{ borderColor: color, background: `${color}20` }}>
            {person.avatar_url
              ? <img src={person.avatar_url} className="w-full h-full rounded-full object-cover" alt="" />
              : ROLE_AVATAR[person.role]}
          </div>
          <p className="text-white text-xl font-bold">{person.name}</p>
          <p className="text-surface-400 text-sm mt-1">در حال اتصال تصویری...</p>
        </div>

        {/* پیش‌نمایش خودم */}
        <div className="absolute bottom-4 right-4 w-20 h-28 rounded-xl bg-surface-800 border-2 border-surface-700 flex items-center justify-center">
          {camOff ? <VideoOff size={20} className="text-surface-500" /> : <span className="text-2xl">🤳</span>}
        </div>
      </div>

      <div className="flex items-center justify-center gap-5 py-6 bg-surface-950">
        <button onClick={() => setMuted(m => !m)}
          className={`w-12 h-12 rounded-full flex items-center justify-center ${muted ? "bg-surface-700" : "bg-surface-800"}`}>
          {muted ? <MicOff size={20} className="text-white" /> : <Mic size={20} className="text-white" />}
        </button>
        <button onClick={onEnd}
          className="w-14 h-14 rounded-full bg-red-600 hover:bg-red-500 flex items-center justify-center">
          <PhoneOff size={24} className="text-white" />
        </button>
        <button onClick={() => setCamOff(c => !c)}
          className={`w-12 h-12 rounded-full flex items-center justify-center ${camOff ? "bg-surface-700" : "bg-surface-800"}`}>
          {camOff ? <VideoOff size={20} className="text-surface-500" /> : <Video size={20} className="text-white" />}
        </button>
      </div>
    </motion.div>
  );
}

function ProfileModal({ person, earthId, color, onClose }: {
  person: typeof MOCK_USERS[string]; earthId: string; color: string; onClose: () => void;
}) {
  return (
    <motion.div
      initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
      className="fixed inset-0 z-[100] bg-black/70 backdrop-blur-sm flex items-end"
      onClick={onClose}
    >
      <motion.div
        initial={{ y: 80 }} animate={{ y: 0 }} exit={{ y: 80 }}
        onClick={e => e.stopPropagation()}
        className="w-full bg-surface-900 rounded-t-3xl p-6"
      >
        <div className="flex items-center gap-4 mb-5">
          <div className="w-16 h-16 rounded-full border-2 flex items-center justify-center text-4xl"
            style={{ borderColor: color, background: `${color}18` }}>
            {person.avatar_url
              ? <img src={person.avatar_url} className="w-full h-full rounded-full object-cover" alt="" />
              : ROLE_AVATAR[person.role]}
          </div>
          <div>
            <p className="text-white font-bold text-lg">{person.name}</p>
            <p className="text-surface-500 font-mono text-xs">{earthId}</p>
            {person.country && <p className="text-surface-400 text-sm mt-0.5">{person.country}</p>}
          </div>
        </div>
        {person.bio && (
          <div className="bg-surface-800 rounded-xl p-3 mb-4">
            <p className="text-surface-300 text-sm leading-relaxed">{person.bio}</p>
          </div>
        )}
        <div className="flex items-center gap-2 mb-4">
          <span className="px-3 py-1 rounded-full text-xs font-semibold"
            style={{ background: `${color}20`, color }}>
            {ROLE_LABEL[person.role] ?? "کاربر"}
          </span>
          <span className={`px-3 py-1 rounded-full text-xs font-semibold ${person.online ? "bg-emerald-500/20 text-emerald-400" : "bg-surface-700 text-surface-500"}`}>
            {person.online ? "آنلاین" : "آفلاین"}
          </span>
        </div>
        <button onClick={onClose}
          className="w-full py-3 rounded-xl bg-surface-800 hover:bg-surface-700 text-surface-300 text-sm font-medium transition-colors">
          بستن
        </button>
      </motion.div>
    </motion.div>
  );
}

function MenuModal({ onClose, earthId }: { onClose: () => void; earthId: string }) {
  const items = [
    { label: "بلاک کاربر", danger: true },
    { label: "گزارش محتوا", danger: true },
    { label: "پاک کردن مکالمه", danger: false },
    { label: "بی‌صدا کردن", danger: false },
  ];
  return (
    <motion.div
      initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
      className="fixed inset-0 z-[100] bg-black/60 backdrop-blur-sm flex items-end"
      onClick={onClose}
    >
      <motion.div
        initial={{ y: 60 }} animate={{ y: 0 }} exit={{ y: 60 }}
        onClick={e => e.stopPropagation()}
        className="w-full bg-surface-900 rounded-t-3xl overflow-hidden"
      >
        <div className="p-4 border-b border-surface-800">
          <p className="text-surface-400 text-xs font-mono text-center">{earthId}</p>
        </div>
        {items.map(item => (
          <button key={item.label} onClick={onClose}
            className={`w-full py-4 px-6 text-right text-sm font-medium border-b border-surface-800 last:border-0 hover:bg-surface-800 transition-colors
              ${item.danger ? "text-red-400" : "text-surface-200"}`}>
            {item.label}
          </button>
        ))}
        <button onClick={onClose} className="w-full py-4 text-center text-sm text-surface-500 hover:bg-surface-800 transition-colors">
          انصراف
        </button>
      </motion.div>
    </motion.div>
  );
}

// ─── Chat Content ─────────────────────────────────────────────
function ChatContent() {
  const params       = useParams();
  const searchParams = useSearchParams();
  const router       = useRouter();

  const earthId       = params.id as string;
  const isCollab      = searchParams.get("type") === "collaboration";
  const person        = MOCK_USERS[earthId] ?? { name: earthId, role: "user", online: false };
  const color         = ROLE_COLOR[person.role] ?? "#6366f1";

  const [messages, setMessages]   = useState<Message[]>([]);
  const [text, setText]           = useState("");
  const [activeModal, setModal]   = useState<ModalType>(null);
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const welcome: Message = {
      id: "sys-welcome",
      text: isCollab ? `درخواست همکاری برای ${person.name} ارسال شد 🤝` : `شروع مکالمه با ${person.name}`,
      mine: false, time: nowTime(), read: true, isSystem: true,
    };
    setMessages([welcome]);
    if (isCollab) setText("سلام، می‌خوام در مورد یه همکاری باهاتون صحبت کنم 🤝");
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => { bottomRef.current?.scrollIntoView({ behavior: "smooth" }); }, [messages]);

  const sendMsg = () => {
    if (!text.trim()) return;
    const t = text.trim(); setText("");
    const msg: Message = { id: Date.now().toString(), text: t, mine: true, time: nowTime(), read: false };
    setMessages(p => [...p, msg]);
    setTimeout(() => setMessages(p => p.map(m => m.id === msg.id ? { ...m, read: true } : m)), 1200);
    const replies = ["ممنون از پیامت، بررسی می‌کنم", "باشه، قبوله 👍", "چشم، به‌زودی خبر می‌دم", "در دسترسم، بفرما"];
    setTimeout(() => setMessages(p => [...p, {
      id: (Date.now()+1).toString(), text: replies[Math.floor(Math.random()*replies.length)],
      mine: false, time: nowTime(), read: true,
    }]), 2000 + Math.random()*1500);
  };

  return (
    <div className="flex flex-col h-dvh bg-surface-950">
      {/* ─── Header ─── */}
      <div className="flex items-center gap-3 px-4 py-3 border-b border-surface-800 bg-surface-950/95 backdrop-blur-md sticky top-0 z-10">
        <button onClick={() => router.back()}
          className="p-2 rounded-xl hover:bg-surface-800 text-surface-400 transition-colors flex-shrink-0">
          <ArrowRight size={20} />
        </button>

        <button onClick={() => setModal("profile")} className="relative flex-shrink-0">
          <div className="w-10 h-10 rounded-full flex items-center justify-center text-xl border-2"
            style={{ borderColor: `${color}60`, background: `${color}15` }}>
            {person.avatar_url
              ? <img src={person.avatar_url} className="w-full h-full rounded-full object-cover" alt="" />
              : ROLE_AVATAR[person.role]}
          </div>
          {person.online && <span className="absolute bottom-0 right-0 w-2.5 h-2.5 bg-emerald-500 rounded-full border-2 border-surface-950" />}
        </button>

        <button onClick={() => setModal("profile")} className="flex-1 min-w-0 text-right">
          <p className="text-sm font-bold text-white truncate">{person.name}</p>
          <p className="text-[11px] text-surface-500 font-mono">{earthId}</p>
        </button>

        <div className="flex items-center gap-0.5 flex-shrink-0">
          <button onClick={() => setModal("video")}
            className="p-2.5 rounded-xl hover:bg-surface-800 text-surface-400 hover:text-white transition-colors">
            <Video size={19} />
          </button>
          <button onClick={() => setModal("call")}
            className="p-2.5 rounded-xl hover:bg-surface-800 text-surface-400 hover:text-white transition-colors">
            <Phone size={19} />
          </button>
          <button onClick={() => setModal("menu")}
            className="p-2.5 rounded-xl hover:bg-surface-800 text-surface-400 hover:text-white transition-colors">
            <MoreVertical size={19} />
          </button>
        </div>
      </div>

      {/* ─── همکاری badge ─── */}
      {isCollab && (
        <div className="mx-4 mt-3 flex items-center gap-2 rounded-xl px-3 py-2.5 text-sm font-semibold flex-shrink-0"
          style={{ background: `${color}18`, color }}>
          <Handshake size={16} />
          <span>درخواست همکاری — {ROLE_LABEL[person.role] ?? "کاربر"}</span>
        </div>
      )}

      {/* ─── Messages ─── */}
      <div className="flex-1 overflow-y-auto px-4 py-4 space-y-2">
        {messages.length === 1 && messages[0].isSystem && (
          <div className="flex flex-col items-center justify-center pt-12 pb-6 text-center">
            <button onClick={() => setModal("profile")}
              className="w-20 h-20 rounded-full flex items-center justify-center text-4xl mb-3 border-2 transition-transform hover:scale-105"
              style={{ borderColor: `${color}50`, background: `${color}15` }}>
              {person.avatar_url
                ? <img src={person.avatar_url} className="w-full h-full rounded-full object-cover" alt="" />
                : ROLE_AVATAR[person.role]}
            </button>
            <p className="text-white font-bold text-lg">{person.name}</p>
            <p className="text-surface-500 text-xs font-mono">{earthId}</p>
            <span className="inline-block mt-2 text-xs font-medium px-3 py-1 rounded-full"
              style={{ background: `${color}20`, color }}>
              {ROLE_LABEL[person.role] ?? "کاربر"}
            </span>
            {person.bio && <p className="text-surface-400 text-xs mt-3 max-w-[220px] leading-relaxed">{person.bio}</p>}
            <p className="text-surface-600 text-xs mt-4">شروع مکالمه کن ✨</p>
          </div>
        )}

        <AnimatePresence initial={false}>
          {messages.map(msg => {
            if (msg.isSystem) return (
              <motion.div key={msg.id} initial={{ opacity:0, scale:.95 }} animate={{ opacity:1, scale:1 }}
                className="flex justify-center">
                <div className="bg-surface-800/60 rounded-2xl px-4 py-2 text-center max-w-[85%]">
                  <p className="text-surface-400 text-xs leading-relaxed">{msg.text}</p>
                </div>
              </motion.div>
            );
            return (
              <motion.div key={msg.id} initial={{ opacity:0, y:8, scale:.97 }} animate={{ opacity:1, y:0, scale:1 }}
                className={`flex ${msg.mine ? "justify-start" : "justify-end"}`}>
                <div className={`max-w-[78%] rounded-2xl px-4 py-2.5 ${msg.mine ? "rounded-br-sm text-white" : "bg-surface-800 text-surface-100 rounded-bl-sm"}`}
                  style={msg.mine ? { background: color } : {}}>
                  <p className="text-sm leading-relaxed">{msg.text}</p>
                  <div className={`flex items-center gap-1 mt-1 ${msg.mine ? "justify-start" : "justify-end"}`}>
                    <span className="text-[10px] opacity-60">{msg.time}</span>
                    {msg.mine && (msg.read ? <CheckCheck size={11} className="opacity-60" /> : <Check size={11} className="opacity-60" />)}
                  </div>
                </div>
              </motion.div>
            );
          })}
        </AnimatePresence>
        <div ref={bottomRef} />
      </div>

      {/* ─── Input ─── */}
      <div className="px-4 pt-3 pb-2 border-t border-surface-800 bg-surface-950 flex-shrink-0">
        <div className="flex items-end gap-2">
          <button className="p-2.5 rounded-xl text-surface-500 hover:text-surface-300 hover:bg-surface-800 transition-colors flex-shrink-0">
            <ImageIcon size={20} />
          </button>
          <button className="p-2.5 rounded-xl text-surface-500 hover:text-surface-300 hover:bg-surface-800 transition-colors flex-shrink-0">
            <Smile size={20} />
          </button>
          <div className="flex-1">
            <textarea
              value={text}
              onChange={e => setText(e.target.value)}
              onKeyDown={e => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); sendMsg(); } }}
              placeholder="پیام بنویس..."
              rows={1}
              className="w-full bg-surface-800 border border-surface-700 rounded-2xl px-4 py-3 text-sm text-surface-100 placeholder-surface-500 focus:outline-none focus:border-primary-500 resize-none"
              style={{ direction:"rtl", maxHeight:"100px", overflowY:"auto" }}
            />
          </div>
          <motion.button whileTap={{ scale:0.9 }} onClick={sendMsg} disabled={!text.trim()}
            className="w-11 h-11 rounded-2xl text-white flex items-center justify-center transition-all flex-shrink-0 disabled:opacity-40"
            style={{ background: text.trim() ? color : "#334155" }}>
            <Send size={18} />
          </motion.button>
        </div>
      </div>

      {/* ─── Bottom Nav ─── */}
      <BottomNav />

      {/* ─── Modals ─── */}
      <AnimatePresence>
        {activeModal === "call"    && <CallModal    person={person} color={color} onEnd={() => setModal(null)} />}
        {activeModal === "video"   && <VideoModal   person={person} color={color} onEnd={() => setModal(null)} />}
        {activeModal === "profile" && <ProfileModal person={person} earthId={earthId} color={color} onClose={() => setModal(null)} />}
        {activeModal === "menu"    && <MenuModal    earthId={earthId} onClose={() => setModal(null)} />}
      </AnimatePresence>
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
