"use client";

import { useState, useEffect, useRef, useCallback, Suspense, Fragment } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Search, MessageCircle, Send, ArrowRight, Loader2, Users, Reply, Pencil, Trash2, Check, CheckCheck, X, UserPlus, LogOut, Crown, Paperclip, Mic, FileText, Download, Play, Pause, MapPin, Radio, Image as ImageIcon, Languages, Phone, Video, PhoneMissed, Smile, Camera, Copy, Palette, Sticker, Star, Compass, Forward, MoreHorizontal, MoreVertical, ChevronDown, Pin, PinOff, BarChart3, PlusCircle, CheckCircle2, BellOff, Bell, Ban, Share2, ListChecks, Plus, UserRound, CalendarClock, Timer, Flag, CalendarPlus, Gift, Banknote, HandCoins, Package } from "lucide-react";
import AppShell from "@/components/layout/AppShell";
import { messagesApi, stickersApi, socialApi, shopApi, getApiErrorMessage} from "@/lib/api";
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
import { useTranslation } from "@/store/i18n";

const ROLE_EMOJI: Record<string, string> = {
  driver: "🚛", cargo_owner: "📦", freight_broker: "🤝",
  insurance_agent: "🛡️", creator: "📢", admin: "⚙️", user: "👤",
};
const ROLE_LABEL: Record<string, string> = {
  driver: "chat.role.driver", cargo_owner: "chat.role.cargo_owner", freight_broker: "chat.role.freight_broker",
  insurance_agent: "chat.role.insurance_agent", creator: "chat.role.creator", admin: "chat.role.admin", user: "chat.role.user",
};

// نمایشِ مبلغ: ریال → تومان (÷۱۰) با جداکنندهٔ هزارگان و ارقامِ فارسی
function fmtToman(rial: number): string {
  const toman = Math.round((rial || 0) / 10);
  return toPersianNum(toman.toLocaleString("en-US"));
}

interface ShopOrderCard {
  id: string;
  ref: string;
  title: string;
  qty: number;
  total: number;
  status: string;
  status_label: string;
  escrow_status: string;
  can_accept: boolean;
  can_ship: boolean;
  can_complete: boolean;
  can_cancel: boolean;
}

/** کارتِ سفارشِ فروشگاه درونِ گفتگو.
 *
 * پیام فقط `ref` را حمل می‌کند، نه وضعیت را؛ وضعیتِ سفارش پس از ارسالِ پیام
 * بارها عوض می‌شود، پس اگر در متنِ پیام ذخیره می‌شد همان لحظه کهنه می‌شد.
 * کارت وضعیت را زنده می‌خواند و دکمه‌ها را از `can_*`ِ سرور می‌گیرد تا قواعدِ
 * گذار دوباره در کلاینت پیاده نشوند و با سرور اختلاف پیدا نکنند. */
function OrderBubble({ orderRef, t }: { orderRef: string; t: (k: string) => string }) {
  const [o, setO] = useState<ShopOrderCard | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const { data } = await shopApi.order(orderRef);
      setO(data);
    } catch {
      setO(null);
    }
  }, [orderRef]);

  useEffect(() => { load(); }, [load]);

  async function act(kind: "accept" | "ship" | "complete" | "cancel") {
    if (!o) return;
    setBusy(true);
    try {
      const { data } = await shopApi[kind](o.id);
      setO(data);
      toast.success(t("shop.done"));
    } catch (e) {
      toast.error(getApiErrorMessage(e));
    } finally {
      setBusy(false);
    }
  }

  if (!o) {
    return (
      <div className="min-w-[13rem] rounded-2xl bg-white/5 px-3.5 py-3 text-white/60 text-[12px]">
        {t("shop.orderCard")} · <span dir="ltr">{orderRef}</span>
      </div>
    );
  }

  const dead = o.status === "cancelled";
  const done = o.status === "completed";
  return (
    <div className="min-w-[14rem] rounded-2xl overflow-hidden">
      <div className={`px-3.5 pt-3 pb-2.5 ${
        dead ? "bg-white/5"
          : done ? "bg-gradient-to-br from-emerald-500 to-teal-600"
            : "bg-gradient-to-br from-orange-500 to-amber-600"
      }`}>
        <div className="flex items-center gap-2">
          <span className="shrink-0 w-9 h-9 rounded-full bg-white/20 flex items-center justify-center">
            <Package size={18} className="text-white" />
          </span>
          <span className="flex-1 min-w-0">
            <span className="block text-white/80 text-[11px]">{t("shop.orderCard")}</span>
            <span className="block text-white font-bold text-[13px] leading-tight truncate">
              {o.title}
            </span>
          </span>
        </div>
        <div className="text-white font-black text-lg mt-1.5">
          {fmtToman(o.total)}{" "}
          <span className="text-[11px] font-bold">{t("shop.toman")}</span>
          <span className="text-white/70 text-[11px] font-normal">
            {" "}× {toPersianNum(o.qty)}
          </span>
        </div>
      </div>
      <div className="px-3.5 py-2 bg-black/25 text-[12px] space-y-2">
        <div className="flex items-center justify-between gap-2">
          <span className="text-white/70">{o.status_label}</span>
          {o.escrow_status === "locked" && (
            <span className="text-amber-300">{t("shop.escrowLocked")}</span>
          )}
        </div>
        {(o.can_accept || o.can_ship || o.can_complete || o.can_cancel) && (
          <div className="flex gap-2">
            {o.can_accept && (
              <button onClick={(e) => { e.stopPropagation(); act("accept"); }} disabled={busy}
                className="flex-1 py-1.5 rounded-lg bg-sky-500 text-white font-bold disabled:opacity-50">
                {t("shop.accept")}
              </button>
            )}
            {o.can_ship && (
              <button onClick={(e) => { e.stopPropagation(); act("ship"); }} disabled={busy}
                className="flex-1 py-1.5 rounded-lg bg-violet-500 text-white font-bold disabled:opacity-50">
                {t("shop.ship")}
              </button>
            )}
            {o.can_complete && (
              <button onClick={(e) => { e.stopPropagation(); act("complete"); }} disabled={busy}
                className="flex-1 py-1.5 rounded-lg bg-emerald-500 text-white font-bold disabled:opacity-50">
                {t("shop.complete")}
              </button>
            )}
            {o.can_cancel && (
              <button onClick={(e) => { e.stopPropagation(); act("cancel"); }} disabled={busy}
                className="px-3 py-1.5 rounded-lg bg-white/10 text-white/70 font-semibold disabled:opacity-50">
                {t("shop.cancel")}
              </button>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

function lastSeenLabel(iso: string | null | undefined, t: (k: string) => string): string {
  if (!iso) return t("chat.offline");
  const diff = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (diff < 60) return t("chat.justNow");
  if (diff < 3600) return `${toPersianNum(Math.floor(diff / 60))} ${t("chat.minAgo")}`;
  if (diff < 86400) return `${toPersianNum(Math.floor(diff / 3600))} ${t("chat.hourAgo")}`;
  const days = Math.floor(diff / 86400);
  if (days === 1) return t("chat.yesterday");
  if (days < 7) return `${toPersianNum(days)} ${t("chat.dayAgo")}`;
  try {
    return new Date(iso).toLocaleDateString("fa-IR", { month: "long", day: "numeric" });
  } catch { return t("chat.longAgo"); }
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
interface ContactData { earth_id: string; name: string; avatar_url?: string | null; }
interface EventData {
  id: string; title: string; starts_at: string;
  location?: string | null; description?: string | null;
}
interface RedPacketClaimData {
  earth_id: string; name: string; avatar_url?: string | null;
  amount: number; created_at: string;
}
interface RedPacketData {
  id: string; sender_earth_id: string; sender_name: string;
  total_amount: number; count: number; claimed_count: number; claimed_amount: number;
  mode: string; greeting?: string | null; status: string; expires_at: string;
  is_mine: boolean; my_amount?: number | null; claimed: boolean; is_exhausted: boolean;
  claims?: RedPacketClaimData[] | null;
}
// 💸 پولِ درون‌چت — `amount` مثل بقیهٔ کیف‌پول در ریال می‌آید.
interface MoneyData {
  id: string; kind: "send" | "request"; amount: number;
  note?: string | null; status: string;
  is_mine: boolean; counterpart_earth_id: string; counterpart_name: string;
  can_pay: boolean; can_cancel: boolean; settled_at?: string | null;
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
  contact?: ContactData | null;
  event?: EventData | null;
  red_packet?: RedPacketData | null;
  money?: MoneyData | null;
  is_forwarded?: boolean;
  forwarded_from?: string | null;
  is_pinned?: boolean;
  _uploading?: boolean;
}

// گزینه‌های زمانِ پیامِ ناپدیدشونده (باید با بک‌اند هماهنگ باشد)
const DISAPPEAR_OPTS: { sec: number; label: string }[] = [
  { sec: 0, label: "chat.disappear.off" },
  { sec: 3600, label: "chat.disappear.1h" },
  { sec: 86400, label: "chat.disappear.1d" },
  { sec: 604800, label: "chat.disappear.1w" },
];
const disappearLabel = (sec: number, t: (k: string) => string) =>
  t(DISAPPEAR_OPTS.find((o) => o.sec === sec)?.label ?? "chat.disappear.off");

// دلایلِ گزارشِ کاربر
const REPORT_REASONS: { key: string; label: string }[] = [
  { key: "spam", label: "chat.report.spam" },
  { key: "harassment", label: "chat.report.harassment" },
  { key: "scam", label: "chat.report.scam" },
  { key: "inappropriate", label: "chat.report.inappropriate" },
  { key: "other", label: "chat.report.other" },
];

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

const WD_KEYS = ["chat.wd.sun","chat.wd.mon","chat.wd.tue","chat.wd.wed","chat.wd.thu","chat.wd.fri","chat.wd.sat"];
function formatTime(iso: string | null, t: (k: string) => string): string {
  if (!iso) return "";
  try {
    const d = new Date(iso);
    const now = new Date();
    const diff = now.getTime() - d.getTime();
    if (diff < 86400000) return d.toLocaleTimeString("fa-IR", { hour: "2-digit", minute: "2-digit" });
    if (diff < 604800000) return t(WD_KEYS[d.getDay()]);
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

function remainingLabel(expiresAt: string | null | undefined, t: (k: string) => string): string {
  if (!expiresAt) return "";
  const ms = new Date(expiresAt).getTime() - Date.now();
  if (ms <= 0) return t("chat.ended");
  const mins = Math.round(ms / 60000);
  if (mins >= 60) return `${toPersianNum(Math.floor(mins / 60))} ${t("chat.hoursLeft")}`;
  return `${toPersianNum(Math.max(1, mins))} ${t("chat.minsLeft")}`;
}

function LocationBubble({ loc, mine, canStop, onStop }: {
  loc: LocationData; mine: boolean; canStop: boolean; onStop: () => void;
}) {
  const { t } = useTranslation();
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
            {active ? t("chat.live") : t("chat.ended")}
          </span>
        )}
      </button>
      <div className="flex items-center justify-between gap-2 mt-1">
        <span className="text-[11px] text-white/50 truncate flex items-center gap-1">
          <MapPin size={11} />
          {loc.label || (isLive ? (active ? remainingLabel(loc.expires_at, t) : t("chat.shareEnded")) : t("chat.location"))}
        </span>
        {isLive && active && mine && canStop && (
          <button onClick={onStop} className="text-[11px] text-red-400 font-medium shrink-0 px-2 py-0.5 rounded-lg bg-red-500/10">
            {t("chat.stop")}
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
  answered: "chat.call.answered", no_answer: "chat.call.noAnswer", rejected: "chat.call.rejected",
  canceled: "chat.call.canceled", missed: "chat.call.noAnswer", failed: "chat.call.failed",
};

function CallBubble({ meta, mine, onCall }: {
  meta: string | null | undefined; mine: boolean; onCall: (m: "audio" | "video") => void;
}) {
  const { t } = useTranslation();
  let media = "audio", status = "answered", duration = 0;
  try {
    const j = JSON.parse(meta || "{}");
    media = j.media === "video" ? "video" : "audio";
    status = typeof j.status === "string" ? j.status : "answered";
    duration = Number(j.duration) || 0;
  } catch { /* noop */ }
  const answered = status === "answered" && duration > 0;
  const Icon = answered ? (media === "video" ? Video : Phone) : PhoneMissed;
  const label = t(CALL_STATUS_LABEL[status] ?? "chat.call.answered");
  return (
    <button
      onClick={(e) => { e.stopPropagation(); onCall(media === "video" ? "video" : "audio"); }}
      className="flex items-center gap-2.5 py-0.5 text-right"
      title={t("chat.callAgain")}
    >
      <span className={`w-9 h-9 rounded-full flex items-center justify-center shrink-0 ${
        answered ? (mine ? "bg-white/15" : "bg-emerald-500/20") : "bg-red-500/20"
      }`}>
        <Icon size={17} className={answered ? (mine ? "text-white" : "text-emerald-400") : "text-red-400"} />
      </span>
      <span className="min-w-0">
        <span className="block text-[13px] font-medium">
          {media === "video" ? t("chat.videoCall") : t("chat.voiceCall")}
        </span>
        <span className={`block text-[11px] ${mine ? "text-white/60" : "text-white/45"}`}>
          {answered ? fmtCallDur(duration) : label}
        </span>
      </span>
    </button>
  );
}

// ── Chat View ─────────────────────────────────────────────────
function ChatView({ room, onBack, onLeave, initialDraft }: { room: Room; onBack: () => void; onLeave?: () => void; initialDraft?: string }) {
  const { t } = useTranslation();
  const isGroup = room.type === "group";
  const [showMembers, setShowMembers] = useState(false);
  const [members, setMembers] = useState<Member[]>([]);
  const [membersLoading, setMembersLoading] = useState(false);
  const [addTarget, setAddTarget] = useState("");
  const [addBusy, setAddBusy] = useState(false);
  const [messages, setMessages] = useState<Message[]>([]);
  const [loading,  setLoading]  = useState(true);
  const [text,     setText]     = useState(initialDraft ?? "");
  const [sending,  setSending]  = useState(false);
  const [replyTo,  setReplyTo]  = useState<Message | null>(null);
  const [editing,  setEditing]  = useState<Message | null>(null);
  const [sheetMsg, setSheetMsg] = useState<Message | null>(null); // action sheet target
  const [reactPicker, setReactPicker] = useState(false); // انتخابِ ایموجیِ دلخواه برای واکنش
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
  const atBottomRef = useRef(true);
  const selRef = useRef<{ start: number; end: number }>({ start: 0, end: 0 });
  const inputRef  = useRef<HTMLInputElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const camInputRef = useRef<HTMLInputElement>(null);
  const [showEmoji, setShowEmoji] = useState(false);
  const [emojiTab, setEmojiTab] = useState<"emoji" | "sticker" | "maker">("emoji");
  // اموجی‌ساز: ترکیبِ دو اموجی و ساختِ یک تصویرِ تازه (سمتِ کلاینت با Canvas)
  const [mixA, setMixA] = useState<string>("🦷");
  const [mixB, setMixB] = useState<string>("🪐");
  const [mixSlot, setMixSlot] = useState<"a" | "b">("a");
  const [mixSending, setMixSending] = useState(false);
  const mixCanvasRef = useRef<HTMLCanvasElement>(null);
  const [showCallMenu, setShowCallMenu] = useState(false);
  const [showOptions, setShowOptions] = useState(false);
  const [isMuted, setIsMuted] = useState(!!room.is_muted);
  const [isBlocked, setIsBlocked] = useState(!!room.is_blocked);
  const [showPollCreate, setShowPollCreate] = useState(false);
  const [pollQuestion, setPollQuestion] = useState("");
  const [pollOptions, setPollOptions] = useState<string[]>(["", ""]);
  const [pollMultiple, setPollMultiple] = useState(false);
  const [pollSending, setPollSending] = useState(false);
  // پیامِ ناپدیدشونده
  const [disappearSec, setDisappearSec] = useState<number>(0);
  const [showDisappear, setShowDisappear] = useState(false);
  // اشتراکِ مخاطب
  const [showContactPick, setShowContactPick] = useState(false);
  const [contactQ, setContactQ] = useState("");
  const [contactResults, setContactResults] = useState<{ earth_id: string; name: string | null; avatar_url: string | null }[]>([]);
  const [contactBusy, setContactBusy] = useState(false);
  // رویداد
  const [showEventCreate, setShowEventCreate] = useState(false);
  const [evTitle, setEvTitle] = useState("");
  const [evWhen, setEvWhen] = useState("");
  const [evLoc, setEvLoc] = useState("");
  const [evDesc, setEvDesc] = useState("");
  const [evSending, setEvSending] = useState(false);
  // 🧧 هدیهٔ نقدی
  const [showRedPacket, setShowRedPacket] = useState(false);
  const [rpAmount, setRpAmount] = useState("");
  const [rpCount, setRpCount] = useState("1");
  const [rpMode, setRpMode] = useState<"equal" | "random">("equal");
  const [rpGreeting, setRpGreeting] = useState("");
  const [rpSending, setRpSending] = useState(false);
  const [rpDetail, setRpDetail] = useState<RedPacketData | null>(null);
  const [rpOpening, setRpOpening] = useState(false);
  // 💸 پولِ درون‌چت (ارسال / درخواست)
  const [moneyMode, setMoneyMode] = useState<"send" | "request" | null>(null);
  const [moneyAmount, setMoneyAmount] = useState("");
  const [moneyNote, setMoneyNote] = useState("");
  const [moneySending, setMoneySending] = useState(false);
  const [moneyBusyId, setMoneyBusyId] = useState<string | null>(null);
  // گزارشِ کاربر
  const [reportTarget, setReportTarget] = useState<Message | null>(null);
  const [reportReason, setReportReason] = useState("");
  const [reportNote, setReportNote] = useState("");
  const [reportBusy, setReportBusy] = useState(false);
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
    const focused = el && document.activeElement === el;
    // اگر ورودی فوکوس دارد از موقعیتِ زندهٔ مکان‌نما استفاده کن؛
    // وگرنه از آخرین موقعیتِ ذخیره‌شده (چون شیت ایموجی فوکوس را می‌گیرد) — باگ ۷
    const rawS = focused ? (el.selectionStart ?? text.length) : selRef.current.start;
    const rawE = focused ? (el.selectionEnd ?? text.length) : selRef.current.end;
    const s = Math.min(Math.max(0, rawS), text.length);
    const e = Math.min(Math.max(0, rawE), text.length);
    const lo = Math.min(s, e), hi = Math.max(s, e);
    const next = text.slice(0, lo) + emo + text.slice(hi);
    setText(next);
    const pos = lo + emo.length;
    selRef.current = { start: pos, end: pos };
    requestAnimationFrame(() => {
      if (!el) return;
      el.focus();
      try { el.setSelectionRange(pos, pos); } catch { /* ignore */ }
    });
  };

  // اموجی‌ساز — دو اموجی را روی یک بومِ ۲۵۶px ترکیب می‌کند: پایهٔ بزرگ در مرکز و
  // اموجیِ دوم کوچک‌تر و هم‌پوشان در گوشهٔ پایین. کاملاً آفلاین (فونتِ اموجیِ مرورگر).
  const drawMix = useCallback((canvas: HTMLCanvasElement | null, a: string, b: string) => {
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    const S = 256;
    canvas.width = S;
    canvas.height = S;
    ctx.clearRect(0, 0, S, S);
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    const emojiFont = '"Apple Color Emoji","Segoe UI Emoji","Noto Color Emoji","Twemoji Mozilla",sans-serif';
    // پایه: بزرگ و کمی بالا-چپ
    ctx.font = `170px ${emojiFont}`;
    ctx.fillText(a, S * 0.44, S * 0.42);
    // دوم: کوچک‌تر، پایین-راست، با هالهٔ سفید برای جداییِ بصری
    ctx.save();
    ctx.shadowColor = "rgba(255,255,255,0.9)";
    ctx.shadowBlur = 10;
    ctx.font = `120px ${emojiFont}`;
    ctx.fillText(b, S * 0.68, S * 0.72);
    ctx.restore();
  }, []);

  // هر بار که پیش‌نمایش باز است یا اموجی‌ها عوض می‌شوند، بوم را دوباره رسم کن.
  useEffect(() => {
    if (showEmoji && emojiTab === "maker") drawMix(mixCanvasRef.current, mixA, mixB);
  }, [showEmoji, emojiTab, mixA, mixB, drawMix]);

  const pickMixEmoji = (emo: string) => {
    if (mixSlot === "a") { setMixA(emo); setMixSlot("b"); }
    else { setMixB(emo); setMixSlot("a"); }
  };

  const sendMix = async () => {
    const canvas = mixCanvasRef.current;
    if (!canvas || mixSending) return;
    drawMix(canvas, mixA, mixB);
    setMixSending(true);
    try {
      const blob: Blob | null = await new Promise((resolve) =>
        canvas.toBlob((b) => resolve(b), "image/png"),
      );
      if (!blob) throw new Error("no-blob");
      setShowEmoji(false);
      await uploadMedia(blob, "image", "emoji-mix.png");
    } catch {
      toast.error(t("chat.toast.fileSendFail"));
    } finally {
      setMixSending(false);
    }
  };

  const copyText = async (msg: Message) => {
    if (!msg.content?.trim()) return;
    try {
      await navigator.clipboard.writeText(msg.content);
      toast.success(t("chat.toast.copied"));
    } catch {
      toast.error(t("chat.toast.copyFail"));
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
      toast.success(willPin ? t("chat.toast.pinned") : t("chat.toast.unpinned"));
    } catch {
      // revert
      setMessages((prev) => prev.map((m) => m.id === msg.id ? { ...m, is_pinned: !willPin } : m));
      toast.error(t("chat.toast.opFail"));
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
      toast.error(t("chat.toast.pollFail"));
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
      toast.error(t("chat.toast.voteFail"));
    }
  };

  // ── 🧧 هدیهٔ نقدی ────────────────────────────────────────
  const openRedPacketCreate = () => {
    setRpAmount("");
    setRpCount("1");
    setRpMode(room.type === "group" ? "random" : "equal");
    setRpGreeting("");
    setShowRedPacket(true);
  };

  const submitRedPacket = async () => {
    const toman = parseInt(rpAmount.replace(/\D/g, ""), 10);
    const count = Math.max(1, parseInt(rpCount, 10) || 1);
    if (!toman || toman < 100) { toast.error(t("chat.toast.rpMin")); return; }
    const rial = toman * 10;
    setRpSending(true);
    try {
      const r = await messagesApi.createRedPacket(room.id, {
        total_amount: rial, count, mode: rpMode,
        greeting: rpGreeting.trim() || undefined,
      });
      setMessages((prev) => [...prev, r.data]);
      setShowRedPacket(false);
      requestAnimationFrame(() => bottomRef.current?.scrollIntoView({ behavior: "smooth" }));
    } catch (e) {
      toast.error(getApiErrorMessage(e, t("chat.toast.rpSendFail")));
    } finally {
      setRpSending(false);
    }
  };

  const openPacket = async (msg: Message) => {
    if (!msg.red_packet) return;
    const rp = msg.red_packet;
    // اگر خودم فرستنده‌ام یا قبلاً باز کرده‌ام یا تمام‌شده → فقط جزئیات
    if (rp.is_mine || rp.claimed || rp.is_exhausted) {
      try {
        const r = await messagesApi.getRedPacket(rp.id);
        setRpDetail(r.data);
      } catch { toast.error(t("chat.toast.detailFail")); }
      return;
    }
    setRpOpening(true);
    try {
      const r = await messagesApi.openRedPacket(rp.id);
      const updated: RedPacketData = r.data.red_packet;
      setMessages((prev) => prev.map((m) => m.id === msg.id ? { ...m, red_packet: updated } : m));
      toast.success(`🧧 ${fmtToman(r.data.amount)}${t("chat.toast.rpClaimedSuffix")}`);
      try {
        const d = await messagesApi.getRedPacket(rp.id);
        setRpDetail(d.data);
      } catch { /* بی‌خیالِ جزئیات */ }
    } catch (e) {
      toast.error(getApiErrorMessage(e, t("chat.toast.rpGone")));
      // وضعیت را تازه کن
      try {
        const d = await messagesApi.getRedPacket(rp.id);
        setMessages((prev) => prev.map((m) => m.id === msg.id ? { ...m, red_packet: d.data } : m));
      } catch { /* noop */ }
    } finally {
      setRpOpening(false);
    }
  };

  // ── 💸 پولِ درون‌چت ──────────────────────────────────────
  const openMoney = (mode: "send" | "request") => {
    setMoneyAmount("");
    setMoneyNote("");
    setMoneyMode(mode);
  };

  const submitMoney = async () => {
    if (!moneyMode) return;
    const toman = parseInt(moneyAmount.replace(/\D/g, ""), 10);
    if (!toman || toman < 100) { toast.error(t("chat.money.min")); return; }
    // سرور مبلغ را در واحدِ خرد (ریال) می‌گیرد و ورودیِ کاربر تومان است.
    const rial = toman * 10;
    setMoneySending(true);
    try {
      const r = moneyMode === "send"
        ? await messagesApi.sendMoney(room.id, rial, moneyNote.trim() || undefined)
        : await messagesApi.requestMoney(room.id, rial, moneyNote.trim() || undefined);
      setMessages((prev) => [...prev, r.data]);
      setMoneyMode(null);
      toast.success(moneyMode === "send" ? t("chat.money.sentOk") : t("chat.money.requestedOk"));
      requestAnimationFrame(() => bottomRef.current?.scrollIntoView({ behavior: "smooth" }));
    } catch (e) {
      toast.error(getApiErrorMessage(e, t("chat.money.failed")));
    } finally {
      setMoneySending(false);
    }
  };

  // پرداخت/ردِ یک درخواست — پاسخ همان `MoneyInfo`ِ به‌روز است، پس فقط همان
  // حباب را جایگزین می‌کنیم و کلِ تاریخچه دوباره بارگیری نمی‌شود.
  const settleRequest = async (msg: Message, action: "pay" | "decline") => {
    const mn = msg.money;
    if (!mn || moneyBusyId) return;
    setMoneyBusyId(mn.id);
    try {
      const r = action === "pay"
        ? await messagesApi.payMoneyRequest(mn.id)
        : await messagesApi.declineMoneyRequest(mn.id);
      const updated: MoneyData = r.data;
      setMessages((prev) => prev.map((m) => (m.id === msg.id ? { ...m, money: updated } : m)));
      if (action === "pay") toast.success(`${fmtToman(mn.amount)}${t("chat.money.paidToast")}`);
    } catch (e) {
      toast.error(getApiErrorMessage(e, t("chat.money.failed")));
    } finally {
      setMoneyBusyId(null);
    }
  };

  // ── اشتراکِ مخاطب ────────────────────────────────────────
  const openContactPick = () => {
    setContactQ("");
    setContactResults([]);
    setShowContactPick(true);
  };

  const searchContacts = useCallback(async (q: string) => {
    const query = q.trim();
    if (query.length < 2) { setContactResults([]); return; }
    setContactBusy(true);
    try {
      const r = await socialApi.search(query);
      setContactResults((r.data || []).map((x: any) => ({
        earth_id: x.earth_id, name: x.name ?? x.username ?? x.earth_id, avatar_url: x.avatar_url ?? null,
      })));
    } catch {
      setContactResults([]);
    } finally {
      setContactBusy(false);
    }
  }, []);

  useEffect(() => {
    if (!showContactPick) return;
    const t = setTimeout(() => searchContacts(contactQ), 350);
    return () => clearTimeout(t);
  }, [contactQ, showContactPick, searchContacts]);

  const sendContact = async (earthId: string) => {
    setShowContactPick(false);
    try {
      const r = await messagesApi.shareContact(room.id, earthId, replyTo?.id ?? null);
      setMessages((prev) => [...prev, r.data]);
      setReplyTo(null);
      requestAnimationFrame(() => bottomRef.current?.scrollIntoView({ behavior: "smooth" }));
    } catch {
      toast.error(t("chat.toast.contactFail"));
    }
  };

  // ── رویداد ───────────────────────────────────────────────
  const openEventCreate = () => {
    setEvTitle(""); setEvWhen(""); setEvLoc(""); setEvDesc("");
    setShowEventCreate(true);
  };

  const submitEvent = async () => {
    const title = evTitle.trim();
    if (!title || !evWhen) return;
    setEvSending(true);
    try {
      const startsAt = new Date(evWhen).toISOString();
      const r = await messagesApi.createEvent(room.id, {
        title, starts_at: startsAt,
        location: evLoc.trim() || undefined,
        description: evDesc.trim() || undefined,
        replyToId: replyTo?.id ?? null,
      });
      setMessages((prev) => [...prev, r.data]);
      setReplyTo(null);
      setShowEventCreate(false);
      requestAnimationFrame(() => bottomRef.current?.scrollIntoView({ behavior: "smooth" }));
    } catch {
      toast.error(t("chat.toast.eventFail"));
    } finally {
      setEvSending(false);
    }
  };

  const addEventToCalendar = (ev: EventData) => {
    try {
      const dt = (iso: string) => new Date(iso).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
      const start = dt(ev.starts_at);
      const end = dt(new Date(new Date(ev.starts_at).getTime() + 3600_000).toISOString());
      const ics = [
        "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Dilix//Event//FA", "BEGIN:VEVENT",
        `UID:${ev.id}@dilix.ir`, `DTSTART:${start}`, `DTEND:${end}`,
        `SUMMARY:${ev.title}`,
        ...(ev.location ? [`LOCATION:${ev.location}`] : []),
        ...(ev.description ? [`DESCRIPTION:${ev.description}`] : []),
        "END:VEVENT", "END:VCALENDAR",
      ].join("\r\n");
      const url = URL.createObjectURL(new Blob([ics], { type: "text/calendar;charset=utf-8" }));
      const a = document.createElement("a");
      a.href = url; a.download = `${ev.title}.ics`; a.click();
      URL.revokeObjectURL(url);
    } catch {
      toast.error(t("chat.toast.calFail"));
    }
  };

  // ── پیامِ ناپدیدشونده ─────────────────────────────────────
  const applyDisappearing = async (seconds: number) => {
    setShowDisappear(false);
    const prev = disappearSec;
    setDisappearSec(seconds);
    try {
      await messagesApi.setDisappearing(room.id, seconds);
      toast.success(seconds > 0 ? t("chat.toast.disOn") : t("chat.toast.disOff"));
    } catch {
      setDisappearSec(prev);
      toast.error(t("chat.toast.stateFail"));
    }
  };

  // ── گزارشِ کاربر ─────────────────────────────────────────
  const openReport = (msg: Message) => {
    setSheetMsg(null);
    setReportReason("");
    setReportNote("");
    setReportTarget(msg);
  };

  const submitReport = async () => {
    if (!reportTarget || !reportReason) return;
    const earthId = reportTarget.sender_earth_id || room.partner_earth_id;
    if (!earthId) { toast.error(t("chat.toast.reportNoTarget")); return; }
    setReportBusy(true);
    try {
      await messagesApi.reportUser(earthId, {
        reason: reportReason,
        note: reportNote.trim() || undefined,
        message_id: reportTarget.id,
      });
      setReportTarget(null);
      toast.success(t("chat.toast.reportOk"));
    } catch {
      toast.error(t("chat.toast.reportFail"));
    } finally {
      setReportBusy(false);
    }
  };

  // ── Export chat (client-side .txt) ───────────────────────
  const exportChat = () => {
    setShowOptions(false);
    try {
      const lines = messages.map((m) => {
        const who = m.is_mine ? t("chat.me") : (m.sender_name || t("chat.partner"));
        let time = "";
        try { time = new Date(m.created_at).toLocaleString("fa-IR"); } catch { time = m.created_at; }
        let body = m.is_deleted ? t("chat.deletedMsgParen") : (m.content || "");
        if (!body && m.media_type) body = `[${m.media_type}]`;
        return `[${time}] ${who}: ${body}`;
      });
      const header = `${t("chat.exportHeaderPre")}${partnerName}\n${"=".repeat(32)}\n`;
      const blob = new Blob([header + lines.join("\n")], { type: "text/plain;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `dilix-chat-${partnerName}.txt`;
      a.click();
      URL.revokeObjectURL(url);
    } catch {
      toast.error(t("chat.toast.exportFail"));
    }
  };

  // ── بی‌صدا / مسدود / پاک‌کردنِ گفتگو ───────────────────────
  const toggleMute = async (durationMinutes?: number | null) => {
    setShowOptions(false);
    const next = !isMuted;
    try {
      const r = await messagesApi.muteRoom(room.id, next, durationMinutes ?? null);
      setIsMuted(!!r.data.muted);
      toast.success(r.data.muted ? t("chat.toast.muted") : t("chat.toast.unmuted"));
    } catch {
      toast.error(t("chat.toast.muteFail"));
    }
  };

  const toggleBlock = async () => {
    setShowOptions(false);
    if (!room.partner_earth_id) return;
    try {
      const r = await messagesApi.blockUser(room.partner_earth_id);
      setIsBlocked(!!r.data.blocked);
      toast.success(r.data.blocked ? t("chat.toast.blocked") : t("chat.toast.unblocked"));
    } catch {
      toast.error(t("chat.toast.blockFail"));
    }
  };

  const doClearChat = async () => {
    setShowOptions(false);
    if (!confirm(t("chat.confirm.clear"))) return;
    try {
      await messagesApi.clearChat(room.id);
      setMessages([]);
      toast.success(t("chat.toast.cleared"));
    } catch {
      toast.error(t("chat.toast.clearFail"));
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
      if (!silent) toast.error(t("chat.toast.translateFail"));
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
    toast.success(`${t("chat.toast.trToPre")}${langLabel(target)}${t("chat.toast.trToSuf")}`);
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
      if (!silent) toast.error(t("chat.toast.loadFail"));
    } finally {
      setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [room.id]);

  useEffect(() => { load(); }, [load]);

  useEffect(() => {
    // فقط وقتی کاربر پایینِ گفتگوست اسکرول کن؛ هنگام مرورِ پیام‌های قدیمی
    // پولِ هر ۵ث نباید به‌زور به آخرین پیام برگرداند (باگ ۸)
    if (atBottomRef.current) {
      bottomRef.current?.scrollIntoView({ behavior: "smooth" });
    }
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
        if (alive) {
          setPresence({
            online: !!data.partner_online,
            lastSeen: data.partner_last_seen ?? null,
            typing: Array.isArray(data.typing) ? data.typing : [],
          });
          setDisappearSec(Number(data.disappear_seconds) || 0);
        }
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
        toast.error(t("chat.toast.editFail"));
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
    atBottomRef.current = true;
    setMessages(prev => [...prev, tmp]);

    try {
      const res = await messagesApi.send(room.id, content, replyId);
      setMessages(prev => prev.map(m => m.id === tmp.id ? res.data : m));
    } catch {
      setMessages(prev => prev.filter(m => m.id !== tmp.id));
      setText(content);
      toast.error(t("chat.toast.sendFail"));
    } finally {
      setSending(false);
    }
  };

  // translate what I'm composing into the target language, in place
  const translateCompose = async () => {
    const srcText = text.trim();
    if (!srcText || composeTr) return;
    setComposeTr(true);
    try {
      const res = await messagesApi.translateText(srcText, trLang);
      const out = res.data.translated_text;
      if (out && out !== srcText) {
        setText(out);
        toast.success(`${t("chat.toast.trToPre")}${langLabel(trLang)}${t("chat.toast.trToSuf")}`);
      } else {
        toast(`${t("chat.toast.alreadyLangPre")}${langLabel(trLang)}${t("chat.toast.alreadyLangSuf")}`);
      }
    } catch {
      toast.error(t("chat.toast.translateFail"));
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
      media_name: mediaType === "file" ? (filename ?? t("chat.file")) : null,
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
      toast.error(t("chat.toast.fileSendFail"));
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
      toast.error(t("chat.toast.stickerFail"));
    }
    void tmpId; void rp;
  };

  const starSticker = async (stickerId: string) => {
    setSheetMsg(null);
    try { await stickersApi.star(stickerId); toast.success(t("chat.toast.starred")); }
    catch { toast.error(t("chat.toast.opFail")); }
  };

  const exploreStickerLibrary = async (stickerId: string) => {
    setSheetMsg(null);
    try {
      const res = await stickersApi.getSticker(stickerId);
      setLibraryPackId(res.data.pack_id);
      setShowLibrary(true);
    } catch { toast.error(t("chat.toast.libNotFound")); }
  };

  const onPickFile = (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0];
    e.target.value = "";
    if (!f) return;
    // عکس/ویدیو → ویرایشگر (برش/فیلتر/متن/فشرده‌سازی)؛ بقیه مستقیم
    if (f.type.startsWith("image/")) { setEditorMedia({ file: f, kind: "image" }); return; }
    if (f.type.startsWith("video/")) { setEditorMedia({ file: f, kind: "video" }); return; }
    if (f.size > 25 * 1024 * 1024) { toast.error(t("chat.toast.fileTooBig")); return; }
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
      toast.error(t("chat.toast.micFail"));
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
      toast.error(t("chat.toast.geoFail"));
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
      toast.error(t("chat.toast.liveStartFail"));
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
      toast.error(t("chat.toast.liveStopFail"));
      load();
    }
  };

  const doReact = async (msg: Message, emoji: string) => {
    setSheetMsg(null);
    setReactPicker(false);
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
      toast.error(t("chat.toast.reactFail"));
      load();
    }
  };

  const doDelete = async (msg: Message) => {
    setSheetMsg(null);
    setMessages(prev => prev.map(m => m.id === msg.id ? { ...m, is_deleted: true, content: "" } : m));
    try {
      await messagesApi.remove(msg.id);
    } catch {
      toast.error(t("chat.toast.deleteFail"));
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
      toast(t("chat.toast.oldMsg"), { icon: "🔎" });
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
        toast.success(target.id === room.id ? t("chat.toast.forwarded") : t("chat.toast.forwardedTo"));
        setForwardMsg(null); setForwardBulk(false); exitSelect();
      } catch {
        toast.error(t("chat.toast.forwardFail"));
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
      toast.success(target.id === room.id ? t("chat.toast.forwarded") : t("chat.toast.forwardedTo"));
      setForwardMsg(null);
    } catch {
      toast.error(t("chat.toast.forwardFail"));
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
    if (!text && !url) { toast(t("chat.toast.nothingShare")); return; }
    const data: { title: string; text?: string; url?: string } = { title: t("chat.appName") };
    if (text) data.text = text;
    if (url) data.url = url;
    try {
      if (navigator.share) await navigator.share(data);
      else { await navigator.clipboard.writeText([text, url].filter(Boolean).join("\n")); toast.success(t("chat.toast.clipCopied")); }
    } catch { /* کاربر لغو کرد */ }
  };
  // ذخیرهٔ رسانه (عکس/ویدیو/فایل/صوت) روی دستگاه — برای پیام‌های دریافتی هم کار می‌کند
  const saveMedia = async (msg: Message) => {
    setSheetMsg(null);
    if (!msg.media_url) { toast(t("chat.toast.noMedia")); return; }
    const url = absUrl(msg.media_url);
    const extByType: Record<string, string> = { image: ".jpg", video: ".mp4", voice: ".webm" };
    const fname = msg.media_name || `dilix-${msg.media_type || "media"}-${Date.now()}${extByType[msg.media_type || ""] || ""}`;
    const tid = toast.loading(t("chat.toast.saving"));
    try {
      const res = await fetch(url);
      if (!res.ok) throw new Error("fetch");
      const blob = await res.blob();
      const objUrl = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = objUrl; a.download = fname;
      document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(objUrl), 4000);
      toast.success(t("chat.toast.saved"), { id: tid });
    } catch {
      toast.dismiss(tid);
      window.open(url, "_blank"); // اگر ذخیرهٔ مستقیم ممکن نبود، در تبِ جدید باز کن
    }
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
    const joined = selectedMsgs().map((m) => m.content?.trim()).filter(Boolean).join("\n");
    if (!joined) { toast(t("chat.toast.noCopyText")); return; }
    try { await navigator.clipboard.writeText(joined); toast.success(t("chat.toast.copiedShort")); } catch { toast.error(t("chat.toast.copyFail")); }
    exitSelect();
  };
  const bulkShare = async () => {
    const parts = selectedMsgs().map((m) => m.content?.trim() || (m.media_url ? absUrl(m.media_url) : "")).filter(Boolean);
    const text = parts.join("\n");
    if (!text) { toast(t("chat.toast.nothingShare")); return; }
    try {
      if (navigator.share) await navigator.share({ title: t("chat.appName"), text });
      else { await navigator.clipboard.writeText(text); toast.success(t("chat.toast.clipCopied")); }
    } catch { /* لغو */ }
    exitSelect();
  };
  const bulkDelete = async () => {
    const mine = selectedMsgs().filter((m) => m.is_mine && !m.is_deleted && !m.id.startsWith("tmp-"));
    if (mine.length === 0) { toast(t("chat.toast.onlyOwnDelete")); return; }
    if (!window.confirm(`${t("chat.confirm.bulkDeletePre")}${mine.length}${t("chat.confirm.bulkDeleteSuf")}`)) return;
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
      toast.error(t("chat.toast.membersFail"));
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
      if (res.data.already_member) toast(t("chat.toast.alreadyMember"));
      else toast.success(t("chat.toast.memberAdded"));
      setAddTarget("");
      const m = await messagesApi.members(room.id);
      setMembers(m.data);
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("chat.toast.addFail")));
    } finally {
      setAddBusy(false);
    }
  };

  const doLeave = async () => {
    if (!me?.earth_id) return;
    try {
      await messagesApi.removeMember(room.id, me.earth_id);
      toast.success(t("chat.toast.leftGroup"));
      setShowMembers(false);
      (onLeave ?? onBack)();
    } catch {
      toast.error(t("chat.toast.leaveFail"));
    }
  };

  const doRemoveMember = async (earthId: string) => {
    try {
      await messagesApi.removeMember(room.id, earthId);
      setMembers(prev => prev.filter(m => m.earth_id !== earthId));
    } catch (e: any) {
      toast.error(getApiErrorMessage(e, t("chat.toast.deleteFail")));
    }
  };

  const dayLabel = (iso: string) => {
    const d = new Date(iso);
    const today = new Date();
    const yst = new Date(); yst.setDate(today.getDate() - 1);
    const sameDay = (a: Date, b: Date) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    if (sameDay(d, today)) return t("chat.today");
    if (sameDay(d, yst)) return t("chat.yesterday");
    return d.toLocaleDateString("fa-IR", { weekday: "long", day: "numeric", month: "long" });
  };
  const isNewDay = (curIso: string, prevIso?: string) => {
    if (!prevIso) return true;
    const a = new Date(curIso), b = new Date(prevIso);
    return a.getFullYear() !== b.getFullYear() || a.getMonth() !== b.getMonth() || a.getDate() !== b.getDate();
  };
  const onMessagesScroll = (e: React.UIEvent<HTMLDivElement>) => {
    const el = e.currentTarget;
    const distance = el.scrollHeight - el.scrollTop - el.clientHeight;
    atBottomRef.current = distance < 120;
    setShowScrollDown(distance > 320);
  };

  const partnerName = isGroup ? (room.name ?? t("chat.group")) : (room.partner_name ?? room.name ?? t("chat.conversation"));
  const partnerRole = room.partner_role ?? "user";
  const iAmAdmin = members.find(m => m.is_me)?.is_admin ?? room.is_admin ?? false;

  return (
    <div className="chat-scope flex flex-col fixed inset-0 z-40 bg-[#0A0A0A] overflow-x-hidden">
      {/* Header */}
      <div className="flex items-center gap-3 px-4 py-3 bg-[var(--chat-header)] border-b border-white/8 safe-top">
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
                {isGroup ? `${presence.typing[0]}${t("chat.typingSuffix")}` : t("chat.typing")}
              </span>
            ) : isGroup ? (
              <span className="text-white/40">{toPersianNum(room.member_count ?? members.length)}{t("chat.membersSuffix")}</span>
            ) : presence.online ? (
              <span className="text-emerald-400">{t("chat.online")}</span>
            ) : presence.lastSeen ? (
              <span className="text-white/40">{t("chat.lastSeenPre")}{lastSeenLabel(presence.lastSeen, t)}</span>
            ) : (
              <span className="text-white/40">{t(ROLE_LABEL[partnerRole] ?? "chat.role.user")}</span>
            )}
          </p>
        </button>
        {!isGroup && room.partner_earth_id && (
          <button
            onClick={() => setShowCallMenu(true)}
            className="p-2 rounded-xl hover:bg-white/5 text-white/60"
            title={t("chat.callTitle")}
          >
            <Phone size={20} />
          </button>
        )}
        <button
          onClick={() => setShowOptions(true)}
          className={`relative p-2 rounded-xl hover:bg-white/5 ${autoTr ? "text-emerald-400" : "text-white/60"}`}
          title={t("chat.moreOptions")}
        >
          <MoreVertical size={20} />
          {autoTr && <span className="absolute top-1.5 right-1.5 w-2 h-2 rounded-full bg-emerald-400" />}
        </button>
      </div>

      {/* Pinned banner */}
      {pins.length > 0 && (() => {
        const idx = Math.min(pinIdx, pins.length - 1);
        const p = pins[idx];
        const preview = p.is_deleted ? t("chat.deleted") : (p.content?.trim() || (p.media_type ? t("chat.media") : t("chat.messageWord")));
        return (
          <button
            onClick={() => { jumpToMessage(p); if (pins.length > 1) setPinIdx((i) => (i + 1) % pins.length); }}
            className="flex items-center gap-2 w-full px-4 py-2 bg-[#141414] border-b border-white/8 text-right active:bg-white/5"
          >
            <Pin size={15} className="text-indigo-400 shrink-0 rotate-45" />
            <div className="flex-1 min-w-0">
              <p className="text-[11px] text-indigo-300/80">
                {t("chat.pinnedMsg")}{pins.length > 1 ? ` ${toPersianNum(idx + 1)}/${toPersianNum(pins.length)}` : ""}
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
            <p className="text-white/30 text-sm">{t("chat.beFirst")}</p>
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
              onContextMenu={(e) => e.preventDefault()}
              style={{ WebkitTouchCallout: "none" }}
              className={`flex flex-col select-none ${msg.is_mine ? "items-end" : "items-start"} rounded-2xl transition ${highlightId === msg.id ? "ring-2 ring-yellow-400/70" : ""} ${selectMode && selectedIds.has(msg.id) ? "bg-indigo-500/10" : ""}`}
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
                      ? "text-white rounded-br-sm bubble-mine"
                      : "bg-[#2C2C2E] text-white/90 rounded-bl-sm"
                }`}
              >
                {/* sender name (group, others' messages) */}
                {isGroup && !msg.is_mine && !msg.is_deleted && (
                  <span className="block text-[11px] font-semibold text-indigo-300 mb-0.5">
                    {msg.sender_name ?? t("chat.role.user")}
                  </span>
                )}
                {/* forwarded label */}
                {msg.is_forwarded && !msg.is_deleted && (
                  <span className={`flex items-center gap-1 text-[11px] mb-1 ${msg.is_mine ? "text-indigo-100/70" : "text-white/45"}`}>
                    <Forward size={12} />
                    {msg.forwarded_from ? `${t("chat.forwardedFromPre")}${msg.forwarded_from}` : t("chat.forwardedLabel")}
                  </span>
                )}
                {/* reply preview */}
                {msg.reply_to && (
                  <div className={`mb-1.5 pr-2 border-r-2 rounded-sm text-xs ${
                    msg.is_mine ? "border-white/50 text-indigo-100/80" : "border-indigo-400/60 text-white/50"
                  }`}>
                    <span className="font-semibold block">{msg.reply_to.sender_name ?? t("chat.role.user")}</span>
                    <span className="line-clamp-1">{msg.reply_to.is_deleted ? t("chat.msgDeleted") : msg.reply_to.content}</span>
                  </div>
                )}
                {/* media */}
                {!msg.is_deleted && msg.media_url && msg.media_type === "image" && (
                  <a href={msg.media_url} target="_blank" rel="noreferrer" draggable={false} onContextMenu={(e) => e.preventDefault()} onClick={(e) => { e.stopPropagation(); if (suppressClickRef.current) { e.preventDefault(); suppressClickRef.current = false; } else if (selectMode) { e.preventDefault(); toggleSelect(msg.id); } }} className="block">
                    <img src={msg.media_url} alt="" draggable={false} className="rounded-xl max-h-72 w-auto object-cover mb-1" style={{ WebkitTouchCallout: "none" }} />
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
                    draggable={false} onContextMenu={(e) => e.preventDefault()}
                    onClick={(e) => { e.stopPropagation(); if (suppressClickRef.current) { e.preventDefault(); suppressClickRef.current = false; } else if (selectMode) { e.preventDefault(); toggleSelect(msg.id); } }}
                    className={`flex items-center gap-2 mb-1 px-2 py-2 rounded-xl ${msg.is_mine ? "bg-white/10" : "bg-white/5"}`}
                  >
                    <FileText size={22} className="shrink-0 text-white/80" />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-[13px]">{msg.media_name ?? t("chat.file")}</span>
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
                      <span className="text-[11px] opacity-70">{t("chat.poll")}{msg.poll.multiple ? t("chat.pollMulti") : ""}</span>
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
                      {msg.poll.total_votes > 0 ? `${msg.poll.total_votes}${t("chat.pollVotesSuffix")}` : t("chat.pollNoVotes")}
                    </p>
                  </div>
                )}
                {!msg.is_deleted && msg.media_type === "contact" && msg.contact && (
                  <a
                    href={`/u/${msg.contact.earth_id}`}
                    onClick={(e) => e.stopPropagation()}
                    className="flex items-center gap-3 min-w-[13rem] rounded-xl bg-black/20 p-2.5 hover:bg-black/30 transition"
                  >
                    <span className="shrink-0 w-11 h-11 rounded-full overflow-hidden bg-white/10 flex items-center justify-center text-lg">
                      {msg.contact.avatar_url
                        ? <img src={msg.contact.avatar_url} alt="" className="w-full h-full object-cover" />
                        : (msg.contact.name?.[0] ?? "👤")}
                    </span>
                    <span className="flex-1 min-w-0">
                      <span className="flex items-center gap-1 text-[11px] opacity-60">
                        <UserRound size={12} /> {t("chat.contact")}
                      </span>
                      <span className="block text-sm font-semibold truncate">{msg.contact.name}</span>
                      <span className="block text-[11px] opacity-60 truncate">{msg.contact.earth_id}</span>
                    </span>
                  </a>
                )}
                {!msg.is_deleted && msg.media_type === "event" && msg.event && (
                  <div onClick={(e) => e.stopPropagation()} className="min-w-[14rem]">
                    <div className="flex items-center gap-1.5 mb-1.5">
                      <CalendarClock size={14} className={msg.is_mine ? "text-indigo-100" : "text-emerald-400"} />
                      <span className="text-[11px] opacity-70">{t("chat.event")}</span>
                    </div>
                    <p className="font-bold text-sm mb-1 leading-snug">{msg.event.title}</p>
                    <p className="text-[12px] opacity-80 mb-1">
                      {(() => { try { return new Date(msg.event.starts_at).toLocaleString("fa-IR", { dateStyle: "full", timeStyle: "short" }); } catch { return msg.event.starts_at; } })()}
                    </p>
                    {msg.event.location && (
                      <p className="flex items-center gap-1 text-[12px] opacity-70 mb-1">
                        <MapPin size={12} /> {msg.event.location}
                      </p>
                    )}
                    {msg.event.description && (
                      <p className="text-[12px] opacity-60 mb-2 whitespace-pre-wrap">{msg.event.description}</p>
                    )}
                    <button
                      onClick={() => addEventToCalendar(msg.event!)}
                      className={`mt-1 w-full flex items-center justify-center gap-1.5 rounded-xl py-2 text-[12px] font-semibold ${msg.is_mine ? "bg-white/15 hover:bg-white/25" : "bg-emerald-500/15 text-emerald-300 hover:bg-emerald-500/25"} transition`}
                    >
                      <CalendarPlus size={14} /> {t("chat.addToCalendar")}
                    </button>
                  </div>
                )}
                {!msg.is_deleted && msg.media_type === "red_packet" && msg.red_packet && (() => {
                  const rp = msg.red_packet!;
                  const done = rp.claimed || rp.is_mine || rp.is_exhausted;
                  return (
                    <button
                      onClick={(e) => { e.stopPropagation(); openPacket(msg); }}
                      disabled={rpOpening}
                      className="block w-full min-w-[13rem] text-right rounded-2xl overflow-hidden active:scale-[0.99] transition disabled:opacity-70"
                    >
                      <div className={`px-3.5 pt-3 pb-2.5 ${done ? "bg-gradient-to-br from-rose-500/40 to-orange-500/30" : "bg-gradient-to-br from-rose-500 to-orange-500"}`}>
                        <div className="flex items-center gap-2">
                          <span className="shrink-0 w-9 h-9 rounded-full bg-white/20 flex items-center justify-center text-lg">🧧</span>
                          <span className="flex-1 min-w-0">
                            <span className="block text-white font-bold text-sm truncate">
                              {rp.greeting || t("chat.redPacket")}
                            </span>
                            <span className="block text-white/80 text-[11px]">
                              {rp.mode === "random" ? t("chat.rpRandom") : t("chat.rpEqual")} · {toPersianNum(rp.count)}{t("chat.rpSharesSuffix")}
                            </span>
                          </span>
                        </div>
                      </div>
                      <div className={`px-3.5 py-2 text-[12px] ${msg.is_mine ? "bg-black/20" : "bg-black/25"}`}>
                        {rp.is_mine ? (
                          <span className="text-white/80">
                            {rp.claimed_count >= rp.count || rp.status !== "active"
                              ? `${t("chat.rpAllClaimedPre")}${fmtToman(rp.claimed_amount)}${t("chat.tomanSuffix")}`
                              : `${toPersianNum(rp.claimed_count)}${t("chat.rpClaimedOfMid")}${toPersianNum(rp.count)}${t("chat.rpClaimedOfSuf")}`}
                          </span>
                        ) : rp.claimed ? (
                          <span className="text-emerald-300 font-semibold">
                            {t("chat.rpYoursPre")}{fmtToman(rp.my_amount || 0)}{t("chat.tomanSuffix")}
                          </span>
                        ) : rp.is_exhausted ? (
                          <span className="text-white/60">{t("chat.rpAllTaken")}</span>
                        ) : (
                          <span className="text-white font-bold flex items-center gap-1">
                            <Gift size={13} /> {t("chat.rpTapOpen")}
                          </span>
                        )}
                      </div>
                    </button>
                  );
                })()}
                {!msg.is_deleted && (msg.media_type === "money" || msg.media_type === "money_request") && msg.money && (() => {
                  const mn = msg.money!;
                  const isReq = mn.kind === "request";
                  // «فرستنده/گیرنده» از دیدِ من: در `send` سازنده پول داده، در
                  // `request` سازنده پول خواسته — پس رنگ و متن نباید یکی باشد.
                  const head = isReq
                    ? (mn.is_mine ? t("chat.money.iRequested") : t("chat.money.theyRequested"))
                    : (mn.is_mine ? t("chat.money.iSent") : t("chat.money.theySent"));
                  const done = mn.status === "paid" || mn.status === "completed";
                  const dead = mn.status === "declined" || mn.status === "cancelled";
                  return (
                    <div className="min-w-[13rem] rounded-2xl overflow-hidden">
                      <div className={`px-3.5 pt-3 pb-2.5 ${
                        dead ? "bg-white/5"
                          : isReq ? "bg-gradient-to-br from-amber-500 to-orange-500"
                            : "bg-gradient-to-br from-emerald-500 to-teal-600"
                      }`}>
                        <div className="flex items-center gap-2">
                          <span className="shrink-0 w-9 h-9 rounded-full bg-white/20 flex items-center justify-center">
                            {isReq ? <HandCoins size={18} className="text-white" /> : <Banknote size={18} className="text-white" />}
                          </span>
                          <span className="flex-1 min-w-0">
                            <span className="block text-white/80 text-[11px]">{head}</span>
                            <span className="block text-white font-black text-lg leading-tight">
                              {fmtToman(mn.amount)} <span className="text-[11px] font-bold">{t("chat.toman")}</span>
                            </span>
                          </span>
                        </div>
                        {mn.note && <p className="text-white/85 text-[12px] mt-1.5 break-words">{mn.note}</p>}
                      </div>
                      <div className="px-3.5 py-2 bg-black/25 text-[12px]">
                        {mn.can_pay ? (
                          <div className="flex gap-2">
                            <button
                              onClick={(e) => { e.stopPropagation(); settleRequest(msg, "pay"); }}
                              disabled={moneyBusyId === mn.id}
                              className="flex-1 py-1.5 rounded-lg bg-emerald-500 text-white font-bold disabled:opacity-50 active:scale-[0.98] transition"
                            >
                              {moneyBusyId === mn.id ? t("chat.sending") : t("chat.money.payBtn")}
                            </button>
                            <button
                              onClick={(e) => { e.stopPropagation(); settleRequest(msg, "decline"); }}
                              disabled={moneyBusyId === mn.id}
                              className="px-3 py-1.5 rounded-lg bg-white/10 text-white/70 font-semibold disabled:opacity-50"
                            >
                              {t("chat.money.declineBtn")}
                            </button>
                          </div>
                        ) : mn.can_cancel ? (
                          <button
                            onClick={(e) => { e.stopPropagation(); settleRequest(msg, "decline"); }}
                            disabled={moneyBusyId === mn.id}
                            className="w-full py-1.5 rounded-lg bg-white/10 text-white/70 font-semibold disabled:opacity-50"
                          >
                            {moneyBusyId === mn.id ? t("chat.sending") : t("chat.money.cancelBtn")}
                          </button>
                        ) : (
                          <span className={done ? "text-emerald-300 font-semibold" : "text-white/50"}>
                            {mn.status === "completed" ? t("chat.money.stCompleted")
                              : mn.status === "paid" ? t("chat.money.stPaid")
                                : mn.status === "declined" ? t("chat.money.stDeclined")
                                  : mn.status === "cancelled" ? t("chat.money.stCancelled")
                                    : t("chat.money.stPending")}
                          </span>
                        )}
                      </div>
                    </div>
                  );
                })()}
                {!msg.is_deleted && msg.media_type === "order" && msg.media_name && (
                  <OrderBubble orderRef={msg.media_name} t={t} />
                )}
                {(msg.is_deleted || (msg.content && msg.media_type !== "call" && msg.media_type !== "poll" && msg.media_type !== "contact" && msg.media_type !== "event" && msg.media_type !== "red_packet" && msg.media_type !== "money" && msg.media_type !== "money_request" && msg.media_type !== "order") || (!msg.media_url && !msg.location && msg.media_type !== "call" && msg.media_type !== "poll" && msg.media_type !== "contact" && msg.media_type !== "event" && msg.media_type !== "red_packet" && msg.media_type !== "money" && msg.media_type !== "money_request" && msg.media_type !== "order")) && (
                  <p>{msg.is_deleted ? t("chat.thisMsgDeleted") : msg.content}</p>
                )}
                {/* inline translation */}
                {!msg.is_deleted && trans[msg.id]?.open && (
                  <div
                    onClick={(e) => e.stopPropagation()}
                    className={`mt-1.5 pt-1.5 border-t text-right ${msg.is_mine ? "border-white/20" : "border-white/10"}`}
                  >
                    {trans[msg.id].loading ? (
                      <span className="flex items-center gap-1.5 text-[12px] text-white/50">
                        <Loader2 size={12} className="animate-spin" /> {t("chat.translating")}
                      </span>
                    ) : (
                      <>
                        <span className={`flex items-center gap-1 text-[10px] mb-0.5 ${msg.is_mine ? "text-indigo-200/70" : "text-emerald-300/70"}`}>
                          <Languages size={11} /> {t("chat.translatedBadgePre")}{langLabel(trans[msg.id].lang ?? trLang)}
                        </span>
                        <p className="text-[13px]">{trans[msg.id].text}</p>
                        <button
                          onClick={() => closeTranslation(msg.id)}
                          className={`mt-0.5 text-[10px] ${msg.is_mine ? "text-indigo-200/60" : "text-white/40"}`}
                        >
                          {t("chat.showOriginal")}
                        </button>
                      </>
                    )}
                  </div>
                )}
                <div className={`flex items-center gap-1 mt-1 ${msg.is_mine ? "text-indigo-200/60" : "text-white/30"} justify-end`}>
                  {msg.is_pinned && !msg.is_deleted && <Pin size={11} className="rotate-45" />}
                  {msg.edited && !msg.is_deleted && <span className="text-[10px]">{t("chat.edited")}</span>}
                  <span className="text-[10px]">{formatTime(msg.created_at, t)}</span>
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
                  aria-label={t("chat.msgOptions")}
                >
                  <MoreHorizontal size={14} /> {t("chat.options")}
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
          aria-label={t("chat.jumpLatest")}
        >
          <ChevronDown size={22} />
        </button>
      )}

      {/* Select-mode action bar */}
      {selectMode && (
        <div className="fixed top-0 inset-x-0 z-[60] bg-[#1C1C1E] border-b border-white/10 px-3 py-2.5 flex items-center gap-1">
          <button onClick={exitSelect} className="p-2 rounded-lg hover:bg-white/5 text-white/80" aria-label={t("chat.close")}>
            <X size={20} />
          </button>
          <span className="text-white text-sm font-semibold flex-1 px-1">{toPersianNum(selectedIds.size)}{t("chat.selectedSuffix")}</span>
          <button onClick={startForwardBulk} disabled={selectedIds.size === 0} className="p-2 rounded-lg hover:bg-white/5 text-white/80 disabled:opacity-30" aria-label={t("chat.forward")}><Forward size={19} /></button>
          <button onClick={bulkShare} disabled={selectedIds.size === 0} className="p-2 rounded-lg hover:bg-white/5 text-white/80 disabled:opacity-30" aria-label={t("chat.share")}><Share2 size={19} /></button>
          <button onClick={bulkCopy} disabled={selectedIds.size === 0} className="p-2 rounded-lg hover:bg-white/5 text-white/80 disabled:opacity-30" aria-label={t("chat.copy")}><Copy size={19} /></button>
          <button onClick={bulkDelete} disabled={selectedIds.size === 0} className="p-2 rounded-lg hover:bg-white/5 text-rose-400 disabled:opacity-30" aria-label={t("chat.delete")}><Trash2 size={19} /></button>
        </div>
      )}

      {/* Action sheet (react / reply / edit / delete) */}
      {sheetMsg && (
        <div
          className="fixed inset-0 z-50 flex items-end justify-center bg-black/50"
          onClick={() => { setSheetMsg(null); setReactPicker(false); }}
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
              <button
                onClick={() => setReactPicker((v) => !v)}
                className={`w-10 h-10 rounded-full flex items-center justify-center transition ${
                  reactPicker ? "bg-indigo-500/25 text-indigo-300" : "bg-white/5 text-white/70 hover:bg-white/10"
                }`}
                aria-label={t("chat.customEmoji")}
              >
                <Plus size={22} />
              </button>
            </div>
            {/* گزینشِ ایموجیِ دلخواه برای واکنش */}
            {reactPicker && (
              <div className="grid grid-cols-8 gap-1 mb-4 px-1 max-h-52 overflow-y-auto">
                {COMPOSE_EMOJIS.map((emoji, i) => (
                  <button
                    key={`${emoji}-${i}`}
                    onClick={() => doReact(sheetMsg, emoji)}
                    className={`text-2xl w-9 h-9 rounded-lg flex items-center justify-center transition-transform active:scale-125 ${
                      sheetMsg.my_reaction === emoji ? "bg-indigo-500/25" : "hover:bg-white/5"
                    }`}
                  >
                    {emoji}
                  </button>
                ))}
              </div>
            )}
            <div className="space-y-1">
              <button
                onClick={() => startReply(sheetMsg)}
                className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
              >
                <Reply size={18} className="text-white/60" /> {t("chat.reply")}
              </button>
              <button
                onClick={() => startForward(sheetMsg)}
                className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
              >
                <Forward size={18} className="text-white/60" /> {t("chat.forward")}
              </button>
              <button
                onClick={() => startForwardAnon(sheetMsg)}
                className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
              >
                <Forward size={18} className="text-white/40" /> {t("chat.forwardAnon")}
              </button>
              <button
                onClick={() => shareMsg(sheetMsg)}
                className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
              >
                <Share2 size={18} className="text-white/60" /> {t("chat.share")}
              </button>
              {!sheetMsg.is_deleted && !!sheetMsg.media_url && ["image", "video", "file", "voice"].includes(sheetMsg.media_type || "") && (
                <button
                  onClick={() => saveMedia(sheetMsg)}
                  className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
                >
                  <Download size={18} className="text-sky-400" /> {t("chat.saveMedia")}
                </button>
              )}
              <button
                onClick={() => enterSelect(sheetMsg)}
                className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
              >
                <ListChecks size={18} className="text-white/60" /> {t("chat.select")}
              </button>
              {!sheetMsg.is_deleted && (
                <button
                  onClick={() => togglePin(sheetMsg)}
                  className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
                >
                  {sheetMsg.is_pinned
                    ? <><PinOff size={18} className="text-white/60" /> {t("chat.unpin")}</>
                    : <><Pin size={18} className="text-indigo-400" /> {t("chat.pin")}</>}
                </button>
              )}
              {!!sheetMsg.sticker_id && (
                <>
                  <button
                    onClick={() => starSticker(sheetMsg.sticker_id!)}
                    className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
                  >
                    <Star size={18} className="text-amber-400" /> {t("chat.saveToStarred")}
                  </button>
                  <button
                    onClick={() => exploreStickerLibrary(sheetMsg.sticker_id!)}
                    className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
                  >
                    <Compass size={18} className="text-fuchsia-400" /> {t("chat.exploreSticker")}
                  </button>
                </>
              )}
              {!!sheetMsg.content?.trim() && (
                <button
                  onClick={() => copyText(sheetMsg)}
                  className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
                >
                  <Copy size={18} className="text-white/60" /> {t("chat.copyText")}
                </button>
              )}
              {!!sheetMsg.content?.trim() && (
                trans[sheetMsg.id]?.open ? (
                  <button
                    onClick={() => { closeTranslation(sheetMsg.id); setSheetMsg(null); }}
                    className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
                  >
                    <Languages size={18} className="text-emerald-400" /> {t("chat.showOriginal")}
                  </button>
                ) : (
                  <div className="px-4 py-2">
                    <p className="flex items-center gap-2 text-white/60 text-xs mb-2">
                      <Languages size={16} className="text-emerald-400" /> {t("chat.translateTo")}
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
              {!sheetMsg.is_mine && (
                <button
                  onClick={() => openReport(sheetMsg)}
                  className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-rose-400 text-sm text-right"
                >
                  <Flag size={18} /> {t("chat.reportMsg")}
                </button>
              )}
              {sheetMsg.is_mine && (
                <>
                  {(!sheetMsg.media_type || ["image", "video", "file", "voice"].includes(sheetMsg.media_type)) && (
                    <button
                      onClick={() => startEdit(sheetMsg)}
                      className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-white text-sm text-right"
                    >
                      <Pencil size={18} className="text-white/60" /> {sheetMsg.media_type ? t("chat.editCaption") : t("chat.edit")}
                    </button>
                  )}
                  <button
                    onClick={() => doDelete(sheetMsg)}
                    className="w-full flex items-center gap-3 px-4 py-3 rounded-xl hover:bg-white/5 text-red-400 text-sm text-right"
                  >
                    <Trash2 size={18} /> {t("chat.deleteForAll")}
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
                <Forward size={18} className="text-indigo-400" /> {forwardBulk ? `${t("chat.forwardNMsgPre")}${toPersianNum(selectedIds.size)}${t("chat.forwardNMsgSuf")}` : t("chat.forwardTo")}
              </p>
              <button onClick={() => { if (!forwardBusy) { setForwardMsg(null); setForwardBulk(false); } }} className="p-1.5 rounded-lg hover:bg-white/5 text-white/50">
                <X size={18} />
              </button>
            </div>
            {/* attribution toggle */}
            <div className="flex gap-2 mb-3 bg-white/5 rounded-xl p-0.5 text-xs">
              <button onClick={() => setForwardAnon(false)} className={`flex-1 py-2 rounded-lg transition ${!forwardAnon ? "bg-indigo-600 text-white" : "text-white/60"}`}>{t("chat.withSenderName")}</button>
              <button onClick={() => setForwardAnon(true)} className={`flex-1 py-2 rounded-lg transition ${forwardAnon ? "bg-indigo-600 text-white" : "text-white/60"}`}>{t("chat.anonymous")}</button>
            </div>
            {forwardRooms.length === 0 ? (
              <p className="text-white/40 text-sm text-center py-6">{t("chat.noForwardTarget")}</p>
            ) : (
              <div className="space-y-1">
                {forwardRooms.map((r) => {
                  const rn = r.type === "group" ? (r.name ?? t("chat.group")) : (r.partner_name ?? r.name ?? t("chat.conversation"));
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
              <p className="text-white font-bold">{t("chat.membersOfPre")}{room.name ?? t("chat.group")}{t("chat.membersOfSuf")}</p>
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
                {addBusy ? <Loader2 size={16} className="animate-spin" /> : <><UserPlus size={16} /> {t("chat.add")}</>}
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
                        {m.is_me ? t("chat.you") : (m.name ?? m.earth_id)}
                        {m.is_admin && <Crown size={13} className="text-amber-400" />}
                      </p>
                      <p className="text-[11px] text-white/40 font-mono" dir="ltr">{m.earth_id}</p>
                    </div>
                    {iAmAdmin && !m.is_me && (
                      <button
                        onClick={() => doRemoveMember(m.earth_id)}
                        className="p-2 rounded-lg hover:bg-white/5 text-red-400/70"
                        title={t("chat.removeFromGroup")}
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
              <LogOut size={16} /> {t("chat.leaveGroup")}
            </button>
          </div>
        </div>
      )}

      {/* Translation settings */}
      {showLangMenu && (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/50" onClick={() => setShowLangMenu(false)}>
          <div className="w-full max-w-md bg-[#1C1C1E] rounded-t-3xl p-4 pb-safe max-h-[80vh] overflow-y-auto animate-[slideUp_0.2s_ease]" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-1">
              <p className="text-white font-bold flex items-center gap-2"><Languages size={18} className="text-emerald-400" /> {t("chat.liveTranslate")}</p>
              <button onClick={() => setShowLangMenu(false)} className="p-1.5 rounded-lg hover:bg-white/5 text-white/50"><X size={18} /></button>
            </div>
            <p className="text-white/40 text-xs mb-3">{t("chat.translateDesc")}</p>

            {/* auto toggle */}
            <button
              onClick={toggleAuto}
              className="w-full flex items-center justify-between gap-3 px-4 py-3 rounded-xl bg-white/5 mb-4"
            >
              <span className="flex items-center gap-2 text-sm text-white">
                <Radio size={16} className={autoTr ? "text-emerald-400" : "text-white/40"} />
                {t("chat.autoTranslate")}
              </span>
              <span className={`w-11 h-6 rounded-full flex items-center px-0.5 transition-colors ${autoTr ? "bg-emerald-500 justify-end" : "bg-white/15 justify-start"}`}>
                <span className="w-5 h-5 rounded-full bg-white" />
              </span>
            </button>

            <p className="text-white/40 text-xs mb-2 px-1">{t("chat.targetLang")}</p>
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
              {editing ? t("chat.editMessage") : `${t("chat.replyToPre")}${replyTo?.sender_name ?? t("chat.role.user")}`}
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
              <Phone size={17} className="text-emerald-400 shrink-0" /> {t("chat.voiceCall")}
            </button>
            <button
              onClick={() => { setShowCallMenu(false); useCallStore.getState().startCall(room.partner_earth_id!, partnerName, "video"); }}
              className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-white text-[13px] text-right"
            >
              <Video size={17} className="text-indigo-400 shrink-0" /> {t("chat.videoCall")}
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
                <Users size={17} className="text-sky-400 shrink-0" /> {t("chat.viewContact")}
              </button>
            )}
            {isGroup && (
              <button
                onClick={() => { setShowOptions(false); openMembers(); }}
                className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-white text-[13px] text-right"
              >
                <Users size={17} className="text-sky-400 shrink-0" /> {t("chat.groupMembers")}
              </button>
            )}
            <button
              onClick={() => { setShowOptions(false); setShowSearch(true); setSearchQ(""); setSearchResults([]); }}
              className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-white text-[13px] text-right"
            >
              <Search size={17} className="text-white/70 shrink-0" /> {t("chat.searchInChat")}
            </button>
            <button
              onClick={() => { setShowOptions(false); setShowLangMenu(true); }}
              className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-white text-[13px] text-right"
            >
              <Languages size={17} className="text-emerald-400 shrink-0" /> {t("chat.liveTranslate")}
              {autoTr && <span className="mr-auto text-[10px] text-emerald-400">{t("chat.on")}</span>}
            </button>
            <button
              onClick={() => { setShowOptions(false); setShowChatSettings(true); }}
              className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-white text-[13px] text-right"
            >
              <Palette size={17} className="text-fuchsia-400 shrink-0" /> {t("chat.customizeChat")}
            </button>
            <button
              onClick={exportChat}
              className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-white text-[13px] text-right"
            >
              <Download size={17} className="text-amber-400 shrink-0" /> {t("chat.exportChat")}
            </button>
            <button
              onClick={() => toggleMute()}
              className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-white text-[13px] text-right"
            >
              {isMuted
                ? <><Bell size={17} className="text-white/70 shrink-0" /> {t("chat.unmute")}</>
                : <><BellOff size={17} className="text-white/70 shrink-0" /> {t("chat.mute")}</>}
            </button>
            <button
              onClick={() => { setShowOptions(false); setShowDisappear(true); }}
              className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-white text-[13px] text-right"
            >
              <Timer size={17} className="text-orange-400 shrink-0" /> {t("chat.disappearing")}
              {disappearSec > 0 && <span className="mr-auto text-[10px] text-orange-400">{disappearLabel(disappearSec, t)}</span>}
            </button>
            <div className="my-1 border-t border-white/8" />
            <button
              onClick={doClearChat}
              className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-white text-[13px] text-right"
            >
              <Trash2 size={17} className="text-white/70 shrink-0" /> {t("chat.clearChat")}
            </button>
            {!isGroup && room.partner_earth_id && (
              <button
                onClick={toggleBlock}
                className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-[13px] text-right text-rose-400"
              >
                <Ban size={17} className="shrink-0" /> {isBlocked ? t("chat.unblock") : t("chat.block")}
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
                title={t("chat.camera")}
                className="w-14 h-14 rounded-full bg-indigo-500/15 flex items-center justify-center active:scale-95 transition"
              >
                <Camera size={24} className="text-indigo-400" />
              </button>
              <button
                onClick={() => { setShowAttach(false); fileInputRef.current?.click(); }}
                title={t("chat.photoOrFile")}
                className="w-14 h-14 rounded-full bg-sky-500/15 flex items-center justify-center active:scale-95 transition"
              >
                <ImageIcon size={24} className="text-sky-400" />
              </button>
              <button
                onClick={shareStaticLocation}
                title={t("chat.location")}
                className="w-14 h-14 rounded-full bg-red-500/15 flex items-center justify-center active:scale-95 transition"
              >
                <MapPin size={24} className="text-red-400" />
              </button>
              <button
                onClick={() => { setShowAttach(false); setShowLiveDur(true); }}
                title={t("chat.liveLocation")}
                className="w-14 h-14 rounded-full bg-emerald-500/15 flex items-center justify-center active:scale-95 transition"
              >
                <Radio size={24} className="text-emerald-400" />
              </button>
              <button
                onClick={() => { setShowAttach(false); openPollCreate(); }}
                title={t("chat.poll")}
                className="w-14 h-14 rounded-full bg-amber-500/15 flex items-center justify-center active:scale-95 transition"
              >
                <BarChart3 size={24} className="text-amber-400" />
              </button>
              <button
                onClick={() => { setShowAttach(false); openContactPick(); }}
                title={t("chat.shareContact")}
                className="w-14 h-14 rounded-full bg-teal-500/15 flex items-center justify-center active:scale-95 transition"
              >
                <UserRound size={24} className="text-teal-400" />
              </button>
              <button
                onClick={() => { setShowAttach(false); openEventCreate(); }}
                title={t("chat.event")}
                className="w-14 h-14 rounded-full bg-fuchsia-500/15 flex items-center justify-center active:scale-95 transition"
              >
                <CalendarClock size={24} className="text-fuchsia-400" />
              </button>
              <button
                onClick={() => { setShowAttach(false); openRedPacketCreate(); }}
                title={t("chat.redPacket")}
                className="w-14 h-14 rounded-full bg-rose-500/15 flex items-center justify-center active:scale-95 transition"
              >
                <Gift size={24} className="text-rose-400" />
              </button>
              {/* پولِ مستقیم فقط در گفتگوی دونفره — پولِ گروهی مسیرِ 🧧 را دارد */}
              {room.type !== "group" && (
                <>
                  <button
                    onClick={() => { setShowAttach(false); openMoney("send"); }}
                    title={t("chat.money.send")}
                    className="w-14 h-14 rounded-full bg-emerald-500/15 flex items-center justify-center active:scale-95 transition"
                  >
                    <Banknote size={24} className="text-emerald-400" />
                  </button>
                  <button
                    onClick={() => { setShowAttach(false); openMoney("request"); }}
                    title={t("chat.money.request")}
                    className="w-14 h-14 rounded-full bg-amber-500/15 flex items-center justify-center active:scale-95 transition"
                  >
                    <HandCoins size={24} className="text-amber-400" />
                  </button>
                </>
              )}
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
              <p className="text-white font-bold">{t("chat.newPoll")}</p>
            </div>
            <label className="block text-white/40 text-xs mb-1">{t("chat.question")}</label>
            <input
              value={pollQuestion}
              onChange={(e) => setPollQuestion(e.target.value)}
              maxLength={300}
              placeholder={t("chat.questionPh")}
              className="w-full bg-[#0A0A0A] border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white outline-none focus:border-amber-500/50 mb-3"
            />
            <label className="block text-white/40 text-xs mb-1">{t("chat.optionsLabel")}</label>
            <div className="space-y-2 mb-3">
              {pollOptions.map((opt, i) => (
                <div key={i} className="flex items-center gap-2">
                  <input
                    value={opt}
                    onChange={(e) => setPollOptions((prev) => prev.map((o, j) => j === i ? e.target.value : o))}
                    maxLength={100}
                    placeholder={`${t("chat.optionPhPre")}${i + 1}`}
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
                <PlusCircle size={18} /> {t("chat.addOption")}
              </button>
            )}
            <button
              onClick={() => setPollMultiple((v) => !v)}
              className="w-full flex items-center justify-between px-3 py-2.5 rounded-xl bg-[#0A0A0A] mb-4"
            >
              <span className="text-white text-sm">{t("chat.allowMulti")}</span>
              <span className={`w-10 h-6 rounded-full flex items-center transition ${pollMultiple ? "bg-amber-500 justify-end" : "bg-white/15 justify-start"} p-0.5`}>
                <span className="w-5 h-5 rounded-full bg-white" />
              </span>
            </button>
            <button
              onClick={submitPoll}
              disabled={pollSending || !pollQuestion.trim() || pollOptions.filter((o) => o.trim()).length < 2}
              className="w-full py-3 rounded-xl bg-amber-500 text-black font-bold text-sm disabled:opacity-40 active:scale-[0.99] transition"
            >
              {pollSending ? t("chat.sending") : t("chat.createPoll")}
            </button>
          </div>
        </div>
      )}

      {/* 🧧 Red-packet composer */}
      {showRedPacket && (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/50" onClick={() => setShowRedPacket(false)}>
          <div className="w-full max-w-md bg-[#1C1C1E] rounded-t-3xl p-4 pb-safe animate-[slideUp_0.2s_ease] max-h-[88vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center gap-2 mb-4">
              <span className="w-9 h-9 rounded-full bg-rose-500/15 flex items-center justify-center text-lg">🧧</span>
              <p className="text-white font-bold">{t("chat.redPacket")}</p>
            </div>

            {room.type === "group" && (
              <div className="flex gap-2 mb-3">
                <button
                  onClick={() => setRpMode("random")}
                  className={`flex-1 py-2 rounded-xl text-sm font-semibold transition ${rpMode === "random" ? "bg-rose-500 text-white" : "bg-[#0A0A0A] text-white/60"}`}
                >{t("chat.rpRandomBtn")}</button>
                <button
                  onClick={() => setRpMode("equal")}
                  className={`flex-1 py-2 rounded-xl text-sm font-semibold transition ${rpMode === "equal" ? "bg-rose-500 text-white" : "bg-[#0A0A0A] text-white/60"}`}
                >{t("chat.rpEqual")}</button>
              </div>
            )}

            <label className="block text-white/40 text-xs mb-1">{t("chat.rpTotalAmount")}</label>
            <input
              value={rpAmount}
              onChange={(e) => setRpAmount(e.target.value.replace(/[^0-9]/g, ""))}
              inputMode="numeric"
              placeholder={t("chat.rpAmountPh")}
              className="w-full bg-[#0A0A0A] border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white outline-none focus:border-rose-500/50 mb-1 text-left"
              dir="ltr"
            />
            {rpAmount && (
              <p className="text-white/50 text-[11px] mb-3">{fmtToman(parseInt(rpAmount || "0", 10) * 10)}{t("chat.tomanSuffix")}</p>
            )}
            {!rpAmount && <div className="mb-3" />}

            {room.type === "group" && (
              <>
                <label className="block text-white/40 text-xs mb-1">{t("chat.rpShareCount")}</label>
                <input
                  value={rpCount}
                  onChange={(e) => setRpCount(e.target.value.replace(/[^0-9]/g, ""))}
                  inputMode="numeric"
                  placeholder="۱"
                  className="w-full bg-[#0A0A0A] border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white outline-none focus:border-rose-500/50 mb-3 text-left"
                  dir="ltr"
                />
              </>
            )}

            <label className="block text-white/40 text-xs mb-1">{t("chat.rpGreetingLabel")}</label>
            <input
              value={rpGreeting}
              onChange={(e) => setRpGreeting(e.target.value)}
              maxLength={200}
              placeholder={t("chat.rpGreetingPh")}
              className="w-full bg-[#0A0A0A] border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white outline-none focus:border-rose-500/50 mb-4"
            />

            <button
              onClick={submitRedPacket}
              disabled={rpSending || !rpAmount}
              className="w-full py-3 rounded-xl bg-gradient-to-r from-rose-500 to-orange-500 text-white font-bold text-sm disabled:opacity-40 active:scale-[0.99] transition"
            >
              {rpSending ? t("chat.sending") : t("chat.rpSendBtn")}
            </button>
            <p className="text-white/35 text-[10px] text-center mt-2">
              {t("chat.rpNote")}
            </p>
          </div>
        </div>
      )}

      {/* 💸 ارسال / درخواستِ پول */}
      {moneyMode && (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/50" onClick={() => setMoneyMode(null)}>
          <div className="w-full max-w-md bg-[#1C1C1E] rounded-t-3xl p-4 pb-safe animate-[slideUp_0.2s_ease] max-h-[88vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center gap-2 mb-4">
              <span className={`w-9 h-9 rounded-full flex items-center justify-center ${moneyMode === "send" ? "bg-emerald-500/15" : "bg-amber-500/15"}`}>
                {moneyMode === "send"
                  ? <Banknote size={18} className="text-emerald-400" />
                  : <HandCoins size={18} className="text-amber-400" />}
              </span>
              <p className="text-white font-bold">
                {moneyMode === "send" ? t("chat.money.send") : t("chat.money.request")}
              </p>
            </div>

            <div className="flex gap-2 mb-4">
              <button
                onClick={() => setMoneyMode("send")}
                className={`flex-1 py-2 rounded-xl text-sm font-semibold transition ${moneyMode === "send" ? "bg-emerald-500 text-white" : "bg-[#0A0A0A] text-white/60"}`}
              >{t("chat.money.send")}</button>
              <button
                onClick={() => setMoneyMode("request")}
                className={`flex-1 py-2 rounded-xl text-sm font-semibold transition ${moneyMode === "request" ? "bg-amber-500 text-white" : "bg-[#0A0A0A] text-white/60"}`}
              >{t("chat.money.request")}</button>
            </div>

            <label className="block text-white/40 text-xs mb-1">{t("chat.money.amount")}</label>
            <input
              value={moneyAmount}
              onChange={(e) => setMoneyAmount(e.target.value.replace(/[^0-9]/g, ""))}
              inputMode="numeric"
              placeholder={t("chat.money.amountPh")}
              className="w-full bg-[#0A0A0A] border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white outline-none focus:border-emerald-500/50 mb-1 text-left"
              dir="ltr"
            />
            <p className="text-white/50 text-[11px] mb-3 h-4">
              {moneyAmount ? `${toPersianNum(parseInt(moneyAmount, 10).toLocaleString("en-US"))}${t("chat.tomanSuffix")}` : ""}
            </p>

            <label className="block text-white/40 text-xs mb-1">{t("chat.money.note")}</label>
            <input
              value={moneyNote}
              onChange={(e) => setMoneyNote(e.target.value)}
              maxLength={200}
              placeholder={t("chat.money.notePh")}
              className="w-full bg-[#0A0A0A] border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white outline-none focus:border-emerald-500/50 mb-4"
            />

            <button
              onClick={submitMoney}
              disabled={moneySending || !moneyAmount}
              className={`w-full py-3 rounded-xl text-white font-bold text-sm disabled:opacity-40 active:scale-[0.99] transition ${
                moneyMode === "send"
                  ? "bg-gradient-to-r from-emerald-500 to-teal-600"
                  : "bg-gradient-to-r from-amber-500 to-orange-500"
              }`}
            >
              {moneySending
                ? t("chat.sending")
                : moneyMode === "send" ? t("chat.money.sendBtn") : t("chat.money.requestBtn")}
            </button>
            <p className="text-white/35 text-[10px] text-center mt-2">
              {moneyMode === "send" ? t("chat.money.sendNote") : t("chat.money.requestNote")}
            </p>
          </div>
        </div>
      )}

      {/* 🧧 Red-packet detail */}
      {rpDetail && (
        <div className="fixed inset-0 z-[55] flex items-end justify-center bg-black/60" onClick={() => setRpDetail(null)}>
          <div className="w-full max-w-md bg-[#1C1C1E] rounded-t-3xl pb-safe animate-[slideUp_0.2s_ease] max-h-[85vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <div className="bg-gradient-to-br from-rose-500 to-orange-500 px-4 pt-5 pb-4 text-center relative">
              <button onClick={() => setRpDetail(null)} className="absolute top-3 left-3 text-white/80"><X size={20} /></button>
              <div className="text-3xl mb-1">🧧</div>
              <p className="text-white font-bold">{rpDetail.greeting || t("chat.redPacket")}</p>
              <p className="text-white/80 text-[12px] mt-0.5">{t("chat.rpFromPre")}{rpDetail.sender_name}</p>
              {rpDetail.my_amount != null && (
                <p className="text-white text-2xl font-black mt-3">{fmtToman(rpDetail.my_amount)} <span className="text-sm font-bold">{t("chat.toman")}</span></p>
              )}
            </div>
            <div className="px-4 py-3">
              <p className="text-white/50 text-[12px] mb-2 flex items-center justify-between">
                <span>{toPersianNum(rpDetail.claimed_count)}{t("chat.rpClaimedSharesMid")}{toPersianNum(rpDetail.count)}{t("chat.rpClaimedSharesSuf")}</span>
                <span>{fmtToman(rpDetail.claimed_amount)} / {fmtToman(rpDetail.total_amount)}{t("chat.tomanSuffix")}</span>
              </p>
              <div className="space-y-1.5">
                {(rpDetail.claims || []).map((c) => (
                  <div key={c.earth_id} className="flex items-center gap-2.5 py-1.5">
                    <span className="shrink-0 w-9 h-9 rounded-full overflow-hidden bg-white/10 flex items-center justify-center text-sm">
                      {c.avatar_url ? <img src={c.avatar_url} alt="" className="w-full h-full object-cover" /> : (c.name?.[0] ?? "👤")}
                    </span>
                    <span className="flex-1 min-w-0">
                      <span className="block text-white text-sm truncate">{c.name}</span>
                      <span className="block text-white/40 text-[10px]">{formatTime(c.created_at, t)}</span>
                    </span>
                    <span className="shrink-0 text-rose-400 font-bold text-sm">{fmtToman(c.amount)} <span className="text-[10px] text-white/50">{t("chat.toman")}</span></span>
                  </div>
                ))}
                {(!rpDetail.claims || rpDetail.claims.length === 0) && (
                  <p className="text-white/40 text-sm text-center py-4">{t("chat.rpNobodyYet")}</p>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Disappearing-messages picker */}
      {showDisappear && (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/50" onClick={() => setShowDisappear(false)}>
          <div className="w-full max-w-md bg-[#1C1C1E] rounded-t-3xl p-4 pb-safe animate-[slideUp_0.2s_ease]" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center gap-2 mb-1">
              <Timer size={20} className="text-orange-400" />
              <p className="text-white font-bold">{t("chat.disappearing")}</p>
            </div>
            <p className="text-white/40 text-xs mb-3">{t("chat.disappearDesc")}</p>
            <div className="space-y-1">
              {DISAPPEAR_OPTS.map((o) => (
                <button
                  key={o.sec}
                  onClick={() => applyDisappearing(o.sec)}
                  className={`w-full flex items-center gap-3 px-4 py-3 rounded-xl text-sm text-right ${disappearSec === o.sec ? "bg-orange-500/15 text-orange-300" : "hover:bg-white/5 text-white"}`}
                >
                  <Timer size={18} className={disappearSec === o.sec ? "text-orange-400" : "text-white/50"} />
                  <span className="flex-1">{t(o.label)}</span>
                  {disappearSec === o.sec && <Check size={17} className="text-orange-400" />}
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Contact picker */}
      {showContactPick && (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/50" onClick={() => setShowContactPick(false)}>
          <div className="w-full max-w-md bg-[#1C1C1E] rounded-t-3xl p-4 pb-safe animate-[slideUp_0.2s_ease] max-h-[80vh] flex flex-col" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center gap-2 mb-3">
              <UserRound size={20} className="text-teal-400" />
              <p className="text-white font-bold">{t("chat.shareContact")}</p>
            </div>
            <div className="relative mb-3">
              <Search size={16} className="absolute right-3 top-1/2 -translate-y-1/2 text-white/40" />
              <input
                autoFocus
                value={contactQ}
                onChange={(e) => setContactQ(e.target.value)}
                placeholder={t("chat.contactSearchPh")}
                className="w-full bg-[#0A0A0A] border border-white/10 rounded-xl pr-9 pl-3 py-2.5 text-sm text-white outline-none focus:border-teal-500/50"
              />
            </div>
            <div className="flex-1 overflow-y-auto -mx-1 px-1">
              {contactBusy ? (
                <div className="flex justify-center py-6"><Loader2 size={20} className="text-white/40 animate-spin" /></div>
              ) : contactResults.length === 0 ? (
                <p className="text-center text-white/30 text-xs py-6">{contactQ.trim().length < 2 ? t("chat.searchMin2") : t("chat.noUserFound")}</p>
              ) : (
                contactResults.map((u) => (
                  <button
                    key={u.earth_id}
                    onClick={() => sendContact(u.earth_id)}
                    className="w-full flex items-center gap-3 px-2 py-2.5 rounded-xl hover:bg-white/5 text-right"
                  >
                    <span className="shrink-0 w-10 h-10 rounded-full overflow-hidden bg-white/10 flex items-center justify-center">
                      {u.avatar_url ? <img src={u.avatar_url} alt="" className="w-full h-full object-cover" /> : (u.name?.[0] ?? "👤")}
                    </span>
                    <span className="flex-1 min-w-0">
                      <span className="block text-sm text-white truncate">{u.name ?? u.earth_id}</span>
                      <span className="block text-[11px] text-white/40 truncate">{u.earth_id}</span>
                    </span>
                    <Send size={16} className="text-teal-400 shrink-0" />
                  </button>
                ))
              )}
            </div>
          </div>
        </div>
      )}

      {/* Event creation sheet */}
      {showEventCreate && (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/50" onClick={() => setShowEventCreate(false)}>
          <div className="w-full max-w-md bg-[#1C1C1E] rounded-t-3xl p-4 pb-safe animate-[slideUp_0.2s_ease] max-h-[85vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center gap-2 mb-3">
              <CalendarClock size={20} className="text-fuchsia-400" />
              <p className="text-white font-bold">{t("chat.newEvent")}</p>
            </div>
            <label className="block text-white/40 text-xs mb-1">{t("chat.title")}</label>
            <input
              value={evTitle}
              onChange={(e) => setEvTitle(e.target.value)}
              maxLength={200}
              placeholder={t("chat.eventTitlePh")}
              className="w-full bg-[#0A0A0A] border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white outline-none focus:border-fuchsia-500/50 mb-3"
            />
            <label className="block text-white/40 text-xs mb-1">{t("chat.time")}</label>
            <input
              type="datetime-local"
              value={evWhen}
              onChange={(e) => setEvWhen(e.target.value)}
              className="w-full bg-[#0A0A0A] border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white outline-none focus:border-fuchsia-500/50 mb-3 [color-scheme:dark]"
            />
            <label className="block text-white/40 text-xs mb-1">{t("chat.locationOptional")}</label>
            <input
              value={evLoc}
              onChange={(e) => setEvLoc(e.target.value)}
              maxLength={300}
              placeholder={t("chat.eventLocationPh")}
              className="w-full bg-[#0A0A0A] border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white outline-none focus:border-fuchsia-500/50 mb-3"
            />
            <label className="block text-white/40 text-xs mb-1">{t("chat.descOptional")}</label>
            <textarea
              value={evDesc}
              onChange={(e) => setEvDesc(e.target.value)}
              rows={2}
              placeholder={t("chat.eventDescPh")}
              className="w-full bg-[#0A0A0A] border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white outline-none focus:border-fuchsia-500/50 mb-4 resize-none"
            />
            <button
              onClick={submitEvent}
              disabled={evSending || !evTitle.trim() || !evWhen}
              className="w-full py-3 rounded-xl bg-fuchsia-500 text-white font-bold text-sm disabled:opacity-40 active:scale-[0.99] transition"
            >
              {evSending ? t("chat.sending") : t("chat.createEvent")}
            </button>
          </div>
        </div>
      )}

      {/* Report sheet */}
      {reportTarget && (
        <div className="fixed inset-0 z-[55] flex items-end justify-center bg-black/50" onClick={() => setReportTarget(null)}>
          <div className="w-full max-w-md bg-[#1C1C1E] rounded-t-3xl p-4 pb-safe animate-[slideUp_0.2s_ease]" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center gap-2 mb-1">
              <Flag size={20} className="text-rose-400" />
              <p className="text-white font-bold">{t("chat.reportMsg")}</p>
            </div>
            <p className="text-white/40 text-xs mb-3">{t("chat.reportDesc")}</p>
            <div className="space-y-1 mb-3">
              {REPORT_REASONS.map((r) => (
                <button
                  key={r.key}
                  onClick={() => setReportReason(r.key)}
                  className={`w-full flex items-center gap-3 px-4 py-2.5 rounded-xl text-sm text-right ${reportReason === r.key ? "bg-rose-500/15 text-rose-300 ring-1 ring-rose-500/40" : "hover:bg-white/5 text-white"}`}
                >
                  <span className="flex-1">{t(r.label)}</span>
                  {reportReason === r.key && <Check size={16} className="text-rose-400" />}
                </button>
              ))}
            </div>
            <textarea
              value={reportNote}
              onChange={(e) => setReportNote(e.target.value)}
              rows={2}
              maxLength={500}
              placeholder={t("chat.reportMorePh")}
              className="w-full bg-[#0A0A0A] border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white outline-none focus:border-rose-500/50 mb-4 resize-none"
            />
            <button
              onClick={submitReport}
              disabled={reportBusy || !reportReason}
              className="w-full py-3 rounded-xl bg-rose-500 text-white font-bold text-sm disabled:opacity-40 active:scale-[0.99] transition"
            >
              {reportBusy ? t("chat.sending") : t("chat.submitReport")}
            </button>
          </div>
        </div>
      )}

      {/* Live-location duration picker */}
      {showLiveDur && (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/50" onClick={() => setShowLiveDur(false)}>
          <div className="w-full max-w-md bg-[#1C1C1E] rounded-t-3xl p-4 pb-safe animate-[slideUp_0.2s_ease]" onClick={(e) => e.stopPropagation()}>
            <p className="text-white font-bold mb-1">{t("chat.shareLiveLocation")}</p>
            <p className="text-white/40 text-xs mb-3">{t("chat.liveLocationDesc")}</p>
            <div className="space-y-1">
              {[{ m: 15, t: t("chat.dur15m") }, { m: 60, t: t("chat.dur1h") }, { m: 480, t: t("chat.dur8h") }].map((o) => (
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
                placeholder={t("chat.searchChatPh")}
                className="flex-1 bg-transparent py-2.5 text-white text-sm outline-none placeholder:text-white/30"
              />
              {searchQ && (
                <button onClick={() => { setSearchQ(""); setSearchResults([]); }} className="text-white/40 hover:text-white/70"><X size={16} /></button>
              )}
            </div>
            <button onClick={runSearch} className="px-3 py-2 rounded-xl bg-indigo-600 text-white text-sm">{t("chat.searchBtn")}</button>
          </div>
          <div className="flex-1 overflow-y-auto">
            {searchBusy ? (
              <div className="flex justify-center pt-10"><Loader2 size={26} className="text-indigo-400 animate-spin" /></div>
            ) : searchQ.trim().length < 2 ? (
              <p className="text-white/30 text-sm text-center pt-10">{t("chat.searchMin2Chars")}</p>
            ) : searchResults.length === 0 ? (
              <p className="text-white/30 text-sm text-center pt-10">{t("chat.noResults")}</p>
            ) : (
              <div className="divide-y divide-white/5">
                {searchResults.map((m) => (
                  <button
                    key={m.id}
                    onClick={() => jumpToMessage(m)}
                    className="w-full text-right px-4 py-3 hover:bg-white/5"
                  >
                    <div className="flex items-center justify-between mb-1">
                      <span className="text-indigo-300 text-xs font-medium truncate">{m.is_mine ? t("chat.you") : (m.sender_name ?? t("chat.role.user"))}</span>
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

      {/* Input */}
      <div className="px-3 py-3 border-t border-white/8 bg-[#0A0A0A] pb-safe">
        <input ref={fileInputRef} type="file" hidden onChange={onPickFile} />
        <input ref={camInputRef} type="file" accept="image/*" capture="environment" hidden onChange={onPickFile} />

        {/* Emoji picker — درون‌جریان و بالای نوارِ ورودی تا متن پنهان نشود (باگ ۲) */}
        {showEmoji && !recording && (
          <div className="mb-2 bg-[#141414] border border-white/8 rounded-2xl p-3 animate-[slideUp_0.15s_ease]">
            <div className="flex items-center justify-between mb-2 px-1">
              <div className="flex gap-1 bg-white/5 rounded-xl p-0.5 text-xs">
                <button
                  onClick={() => setEmojiTab("emoji")}
                  className={`px-3 py-1 rounded-lg transition ${emojiTab === "emoji" ? "bg-indigo-600 text-white" : "text-white/60"}`}
                >
                  {t("chat.emoji")}
                </button>
                <button
                  onClick={() => setEmojiTab("sticker")}
                  className={`px-3 py-1 rounded-lg transition ${emojiTab === "sticker" ? "bg-indigo-600 text-white" : "text-white/60"}`}
                >
                  {t("chat.sticker")}
                </button>
                <button
                  onClick={() => setEmojiTab("maker")}
                  className={`px-3 py-1 rounded-lg transition ${emojiTab === "maker" ? "bg-indigo-600 text-white" : "text-white/60"}`}
                >
                  اموجی‌ساز
                </button>
              </div>
              <button onClick={() => setShowEmoji(false)} className="p-1 rounded-lg text-white/50 hover:bg-white/5"><X size={16} /></button>
            </div>

            {emojiTab === "emoji" && (
              <div className="grid grid-cols-8 gap-1 max-h-56 overflow-y-auto">
                {COMPOSE_EMOJIS.map((emo, i) => (
                  <button
                    key={`${emo}-${i}`}
                    onMouseDown={(e) => e.preventDefault()}
                    onClick={() => insertEmoji(emo)}
                    className="h-9 rounded-lg text-xl hover:bg-white/5 flex items-center justify-center"
                  >
                    {emo}
                  </button>
                ))}
              </div>
            )}

            {emojiTab === "sticker" && (
              <div className="max-h-56 overflow-y-auto space-y-2 py-1">
                <button
                  onClick={() => { setShowEmoji(false); setLibraryPackId(null); setShowLibrary(true); }}
                  className="w-full flex items-center gap-3 px-3 py-3 rounded-xl bg-white/5 hover:bg-white/10 text-white text-sm text-right"
                >
                  <span className="w-9 h-9 rounded-full bg-amber-500/15 flex items-center justify-center"><Star size={18} className="text-amber-400" /></span>
                  <span className="flex-1">{t("chat.stickerLib")}</span>
                </button>
                <button
                  onClick={() => { setShowEmoji(false); setShowStudio(true); }}
                  className="w-full flex items-center gap-3 px-3 py-3 rounded-xl bg-white/5 hover:bg-white/10 text-white text-sm text-right"
                >
                  <span className="w-9 h-9 rounded-full bg-fuchsia-500/15 flex items-center justify-center"><Sticker size={18} className="text-fuchsia-400" /></span>
                  <span className="flex-1">{t("chat.makeSticker")}</span>
                </button>
              </div>
            )}

            {emojiTab === "maker" && (
              <div>
                <div className="flex items-center gap-3 mb-2">
                  <canvas ref={mixCanvasRef} width={256} height={256} className="w-16 h-16 rounded-xl bg-white/5 border border-white/10 shrink-0" />
                  <div className="flex-1 flex items-center justify-center gap-2">
                    <button
                      onClick={() => setMixSlot("a")}
                      className={`w-12 h-12 rounded-xl text-2xl flex items-center justify-center border transition ${mixSlot === "a" ? "border-indigo-500 bg-indigo-500/15" : "border-white/10 bg-white/5"}`}
                    >
                      {mixA}
                    </button>
                    <span className="text-white/40 text-lg">+</span>
                    <button
                      onClick={() => setMixSlot("b")}
                      className={`w-12 h-12 rounded-xl text-2xl flex items-center justify-center border transition ${mixSlot === "b" ? "border-indigo-500 bg-indigo-500/15" : "border-white/10 bg-white/5"}`}
                    >
                      {mixB}
                    </button>
                  </div>
                  <button
                    onClick={sendMix}
                    disabled={mixSending}
                    className="w-11 h-11 rounded-2xl bg-indigo-600 flex items-center justify-center disabled:opacity-40 hover:bg-indigo-500 transition-colors shrink-0"
                    title={t("chat.send")}
                  >
                    {mixSending ? <Loader2 size={18} className="text-white animate-spin" /> : <Send size={18} className="text-white" />}
                  </button>
                </div>
                <p className="text-[11px] text-white/40 px-1 mb-1">خانهٔ فعال را انتخاب و یک اموجی بزنید تا با هم ترکیب شوند، سپس ارسال کنید.</p>
                <div className="grid grid-cols-8 gap-1 max-h-40 overflow-y-auto">
                  {COMPOSE_EMOJIS.map((emo, i) => (
                    <button
                      key={`mix-${emo}-${i}`}
                      onMouseDown={(e) => e.preventDefault()}
                      onClick={() => pickMixEmoji(emo)}
                      className="h-9 rounded-lg text-xl hover:bg-white/5 flex items-center justify-center"
                    >
                      {emo}
                    </button>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}
        {recording ? (
          <div className="flex items-center gap-3">
            <button
              onClick={() => stopRec(true)}
              className="w-11 h-11 rounded-2xl bg-white/5 flex items-center justify-center text-white/60 hover:bg-white/10 flex-shrink-0"
              title={t("chat.cancel")}
            >
              <Trash2 size={18} />
            </button>
            <div className="flex-1 flex items-center gap-2 text-red-400">
              <span className="w-2.5 h-2.5 rounded-full bg-red-500 animate-pulse" />
              <span className="text-sm font-mono">{toPersianNum(`${Math.floor(recSeconds / 60)}:${(recSeconds % 60).toString().padStart(2, "0")}`)}</span>
              <span className="text-xs text-white/40">{t("chat.recording")}</span>
            </div>
            <button
              onClick={() => stopRec(false)}
              className="w-11 h-11 rounded-2xl bg-indigo-600 flex items-center justify-center hover:bg-indigo-500 flex-shrink-0"
              title={t("chat.send")}
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
                title={t("chat.emoji")}
              >
                <Smile size={18} />
              </button>
            )}
            {!editing && (
              <button
                onClick={() => { setShowEmoji(false); setShowAttach(true); }}
                disabled={locBusy}
                className="w-11 h-11 rounded-2xl bg-[#1C1C1E] border border-white/8 flex items-center justify-center text-white/60 hover:text-white hover:bg-white/5 flex-shrink-0 disabled:opacity-50"
                title={t("chat.attach")}
              >
                {locBusy ? <Loader2 size={18} className="animate-spin" /> : <Paperclip size={18} />}
              </button>
            )}
            <input
              ref={inputRef}
              value={text}
              onSelect={(e) => { const el = e.currentTarget; selRef.current = { start: el.selectionStart ?? 0, end: el.selectionEnd ?? 0 }; }}
              onChange={(e) => { const el = e.currentTarget; selRef.current = { start: el.selectionStart ?? el.value.length, end: el.selectionEnd ?? el.value.length }; setText(el.value); signalTyping(); }}
              onKeyDown={(e) => e.key === "Enter" && !e.shiftKey && (e.preventDefault(), send())}
              placeholder={editing ? t("chat.editMsgPh") : t("chat.msgPh")}
              className="flex-1 min-w-0 bg-[#1C1C1E] border border-white/8 rounded-2xl px-4 py-3 text-white text-sm placeholder-white/30 focus:outline-none focus:border-indigo-500/50 resize-none"
            />
            {text.trim() && (
              <button
                onClick={translateCompose}
                disabled={composeTr}
                className="w-11 h-11 rounded-2xl bg-[#1C1C1E] border border-white/8 flex items-center justify-center text-emerald-400 hover:bg-white/5 flex-shrink-0 disabled:opacity-50"
                title={`${t("chat.translateDraftPre")}${langLabel(trLang)}`}
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
                title={t("chat.voiceMsg")}
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
  const { t } = useTranslation();
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
  const [chatDraft, setChatDraft] = useState("");

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

  // /*rt-poll*/ پولِ لیستِ گفتگوها هر ۱۰ث تا پیام/گفتگوی جدید بدونِ رفرشِ دستی دیده شود
  useEffect(() => {
    const iv = setInterval(() => { loadRooms(); }, 10000);
    return () => clearInterval(iv);
  }, [loadRooms]);

  // URL param: ?to=EARTH_ID → start room directly (intent=collaboration → پیش‌نویسِ همکاری)
  useEffect(() => {
    const to = searchParams.get("to");
    if (to) {
      if (searchParams.get("intent") === "collaboration") {
        setChatDraft(t("chat.collabDraft"));
      }
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
      toast.error(getApiErrorMessage(e, t("chat.toast.userNotFound")));
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
      toast.error(getApiErrorMessage(e, t("chat.toast.groupFail")));
    } finally {
      setCreatingGroup(false);
    }
  };

  if (activeRoom) {
    return (
      <ChatView
        room={activeRoom}
        initialDraft={chatDraft}
        onBack={() => { setActiveRoom(null); setChatDraft(""); loadRooms(); }}
        onLeave={() => { setActiveRoom(null); setChatDraft(""); loadRooms(); }}
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
    <AppShell title={totalUnread > 0 ? `${t("chat.messagesTitlePre")}${toPersianNum(totalUnread)})` : t("chat.messagesTitle")}>
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
              placeholder={t("chat.searchPh")}
              className="w-full bg-[#1C1C1E] border border-white/8 rounded-xl py-2.5 pr-9 pl-3 text-sm text-white placeholder-white/30 focus:outline-none focus:border-indigo-500/50"
            />
          </div>
          <button
            onClick={() => { setShowNew(!showNew); setShowGroup(false); }}
            aria-label={t("chat.newChat")}
            className={`w-10 h-10 rounded-xl flex items-center justify-center transition-colors flex-shrink-0 ${showNew ? "bg-indigo-500" : "bg-indigo-600 hover:bg-indigo-500"}`}
          >
            <MessageCircle size={18} className="text-white" />
          </button>
          <button
            onClick={() => { setShowGroup(!showGroup); setShowNew(false); }}
            aria-label={t("chat.newGroup")}
            className={`w-10 h-10 rounded-xl flex items-center justify-center transition-colors flex-shrink-0 ${showGroup ? "bg-indigo-500" : "bg-[#1C1C1E] border border-white/10 hover:bg-white/5"}`}
          >
            <Users size={18} className="text-white" />
          </button>
        </div>

        {/* New conversation input */}
        {showNew && (
          <div className="mb-4 bg-[#1C1C1E] border border-white/8 rounded-xl p-4">
            <p className="text-white/60 text-xs mb-2">{t("chat.startWithEarthId")}</p>
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
                {starting ? <Loader2 size={16} className="animate-spin" /> : t("chat.start")}
              </button>
            </div>
          </div>
        )}

        {/* New group */}
        {showGroup && (
          <div className="mb-4 bg-[#1C1C1E] border border-white/8 rounded-xl p-4 space-y-2">
            <p className="text-white/60 text-xs">{t("chat.createNewGroup")}</p>
            <input
              value={groupName}
              onChange={(e) => setGroupName(e.target.value)}
              placeholder={t("chat.groupNamePh")}
              maxLength={200}
              className="w-full bg-[#262626] border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white placeholder-white/30 focus:outline-none focus:border-indigo-500"
            />
            <input
              value={groupMembers}
              onChange={(e) => setGroupMembers(e.target.value.toUpperCase())}
              placeholder={t("chat.memberIdsPh")}
              dir="ltr"
              className="w-full bg-[#262626] border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white placeholder-white/30 focus:outline-none focus:border-indigo-500 font-mono"
            />
            <button
              onClick={handleCreateGroup}
              disabled={!groupName.trim() || creatingGroup}
              className="w-full px-4 py-2.5 rounded-xl bg-indigo-600 text-white text-sm font-medium disabled:opacity-40 hover:bg-indigo-500 transition-colors flex items-center justify-center gap-2"
            >
              {creatingGroup ? <Loader2 size={16} className="animate-spin" /> : <><Users size={16} /> {t("chat.makeGroup")}</>}
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
              {search ? t("chat.noResults") : t("chat.noChatsYet")}
            </p>
            {!search && (
              <p className="text-white/20 text-xs">{t("chat.findOnGlobe")}</p>
            )}
          </div>
        ) : (
          <div className="space-y-1">
            {filtered.map((room) => {
              const isGroup = room.type === "group";
              const name = isGroup ? (room.name ?? t("chat.group")) : (room.partner_name ?? room.name ?? t("chat.conversation"));
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
                      <p className="text-xs text-white/30 flex-shrink-0 mr-2">{formatTime(room.last_message_at, t)}</p>
                    </div>
                    <p className="text-xs text-white/40 truncate">
                      {room.last_message || (isGroup ? `${toPersianNum(room.member_count ?? 0)}${t("chat.membersSuffix")}` : t("chat.startConversation"))}
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
