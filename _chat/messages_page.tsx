"use client";

import { useState, useEffect, useRef, useCallback, Suspense, Fragment } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Search, MessageCircle, Send, ArrowRight, Loader2, Users, Reply, Pencil, Trash2, Check, CheckCheck, X, UserPlus, LogOut, Crown, Paperclip, Mic, FileText, Download, Play, Pause, MapPin, Radio, Image as ImageIcon, Languages, Phone, Video, PhoneMissed, Smile, Camera, Copy, Palette, Sticker, Star, Compass, Forward, MoreHorizontal, MoreVertical, ChevronDown, Pin, PinOff, BarChart3, PlusCircle, CheckCircle2, BellOff, Bell, Ban, Share2, ListChecks } from "lucide-react";
import AppShell from "@/components/layout/AppShell";
import { messagesApi, stickersApi, getApiErrorMessage} from "@/lib/api";
import { useAuthStore } from "@/store/auth";
import { useCallStore } from "@/store/call";
import { toPersianNum } from "@/lib/utils";
import { ChatTheme, getChatTheme, saveChatTheme, bgStyle } from "@/lib/chatTheme";
import ChatSettingsSheet from "@/components/chat/ChatSettingsSheet";
import CameraCapture from "@/components/chat/CameraCapture";
import StickerStudio from "@/components/chat/StickerStudio";
import StickerLibrary from "@/components/chat/StickerLibrary";
import MediaEditor from "@/components/chat/MediaEditor";
import StoryBar from "@/components/chat/StoryBar";
import toast from "react-hot-toast";

const ROLE_EMOJI: Record<string, string> = {
  driver: "🚛", cargo_owner: "📦", freight_broker: "🤝",
  insurance_agent: "🛡️", creator: "📢", admin: "⚙️", user: "👤",
};
const ROLE_LABEL: Record<string, string> = {
  driver: "راننده", cargo_owner: "صاحب بار", freight_broker: "کارگزار",
  insurance_agent: "نماینده بیمه", creator: "بازاریاب", admin: "سیستم", user: "کاربر",
};

function lastSeenLabel(iso?: string | null): string {
  if (!iso) return "آفلاین";
  const diff = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (diff < 60) return "چند لحظه پیش";
  if (diff < 3600) return `${toPersianNum(Math.floor(diff / 60))} دقیقه پیش`;
  if (diff < 86400) return `${toPersianNum(Math.floor(diff / 3600))} ساعت پیش`;
  const days = Math.floor(diff / 86400);
  if (days === 1) return "دیروز";
  if (days < 7) return `${toPersianNum(days)} روز پیش`;
  try {
    return new Date(iso).toLocaleDateString("fa-IR", { month: "long", day: "numeric" });
  } catch { return "خیلی وقت پیش"; }
}

interface Room {
  id: string; type: string; name: string | null;
  partner_name: string | null; partner_earth_id: string | null;
  partner_role: string | null; partner_avatar: string | null;
  last_message: string | null; last_message_at: string | null;
  unread_count: number; member_count?: number; is_admin?: boolean;
  partner_online?: boolean; partner_last_seen?: string | null;
  is_muted?: boolean; is_blocked?: boolean;
  created_at: string;
}

interface Member {
  earth_id: string; name: string | null; role: string | null;
  avatar_url: string | null; is_me: boolean; is_admin: boolean;
}

interface ReplyPreview {
  id: string; sender_name: string | null; content: string; is_deleted: boolean;
}
interface LocationData {
  lat: number; lng: number; label?: string | null;
  live: boolean; active: boolean;
  updated_at?: string | null; expires_at?: string | null;
}
interface PollOptionData { text: string; votes: number; voted: boolean; }
interface PollData {
  id: string; question: string; multiple: boolean;
  total_votes: number; options: PollOptionData[];
}
interface Message {
  id: string; sender_id: string; sender_name: string | null;
  sender_earth_id: string | null; content: string;
  is_mine: boolean; created_at: string;
  is_deleted?: boolean; edited?: boolean;
  reply_to?: ReplyPreview | null;
  reactions?: Record<string, number>;
  my_reaction?: string | null;
  is_read?: boolean;
  media_url?: string | null;
  media_type?: string | null;   // image | voice | file | location | live_location
  media_name?: string | null;
  media_meta?: string | null;
  sticker_id?: string | null;
  location?: LocationData | null;
  poll?: PollData | null;
  is_forwarded?: boolean;
  forwarded_from?: string | null;
  is_pinned?: boolean;
  _uploading?: boolean;
}

const REACTION_EMOJIS = ["❤️", "👍", "😂", "😮", "😢", "🙏", "🔥", "👏"];

// اموجی‌های پرکاربرد برای درجِ داخلِ متن (نوارِ ورودی)
const COMPOSE_EMOJIS = [
  "😀","😁","😂","🤣","😊","😍","😘","😎","🤩","🥳","😉","🙂","😌","😴","🤔","🤗",
  "😢","😭","😡","😱","😳","🥺","😅","😏","😢","🙄","😤","😬","🤯","😷","🤒","🥶",
  "👍","👎","👏","🙏","💪","🤝","👌","✌️","🤞","👋","🫰","🙌","🤙","☝️","✊","🫶",
  "❤️","🧡","💛","💚","💙","💜","🖤","🤍","💖","💔","💯","🔥","✨","⭐","🎉","🎁",
  "🌹","🌸","🌟","☀️","🌙","⚡","💦","🍀","🎂","☕","🍕","⚽","🚀","📌","✅","❌",
];

// ترجمهٔ همزمان — زبان‌های مقصد
const TRANSLATE_LANGS: { code: string; label: string; flag: string }[] = [
  { code: "fa", label: "فارسی", flag: "🇮🇷" },
  { code: "en", label: "English", flag: "🇬🇧" },
  { code: "ar", label: "العربية", flag: "🇸🇦" },
  { code: "tr", label: "Türkçe", flag: "🇹🇷" },
  { code: "ru", label: "Русский", flag: "🇷🇺" },
  { code: "zh-CN", label: "中文", flag: "🇨🇳" },
  { code: "fr", label: "Français", flag: "🇫🇷" },
  { code: "de", label: "Deutsch", flag: "🇩🇪" },
  { code: "es", label: "Español", flag: "🇪🇸" },
  { code: "hi", label: "हिन्दी", flag: "🇮🇳" },
  { code: "ur", label: "اردو", flag: "🇵🇰" },
  { code: "ku", label: "کوردی", flag: "🏴" },
];
const langLabel = (code: string) =>
  TRANSLATE_LANGS.find((l) => l.code === code)?.label ?? code;

const TR_LANG_KEY = "dilix_tr_lang";
const TR_AUTO_KEY = "dilix_tr_auto";

interface TransState {
  text: string;
  detected?: string | null;
  open: boolean;
  loading?: boolean;
  lang?: string;   // زبانی که این ترجمه به آن انجام شده
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

// ── Voice message player ──────────────────────────────────────
function VoiceBubble({ url, mine, uploading }: { url: string; mine: boolean; uploading: boolean }) {
  const audioRef = useRef<HTMLAudioElement>(null);
  const [playing, setPlaying] = useState(false);
  const [dur, setDur] = useState(0);
  const [cur, setCur] = useState(0);
  const toggle = () => {
    const a = audioRef.current;
    if (!a) return;
    if (playing) { a.pause(); } else { a.play().catch(() => {}); }
  };
  const fmt = (s: number) => {
    if (!isFinite(s) || s < 0) s = 0;
    const m = Math.floor(s / 60), ss = Math.floor(s % 60);
    return toPersianNum(`${m}:${ss.toString().padStart(2, "0")}`);
  };
  const pct = dur > 0 ? Math.min(100, (cur / dur) * 100) : 0;
  return (
    <div className="flex items-center gap-2 min-w-[160px]">
      <button
        onClick={toggle} disabled={uploading}
        className={`w-9 h-9 rounded-full flex items-center justify-center shrink-0 ${mine ? "bg-white/20" : "bg-white/10"}`}
      >
        {uploading ? <Loader2 size={16} className="animate-spin" /> : playing ? <Pause size={16} /> : <Play size={16} className="ml-0.5" />}
      </button>
      <div className="flex-1">
        <div className={`h-1 rounded-full ${mine ? "bg-white/25" : "bg-white/15"}`}>
          <div className="h-full rounded-full bg-white/70" style={{ width: `${pct}%` }} />
        </div>
        <div className="text-[10px] text-white/50 mt-1">{fmt(playing || cur > 0 ? cur : dur)}</div>
      </div>
      <Mic size={14} className="text-white/40 shrink-0" />
      <audio
        ref={audioRef} src={url} preload="metadata"
        onLoadedMetadata={(e) => setDur((e.target as HTMLAudioElement).duration)}
        onTimeUpdate={(e) => setCur((e.target as HTMLAudioElement).currentTime)}
        onPlay={() => setPlaying(true)}
        onPause={() => setPlaying(false)}
        onEnded={() => { setPlaying(false); setCur(0); }}
      />
    </div>
  );
}

// ── Location bubble (tile-based map preview + live badge) ──────
function tileForLatLng(lat: number, lng: number, z: number) {
  const n = 2 ** z;
  const x = ((lng + 180) / 360) * n;
  const latRad = (lat * Math.PI) / 180;
  const y = ((1 - Math.asinh(Math.tan(latRad)) / Math.PI) / 2) * n;
  const tx = Math.floor(x), ty = Math.floor(y);
  return { tx, ty, fx: x - tx, fy: y - ty };
}

function remainingLabel(expiresAt?: string | null): string {
  if (!expiresAt) return "";
  const ms = new Date(expiresAt).getTime() - Date.now();
  if (ms <= 0) return "پایان‌یافته";
  const mins = Math.round(ms / 60000);
  if (mins >= 60) return `${toPersianNum(Math.floor(mins / 60))} ساعت باقی‌مانده`;
  return `${toPersianNum(Math.max(1, mins))} دقیقه باقی‌مانده`;
}

function LocationBubble({ loc, mine, canStop, onStop }: {
  loc: LocationData; mine: boolean; canStop: boolean; onStop: () => void;
}) {
  const Z = 15;
  const { tx, ty, fx, fy } = tileForLatLng(loc.lat, loc.lng, Z);
  const openMap = () => window.open(`https://www.google.com/maps?q=${loc.lat},${loc.lng}`, "_blank", "noopener");
  const isLive = loc.live;
  const active = loc.active;
  return (
    <div className="mb-1">
      <button onClick={openMap} className="relative block w-[200px] h-[200px] rounded-xl overflow-hidden bg-[#1a2733]">
        <img
          src={`/globe-tiles/${Z}/${tx}/${ty}`} alt="map"
          className="w-full h-full object-cover select-none pointer-events-none"
          draggable={false}
        />
        {/* pin */}
        <span
          className="absolute"
          style={{ left: `${fx * 100}%`, top: `${fy * 100}%`, transform: "translate(-50%,-100%)" }}
        >
          {isLive && active
            ? <Radio size={26} className="text-emerald-400 drop-shadow-[0_1px_2px_rgba(0,0,0,0.8)]" />
            : <MapPin size={26} className={`${isLive ? "text-white/70" : "text-red-500"} fill-current drop-shadow-[0_1px_2px_rgba(0,0,0,0.8)]`} />}
        </span>
        {/* live badge */}
        {isLive && (
          <span className={`absolute top-2 right-2 px-2 py-0.5 rounded-full text-[10px] font-semibold flex items-center gap-1 ${
            active ? "bg-emerald-500 text-white" : "bg-black/60 text-white/70"
          }`}>
            {active && <span className="w-1.5 h-1.5 rounded-full bg-white animate-pulse" />}
            {active ? "زنده" : "پایان‌یافته"}
          </span>
        )}
      </button>
      <div className="flex items-center justify-between gap-2 mt-1">
        <span className="text-[11px] text-white/50 truncate flex items-center gap-1">
          <MapPin size={11} />
          {loc.label || (isLive ? (active ? remainingLabel(loc.expires_at) : "اشتراک پایان یافت") : "موقعیت مکانی")}
        </span>
        {isLive && active && mine && canStop && (
          <button onClick={onStop} className="text-[11px] text-red-400 font-medium shrink-0 px-2 py-0.5 rounded-lg bg-red-500/10">
            توقف
          </button>
        )}
      </div>
    </div>
  );
}

function fmtCallDur(sec: number): string {
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return toPersianNum(`${m}:${s.toString().padStart(2, "0")}`);
}

const CALL_STATUS_LABEL: Record<string, string> = {
  answered: "تماس", no_answer: "بی‌پاسخ", rejected: "رد شد",
  canceled: "لغو شد", missed: "بی‌پاسخ", failed: "ناموفق",
};

function CallBubble({ meta, mine, onCall }: {
  meta: string | null | undefined; mine: boolean; onCall: (m: "audio" | "video") => void;
}) {
  let media = "audio", status = "answered", duration = 0;
  try {
    const j = JSON.parse(meta || "{}");
    media = j.media === "video" ? "video" : "audio";
    status = typeof j.status === "string" ? j.status : "answered";
    duration = Number(j.duration) || 0;
  } catch { /* noop */ }
  const answered = status === "answered" && duration > 0;
  const Icon = answered ? (media === "video" ? Video : Phone) : PhoneMissed;
  const label = CALL_STATUS_LABEL[status] ?? "تماس";
  return (
    <button
      onClick={(e) => { e.stopPropagation(); onCall(media === "video" ? "video" : "audio"); }}
      className="flex items-center gap-2.5 py-0.5 text-right"
      title="تماس مجدد"
    >
      <span className={`w-9 h-9 rounded-full flex items-center justify-center shrink-0 ${
        answered ? (mine ? "bg-white/15" : "bg-emerald-500/20") : "bg-red-500/20"
      }`}>
        <Icon size={17} className={answered ? (mine ? "text-white" : "text-emerald-400") : "text-red-400"} />
      </span>
      <span className="min-w-0">
        <span className="block text-[13px] font-medium">
          {media === "video" ? "تماس تصویری" : "تماس صوتی"}
        </span>
        <span className={`block text-[11px] ${mine ? "text-white/60" : "text-white/45"}`}>
          {answered ? fmtCallDur(duration) : label}
        </span>
      </span>
    </button>
  );
}

// ── Chat View ─────────────────────────────────────────────────
function ChatView({ room, onBack, onLeave }: { room: Room; onBack: () => void; onLeave?: () => void }) {
  const isGroup = room.type === "group";
  const [showMembers, setShowMembers] = useState(false);
  const [members, setMembers] = useState<Member[]>([]);
  const [membersLoading, setMembersLoading] = useState(false);
  const [addTarget, setAddTarget] = useState("");
  const [addBusy, setAddBusy] = useState(false);
  const [messages, setMessages] = useState<Message[]>([]);
  const [loading,  setLoading]  = useState(true);
  const [text,     setText]     = useState("");
  const [sending,  setSending]  = useState(false);
  const [replyTo,  setReplyTo]  = useState<Message | null>(null);
  const [editing,  setEditing]  = useState<Message | null>(null);
  const [sheetMsg, setSheetMsg] = useState<Message | null>(null); // action sheet target
  const [forwardMsg, setForwardMsg] = useState<Message | null>(null); // forward picker target
  const [forwardRooms, setForwardRooms] = useState<Room[]>([]);
  const [forwardAnon, setForwardAnon] = useState(false);
  const [forwardBusy, setForwardBusy] = useState(false);
  const [forwardBulk, setForwardBulk] = useState(false);
  const [selectMode, setSelectMode] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [swipe, setSwipe] = useState<{ id: string; dx: number } | null>(null);
  const gestureRef = useRef<{ id: string; x0: number; y0: number; dx: number; moved: boolean; swiping: boolean; longFired: boolean; long: number } | null>(null);
  const suppressClickRef = useRef(false);
  const bottomRef = useRef<HTMLDivElement>(null);
  const inputRef  = useRef<HTMLInputElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const camInputRef = useRef<HTMLInputElement>(null);
  const [showEmoji, setShowEmoji] = useState(false);
  const [emojiTab, setEmojiTab] = useState<"emoji" | "sticker">("emoji");
  const [showCallMenu, setShowCallMenu] = useState(false);
  const [showOptions, setShowOptions] = useState(false);
  const [isMuted, setIsMuted] = useState(!!room.is_muted);
  const [isBlocked, setIsBlocked] = useState(!!room.is_blocked);
  const [showPollCreate, setShowPollCreate] = useState(false);
  const [pollQuestion, setPollQuestion] = useState("");
  const [pollOptions, setPollOptions] = useState<string[]>(["", ""]);
  const [pollMultiple, setPollMultiple] = useState(false);
  const [pollSending, setPollSending] = useState(false);
  const [showCamera, setShowCamera] = useState(false);
  const [showStudio, setShowStudio] = useState(false);
  const [showLibrary, setShowLibrary] = useState(false);
  const [libraryPackId, setLibraryPackId] = useState<string | null>(null);
  const [editorMedia, setEditorMedia] = useState<{ file: File; kind: "image" | "video" } | null>(null);
  const [chatTheme, setChatTheme] = useState<ChatTheme>({ bg: "dark", accent: "#4F46E5" });
  const [showChatSettings, setShowChatSettings] = useState(false);
  const [showSearch, setShowSearch] = useState(false);
  const [searchQ, setSearchQ] = useState("");
  const [searchResults, setSearchResults] = useState<Message[]>([]);
  const [searchBusy, setSearchBusy] = useState(false);
  const [highlightId, setHighlightId] = useState<string | null>(null);
  const msgRefs = useRef<Record<string, HTMLDivElement | null>>({});
  const [showScrollDown, setShowScrollDown] = useState(false);
  const [presence, setPresence] = useState<{ online: boolean; lastSeen: string | null; typing: string[] }>({ online: false, lastSeen: null, typing: [] });
  const typingSentRef = useRef(0);
  const [pins, setPins] = useState<Message[]>([]);
  const [pinIdx, setPinIdx] = useState(0);
  const me = useAuthStore((s) => s.user);

  useEffect(() => { setChatTheme(getChatTheme()); }, []);
  const applyTheme = (t: ChatTheme) => { setChatTheme(t); saveChatTheme(t); };

  // درجِ اموجی در محلِ نشانگرِ متن
  const insertEmoji = (emo: string) => {
    const el = inputRef.current;
    if (!el) { setText((t) => t + emo); return; }
    const start = el.selectionStart ?? text.length;
    const end = el.selectionEnd ?? text.length;
    const next = text.slice(0, start) + emo + text.slice(end);
    setText(next);
    requestAnimationFrame(() => {
      el.focus();
      const pos = start + emo.length;
      try { el.setSelectionRange(pos, pos); } catch { /* ignore */ }
    });
  };

  const copyText = async (msg: Message) => {
    if (!msg.content?.trim()) return;
    try {
      await navigator.clipboard.writeText(msg.content);
      toast.success("متن کپی شد");
    } catch {
      toast.error("کپی ناموفق بود");
    }
    setSheetMsg(null);
  };

  const togglePin = async (msg: Message) => {
    setSheetMsg(null);
    const willPin = !msg.is_pinned;
    // optimistic on the message list
    setMessages((prev) => prev.map((m) => m.id === msg.id ? { ...m, is_pinned: willPin } : m));
    try {
      await messagesApi.pin(msg.id);
      const r = await messagesApi.pins(room.id);
      setPins(r.data);
      setPinIdx(0);
      toast.success(willPin ? "پیام سنجاق شد" : "سنجاق برداشته شد");
    } catch {
      // revert
      setMessages((prev) => prev.map((m) => m.id === msg.id ? { ...m, is_pinned: !willPin } : m));
      toast.error("عملیات ناموفق بود");
    }
  };

  // ── Poll ─────────────────────────────────────────────────
  const openPollCreate = () => {
    setPollQuestion("");
    setPollOptions(["", ""]);
    setPollMultiple(false);
    setShowPollCreate(true);
  };

  const submitPoll = async () => {
    const question = pollQuestion.trim();
    const options = pollOptions.map((o) => o.trim()).filter(Boolean);
    if (!question || options.length < 2) return;
    setPollSending(true);
    try {
      const r = await messagesApi.createPoll(room.id, question, options, pollMultiple);
      setMessages((prev) => [...prev, r.data]);
      setShowPollCreate(false);
      requestAnimationFrame(() => bottomRef.current?.scrollIntoView({ behavior: "smooth" }));
    } catch {
      toast.error("ساختِ نظرسنجی ناموفق بود");
    } finally {
      setPollSending(false);
    }
  };

  const votePoll = async (msg: Message, optionIndex: number) => {
    if (!msg.poll) return;
    const pollId = msg.poll.id;
    try {
      const r = await messagesApi.votePoll(pollId, optionIndex);
      setMessages((prev) => prev.map((m) => m.id === msg.id ? { ...m, poll: r.data } : m));
    } catch {
      toast.error("ثبتِ رأی ناموفق بود");
    }
  };

  // ── Export chat (client-side .txt) ───────────────────────
  const exportChat = () => {
    setShowOptions(false);
    try {
      const lines = messages.map((m) => {
        const who = m.is_mine ? "من" : (m.sender_name || "مخاطب");
        let time = "";
        try { time = new Date(m.created_at).toLocaleString("fa-IR"); } catch { time = m.created_at; }
        let body = m.is_deleted ? "(پیام حذف‌شده)" : (m.content || "");
        if (!body && m.media_type) body = `[${m.media_type}]`;
        return `[${time}] ${who}: ${body}`;
      });
      const header = `گفتگو با ${partnerName}\n${"=".repeat(32)}\n`;
      const blob = new Blob([header + lines.join("\n")], { type: "text/plain;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `dilix-chat-${partnerName}.txt`;
      a.click();
      URL.revokeObjectURL(url);
    } catch {
      toast.error("صادر کردنِ گفتگو ناموفق بود");
    }
  };

  // ── بی‌صدا / مسدود / پاک‌کردنِ گفتگو ───────────────────────
  const toggleMute = async (durationMinutes?: number | null) => {
    setShowOptions(false);
    const next = !isMuted;
    try {
      const r = await messagesApi.muteRoom(room.id, next, durationMinutes ?? null);
      setIsMuted(!!r.data.muted);
      toast.success(r.data.muted ? "اعلانِ این گفتگو بی‌صدا شد" : "اعلانِ این گفتگو روشن شد");
    } catch {
      toast.error("تغییرِ وضعیتِ اعلان ناموفق بود");
    }
  };

  const toggleBlock = async () => {
    setShowOptions(false);
    if (!room.partner_earth_id) return;
    try {
      const r = await messagesApi.blockUser(room.partner_earth_id);
      setIsBlocked(!!r.data.blocked);
      toast.success(r.data.blocked ? "مخاطب مسدود شد" : "مسدودی برداشته شد");
    } catch {
      toast.error("تغییرِ وضعیتِ مسدودی ناموفق بود");
    }
  };

  const doClearChat = async () => {
    setShowOptions(false);
    if (!confirm("گفتگو برایِ شما پاک شود؟ (برای مخاطب دست‌نخورده می‌ماند)")) return;
    try {
      await messagesApi.clearChat(room.id);
      setMessages([]);
      toast.success("گفتگو پاک شد");
    } catch {
      toast.error("پاک کردنِ گفتگو ناموفق بود");
    }
  };

  // ── Translation ──────────────────────────────────────────
  const [trans, setTrans] = useState<Record<string, TransState>>({});
  const [trLang, setTrLang] = useState("fa");
  const [autoTr, setAutoTr] = useState(false);
  const [showLangMenu, setShowLangMenu] = useState(false);
  const [composeTr, setComposeTr] = useState(false);
  const [translateAllTarget, setTranslateAllTarget] = useState<string | null>(null);

  useEffect(() => {
    try {
      const l = localStorage.getItem(TR_LANG_KEY);
      if (l) setTrLang(l);
      setAutoTr(localStorage.getItem(TR_AUTO_KEY) === "1");
    } catch { /* ignore */ }
  }, []);

  const pickLang = (code: string) => {
    setTrLang(code);
    try { localStorage.setItem(TR_LANG_KEY, code); } catch { /* ignore */ }
    setTrans({});   // stale — retranslate immediately for new target
    setTranslateAllTarget(code);
    setShowLangMenu(false);
  };
  const toggleAuto = () => {
    setAutoTr((v) => {
      const nv = !v;
      try { localStorage.setItem(TR_AUTO_KEY, nv ? "1" : "0"); } catch { /* ignore */ }
      if (!nv) setTrans({});
      return nv;
    });
  };

  const doTranslate = useCallback(async (msg: Message, silent = false, target?: string) => {
    const tgt = target || trLang;
    if (!msg.content?.trim() || msg.is_deleted || msg.id.startsWith("tmp-")) return;
    if (!silent) setSheetMsg(null);
    const existing = trans[msg.id];
    if (existing && existing.text && existing.lang === tgt) {   // همان زبان کش‌شده → toggle
      setTrans((p) => ({ ...p, [msg.id]: { ...existing, open: !existing.open } }));
      return;
    }
    setTrans((p) => ({ ...p, [msg.id]: { text: "", open: true, loading: true, lang: tgt } }));
    try {
      const res = await messagesApi.translateMessage(msg.id, tgt);
      const d = res.data;
      const same = d.detected_lang && d.detected_lang === tgt;
      setTrans((p) => ({
        ...p,
        [msg.id]: { text: d.translated_text, detected: d.detected_lang, loading: false, lang: tgt, open: silent ? !same : true },
      }));
    } catch {
      setTrans((p) => { const n = { ...p }; delete n[msg.id]; return n; });
      if (!silent) toast.error("ترجمه ناموفق بود");
    }
  }, [trans, trLang]);

  // انتخابِ دستیِ زبان برای ترجمهٔ یک پیامِ مشخص (زبانِ انتخابی پیش‌فرضِ بعدی هم می‌شود)
  const translateTo = (msg: Message, code: string) => {
    setTrLang(code);
    try { localStorage.setItem(TR_LANG_KEY, code); } catch { /* ignore */ }
    doTranslate(msg, false, code);
  };

  // وقتی زبان از شیتِ بالای چت انتخاب می‌شود، پیام‌های متنیِ موجود فوراً ترجمه شوند
  useEffect(() => {
    if (!translateAllTarget) return;
    const target = translateAllTarget;
    setTranslateAllTarget(null);
    const items = messages.filter((m) =>
      m.content?.trim() && !m.is_deleted && !m.id.startsWith("tmp-") && !m.media_type
    );
    if (!items.length) return;
    items.slice(-30).forEach((m) => doTranslate(m, true, target));
    toast.success(`ترجمه به ${langLabel(target)} انجام شد`);
  }, [translateAllTarget, messages, doTranslate]);

  const closeTranslation = (id: string) =>
    setTrans((p) => (p[id] ? { ...p, [id]: { ...p[id], open: false } } : p));

  const load = useCallback(async (silent = false) => {
    try {
      const res = await messagesApi.getMessages(room.id, 50);
      const data: Message[] = res.data;
      setMessages(data);
      messagesApi.markRead(room.id).catch(() => {});
      messagesApi.pins(room.id).then((r) => setPins(r.data)).catch(() => {});
      // resume watcher for my still-active live share
      const mine = data.filter(m => m.is_mine && m.media_type === "live_location" && m.location?.active);
      if (mine.length) {
        const latest = mine[mine.length - 1];
        if (liveShareRef.current?.id !== latest.id) startWatching(latest.id);
      } else if (liveShareRef.current) {
        stopWatching();
      }
    } catch {
      // فقط بارگذاریِ اولیه خطا نشان می‌دهد؛ رفرشِ پس‌زمینه (هر ۵ث) بی‌صدا است
      if (!silent) toast.error("خطا در بارگذاری پیام‌ها");
    } finally {
      setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [room.id]);

  useEffect(() => { load(); }, [load]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  // poll every 5s for new messages (silent: no error toast on transient failures)
  useEffect(() => {
    const t = setInterval(() => load(true), 5000);
    return () => clearInterval(t);
  }, [load]);

  // poll presence (online/last-seen) + typing every 4s
  useEffect(() => {
    let alive = true;
    const tick = async () => {
      try {
        const { data } = await messagesApi.roomStatus(room.id);
        if (alive) setPresence({
          online: !!data.partner_online,
          lastSeen: data.partner_last_seen ?? null,
          typing: Array.isArray(data.typing) ? data.typing : [],
        });
      } catch { /* ignore transient */ }
    };
    tick();
    const t = setInterval(tick, 4000);
    return () => { alive = false; clearInterval(t); };
  }, [room.id]);

  // اعلامِ «در حال نوشتن» با throttle (حداکثر هر ۳ ثانیه)
  const signalTyping = () => {
    const now = Date.now();
    if (now - typingSentRef.current < 3000) return;
    typingSentRef.current = now;
    messagesApi.setTyping(room.id).catch(() => {});
  };

  // auto-translate incoming (others') text messages when enabled
  useEffect(() => {
    if (!autoTr) return;
    const pending = messages.filter(
      (m) => !m.is_mine && !m.is_deleted && m.content?.trim()
        && !m.id.startsWith("tmp-") && !m.media_type && !trans[m.id]
    );
    pending.slice(0, 8).forEach((m) => doTranslate(m, true));
  }, [messages, autoTr, trLang, trans, doTranslate]);

  const send = async () => {
    if (!text.trim() || sending) return;
    const content = text.trim();

    // Editing an existing message
    if (editing) {
      const target = editing;
      setText("");
      setEditing(null);
      setMessages(prev => prev.map(m => m.id === target.id ? { ...m, content, edited: true } : m));
      try {
        await messagesApi.edit(target.id, content);
      } catch {
        toast.error("ویرایش ناموفق بود");
        load();
      }
      return;
    }

    const replyId = replyTo?.id ?? null;
    setText("");
    setReplyTo(null);
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
      reply_to: replyTo ? {
        id: replyTo.id,
        sender_name: replyTo.sender_name,
        content: replyTo.content,
        is_deleted: !!replyTo.is_deleted,
      } : null,
      reactions: {},
    };
    setMessages(prev => [...prev, tmp]);

    try {
      const res = await messagesApi.send(room.id, content, replyId);
      setMessages(prev => prev.map(m => m.id === tmp.id ? res.data : m));
    } catch {
      setMessages(prev => prev.filter(m => m.id !== tmp.id));
      setText(content);
      toast.error("ارسال پیام ناموفق بود");
    } finally {
      setSending(false);
    }
  };

  // translate what I'm composing into the target language, in place
  const translateCompose = async () => {
    const t = text.trim();
    if (!t || composeTr) return;
    setComposeTr(true);
    try {
      const res = await messagesApi.translateText(t, trLang);
      const out = res.data.translated_text;
      if (out && out !== t) {
        setText(out);
        toast.success(`به ${langLabel(trLang)} ترجمه شد`);
      } else {
        toast(`متن از قبل به ${langLabel(trLang)} است`);
      }
    } catch {
      toast.error("ترجمه ناموفق بود");
    } finally {
      setComposeTr(false);
    }
  };

  const uploadMedia = async (
    file: File | Blob,
    mediaType: "image" | "voice" | "file" | "video",
    filename?: string,
    metaHint?: string,
  ) => {
    const replyId = replyTo?.id ?? null;
    const rp = replyTo;
    setReplyTo(null);
    const tmpId = "tmp-" + Date.now();
    const localUrl = URL.createObjectURL(file);
    const tmp: Message = {
      id: tmpId,
      sender_id: me?.id ?? "",
      sender_name: me?.full_name ?? "",
      sender_earth_id: me?.earth_id ?? "",
      content: "",
      is_mine: true,
      created_at: new Date().toISOString(),
      reactions: {},
      media_url: localUrl,
      media_type: mediaType,
      media_name: mediaType === "file" ? (filename ?? "فایل") : null,
      media_meta: metaHint ?? "",
      reply_to: rp ? { id: rp.id, sender_name: rp.sender_name, content: rp.content, is_deleted: !!rp.is_deleted } : null,
      _uploading: true,
    };
    setMessages(prev => [...prev, tmp]);
    try {
      const res = await messagesApi.sendMedia(room.id, file, { replyToId: replyId, filename });
      setMessages(prev => prev.map(m => m.id === tmpId ? res.data : m));
    } catch {
      setMessages(prev => prev.filter(m => m.id !== tmpId));
      toast.error("ارسال فایل ناموفق بود");
    } finally {
      URL.revokeObjectURL(localUrl);
    }
  };

  const sendSticker = async (stickerId: string) => {
    const replyId = replyTo?.id ?? null;
    const rp = replyTo;
    setReplyTo(null);
    const tmpId = "tmp-" + Date.now();
    try {
      const res = await messagesApi.sendSticker(room.id, stickerId, replyId);
      setMessages(prev => [...prev, res.data]);
    } catch {
      toast.error("ارسال استیکر ناموفق بود");
    }
    void tmpId; void rp;
  };

  const starSticker = async (stickerId: string) => {
    setSheetMsg(null);
    try { await stickersApi.star(stickerId); toast.success("به ستاره‌دارها افزوده شد"); }
    catch { toast.error("عملیات ناموفق بود"); }
  };

  const exploreStickerLibrary = async (stickerId: string) => {
    setSheetMsg(null);
    try {
      const res = await stickersApi.getSticker(stickerId);
      setLibraryPackId(res.data.pack_id);
      setShowLibrary(true);
    } catch { toast.error("کتابخانه یافت نشد"); }
  };

  const onPickFile = (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0];
    e.target.value = "";
    if (!f) return;
    // عکس/ویدیو → ویرایشگر (برش/فیلتر/متن/فشرده‌سازی)؛ بقیه مستقیم
    if (f.type.startsWith("image/")) { setEditorMedia({ file: f, kind: "image" }); return; }
    if (f.type.startsWith("video/")) { setEditorMedia({ file: f, kind: "video" }); return; }
    if (f.size > 25 * 1024 * 1024) { toast.error("حجم فایل نباید بیشتر از ۲۵ مگابایت باشد"); return; }
    uploadMedia(f, "file", f.name);
  };

  // ── Voice recording ──────────────────────────────────────
  const recorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const recTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const [recording, setRecording] = useState(false);
  const [recSeconds, setRecSeconds] = useState(0);

  const startRec = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const mr = new MediaRecorder(stream);
      chunksRef.current = [];
      mr.ondataavailable = (ev) => { if (ev.data.size > 0) chunksRef.current.push(ev.data); };
      mr.onstop = () => {
        stream.getTracks().forEach(t => t.stop());
        if (recTimerRef.current) clearInterval(recTimerRef.current);
        const blob = new Blob(chunksRef.current, { type: mr.mimeType || "audio/webm" });
        setRecording(false);
        if (blob.size > 0 && !cancelRecRef.current) uploadMedia(blob, "voice", "voice.webm");
        cancelRecRef.current = false;
        setRecSeconds(0);
      };
      recorderRef.current = mr;
      mr.start();
      setRecording(true);
      setRecSeconds(0);
      recTimerRef.current = setInterval(() => setRecSeconds(s => s + 1), 1000);
    } catch {
      toast.error("دسترسی به میکروفون ممکن نشد");
    }
  };
  const cancelRecRef = useRef(false);
  const stopRec = (cancel = false) => {
    cancelRecRef.current = cancel;
    recorderRef.current?.stop();
  };

  // ── Location sharing ─────────────────────────────────────
  const [showAttach, setShowAttach] = useState(false);
  const [showLiveDur, setShowLiveDur] = useState(false);
  const [locBusy, setLocBusy] = useState(false);

  const getPos = () => new Promise<GeolocationPosition>((resolve, reject) => {
    if (!navigator.geolocation) return reject(new Error("no-geo"));
    navigator.geolocation.getCurrentPosition(resolve, reject, {
      enableHighAccuracy: true, timeout: 12000, maximumAge: 0,
    });
  });

  const shareStaticLocation = async () => {
    setShowAttach(false);
    if (locBusy) return;
    setLocBusy(true);
    const replyId = replyTo?.id ?? null;
    try {
      const p = await getPos();
      const res = await messagesApi.sendLocation(room.id, {
        lat: p.coords.latitude, lng: p.coords.longitude, replyToId: replyId,
      });
      setReplyTo(null);
      setMessages(prev => [...prev, res.data]);
    } catch {
      toast.error("دسترسی به موقعیت مکانی ممکن نشد");
    } finally { setLocBusy(false); }
  };

  const shareLiveLocation = async (minutes: number) => {
    setShowLiveDur(false);
    setShowAttach(false);
    if (locBusy) return;
    setLocBusy(true);
    const replyId = replyTo?.id ?? null;
    try {
      const p = await getPos();
      const res = await messagesApi.startLiveLocation(room.id, {
        lat: p.coords.latitude, lng: p.coords.longitude,
        durationMinutes: minutes, replyToId: replyId,
      });
      setReplyTo(null);
      setMessages(prev => [...prev, res.data]);
      startWatching(res.data.id);
    } catch {
      toast.error("شروع موقعیت زنده ممکن نشد");
    } finally { setLocBusy(false); }
  };

  // live-location watcher (updates my active share while page is open)
  const liveShareRef = useRef<{ id: string; watchId: number; lastSent: number } | null>(null);
  const startWatching = (messageId: string) => {
    if (!navigator.geolocation) return;
    if (liveShareRef.current?.id === messageId) return;
    stopWatching();
    const watchId = navigator.geolocation.watchPosition(
      (p) => {
        const now = Date.now();
        const s = liveShareRef.current;
        if (!s || s.id !== messageId) return;
        if (now - s.lastSent < 8000) return;   // throttle to ≥8s
        s.lastSent = now;
        messagesApi.updateLiveLocation(messageId, p.coords.latitude, p.coords.longitude)
          .then((res) => setMessages(prev => prev.map(m => m.id === messageId ? { ...m, location: res.data.location } : m)))
          .catch(() => {});
      },
      () => {},
      { enableHighAccuracy: true, maximumAge: 5000, timeout: 20000 },
    );
    liveShareRef.current = { id: messageId, watchId, lastSent: Date.now() };
  };
  const stopWatching = () => {
    const s = liveShareRef.current;
    if (s && navigator.geolocation) navigator.geolocation.clearWatch(s.watchId);
    liveShareRef.current = null;
  };
  useEffect(() => () => stopWatching(), []);

  const doStopLive = async (msg: Message) => {
    if (liveShareRef.current?.id === msg.id) stopWatching();
    setMessages(prev => prev.map(m => m.id === msg.id && m.location
      ? { ...m, location: { ...m.location, active: false } } : m));
    try {
      await messagesApi.stopLiveLocation(msg.id);
    } catch {
      toast.error("توقف اشتراک ناموفق بود");
      load();
    }
  };

  const doReact = async (msg: Message, emoji: string) => {
    setSheetMsg(null);
    // optimistic toggle
    setMessages(prev => prev.map(m => {
      if (m.id !== msg.id) return m;
      const reactions = { ...(m.reactions ?? {}) };
      const prevEmoji = m.my_reaction;
      if (prevEmoji) reactions[prevEmoji] = Math.max(0, (reactions[prevEmoji] ?? 1) - 1);
      let myReaction: string | null = emoji;
      if (prevEmoji === emoji) { myReaction = null; }
      else { reactions[emoji] = (reactions[emoji] ?? 0) + 1; }
      Object.keys(reactions).forEach(k => { if (reactions[k] <= 0) delete reactions[k]; });
      return { ...m, reactions, my_reaction: myReaction };
    }));
    try {
      const res = await messagesApi.react(msg.id, emoji);
      setMessages(prev => prev.map(m => m.id === msg.id
        ? { ...m, reactions: res.data.reactions, my_reaction: res.data.my_reaction }
        : m));
    } catch {
      toast.error("خطا در واکنش");
      load();
    }
  };

  const doDelete = async (msg: Message) => {
    setSheetMsg(null);
    setMessages(prev => prev.map(m => m.id === msg.id ? { ...m, is_deleted: true, content: "" } : m));
    try {
      await messagesApi.remove(msg.id);
    } catch {
      toast.error("حذف ناموفق بود");
      load();
    }
  };

  const startEdit = (msg: Message) => {
    setSheetMsg(null);
    setReplyTo(null);
    setEditing(msg);
    setText(msg.content);
    setTimeout(() => inputRef.current?.focus(), 50);
  };

  const startReply = (msg: Message) => {
    setSheetMsg(null);
    setEditing(null);
    setReplyTo(msg);
    setTimeout(() => inputRef.current?.focus(), 50);
  };

  const runSearch = async () => {
    const q = searchQ.trim();
    if (q.length < 2) { setSearchResults([]); return; }
    setSearchBusy(true);
    try {
      const res = await messagesApi.searchMessages(room.id, q);
      setSearchResults(res.data as Message[]);
    } catch {
      setSearchResults([]);
    } finally {
      setSearchBusy(false);
    }
  };

  const jumpToMessage = (m: Message) => {
    setShowSearch(false);
    setSearchQ("");
    setSearchResults([]);
    const el = msgRefs.current[m.id];
    if (el) {
      el.scrollIntoView({ behavior: "smooth", block: "center" });
      setHighlightId(m.id);
      setTimeout(() => setHighlightId((h) => (h === m.id ? null : h)), 2200);
    } else {
      toast("این پیام قدیمی است؛ کمی در گفتگو بالا برو تا بارگذاری شود", { icon: "🔎" });
    }
  };

  const startForward = async (msg: Message) => {
    setSheetMsg(null);
    setForwardAnon(false);
    setForwardMsg(msg);
    try {
      const res = await messagesApi.listRooms();
      setForwardRooms(res.data as Room[]);
    } catch {
      setForwardRooms([]);
    }
  };

  const doForward = async (target: Room) => {
    if (forwardBusy) return;
    // حالتِ گروهی: همهٔ پیام‌های انتخاب‌شده به ترتیب بازارسال می‌شوند
    if (forwardBulk) {
      const list = messages.filter((m) => selectedIds.has(m.id) && !m.is_deleted && !m.id.startsWith("tmp-"));
      if (list.length === 0) { setForwardMsg(null); setForwardBulk(false); return; }
      setForwardBusy(true);
      try {
        for (const m of list) {
          const res = await messagesApi.forward(m.id, target.id, forwardAnon);
          if (target.id === room.id) setMessages((prev) => [...prev, res.data as Message]);
        }
        toast.success(target.id === room.id ? "بازارسال شد" : "به مکالمهٔ انتخابی بازارسال شد");
        setForwardMsg(null); setForwardBulk(false); exitSelect();
      } catch {
        toast.error("بازارسال ناموفق بود");
      } finally {
        setForwardBusy(false);
      }
      return;
    }
    if (!forwardMsg) return;
    setForwardBusy(true);
    try {
      const res = await messagesApi.forward(forwardMsg.id, target.id, forwardAnon);
      // اگر مقصد همین اتاقِ باز است، پیام را فوری نمایش بده
      if (target.id === room.id) setMessages((prev) => [...prev, res.data as Message]);
      toast.success(target.id === room.id ? "بازارسال شد" : "به مکالمهٔ انتخابی بازارسال شد");
      setForwardMsg(null);
    } catch {
      toast.error("بازارسال ناموفق بود");
    } finally {
      setForwardBusy(false);
    }
  };

  // بازارسالِ بی‌نام (بدونِ مشخصاتِ فرستنده) — همان پیکرِ بازارسال با حالتِ بی‌نام
  const startForwardAnon = async (msg: Message) => {
    setSheetMsg(null);
    setForwardBulk(false);
    setForwardAnon(true);
    setForwardMsg(msg);
    try { const res = await messagesApi.listRooms(); setForwardRooms(res.data as Room[]); }
    catch { setForwardRooms([]); }
  };

  // اشتراک‌گذاری با Web Share API (fallback: کپی در کلیپ‌بورد)
  const absUrl = (u: string) => (u.startsWith("http") || typeof window === "undefined") ? u : window.location.origin + u;
  const shareMsg = async (msg: Message) => {
    setSheetMsg(null);
    const text = msg.content?.trim() || "";
    const url = msg.media_url ? absUrl(msg.media_url) : "";
    if (!text && !url) { toast("چیزی برای اشتراک‌گذاری نیست"); return; }
    const data: { title: string; text?: string; url?: string } = { title: "دیلیکس" };
    if (text) data.text = text;
    if (url) data.url = url;
    try {
      if (navigator.share) await navigator.share(data);
      else { await navigator.clipboard.writeText([text, url].filter(Boolean).join("\n")); toast.success("در کلیپ‌بورد کپی شد"); }
    } catch { /* کاربر لغو کرد */ }
  };

  // ── انتخابِ چندتایی ──────────────────────────────────────
  const enterSelect = (msg: Message) => {
    setSheetMsg(null);
    setSelectMode(true);
    setSelectedIds(new Set([msg.id]));
  };
  const exitSelect = () => { setSelectMode(false); setSelectedIds(new Set()); };
  const toggleSelect = (id: string) => setSelectedIds((prev) => {
    const next = new Set(prev);
    if (next.has(id)) next.delete(id); else next.add(id);
    return next;
  });
  const selectedMsgs = () => messages.filter((m) => selectedIds.has(m.id));
  const bulkCopy = async () => {
    const t = selectedMsgs().map((m) => m.content?.trim()).filter(Boolean).join("\n");
    if (!t) { toast("متنی برای کپی نیست"); return; }
    try { await navigator.clipboard.writeText(t); toast.success("کپی شد"); } catch { toast.error("کپی ناموفق بود"); }
    exitSelect();
  };
  const bulkShare = async () => {
    const parts = selectedMsgs().map((m) => m.content?.trim() || (m.media_url ? absUrl(m.media_url) : "")).filter(Boolean);
    const text = parts.join("\n");
    if (!text) { toast("چیزی برای اشتراک‌گذاری نیست"); return; }
    try {
      if (navigator.share) await navigator.share({ title: "دیلیکس", text });
      else { await navigator.clipboard.writeText(text); toast.success("در کلیپ‌بورد کپی شد"); }
    } catch { /* لغو */ }
    exitSelect();
  };
  const bulkDelete = async () => {
    const mine = selectedMsgs().filter((m) => m.is_mine && !m.is_deleted && !m.id.startsWith("tmp-"));
    if (mine.length === 0) { toast("فقط پیام‌های خودت حذف می‌شوند"); return; }
    if (!window.confirm(`«${mine.length}» پیام برای همه حذف شود؟`)) return;
    const ids = new Set(mine.map((m) => m.id));
    setMessages((prev) => prev.map((m) => ids.has(m.id) ? { ...m, is_deleted: true, content: "" } : m));
    exitSelect();
    await Promise.allSettled(mine.map((m) => messagesApi.remove(m.id)));
  };
  const startForwardBulk = async () => {
    if (selectedIds.size === 0) return;
    setForwardBulk(true);
    setForwardAnon(false);
    setForwardMsg({ id: "__bulk__" } as Message);
    try { const res = await messagesApi.listRooms(); setForwardRooms(res.data as Room[]); }
    catch { setForwardRooms([]); }
  };

  // ── حرکات لمسی روی حباب: فشارِ طولانی = منو، کشیدن = پاسخ/اشتراک ──
  const onMsgDown = (e: React.PointerEvent, msg: Message) => {
    if (msg.is_deleted || msg.id.startsWith("tmp-") || selectMode) return;
    if ((e.target as HTMLElement).closest("video")) return; // با کنترل‌های ویدیو تداخل نکن
    try { (e.currentTarget as HTMLElement).setPointerCapture?.(e.pointerId); } catch { /* ignore */ }
    const long = window.setTimeout(() => {
      if (!gestureRef.current) return;
      gestureRef.current.longFired = true;
      suppressClickRef.current = true;
      navigator.vibrate?.(15);
      setSwipe(null);
      setSheetMsg(msg);
    }, 450);
    gestureRef.current = { id: msg.id, x0: e.clientX, y0: e.clientY, dx: 0, moved: false, swiping: false, longFired: false, long };
  };
  const onMsgMove = (e: React.PointerEvent) => {
    const g = gestureRef.current; if (!g || g.longFired) return;
    const dx = e.clientX - g.x0, dy = e.clientY - g.y0;
    if (!g.moved && (Math.abs(dx) > 6 || Math.abs(dy) > 6)) { g.moved = true; clearTimeout(g.long); }
    if (Math.abs(dx) > Math.abs(dy) && Math.abs(dx) > 6) {
      g.swiping = true;
      g.dx = Math.max(-90, Math.min(90, dx));
      setSwipe({ id: g.id, dx: g.dx });
    }
  };
  const onMsgUp = (_e: React.PointerEvent, msg: Message) => {
    const g = gestureRef.current; if (!g) return;
    clearTimeout(g.long);
    const { dx, swiping, longFired } = g;
    gestureRef.current = null;
    setSwipe(null);
    if (longFired) return;
    if (swiping) {
      suppressClickRef.current = true;
      if (Math.abs(dx) >= 60) { if (dx > 0) startReply(msg); else shareMsg(msg); }
    }
  };
  const onMsgCancel = () => { const g = gestureRef.current; if (g) clearTimeout(g.long); gestureRef.current = null; setSwipe(null); };
  const onMsgClick = (msg: Message) => {
    if (suppressClickRef.current) { suppressClickRef.current = false; return; }
    if (msg.is_deleted || msg.id.startsWith("tmp-")) return;
    if (selectMode) { toggleSelect(msg.id); return; }
    setSheetMsg(msg);
  };

  const openMembers = async () => {
    setShowMembers(true);
    setMembersLoading(true);
    try {
      const res = await messagesApi.members(room.id);
      setMembers(res.data);
    } catch {
      toast.error("خطا در بارگذاری اعضا");
    } finally {
      setMembersLoading(false);
    }
  };

  const doAddMember = async () => {
    const eid = addTarget.trim().toUpperCase();
    if (!eid.startsWith("DLX-") || addBusy) return;
    setAddBusy(true);
    try {
      const res = await messagesApi.addMember(room.id, eid);
      if (res.data.already_member) toast("قبلاً عضو است");
      else toast.success("عضو اضافه شد");
      setAddTarget("");
      const m = await messagesApi.members(room.id);
      setMembers(m.data);
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, "افزودن ناموفق بود"));
    } finally {
      setAddBusy(false);
    }
  };

  const doLeave = async () => {
    if (!me?.earth_id) return;
    try {
      await messagesApi.removeMember(room.id, me.earth_id);
      toast.success("از گروه خارج شدی");
      setShowMembers(false);
      (onLeave ?? onBack)();
    } catch {
      toast.error("خروج ناموفق بود");
    }
  };

  const doRemoveMember = async (earthId: string) => {
    try {
      await messagesApi.removeMember(room.id, earthId);
      setMembers(prev => prev.filter(m => m.earth_id !== earthId));
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, "حذف ناموفق بود"));
    }
  };

  const dayLabel = (iso: string) => {
    const d = new Date(iso);
    const today = new Date();
    const yst = new Date(); yst.setDate(today.getDate() - 1);
    const sameDay = (a: Date, b: Date) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    if (sameDay(d, today)) return "امروز";
    if (sameDay(d, yst)) return "دیروز";
    return d.toLocaleDateString("fa-IR", { weekday: "long", day: "numeric", month: "long" });
  };
  const isNewDay = (curIso: string, prevIso?: string) => {
    if (!prevIso) return true;
    const a = new Date(curIso), b = new Date(prevIso);
    return a.getFullYear() !== b.getFullYear() || a.getMonth() !== b.getMonth() || a.getDate() !== b.getDate();
  };
  const onMessagesScroll = (e: React.UIEvent<HTMLDivElement>) => {
    const el = e.currentTarget;
    setShowScrollDown(el.scrollHeight - el.scrollTop - el.clientHeight > 320);
  };

  const partnerName = isGroup ? (room.name ?? "گروه") : (room.partner_name ?? room.name ?? "مکالمه");
  const partnerRole = room.partner_role ?? "user";
  const iAmAdmin = members.find(m => m.is_me)?.is_admin ?? room.is_admin ?? false;

  return (
    <div className="flex flex-col h-[100dvh] bg-[#0A0A0A] relative overflow-x-hidden">
      {/* Header */}
      <div className="flex items-center gap-3 px-4 py-3 bg-[rgba(10,10,10,0.95)] border-b border-white/8 safe-top">
        <button onClick={onBack} className="p-2 rounded-xl hover:bg-white/5 text-white/70">
          <ArrowRight size={20} />
        </button>
        <button
          onClick={() => isGroup
            ? openMembers()
            : (room.partner_earth_id && (window.location.href = `/u/${room.partner_earth_id}`))}
          className={`w-10 h-10 rounded-full flex items-center justify-center text-lg flex-shrink-0 ${
            isGroup ? "bg-indigo-600/30 text-indigo-300" : "bg-[#2C2C2E]"
          }`}
        >
          {isGroup ? <Users size={18} /> : (ROLE_EMOJI[partnerRole] ?? "👤")}
        </button>
        <button
          onClick={() => isGroup && openMembers()}
          className="flex-1 min-w-0 text-right"
        >
          <p className="text-white font-semibold truncate">{partnerName}</p>
          <p className="text-xs truncate">
            {presence.typing.length > 0 ? (
              <span className="text-emerald-400">
                {isGroup ? `${presence.typing[0]} در حال نوشتن…` : "در حال نوشتن…"}
              </span>
            ) : isGroup ? (
              <span className="text-white/40">{toPersianNum(room.member_count ?? members.length)} عضو</span>
            ) : presence.online ? (
              <span className="text-emerald-400">آنلاین</span>
            ) : presence.lastSeen ? (
              <span className="text-white/40">آخرین بازدید {lastSeenLabel(presence.lastSeen)}</span>
            ) : (
              <span className="text-white/40">{ROLE_LABEL[partnerRole] ?? "کاربر"}</span>
            )}
          </p>
        </button>
        {!isGroup && room.partner_earth_id && (
          <button
            onClick={() => setShowCallMenu(true)}
            className="p-2 rounded-xl hover:bg-white/5 text-white/60"
            title="تماس"
          >
            <Phone size={20} />
          </button>
        )}
        <button
          onClick={() => setShowOptions(true)}
          className={`relative p-2 rounded-xl hover:bg-white/5 ${autoTr ? "text-emerald-400" : "text-white/60"}`}
          title="گزینه‌های بیشتر"
        >
          <MoreVertical size={20} />
          {autoTr && <span className="absolute top-1.5 right-1.5 w-2 h-2 rounded-full bg-emerald-400" />}
        </button>
      </div>

      {/* Pinned banner */}
      {pins.length > 0 && (() => {
        const idx = Math.min(pinIdx, pins.length - 1);
        const p = pins[idx];
        const preview = p.is_deleted ? "حذف شد" : (p.content?.trim() || (p.media_type ? "رسانه" : "پیام"));
        return (
          <button
            onClick={() => { jumpToMessage(p); if (pins.length > 1) setPinIdx((i) => (i + 1) % pins.length); }}
            className="flex items-center gap-2 w-full px-4 py-2 bg-[#141414] border-b border-white/8 text-right active:bg-white/5"
          >
            <Pin size={15} className="text-indigo-400 shrink-0 rotate-45" />
            <div className="flex-1 min-w-0">
              <p className="text-[11px] text-indigo-300/80">
                پیام سنجاق‌شده{pins.length > 1 ? ` ${toPersianNum(idx + 1)}/${toPersianNum(pins.length)}` : ""}
              </p>
              <p className="text-xs text-white/70 truncate">{preview}</p>
            </div>
          </button>
        );
      })()}

      {/* Messages */}
      <div className="flex-1 overflow-y-auto px-4 py-4 space-y-3 relative" onScroll={onMessagesScroll} style={bgStyle(chatTheme.bg)}>
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
          messages.map((msg, i) => {
            const reactionEntries = Object.entries(msg.reactions ?? {}).filter(([, c]) => c > 0);
            const showDay = isNewDay(msg.created_at, messages[i - 1]?.created_at);
            return (
            <Fragment key={msg.id}>
            {showDay && (
              <div className="flex justify-center py-1">
                <span className="text-[11px] text-white/60 bg-black/30 px-3 py-1 rounded-full">{dayLabel(msg.created_at)}</span>
              </div>
            )}
            <div
              ref={(el) => { msgRefs.current[msg.id] = el; }}
              className={`flex flex-col ${msg.is_mine ? "items-end" : "items-start"} rounded-2xl transition ${highlightId === msg.id ? "ring-2 ring-yellow-400/70" : ""} ${selectMode && selectedIds.has(msg.id) ? "bg-indigo-500/10" : ""}`}
            >
              <div className="relative max-w-[78%]">
              {/* راهنمای کشیدن: راست=پاسخ، چپ=اشتراک */}
              {swipe?.id === msg.id && swipe.dx > 8 && (
                <div className="absolute inset-y-0 left-0 flex items-center pointer-events-none">
                  <span className="w-8 h-8 rounded-full bg-indigo-500 text-white flex items-center justify-center" style={{ opacity: Math.min(1, swipe.dx / 60) }}><Reply size={16} /></span>
                </div>
              )}
              {swipe?.id === msg.id && swipe.dx < -8 && (
                <div className="absolute inset-y-0 right-0 flex items-center pointer-events-none">
                  <span className="w-8 h-8 rounded-full bg-emerald-500 text-white flex items-center justify-center" style={{ opacity: Math.min(1, -swipe.dx / 60) }}><Share2 size={16} /></span>
                </div>
              )}
              {/* نشانهٔ انتخاب */}
              {selectMode && selectedIds.has(msg.id) && (
                <CheckCircle2 size={20} className="absolute -top-1 -right-1 z-10 text-indigo-400 bg-[#1C1C1E] rounded-full" />
              )}
              <button
                onPointerDown={(e) => onMsgDown(e, msg)}
                onPointerMove={onMsgMove}
                onPointerUp={(e) => onMsgUp(e, msg)}
                onPointerCancel={onMsgCancel}
                onClick={() => onMsgClick(msg)}
                style={{
                  ...(msg.is_mine && !msg.is_deleted ? { backgroundColor: chatTheme.accent } : {}),
                  transform: swipe?.id === msg.id ? `translateX(${swipe.dx}px)` : undefined,
                  transition: swipe?.id === msg.id ? "none" : "transform 0.18s ease",
                  touchAction: "pan-y",
                }}
                className={`w-full px-4 py-2.5 rounded-2xl text-sm leading-relaxed text-right ${
                  msg.is_deleted
                    ? "bg-white/5 text-white/30 italic"
                    : msg.is_mine
                      ? "text-white rounded-br-sm"
                      : "bg-[#2C2C2E] text-white/90 rounded-bl-sm"
                }`}
              >
                {/* sender name (group, others' messages) */}
                {isGroup && !msg.is_mine && !msg.is_deleted && (
                  <span className="block text-[11px] font-semibold text-indigo-300 mb-0.5">
                    {msg.sender_name ?? "کاربر"}
                  </span>
                )}
                {/* forwarded label */}
                {msg.is_forwarded && !msg.is_deleted && (
                  <span className={`flex items-center gap-1 text-[11px] mb-1 ${msg.is_mine ? "text-indigo-100/70" : "text-white/45"}`}>
                    <Forward size={12} />
                    {msg.forwarded_from ? `بازارسال از ${msg.forwarded_from}` : "بازارسال‌شده"}
                  </span>
                )}
                {/* reply preview */}
                {msg.reply_to && (
                  <div className={`mb-1.5 pr-2 border-r-2 rounded-sm text-xs ${
                    msg.is_mine ? "border-white/50 text-indigo-100/80" : "border-indigo-400/60 text-white/50"
                  }`}>
                    <span className="font-semibold block">{msg.reply_to.sender_name ?? "کاربر"}</span>
                    <span className="line-clamp-1">{msg.reply_to.is_deleted ? "پیام حذف شد" : msg.reply_to.content}</span>
                  </div>
                )}
                {/* media */}
                {!msg.is_deleted && msg.media_url && msg.media_type === "image" && (
                  <a href={msg.media_url} target="_blank" rel="noreferrer" onClick={(e) => { e.stopPropagation(); if (suppressClickRef.current) { e.preventDefault(); suppressClickRef.current = false; } else if (selectMode) { e.preventDefault(); toggleSelect(msg.id); } }} className="block">
                    <img src={msg.media_url} alt="" className="rounded-xl max-h-72 w-auto object-cover mb-1" />
                  </a>
                )}
                {!msg.is_deleted && msg.media_url && msg.media_type === "video" && (
                  <div onClick={(e) => e.stopPropagation()} className="mb-1">
                    <video
                      src={msg.media_url}
                      className="rounded-xl max-h-72 w-auto object-cover"
                      controls loop playsInline
                    />
                  </div>
                )}
                {!msg.is_deleted && msg.media_url && msg.media_type === "voice" && (
                  <div onClick={(e) => e.stopPropagation()} className="mb-1">
                    <VoiceBubble url={msg.media_url} mine={msg.is_mine} uploading={!!msg._uploading} />
                  </div>
                )}
                {!msg.is_deleted && msg.media_url && msg.media_type === "file" && (
                  <a
                    href={msg.media_url} target="_blank" rel="noreferrer" download={msg.media_name ?? true}
                    onClick={(e) => { e.stopPropagation(); if (suppressClickRef.current) { e.preventDefault(); suppressClickRef.current = false; } else if (selectMode) { e.preventDefault(); toggleSelect(msg.id); } }}
                    className={`flex items-center gap-2 mb-1 px-2 py-2 rounded-xl ${msg.is_mine ? "bg-white/10" : "bg-white/5"}`}
                  >
                    <FileText size={22} className="shrink-0 text-white/80" />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-[13px]">{msg.media_name ?? "فایل"}</span>
                      {msg.media_meta && <span className="block text-[10px] text-white/40">{msg.media_meta}</span>}
                    </span>
                    {msg._uploading ? <Loader2 size={16} className="animate-spin" /> : <Download size={16} className="text-white/60" />}
                  </a>
                )}
                {!msg.is_deleted && msg.location && (msg.media_type === "location" || msg.media_type === "live_location") && (
                  <LocationBubble
                    loc={msg.location}
                    mine={msg.is_mine}
                    canStop
                    onStop={() => doStopLive(msg)}
                  />
                )}
                {!msg.is_deleted && msg.media_type === "call" && (
                  <CallBubble
                    meta={msg.media_meta}
                    mine={msg.is_mine}
                    onCall={(m) => room.partner_earth_id && useCallStore.getState().startCall(room.partner_earth_id, partnerName, m)}
                  />
                )}
                {!msg.is_deleted && msg.media_type === "poll" && msg.poll && (
                  <div onClick={(e) => e.stopPropagation()} className="min-w-[13rem]">
                    <div className="flex items-center gap-1.5 mb-2">
                      <BarChart3 size={14} className={msg.is_mine ? "text-indigo-100" : "text-amber-400"} />
                      <span className="text-[11px] opacity-70">نظرسنجی{msg.poll.multiple ? " · چندگزینه‌ای" : ""}</span>
                    </div>
                    <p className="font-bold text-sm mb-2.5 leading-snug">{msg.poll.question}</p>
                    <div className="space-y-1.5">
                      {msg.poll.options.map((opt, i) => {
                        const total = msg.poll!.total_votes || 0;
                        const pct = total > 0 ? Math.round((opt.votes / total) * 100) : 0;
                        return (
                          <button
                            key={i}
                            onClick={() => votePoll(msg, i)}
                            className={`relative w-full text-right rounded-xl overflow-hidden border transition active:scale-[0.99] ${opt.voted ? (msg.is_mine ? "border-white/60" : "border-amber-400") : "border-white/10"}`}
                          >
                            <span
                              className={`absolute inset-y-0 right-0 ${msg.is_mine ? "bg-white/20" : "bg-amber-400/20"} transition-all`}
                              style={{ width: `${pct}%` }}
                            />
                            <span className="relative flex items-center gap-2 px-3 py-2">
                              {opt.voted
                                ? <CheckCircle2 size={16} className={`shrink-0 ${msg.is_mine ? "text-white" : "text-amber-400"}`} />
                                : <span className="shrink-0 w-4 h-4 rounded-full border border-white/30" />}
                              <span className="flex-1 min-w-0 truncate text-[13px]">{opt.text}</span>
                              <span className="shrink-0 text-[11px] opacity-70">{opt.votes}</span>
                            </span>
                          </button>
                        );
                      })}
                    </div>
                    <p className="text-[10px] opacity-50 mt-2">
                      {msg.poll.total_votes > 0 ? `${msg.poll.total_votes} رأی · برای رأی روی گزینه بزنید` : "هنوز رأیی ثبت نشده · برای رأی روی گزینه بزنید"}
                    </p>
                  </div>
                )}
                {(msg.is_deleted || (msg.content && msg.media_type !== "call" && msg.media_type !== "poll") || (!msg.media_url && !msg.location && msg.media_type !== "call" && msg.media_type !== "poll")) && (
                  <p>{msg.is_deleted ? "این پیام حذف شد" : msg.content}</p>
                )}
                {/* inline translation */}
                {!msg.is_deleted && trans[msg.id]?.open && (
                  <div
                    onClick={(e) => e.stopPropagation()}
                    className={`mt-1.5 pt-1.5 border-t text-right ${msg.is_mine ? "border-white/20" : "border-white/10"}`}
                  >
                    {trans[msg.id].loading ? (
                      <span className="flex items-center gap-1.5 text-[12px] text-white/50">
                        <Loader2 size={12} className="animate-spin" /> در حال ترجمه…
                      </span>
                    ) : (
                      <>
                        <span className={`flex items-center gap-1 text-[10px] mb-0.5 ${msg.is_mine ? "text-indigo-200/70" : "text-emerald-300/70"}`}>
                          <Languages size={11} /> ترجمه · {langLabel(trans[msg.id].lang ?? trLang)}
                        </span>
                        <p className="text-[13px]">{trans[msg.id].text}</p>
                        <button
                          onClick={() => closeTranslation(msg.id)}
                          className={`mt-0.5 text-[10px] ${msg.is_mine ? "text-indigo-200/60" : "text-white/40"}`}
                        >
                          نمایش اصل
                        </button>
                      </>
                    )}
                  </div>
                )}
                <div className={`flex items-center gap-1 mt-1 ${msg.is_mine ? "text-indigo-200/60" : "text-white/30"} justify-end`}>
                  {msg.is_pinned && !msg.is_deleted && <Pin size={11} className="rotate-45" />}
                  {msg.edited && !msg.is_deleted && <span className="text-[10px]">ویرایش‌شده</span>}
                  <span className="text-[10px]">{formatTime(msg.created_at)}</span>
                  {msg.is_mine && !msg.is_deleted && (
                    msg.is_read
                      ? <CheckCheck size={13} className="text-sky-300" />
                      : <Check size={13} />
                  )}
                </div>
              </button>
              </div>
              {/* action handle — reply/react/edit/forward on every message (incl. media) */}
              {!msg.is_deleted && !msg.id.startsWith("tmp-") && (
                <button
                  onClick={() => setSheetMsg(msg)}
                  className={`mt-0.5 flex items-center gap-0.5 text-[10px] text-white/35 hover:text-white/70 ${msg.is_mine ? "self-end" : "self-start"}`}
                  aria-label="گزینه‌های پیام"
                >
                  <MoreHorizontal size={14} /> گزینه‌ها
                </button>
              )}
              {/* reactions row */}
              {reactionEntries.length > 0 && (
                <div className={`flex gap-1 mt-1 flex-wrap ${msg.is_mine ? "justify-end" : "justify-start"}`}>
                  {reactionEntries.map(([emoji, count]) => (
                    <button
                      key={emoji}
                      onClick={() => doReact(msg, emoji)}
                      className={`px-2 py-0.5 rounded-full text-xs flex items-center gap-1 border ${
                        msg.my_reaction === emoji
                          ? "bg-indigo-500/25 border-indigo-400/50"
                          : "bg-white/5 border-white/10"
                      }`}
                    >
                      <span>{emoji}</span>
                      {count > 1 && <span className="text-white/60">{toPersianNum(count)}</span>}
                    </button>
                  ))}
                </div>
              )}
            </div>
            </Fragment>
            );
          })
        )}
        <div ref={bottomRef} />
      </div>

      {/* scroll-to-bottom */}
      {showScrollDown && (
        <button
          onClick={() => { bottomRef.current?.scrollIntoView({ behavior: "smooth" }); setShowScrollDown(false); }}
          className="absolute bottom-24 left-4 z-30 w-11 h-11 rounded-full bg-[#2C2C2E] border border-white/10 shadow-lg flex items-center justify-center text-white/80 hover:bg-[#3A3A3C]"
          aria-label="پرش به آخرین پیام"
        >
          <ChevronDown size={22} />
        </button>
      )}

      {/* Select-mode action bar */}
      {selectMode && (
        <div className="fixed top-0 inset-x-0 z-[60] bg-[#1C1C1E] border-b border-white/10 px-3 py-2.5 flex items-center gap-1">
          <button onClick={exitSelect} className="p-2 rounded-lg hover:bg-white/5 text-white/80" aria-label="بستن">
            <X size={20} />
          </button>
          <span className="text-white text-sm font-semibold flex-1 px-1">{toPersianNum(selectedIds.size)} انتخاب‌شده</span>
          <button onClick={startForwardBulk} disabled={selectedIds.size === 0} className="p-2 rounded-lg hover:bg-white/5 text-white/80 disabled:opacity-30" aria-label="بازارسال"><Forward size={19} /></button>
          <button onClick={bulkShare} disabled={selectedIds.size === 0} className="p-2 rounded-lg hover:bg-white/5 text-white/80 disabled:opacity-30" aria-label="اشتراک‌گذاری"><Share2 size={19} /></button>
          <button onClick={bulkCopy} disabled={selectedIds.size === 0} className="p-2 rounded-lg hover:bg-white/5 text-white/80 disabled:opacity-30" aria-label="کپی"><Copy size={19} /></button>
          <button onClick={bulkDelete} disabled={selectedIds.size === 0} className="p-2 rounded-lg hover:bg-white/5 text-rose-400 disabled:opacity-30" aria-label="حذف"><Trash2 size={19} /></button>
        </div>
      )}

      {/* Action sheet (react / reply / edit / delete) */}
      {sheetMsg && (
        <div
          className="fixed inset-0 z-50 flex items-end justify-center bg-black/50"
          onClick={() => setSheetMsg(null)}
        >
          <div
            className="w-full max-w-md bg-[#1C1C1E] rounded-t-3xl p-4 pb-safe animate-[slideUp_0.2s_ease]"
            onClick={(e) => e.stopPropagation()}
          >
            {/* emoji reactions */}
            <div className="flex justify-between gap-1 mb-4 px-1">
              {REACTION_EMOJIS.map((emoji) => (
                <button
                  key={emoji}
                  onClick={() => doReact(sheetMsg, emoji)}
                  className={`text-2xl w-10 h-10 rounded-full flex items-center justify-center transition-transform active:scale-125 ${
                    sheetMsg.my_reaction === emoji ? "bg-indigo-500/25" : "hover:bg-white/5"
                  }`}
                >
                  {emoji}
                </button>
              ))}
            </div>
            <div className="space-y-1">
              <button
                onClick={() => startReply(sheetMsg)}
                className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
              >
                <Reply size={18} className="text-white/60" /> پاسخ
              </button>
              <button
                onClick={() => startForward(sheetMsg)}
                className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
              >
                <Forward size={18} className="text-white/60" /> بازارسال
              </button>
              <button
                onClick={() => startForwardAnon(sheetMsg)}
                className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
              >
                <Forward size={18} className="text-white/40" /> بازارسال بدون مشخصات
              </button>
              <button
                onClick={() => shareMsg(sheetMsg)}
                className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
              >
                <Share2 size={18} className="text-white/60" /> اشتراک‌گذاری
              </button>
              <button
                onClick={() => enterSelect(sheetMsg)}
                className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
              >
                <ListChecks size={18} className="text-white/60" /> انتخاب
              </button>
              {!sheetMsg.is_deleted && (
                <button
                  onClick={() => togglePin(sheetMsg)}
                  className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
                >
                  {sheetMsg.is_pinned
                    ? <><PinOff size={18} className="text-white/60" /> برداشتن سنجاق</>
                    : <><Pin size={18} className="text-indigo-400" /> سنجاق کردن</>}
                </button>
              )}
              {!!sheetMsg.sticker_id && (
                <>
                  <button
                    onClick={() => starSticker(sheetMsg.sticker_id!)}
                    className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
                  >
                    <Star size={18} className="text-amber-400" /> ذخیره در ستاره‌دارها
                  </button>
                  <button
                    onClick={() => exploreStickerLibrary(sheetMsg.sticker_id!)}
                    className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
                  >
                    <Compass size={18} className="text-fuchsia-400" /> کاوشِ کتابخانهٔ این استیکر
                  </button>
                </>
              )}
              {!!sheetMsg.content?.trim() && (
                <button
                  onClick={() => copyText(sheetMsg)}
                  className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
                >
                  <Copy size={18} className="text-white/60" /> کپیِ متن
                </button>
              )}
              {!!sheetMsg.content?.trim() && (
                trans[sheetMsg.id]?.open ? (
                  <button
                    onClick={() => { closeTranslation(sheetMsg.id); setSheetMsg(null); }}
                    className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
                  >
                    <Languages size={18} className="text-emerald-400" /> نمایشِ اصل
                  </button>
                ) : (
                  <div className="px-4 py-2">
                    <p className="flex items-center gap-2 text-white/60 text-xs mb-2">
                      <Languages size={16} className="text-emerald-400" /> ترجمه به:
                    </p>
                    <div className="flex gap-1.5 overflow-x-auto pb-1 -mx-1 px-1">
                      {TRANSLATE_LANGS.map((l) => (
                        <button
                          key={l.code}
                          onClick={() => translateTo(sheetMsg, l.code)}
                          className={`shrink-0 flex items-center gap-1.5 px-3 py-2 rounded-xl text-xs border ${
                            trLang === l.code
                              ? "bg-emerald-500/15 border-emerald-400/40 text-white"
                              : "bg-white/5 border-white/8 text-white/80 hover:bg-white/10"
                          }`}
                        >
                          <span className="text-base">{l.flag}</span>
                          <span>{l.label}</span>
                        </button>
                      ))}
                    </div>
                  </div>
                )
              )}
              {sheetMsg.is_mine && (
                <>
                  {(!sheetMsg.media_type || ["image", "video", "file", "voice"].includes(sheetMsg.media_type)) && (
                    <button
                      onClick={() => startEdit(sheetMsg)}
                      className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
                    >
                      <Pencil size={18} className="text-white/60" /> {sheetMsg.media_type ? "ویرایشِ متن/کپشن" : "ویرایش"}
                    </button>
                  )}
                  <button
                    onClick={() => doDelete(sheetMsg)}
                    className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-red-400 text-sm text-right"
                  >
                    <Trash2 size={18} /> حذف برای همه
                  </button>
                </>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Forward picker */}
      {forwardMsg && (
        <div
          className="fixed inset-0 z-[55] flex items-end justify-center bg-black/50"
          onClick={() => { if (!forwardBusy) { setForwardMsg(null); setForwardBulk(false); } }}
        >
          <div
            className="w-full max-w-md bg-[#1C1C1E] rounded-t-3xl p-4 pb-safe max-h-[80vh] overflow-y-auto animate-[slideUp_0.2s_ease]"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between mb-3">
              <p className="text-white font-bold flex items-center gap-2">
                <Forward size={18} className="text-indigo-400" /> {forwardBulk ? `بازارسالِ ${toPersianNum(selectedIds.size)} پیام به…` : "بازارسال به…"}
              </p>
              <button onClick={() => { if (!forwardBusy) { setForwardMsg(null); setForwardBulk(false); } }} className="p-1.5 rounded-lg hover:bg-white/5 text-white/50">
                <X size={18} />
              </button>
            </div>
            {/* attribution toggle */}
            <div className="flex gap-2 mb-3 bg-white/5 rounded-xl p-0.5 text-xs">
              <button onClick={() => setForwardAnon(false)} className={`flex-1 py-2 rounded-lg transition ${!forwardAnon ? "bg-indigo-600 text-white" : "text-white/60"}`}>با نامِ فرستنده</button>
              <button onClick={() => setForwardAnon(true)} className={`flex-1 py-2 rounded-lg transition ${forwardAnon ? "bg-indigo-600 text-white" : "text-white/60"}`}>بی‌نام</button>
            </div>
            {forwardRooms.length === 0 ? (
              <p className="text-white/40 text-sm text-center py-6">مکالمه‌ای برای بازارسال نداری</p>
            ) : (
              <div className="space-y-1">
                {forwardRooms.map((r) => {
                  const rn = r.type === "group" ? (r.name ?? "گروه") : (r.partner_name ?? r.name ?? "مکالمه");
                  return (
                    <button
                      key={r.id}
                      disabled={forwardBusy}
                      onClick={() => doForward(r)}
                      className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl hover:bg-white/5 disabled:opacity-50 text-right"
                    >
                      <span className="w-9 h-9 rounded-full bg-indigo-500/20 flex items-center justify-center text-indigo-300 shrink-0 overflow-hidden">
                        {r.type === "group"
                          ? <Users size={16} />
                          : r.partner_avatar
                            ? <img src={r.partner_avatar} className="w-full h-full rounded-full object-cover" alt="" />
                            : <span className="text-sm">{rn.charAt(0)}</span>}
                      </span>
                      <span className="min-w-0 flex-1 block truncate text-white text-sm">{rn}</span>
                    </button>
                  );
                })}
              </div>
            )}
          </div>
        </div>
      )}

      {/* Members panel (group) */}
      {showMembers && (
        <div
          className="fixed inset-0 z-50 flex items-end justify-center bg-black/50"
          onClick={() => setShowMembers(false)}
        >
          <div
            className="w-full max-w-md bg-[#1C1C1E] rounded-t-3xl p-4 pb-safe max-h-[80vh] overflow-y-auto"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between mb-3">
              <p className="text-white font-bold">اعضای «{room.name ?? "گروه"}»</p>
              <button onClick={() => setShowMembers(false)} className="p-1.5 rounded-lg hover:bg-white/5 text-white/50">
                <X size={18} />
              </button>
            </div>

            {/* add member */}
            <div className="flex gap-2 mb-4">
              <input
                value={addTarget}
                onChange={(e) => setAddTarget(e.target.value.toUpperCase())}
                placeholder="DLX-XXXXXXXX"
                dir="ltr"
                className="flex-1 bg-[#262626] border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white placeholder-white/30 focus:outline-none focus:border-indigo-500 font-mono"
              />
              <button
                onClick={doAddMember}
                disabled={!addTarget.startsWith("DLX-") || addBusy}
                className="px-4 rounded-xl bg-indigo-600 text-white text-sm font-medium disabled:opacity-40 flex items-center gap-1"
              >
                {addBusy ? <Loader2 size={16} className="animate-spin" /> : <><UserPlus size={16} /> افزودن</>}
              </button>
            </div>

            {membersLoading ? (
              <div className="flex justify-center py-6"><Loader2 size={24} className="text-indigo-400 animate-spin" /></div>
            ) : (
              <div className="space-y-1">
                {members.map((m) => (
                  <div key={m.earth_id} className="flex items-center gap-3 p-2.5 rounded-xl">
                    <div className="w-10 h-10 rounded-full bg-[#2C2C2E] flex items-center justify-center text-lg flex-shrink-0">
                      {m.avatar_url ? <img src={m.avatar_url} className="w-full h-full object-cover rounded-full" alt="" /> : (ROLE_EMOJI[m.role ?? "user"] ?? "👤")}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm text-white truncate flex items-center gap-1">
                        {m.is_me ? "شما" : (m.name ?? m.earth_id)}
                        {m.is_admin && <Crown size={13} className="text-amber-400" />}
                      </p>
                      <p className="text-[11px] text-white/40 font-mono" dir="ltr">{m.earth_id}</p>
                    </div>
                    {iAmAdmin && !m.is_me && (
                      <button
                        onClick={() => doRemoveMember(m.earth_id)}
                        className="p-2 rounded-lg hover:bg-white/5 text-red-400/70"
                        title="حذف از گروه"
                      >
                        <Trash2 size={16} />
                      </button>
                    )}
                  </div>
                ))}
              </div>
            )}

            <button
              onClick={doLeave}
              className="w-full mt-4 flex items-center justify-center gap-2 px-4 py-3 rounded-xl bg-red-500/10 text-red-400 text-sm font-medium hover:bg-red-500/20"
            >
              <LogOut size={16} /> خروج از گروه
            </button>
          </div>
        </div>
      )}

      {/* Translation settings */}
      {showLangMenu && (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/50" onClick={() => setShowLangMenu(false)}>
          <div className="w-full max-w-md bg-[#1C1C1E] rounded-t-3xl p-4 pb-safe max-h-[80vh] overflow-y-auto animate-[slideUp_0.2s_ease]" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-1">
              <p className="text-white font-bold flex items-center gap-2"><Languages size={18} className="text-emerald-400" /> ترجمهٔ همزمان</p>
              <button onClick={() => setShowLangMenu(false)} className="p-1.5 rounded-lg hover:bg-white/5 text-white/50"><X size={18} /></button>
            </div>
            <p className="text-white/40 text-xs mb-3">پیام‌ها را با یک تپ به زبانِ دلخواه ترجمه کن؛ یا ترجمهٔ خودکارِ پیام‌های دریافتی را روشن کن.</p>

            {/* auto toggle */}
            <button
              onClick={toggleAuto}
              className="w-full flex items-center justify-between gap-3 px-4 py-3 rounded-xl bg-white/5 mb-4"
            >
              <span className="flex items-center gap-2 text-sm text-white">
                <Radio size={16} className={autoTr ? "text-emerald-400" : "text-white/40"} />
                ترجمهٔ خودکارِ پیام‌های دریافتی
              </span>
              <span className={`w-11 h-6 rounded-full flex items-center px-0.5 transition-colors ${autoTr ? "bg-emerald-500 justify-end" : "bg-white/15 justify-start"}`}>
                <span className="w-5 h-5 rounded-full bg-white" />
              </span>
            </button>

            <p className="text-white/40 text-xs mb-2 px-1">زبانِ مقصد</p>
            <div className="grid grid-cols-2 gap-1.5">
              {TRANSLATE_LANGS.map((l) => (
                <button
                  key={l.code}
                  onClick={() => pickLang(l.code)}
                  className={`flex items-center gap-2 px-3 py-2.5 rounded-xl text-sm text-right border ${
                    trLang === l.code
                      ? "bg-emerald-500/15 border-emerald-400/40 text-white"
                      : "bg-white/5 border-white/8 text-white/80 hover:bg-white/10"
                  }`}
                >
                  <span className="text-lg">{l.flag}</span>
                  <span className="flex-1">{l.label}</span>
                  {trLang === l.code && <Check size={15} className="text-emerald-400" />}
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Reply / Edit banner */}
      {(replyTo || editing) && (
        <div className="px-3 py-2 border-t border-white/8 bg-[#141414] flex items-center gap-2">
          <div className={`w-1 self-stretch rounded-full ${editing ? "bg-amber-400" : "bg-indigo-400"}`} />
          <div className="flex-1 min-w-0">
            <p className={`text-xs font-semibold ${editing ? "text-amber-400" : "text-indigo-400"}`}>
              {editing ? "ویرایش پیام" : `پاسخ به ${replyTo?.sender_name ?? "کاربر"}`}
            </p>
            <p className="text-xs text-white/50 truncate">{(editing ?? replyTo)?.content}</p>
          </div>
          <button
            onClick={() => { setReplyTo(null); setEditing(null); setText(""); }}
            className="p-1.5 rounded-lg hover:bg-white/5 text-white/50"
          >
            <X size={16} />
          </button>
        </div>
      )}

      {/* Call menu — dropdown anchored under the header call button (WhatsApp-style) */}
      {showCallMenu && !isGroup && room.partner_earth_id && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setShowCallMenu(false)} />
          <div className="fixed top-14 left-2 z-50 w-52 bg-[#2A2A2E] rounded-2xl shadow-2xl ring-1 ring-white/10 py-1.5 animate-[slideUp_0.14s_ease] overflow-hidden">
            <button
              onClick={() => { setShowCallMenu(false); useCallStore.getState().startCall(room.partner_earth_id!, partnerName, "audio"); }}
              className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-white text-[13px] text-right"
            >
              <Phone size={17} className="text-emerald-400 shrink-0" /> تماس صوتی
            </button>
            <button
              onClick={() => { setShowCallMenu(false); useCallStore.getState().startCall(room.partner_earth_id!, partnerName, "video"); }}
              className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-white text-[13px] text-right"
            >
              <Video size={17} className="text-indigo-400 shrink-0" /> تماس تصویری
            </button>
          </div>
        </>
      )}

      {/* Options menu — dropdown anchored under the three-dot button (WhatsApp-style) */}
      {showOptions && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setShowOptions(false)} />
          <div className="fixed top-14 left-2 z-50 w-56 bg-[#2A2A2E] rounded-2xl shadow-2xl ring-1 ring-white/10 py-1.5 animate-[slideUp_0.14s_ease] overflow-hidden max-h-[80vh] overflow-y-auto">
            {!isGroup && room.partner_earth_id && (
              <button
                onClick={() => { setShowOptions(false); window.location.href = `/u/${room.partner_earth_id}`; }}
                className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-white text-[13px] text-right"
              >
                <Users size={17} className="text-sky-400 shrink-0" /> مشاهدهٔ مخاطب
              </button>
            )}
            {isGroup && (
              <button
                onClick={() => { setShowOptions(false); openMembers(); }}
                className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-white text-[13px] text-right"
              >
                <Users size={17} className="text-sky-400 shrink-0" /> اعضای گروه
              </button>
            )}
            <button
              onClick={() => { setShowOptions(false); setShowSearch(true); setSearchQ(""); setSearchResults([]); }}
              className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-white text-[13px] text-right"
            >
              <Search size={17} className="text-white/70 shrink-0" /> جستجو در گفتگو
            </button>
            <button
              onClick={() => { setShowOptions(false); setShowLangMenu(true); }}
              className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-white text-[13px] text-right"
            >
              <Languages size={17} className="text-emerald-400 shrink-0" /> ترجمهٔ همزمان
              {autoTr && <span className="mr-auto text-[10px] text-emerald-400">روشن</span>}
            </button>
            <button
              onClick={() => { setShowOptions(false); setShowChatSettings(true); }}
              className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-white text-[13px] text-right"
            >
              <Palette size={17} className="text-fuchsia-400 shrink-0" /> شخصی‌سازیِ چت
            </button>
            <button
              onClick={exportChat}
              className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-white text-[13px] text-right"
            >
              <Download size={17} className="text-amber-400 shrink-0" /> صادر کردنِ گفتگو
            </button>
            <button
              onClick={() => toggleMute()}
              className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-white text-[13px] text-right"
            >
              {isMuted
                ? <><Bell size={17} className="text-white/70 shrink-0" /> روشن کردنِ اعلان</>
                : <><BellOff size={17} className="text-white/70 shrink-0" /> بی‌صدا کردنِ اعلان</>}
            </button>
            <div className="my-1 border-t border-white/8" />
            <button
              onClick={doClearChat}
              className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-white text-[13px] text-right"
            >
              <Trash2 size={17} className="text-white/70 shrink-0" /> پاک کردنِ گفتگو
            </button>
            {!isGroup && room.partner_earth_id && (
              <button
                onClick={toggleBlock}
                className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-[13px] text-right text-rose-400"
              >
                <Ban size={17} className="shrink-0" /> {isBlocked ? "رفعِ مسدودی" : "مسدود کردنِ مخاطب"}
              </button>
            )}
          </div>
        </>
      )}

      {/* Attach menu */}
      {showAttach && (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/50" onClick={() => setShowAttach(false)}>
          <div className="w-full max-w-md bg-[#1C1C1E] rounded-t-3xl p-4 pb-safe animate-[slideUp_0.2s_ease]" onClick={(e) => e.stopPropagation()}>
            <div className="grid grid-cols-4 gap-3 justify-items-center">
              <button
                onClick={() => { setShowAttach(false); setShowCamera(true); }}
                title="دوربین"
                className="w-14 h-14 rounded-full bg-indigo-500/15 flex items-center justify-center active:scale-95 transition"
              >
                <Camera size={24} className="text-indigo-400" />
              </button>
              <button
                onClick={() => { setShowAttach(false); fileInputRef.current?.click(); }}
                title="عکس یا فایل"
                className="w-14 h-14 rounded-full bg-sky-500/15 flex items-center justify-center active:scale-95 transition"
              >
                <ImageIcon size={24} className="text-sky-400" />
              </button>
              <button
                onClick={shareStaticLocation}
                title="موقعیتِ مکانی"
                className="w-14 h-14 rounded-full bg-red-500/15 flex items-center justify-center active:scale-95 transition"
              >
                <MapPin size={24} className="text-red-400" />
              </button>
              <button
                onClick={() => { setShowAttach(false); setShowLiveDur(true); }}
                title="موقعیتِ زندهٔ لحظه‌ای"
                className="w-14 h-14 rounded-full bg-emerald-500/15 flex items-center justify-center active:scale-95 transition"
              >
                <Radio size={24} className="text-emerald-400" />
              </button>
              <button
                onClick={() => { setShowAttach(false); openPollCreate(); }}
                title="نظرسنجی"
                className="w-14 h-14 rounded-full bg-amber-500/15 flex items-center justify-center active:scale-95 transition"
              >
                <BarChart3 size={24} className="text-amber-400" />
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Poll creation sheet */}
      {showPollCreate && (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/50" onClick={() => setShowPollCreate(false)}>
          <div className="w-full max-w-md bg-[#1C1C1E] rounded-t-3xl p-4 pb-safe animate-[slideUp_0.2s_ease] max-h-[85vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center gap-2 mb-3">
              <BarChart3 size={20} className="text-amber-400" />
              <p className="text-white font-bold">نظرسنجیِ جدید</p>
            </div>
            <label className="block text-white/40 text-xs mb-1">سؤال</label>
            <input
              value={pollQuestion}
              onChange={(e) => setPollQuestion(e.target.value)}
              maxLength={300}
              placeholder="سؤالِ خود را بنویسید…"
              className="w-full bg-[#0A0A0A] border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white outline-none focus:border-amber-500/50 mb-3"
            />
            <label className="block text-white/40 text-xs mb-1">گزینه‌ها</label>
            <div className="space-y-2 mb-3">
              {pollOptions.map((opt, i) => (
                <div key={i} className="flex items-center gap-2">
                  <input
                    value={opt}
                    onChange={(e) => setPollOptions((prev) => prev.map((o, j) => j === i ? e.target.value : o))}
                    maxLength={100}
                    placeholder={`گزینهٔ ${i + 1}`}
                    className="flex-1 min-w-0 bg-[#0A0A0A] border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white outline-none focus:border-amber-500/50"
                  />
                  {pollOptions.length > 2 && (
                    <button
                      onClick={() => setPollOptions((prev) => prev.filter((_, j) => j !== i))}
                      className="p-2 rounded-lg text-white/40 hover:text-red-400 hover:bg-white/5 shrink-0"
                    >
                      <X size={18} />
                    </button>
                  )}
                </div>
              ))}
            </div>
            {pollOptions.length < 12 && (
              <button
                onClick={() => setPollOptions((prev) => [...prev, ""])}
                className="flex items-center gap-2 text-amber-400 text-sm mb-4 px-1"
              >
                <PlusCircle size={18} /> افزودنِ گزینه
              </button>
            )}
            <button
              onClick={() => setPollMultiple((v) => !v)}
              className="w-full flex items-center justify-between px-3 py-2.5 rounded-xl bg-[#0A0A0A] mb-4"
            >
              <span className="text-white text-sm">اجازهٔ انتخابِ چند گزینه</span>
              <span className={`w-10 h-6 rounded-full flex items-center transition ${pollMultiple ? "bg-amber-500 justify-end" : "bg-white/15 justify-start"} p-0.5`}>
                <span className="w-5 h-5 rounded-full bg-white" />
              </span>
            </button>
            <button
              onClick={submitPoll}
              disabled={pollSending || !pollQuestion.trim() || pollOptions.filter((o) => o.trim()).length < 2}
              className="w-full py-3 rounded-xl bg-amber-500 text-black font-bold text-sm disabled:opacity-40 active:scale-[0.99] transition"
            >
              {pollSending ? "در حال ارسال…" : "ایجادِ نظرسنجی"}
            </button>
          </div>
        </div>
      )}

      {/* Live-location duration picker */}
      {showLiveDur && (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/50" onClick={() => setShowLiveDur(false)}>
          <div className="w-full max-w-md bg-[#1C1C1E] rounded-t-3xl p-4 pb-safe animate-[slideUp_0.2s_ease]" onClick={(e) => e.stopPropagation()}>
            <p className="text-white font-bold mb-1">اشتراکِ موقعیتِ زنده</p>
            <p className="text-white/40 text-xs mb-3">موقعیتِ لحظه‌ایِ شما تا پایانِ مدت با این گفتگو به‌روز می‌شود.</p>
            <div className="space-y-1">
              {[{ m: 15, t: "۱۵ دقیقه" }, { m: 60, t: "۱ ساعت" }, { m: 480, t: "۸ ساعت" }].map((o) => (
                <button
                  key={o.m}
                  onClick={() => shareLiveLocation(o.m)}
                  className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
                >
                  <Radio size={18} className="text-emerald-400" /> {o.t}
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Chat personalization */}
      {showChatSettings && (
        <ChatSettingsSheet theme={chatTheme} onChange={applyTheme} onClose={() => setShowChatSettings(false)} />
      )}

      {/* In-chat message search */}
      {showSearch && (
        <div className="fixed inset-0 z-[55] flex flex-col bg-[#0A0A0A]">
          <div className="flex items-center gap-2 px-3 py-3 border-b border-white/8 safe-top">
            <button onClick={() => setShowSearch(false)} className="p-2 rounded-xl hover:bg-white/5 text-white/70">
              <ArrowRight size={20} />
            </button>
            <div className="flex-1 flex items-center gap-2 bg-white/5 rounded-xl px-3">
              <Search size={16} className="text-white/40" />
              <input
                autoFocus
                value={searchQ}
                onChange={(e) => setSearchQ(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && runSearch()}
                placeholder="جستجو در این گفتگو…"
                className="flex-1 bg-transparent py-2.5 text-white text-sm outline-none placeholder:text-white/30"
              />
              {searchQ && (
                <button onClick={() => { setSearchQ(""); setSearchResults([]); }} className="text-white/40 hover:text-white/70"><X size={16} /></button>
              )}
            </div>
            <button onClick={runSearch} className="px-3 py-2 rounded-xl bg-indigo-600 text-white text-sm">جستجو</button>
          </div>
          <div className="flex-1 overflow-y-auto">
            {searchBusy ? (
              <div className="flex justify-center pt-10"><Loader2 size={26} className="text-indigo-400 animate-spin" /></div>
            ) : searchQ.trim().length < 2 ? (
              <p className="text-white/30 text-sm text-center pt-10">حداقل ۲ حرف بنویس</p>
            ) : searchResults.length === 0 ? (
              <p className="text-white/30 text-sm text-center pt-10">نتیجه‌ای پیدا نشد</p>
            ) : (
              <div className="divide-y divide-white/5">
                {searchResults.map((m) => (
                  <button
                    key={m.id}
                    onClick={() => jumpToMessage(m)}
                    className="w-full text-right px-4 py-3 hover:bg-white/5"
                  >
                    <div className="flex items-center justify-between mb-1">
                      <span className="text-indigo-300 text-xs font-medium truncate">{m.is_mine ? "شما" : (m.sender_name ?? "کاربر")}</span>
                      <span className="text-white/30 text-[11px]">{new Date(m.created_at).toLocaleDateString("fa-IR")}</span>
                    </div>
                    <p className="text-white/80 text-sm line-clamp-2">{m.content}</p>
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>
      )}

      {/* In-app camera (front/back) → editor */}
      {showCamera && (
        <CameraCapture
          onClose={() => setShowCamera(false)}
          onCapture={(file, kind) => { setShowCamera(false); setEditorMedia({ file, kind }); }}
        />
      )}

      {/* Media editor / compressor (photo & video) */}
      {editorMedia && (
        <MediaEditor
          file={editorMedia.file}
          kind={editorMedia.kind}
          onCancel={() => setEditorMedia(null)}
          onDone={(file) => {
            const kind = editorMedia.kind;
            setEditorMedia(null);
            uploadMedia(file, kind, file.name);
          }}
        />
      )}

      {/* Custom sticker / emoji studio */}
      {showStudio && (
        <StickerStudio
          onClose={() => setShowStudio(false)}
          onSend={(file, kind) => { setShowStudio(false); uploadMedia(file, kind, file.name); }}
        />
      )}

      {/* Sticker / emoji library */}
      {showLibrary && (
        <StickerLibrary
          initialPackId={libraryPackId}
          onClose={() => { setShowLibrary(false); setLibraryPackId(null); }}
          onSendSticker={(stickerId) => { setShowLibrary(false); setLibraryPackId(null); sendSticker(stickerId); }}
        />
      )}

      {/* Emoji picker */}
      {showEmoji && !recording && (
        <div className="fixed inset-0 z-40" onClick={() => setShowEmoji(false)}>
          <div
            className="absolute inset-x-0 bottom-0 mx-auto w-full max-w-md bg-[#141414] border-t border-white/8 rounded-t-2xl p-3 pb-safe animate-[slideUp_0.15s_ease]"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between mb-2 px-1">
              <div className="flex gap-1 bg-white/5 rounded-xl p-0.5 text-xs">
                <button
                  onClick={() => setEmojiTab("emoji")}
                  className={`px-3 py-1 rounded-lg transition ${emojiTab === "emoji" ? "bg-indigo-600 text-white" : "text-white/60"}`}
                >
                  ایموجی
                </button>
                <button
                  onClick={() => setEmojiTab("sticker")}
                  className={`px-3 py-1 rounded-lg transition ${emojiTab === "sticker" ? "bg-indigo-600 text-white" : "text-white/60"}`}
                >
                  استیکر
                </button>
              </div>
              <button onClick={() => setShowEmoji(false)} className="p-1 rounded-lg text-white/50 hover:bg-white/5"><X size={16} /></button>
            </div>
            {emojiTab === "emoji" ? (
              <div className="grid grid-cols-8 gap-1 max-h-56 overflow-y-auto">
                {COMPOSE_EMOJIS.map((emo, i) => (
                  <button
                    key={`${emo}-${i}`}
                    onClick={() => insertEmoji(emo)}
                    className="h-9 rounded-lg text-xl hover:bg-white/5 flex items-center justify-center"
                  >
                    {emo}
                  </button>
                ))}
              </div>
            ) : (
              <div className="max-h-56 overflow-y-auto space-y-2 py-1">
                <button
                  onClick={() => { setShowEmoji(false); setLibraryPackId(null); setShowLibrary(true); }}
                  className="w-full flex items-center gap-3 px-3 py-3 rounded-xl bg-white/5 hover:bg-white/10 text-white text-sm text-right"
                >
                  <span className="w-9 h-9 rounded-full bg-amber-500/15 flex items-center justify-center"><Star size={18} className="text-amber-400" /></span>
                  <span className="flex-1">کتابخانهٔ استیکر و ایموجی</span>
                </button>
                <button
                  onClick={() => { setShowEmoji(false); setShowStudio(true); }}
                  className="w-full flex items-center gap-3 px-3 py-3 rounded-xl bg-white/5 hover:bg-white/10 text-white text-sm text-right"
                >
                  <span className="w-9 h-9 rounded-full bg-fuchsia-500/15 flex items-center justify-center"><Sticker size={18} className="text-fuchsia-400" /></span>
                  <span className="flex-1">ساختِ استیکر / ایموجیِ اختصاصی</span>
                </button>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Input */}
      <div className="px-3 py-3 border-t border-white/8 bg-[#0A0A0A] pb-safe">
        <input ref={fileInputRef} type="file" hidden onChange={onPickFile} />
        <input ref={camInputRef} type="file" accept="image/*" capture="environment" hidden onChange={onPickFile} />
        {recording ? (
          <div className="flex items-center gap-3">
            <button
              onClick={() => stopRec(true)}
              className="w-11 h-11 rounded-2xl bg-white/5 flex items-center justify-center text-white/60 hover:bg-white/10 flex-shrink-0"
              title="لغو"
            >
              <Trash2 size={18} />
            </button>
            <div className="flex-1 flex items-center gap-2 text-red-400">
              <span className="w-2.5 h-2.5 rounded-full bg-red-500 animate-pulse" />
              <span className="text-sm font-mono">{toPersianNum(`${Math.floor(recSeconds / 60)}:${(recSeconds % 60).toString().padStart(2, "0")}`)}</span>
              <span className="text-xs text-white/40">در حال ضبط…</span>
            </div>
            <button
              onClick={() => stopRec(false)}
              className="w-11 h-11 rounded-2xl bg-indigo-600 flex items-center justify-center hover:bg-indigo-500 flex-shrink-0"
              title="ارسال"
            >
              <Send size={18} className="text-white" />
            </button>
          </div>
        ) : (
          <div className="flex items-end gap-2">
            {!editing && (
              <button
                onClick={() => { setShowAttach(false); setShowEmoji((v) => !v); }}
                className={`w-11 h-11 rounded-2xl border border-white/8 flex items-center justify-center flex-shrink-0 transition-colors ${showEmoji ? "bg-indigo-500/20 text-indigo-300" : "bg-[#1C1C1E] text-white/60 hover:text-white hover:bg-white/5"}`}
                title="اموجی"
              >
                <Smile size={18} />
              </button>
            )}
            {!editing && (
              <button
                onClick={() => { setShowEmoji(false); setShowAttach(true); }}
                disabled={locBusy}
                className="w-11 h-11 rounded-2xl bg-[#1C1C1E] border border-white/8 flex items-center justify-center text-white/60 hover:text-white hover:bg-white/5 flex-shrink-0 disabled:opacity-50"
                title="پیوست"
              >
                {locBusy ? <Loader2 size={18} className="animate-spin" /> : <Paperclip size={18} />}
              </button>
            )}
            <input
              ref={inputRef}
              value={text}
              onChange={(e) => { setText(e.target.value); signalTyping(); }}
              onKeyDown={(e) => e.key === "Enter" && !e.shiftKey && (e.preventDefault(), send())}
              placeholder={editing ? "ویرایش پیام..." : "پیام..."}
              className="flex-1 min-w-0 bg-[#1C1C1E] border border-white/8 rounded-2xl px-4 py-3 text-white text-sm placeholder-white/30 focus:outline-none focus:border-indigo-500/50 resize-none"
            />
            {text.trim() && (
              <button
                onClick={translateCompose}
                disabled={composeTr}
                className="w-11 h-11 rounded-2xl bg-[#1C1C1E] border border-white/8 flex items-center justify-center text-emerald-400 hover:bg-white/5 flex-shrink-0 disabled:opacity-50"
                title={`ترجمهٔ نوشته به ${langLabel(trLang)}`}
              >
                {composeTr ? <Loader2 size={18} className="animate-spin" /> : <Languages size={18} />}
              </button>
            )}
            {text.trim() || editing ? (
              <button
                onClick={send}
                disabled={!text.trim() || sending}
                className="w-11 h-11 rounded-2xl bg-indigo-600 flex items-center justify-center disabled:opacity-40 hover:bg-indigo-500 transition-colors flex-shrink-0"
              >
                {sending
                  ? <Loader2 size={18} className="text-white animate-spin" />
                  : editing
                    ? <Check size={18} className="text-white" />
                    : <Send size={18} className="text-white" />
                }
              </button>
            ) : (
              <button
                onClick={startRec}
                className="w-11 h-11 rounded-2xl bg-indigo-600 flex items-center justify-center hover:bg-indigo-500 transition-colors flex-shrink-0"
                title="پیام صوتی"
              >
                <Mic size={18} className="text-white" />
              </button>
            )}
          </div>
        )}
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
  const [showGroup, setShowGroup] = useState(false);
  const [groupName, setGroupName] = useState("");
  const [groupMembers, setGroupMembers] = useState("");
  const [creatingGroup, setCreatingGroup] = useState(false);

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
      toast.error(getApiErrorMessage(e, "کاربر پیدا نشد"));
    } finally {
      setStarting(false);
    }
  };

  const handleCreateGroup = async () => {
    const name = groupName.trim();
    if (!name || creatingGroup) return;
    const ids = groupMembers
      .split(/[\s,،]+/)
      .map((s) => s.trim().toUpperCase())
      .filter((s) => s.startsWith("DLX-"));
    setCreatingGroup(true);
    try {
      const res = await messagesApi.createGroup(name, ids);
      const room: Room = res.data;
      await loadRooms();
      setActiveRoom(room);
      setShowGroup(false);
      setGroupName("");
      setGroupMembers("");
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, "ساخت گروه ناموفق بود"));
    } finally {
      setCreatingGroup(false);
    }
  };

  if (activeRoom) {
    return (
      <ChatView
        room={activeRoom}
        onBack={() => { setActiveRoom(null); loadRooms(); }}
        onLeave={() => { setActiveRoom(null); loadRooms(); }}
      />
    );
  }

  const filtered = rooms.filter((r) => {
    const q = search.toLowerCase();
    return (
      (r.partner_name ?? "").toLowerCase().includes(q) ||
      (r.name ?? "").toLowerCase().includes(q) ||
      (r.partner_earth_id ?? "").toLowerCase().includes(q) ||
      (r.last_message ?? "").toLowerCase().includes(q)
    );
  });

  const totalUnread = rooms.reduce((s, r) => s + r.unread_count, 0);

  return (
    <AppShell title={totalUnread > 0 ? `پیام‌ها (${toPersianNum(totalUnread)})` : "پیام‌ها"}>
      <div className="page-inner">
        {/* Stories */}
        <StoryBar />

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
            onClick={() => { setShowNew(!showNew); setShowGroup(false); }}
            aria-label="مکالمهٔ جدید"
            className={`w-10 h-10 rounded-xl flex items-center justify-center transition-colors flex-shrink-0 ${showNew ? "bg-indigo-500" : "bg-indigo-600 hover:bg-indigo-500"}`}
          >
            <MessageCircle size={18} className="text-white" />
          </button>
          <button
            onClick={() => { setShowGroup(!showGroup); setShowNew(false); }}
            aria-label="گروه جدید"
            className={`w-10 h-10 rounded-xl flex items-center justify-center transition-colors flex-shrink-0 ${showGroup ? "bg-indigo-500" : "bg-[#1C1C1E] border border-white/10 hover:bg-white/5"}`}
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

        {/* New group */}
        {showGroup && (
          <div className="mb-4 bg-[#1C1C1E] border border-white/8 rounded-xl p-4 space-y-2">
            <p className="text-white/60 text-xs">ساختِ گروه جدید</p>
            <input
              value={groupName}
              onChange={(e) => setGroupName(e.target.value)}
              placeholder="نامِ گروه"
              maxLength={200}
              className="w-full bg-[#262626] border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white placeholder-white/30 focus:outline-none focus:border-indigo-500"
            />
            <input
              value={groupMembers}
              onChange={(e) => setGroupMembers(e.target.value.toUpperCase())}
              placeholder="Earth ID اعضا (با فاصله/کاما)"
              dir="ltr"
              className="w-full bg-[#262626] border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white placeholder-white/30 focus:outline-none focus:border-indigo-500 font-mono"
            />
            <button
              onClick={handleCreateGroup}
              disabled={!groupName.trim() || creatingGroup}
              className="w-full px-4 py-2.5 rounded-xl bg-indigo-600 text-white text-sm font-medium disabled:opacity-40 hover:bg-indigo-500 transition-colors flex items-center justify-center gap-2"
            >
              {creatingGroup ? <Loader2 size={16} className="animate-spin" /> : <><Users size={16} /> ساخت گروه</>}
            </button>
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
              const isGroup = room.type === "group";
              const name = isGroup ? (room.name ?? "گروه") : (room.partner_name ?? room.name ?? "مکالمه");
              const role = room.partner_role ?? "user";
              return (
                <button
                  key={room.id}
                  onClick={() => setActiveRoom(room)}
                  className="w-full flex items-center gap-3 p-3.5 rounded-xl hover:bg-[#1C1C1E] transition-colors text-right"
                >
                  <div className={`w-12 h-12 rounded-full flex items-center justify-center text-xl flex-shrink-0 relative ${
                    isGroup ? "bg-indigo-600/30 text-indigo-300" : "bg-[#2C2C2E]"
                  }`}>
                    {isGroup
                      ? <Users size={22} />
                      : room.partner_avatar
                        ? <img src={room.partner_avatar} className="w-full h-full object-cover rounded-full" alt="" />
                        : ROLE_EMOJI[role] ?? "👤"
                    }
                    {room.unread_count > 0 && (
                      <span className="absolute -top-1 -left-1 min-w-5 h-5 px-1 bg-indigo-500 text-white text-[10px] font-bold rounded-full flex items-center justify-center">
                        {toPersianNum(room.unread_count)}
                      </span>
                    )}
                    {!isGroup && room.partner_online && (
                      <span className="absolute bottom-0 right-0 w-3.5 h-3.5 rounded-full bg-emerald-500 border-2 border-[#0A0A0A]" />
                    )}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between mb-0.5">
                      <p className="text-sm font-semibold text-white truncate flex items-center gap-1">
                        {isGroup && <Users size={13} className="text-white/40 flex-shrink-0" />}
                        {name}
                      </p>
                      <p className="text-xs text-white/30 flex-shrink-0 mr-2">{formatTime(room.last_message_at)}</p>
                    </div>
                    <p className="text-xs text-white/40 truncate">
                      {room.last_message || (isGroup ? `${toPersianNum(room.member_count ?? 0)} عضو` : "مکالمه را شروع کن")}
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
