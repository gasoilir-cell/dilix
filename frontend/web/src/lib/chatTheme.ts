// شخصی‌سازیِ ظاهرِ چت — پس‌زمینه و رنگِ حباب‌ها. ذخیره در localStorage (سمتِ کاربر).
import type { CSSProperties } from "react";

export interface ChatTheme {
  bg: string;      // شناسهٔ پس‌زمینهٔ پیش‌فرض یا "img:<dataURL>" برای تصویرِ سفارشی
  accent: string;  // رنگِ حبابِ پیام‌های من (HEX)
}

const DOODLE =
  "data:image/svg+xml;utf8," +
  encodeURIComponent(
    `<svg xmlns='http://www.w3.org/2000/svg' width='120' height='120' viewBox='0 0 120 120'>` +
      `<g fill='none' stroke='rgba(255,255,255,0.05)' stroke-width='2'>` +
      `<circle cx='20' cy='20' r='10'/><path d='M50 15h20v20h-20z'/>` +
      `<path d='M90 25l8 14h-16z'/><circle cx='30' cy='80' r='7'/>` +
      `<path d='M70 70h18v18h-18z' rx='4'/><path d='M100 90l6 10h-12z'/>` +
      `<path d='M10 55h16M55 95h20M95 55h14'/></g></svg>`,
  );

export const CHAT_BACKGROUNDS: { id: string; label: string; preview: string }[] = [
  { id: "dark", label: "پیش‌فرض", preview: "#0A0A0A" },
  { id: "graphite", label: "گرافیت", preview: "linear-gradient(160deg,#1c1c22,#0a0a0a)" },
  { id: "midnight", label: "نیمه‌شب", preview: "linear-gradient(160deg,#0f172a,#020617)" },
  { id: "ocean", label: "اقیانوس", preview: "linear-gradient(160deg,#0b3d4d,#06121a)" },
  { id: "sunset", label: "غروب", preview: "linear-gradient(160deg,#3a1c2e,#120a14)" },
  { id: "forest", label: "جنگل", preview: "linear-gradient(160deg,#12331f,#08160d)" },
  { id: "royal", label: "بنفشِ سلطنتی", preview: "linear-gradient(160deg,#2a1a4a,#0d0820)" },
  { id: "doodle", label: "طرح‌دار", preview: "#0d0d10" },
];

export const CHAT_ACCENTS: { id: string; color: string }[] = [
  { id: "indigo", color: "#4F46E5" },
  { id: "violet", color: "#7C3AED" },
  { id: "emerald", color: "#059669" },
  { id: "rose", color: "#E11D48" },
  { id: "amber", color: "#D97706" },
  { id: "sky", color: "#0284C7" },
  { id: "teal", color: "#0D9488" },
  { id: "fuchsia", color: "#C026D3" },
];

export const DEFAULT_THEME: ChatTheme = { bg: "dark", accent: "#4F46E5" };

const KEY = "dilix_chat_theme";

export function getChatTheme(): ChatTheme {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return DEFAULT_THEME;
    const t = JSON.parse(raw) as Partial<ChatTheme>;
    return { bg: t.bg || DEFAULT_THEME.bg, accent: t.accent || DEFAULT_THEME.accent };
  } catch {
    return DEFAULT_THEME;
  }
}

export function saveChatTheme(t: ChatTheme): void {
  try { localStorage.setItem(KEY, JSON.stringify(t)); } catch { /* ignore */ }
}

// استایلِ پس‌زمینه برای ظرفِ پیام‌ها
export function bgStyle(bg: string): CSSProperties {
  if (bg.startsWith("img:")) {
    return {
      backgroundImage: `linear-gradient(rgba(0,0,0,0.45),rgba(0,0,0,0.45)),url(${bg.slice(4)})`,
      backgroundSize: "cover",
      backgroundPosition: "center",
    };
  }
  if (bg === "dark") {
    // پیش‌فرض: بوم چت از تمِ برنامه (روز/شب) پیروی می‌کند — باگ ۶
    return { backgroundColor: "var(--chat-canvas)" };
  }
  const preset = CHAT_BACKGROUNDS.find((b) => b.id === bg);
  if (bg === "doodle") {
    return { backgroundColor: "#0d0d10", backgroundImage: `url(${DOODLE})`, backgroundSize: "120px 120px" };
  }
  const val = preset?.preview ?? "#0A0A0A";
  return val.startsWith("linear")
    ? { backgroundImage: val }
    : { backgroundColor: val };
}
