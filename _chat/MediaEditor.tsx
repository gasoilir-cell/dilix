"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  X, Send, Type as TypeIcon, Square, Crop, Smile, Loader2, Pencil,
  Eraser, Move, Trash2, Languages, Undo2, ImagePlus, Frame as FrameIcon,
  Sun, Contrast, Droplet, Thermometer, Aperture, RotateCcw, Check,
} from "lucide-react";
import toast from "react-hot-toast";
import { messagesApi } from "@/lib/api";

interface Props {
  file: File;
  kind: "image" | "video";
  onCancel: () => void;
  onDone: (file: File) => void;
}

// ── دستیِ تنظیمِ نور/رنگ (روی کلِ تصویر، bake روی خروجی) ──────
type Adjust = { brightness: number; contrast: number; saturate: number; warmth: number; blur: number };
const ADJUST_DEFAULT: Adjust = { brightness: 1, contrast: 1, saturate: 1, warmth: 0, blur: 0 };
function adjustToCss(a: Adjust): string {
  const p: string[] = [];
  if (a.brightness !== 1) p.push(`brightness(${a.brightness})`);
  if (a.contrast !== 1) p.push(`contrast(${a.contrast})`);
  if (a.saturate !== 1) p.push(`saturate(${a.saturate})`);
  if (a.warmth > 0) p.push(`sepia(${(a.warmth / 100 * 0.55).toFixed(3)})`);
  else if (a.warmth < 0) p.push(`hue-rotate(${Math.round(a.warmth / 100 * 22)}deg) saturate(${(1 + (-a.warmth) / 100 * 0.15).toFixed(2)})`);
  if (a.blur > 0) p.push(`blur(${a.blur}px)`);
  return p.join(" ");
}
function combineFilter(base: string, adj: string): string {
  const parts = [base !== "none" ? base : "", adj].filter(Boolean);
  return parts.length ? parts.join(" ") : "none";
}

// ── palettes / presets ───────────────────────────────────────
const FILTERS: { id: string; label: string; css: string }[] = [
  { id: "none", label: "عادی", css: "none" },
  { id: "mono", label: "سیاه‌سفید", css: "grayscale(1)" },
  { id: "warm", label: "گرم", css: "sepia(0.4) saturate(1.5)" },
  { id: "cool", label: "سرد", css: "hue-rotate(180deg) saturate(1.2)" },
  { id: "vintage", label: "قدیمی", css: "sepia(0.6) contrast(0.9) brightness(1.1)" },
  { id: "bright", label: "روشن", css: "brightness(1.3) saturate(1.2)" },
  { id: "punch", label: "کنتراست", css: "contrast(1.4) saturate(1.3)" },
  { id: "blur", label: "محو", css: "blur(2.2px)" },
];

const PIXEL_LEVELS: { id: string; label: string; blocks: number }[] = [
  { id: "off", label: "بدون شطرنجی", blocks: 0 },
  { id: "soft", label: "شطرنجیِ ملایم", blocks: 64 },
  { id: "hard", label: "شطرنجیِ درشت", blocks: 28 },
];

const COLORS = ["#FFFFFF", "#000000", "#F87171", "#34D399", "#38BDF8", "#EC4899", "#FACC15", "#A855F7", "#FB923C"];

// ── نوارِ رنگِ کشیدنی (اسپکترومِ کامل: مشکی › رنگین‌کمان › سفید) ──────
const SPECTRUM_BG = (() => {
  const mid: string[] = [];
  for (let i = 0; i <= 12; i++) mid.push(`hsl(${Math.round((i / 12) * 360)},85%,55%) ${(5 + (i / 12) * 90).toFixed(1)}%`);
  return `linear-gradient(to right, #000 0%, #000 5%, ${mid.join(",")}, #fff 95%, #fff 100%)`;
})();
function spectrumColor(t: number): string {
  const x = Math.min(1, Math.max(0, t));
  if (x <= 0.05) return "#000000";
  if (x >= 0.95) return "#FFFFFF";
  return `hsl(${Math.round(((x - 0.05) / 0.9) * 360)}, 85%, 55%)`;
}
function hexHue(hex: string): number {
  let h = hex.replace("#", ""); if (h.length === 3) h = h.split("").map((c) => c + c).join("");
  const r = parseInt(h.slice(0, 2), 16) / 255, g = parseInt(h.slice(2, 4), 16) / 255, b = parseInt(h.slice(4, 6), 16) / 255;
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn; if (d === 0) return -1;
  let hue = mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
  hue *= 60; if (hue < 0) hue += 360; return hue;
}
function colorToT(c: string): number {
  const s = (c || "").toLowerCase().trim();
  if (s === "#000000" || s === "#000" || s === "black") return 0;
  if (s === "#ffffff" || s === "#fff" || s === "white") return 1;
  const m = s.match(/hsl\(\s*(\d+)/);
  let hue = m ? parseInt(m[1]) : s[0] === "#" ? hexHue(s) : -1;
  if (hue < 0) return 0.5;
  return 0.05 + (hue / 360) * 0.9;
}
function SpectrumPicker({ value, onPick }: { value: string; onPick: (c: string) => void }) {
  const ref = useRef<HTMLDivElement>(null);
  const dragging = useRef(false);
  const t = colorToT(value);
  const pick = (clientX: number) => {
    const el = ref.current; if (!el) return;
    const r = el.getBoundingClientRect();
    onPick(spectrumColor((clientX - r.left) / r.width));
  };
  return (
    <div
      ref={ref}
      onPointerDown={(e) => { dragging.current = true; (e.target as HTMLElement).setPointerCapture?.(e.pointerId); pick(e.clientX); }}
      onPointerMove={(e) => { if (dragging.current) pick(e.clientX); }}
      onPointerUp={() => { dragging.current = false; }}
      onPointerCancel={() => { dragging.current = false; }}
      className="relative h-7 rounded-full cursor-pointer touch-none select-none"
      style={{ background: SPECTRUM_BG }}
    >
      <div
        className="absolute top-1/2 w-5 h-5 rounded-full border-2 border-white shadow -translate-x-1/2 -translate-y-1/2 pointer-events-none"
        style={{ left: `${(t * 100).toFixed(1)}%`, backgroundColor: value }}
      />
    </div>
  );
}
const QUICK_EMOJIS = [
  "😀","😁","😂","🤣","😊","😇","🙂","😉","😍","🥰","😘","😗","😋","😛","😜","🤪",
  "🤨","🧐","😎","🥳","🤩","😏","😒","😞","😔","😟","😕","🙁","😣","😖","😫","😩",
  "🥺","😢","😭","😤","😠","😡","🤬","🤯","😳","🥵","🥶","😱","😨","😰","😥","🤗",
  "🤔","🤭","🤫","🤥","😶","😐","😑","😬","🙄","😯","😮","😲","🥱","😴","🤤","😪",
  "😵","🤐","🥴","🤢","🤮","🤧","😷","🤒","🤕","🤑","🤠","😈","👿","👻","💀","👽",
  "🤖","🎃","😺","😸","😹","😻","😼","🙀","😿","😾","👍","👎","👌","✌️","🤞","🤟",
  "🤙","👋","🙏","💪","👏","🙌","🤝","☝️","✊","👊","🫰","🫶","❤️","🧡","💛","💚",
  "💙","💜","🖤","🤍","🤎","💔","❣️","💕","💞","💓","💗","💖","💘","💝","💯","🔥",
  "✨","⭐","🌟","💫","⚡","🎉","🎊","🎁","🎈","👑","💎","🌈","☀️","🌙","⭐","❄️",
  "🌸","🌹","🌺","🌻","🌼","🍀","🌵","🎯","🏆","🥇","⚽","🏀","🎵","🎶","💐","🍕",
];

// فونت‌های فارسیِ ویرایشگر (وب‌فونتِ لوکال در public/me-fonts؛ @font-face در globals.css)
const FONTS: { id: string; label: string; css: string }[] = [
  { id: "sans", label: "معمولی", css: '"MEVazir", Tahoma, sans-serif' },
  { id: "kufi", label: "کوفی", css: '"MEKufi", Tahoma, sans-serif' },
  { id: "classic", label: "کلاسیک", css: '"MEMarkazi", Georgia, serif' },
  { id: "naskh", label: "نسخ", css: '"MEAmiri", Georgia, serif' },
  { id: "hand", label: "خوش‌نویسی", css: '"MEGulzar", cursive' },
];
const ME_FONT_FAMS = ["MEVazir", "MEKufi", "MEMarkazi", "MEAmiri", "MEGulzar"];

const TEXT_EFFECTS: { id: EffectId; label: string }[] = [
  { id: "stroke", label: "دورخط" },
  { id: "shadow", label: "سایه" },
  { id: "neon", label: "نئون" },
  { id: "label", label: "برچسب" },
  { id: "plain", label: "ساده" },
];

const BRUSH_SIZES: { id: string; label: string; w: number }[] = [
  { id: "thin", label: "نازک", w: 0.006 },
  { id: "med", label: "متوسط", w: 0.013 },
  { id: "thick", label: "ضخیم", w: 0.024 },
];

const TRANSLATE_LANGS: { code: string; label: string }[] = [
  { code: "fa", label: "فارسی" }, { code: "en", label: "English" },
  { code: "ar", label: "عربی" }, { code: "tr", label: "ترکی" },
  { code: "ru", label: "روسی" }, { code: "fr", label: "فرانسه" },
];

// افکتِ حاشیه برای لایه‌های اضافه‌شده (رنگِ null = بدونِ حاشیه)
const BORDER_COLORS: { id: string; label: string; color: string | null }[] = [
  { id: "off", label: "بدون", color: null },
  { id: "white", label: "سفید", color: "#FFFFFF" },
  { id: "black", label: "مشکی", color: "#000000" },
  { id: "amber", label: "طلایی", color: "#FACC15" },
  { id: "rose", label: "صورتی", color: "#EC4899" },
  { id: "sky", label: "آبی", color: "#38BDF8" },
];

// افکتِ قابِ دورِ تصویرِ اصلی + همه‌ی لایه‌ها
const FRAMES: { id: string; label: string }[] = [
  { id: "none", label: "بدون قاب" },
  { id: "white", label: "سفید" },
  { id: "black", label: "مشکی" },
  { id: "gold", label: "طلایی" },
  { id: "polaroid", label: "پولاروید" },
  { id: "film", label: "فیلم" },
  { id: "neon", label: "نئون" },
];

const IMG_PRESETS = [
  { id: "orig", label: "اصل", maxDim: 0, q: 0.92 },
  { id: "high", label: "بالا", maxDim: 1600, q: 0.85 },
  { id: "mid", label: "متوسط", maxDim: 1080, q: 0.72 },
  { id: "low", label: "کوچک", maxDim: 720, q: 0.6 },
];
const VID_PRESETS = [
  { id: "orig", label: "اصل", maxDim: 0, bitrate: 0 },
  { id: "720", label: "۷۲۰p", maxDim: 720, bitrate: 2_000_000 },
  { id: "480", label: "۴۸۰p", maxDim: 480, bitrate: 1_000_000 },
  { id: "360", label: "۳۶۰p", maxDim: 360, bitrate: 600_000 },
];

// نسبت‌های آمادهٔ برشِ دستی (ratio = عرض÷ارتفاعِ خروجی؛ null = آزاد)
const CROP_RATIOS: { id: string; label: string; ratio: number | null }[] = [
  { id: "free", label: "آزاد", ratio: null },
  { id: "1", label: "۱:۱", ratio: 1 },
  { id: "45", label: "۴:۵", ratio: 4 / 5 },
  { id: "34", label: "۳:۴", ratio: 3 / 4 },
  { id: "43", label: "۴:۳", ratio: 4 / 3 },
  { id: "169", label: "۱۶:۹", ratio: 16 / 9 },
  { id: "916", label: "۹:۱۶", ratio: 9 / 16 },
];

// ── types ────────────────────────────────────────────────────
type EffectId = "stroke" | "shadow" | "neon" | "label" | "plain";
// کادرِ برشِ دستی — مختصاتِ نرمال (۰..۱) نسبت به تصویرِ اصلی
interface CropRect { x: number; y: number; w: number; h: number }
interface Overlay {
  id: string; kind: "text" | "emoji" | "image"; value: string;
  nx: number; ny: number; size: number; // size = fraction of width
  color: string; fontCss: string; effect: EffectId;
  border?: string | null;               // رنگِ حاشیه (null/undefined = بدون)
  aspect?: number;                       // برای لایهٔ تصویری: w/h
  el?: HTMLImageElement;                 // المانِ بارگذاری‌شدهٔ تصویر
  filterCss?: string;                    // فیلترِ مخصوصِ همین لایهٔ تصویری
  blocks?: number;                       // شطرنجیِ مخصوصِ همین لایهٔ تصویری
}
interface Pt { nx: number; ny: number }
interface Stroke { points: Pt[]; color: string; width: number; erase: boolean }
interface SceneOpts { square: boolean; filterCss: string; blocks: number; overlays: Overlay[]; strokes: Stroke[]; frame: string; manual?: CropRect | null }

// ── utils ────────────────────────────────────────────────────
function fmtBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(0)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}
function toPersianDigits(s: string): string { return s.replace(/[0-9]/g, (d) => "۰۱۲۳۴۵۶۷۸۹"[+d]); }
const uid = () => Math.random().toString(36).slice(2, 9);

function baseCrop(sw: number, sh: number, square: boolean, manual?: CropRect | null) {
  if (manual) {
    return { sx: manual.x * sw, sy: manual.y * sh, sw: Math.max(1, manual.w * sw), sh: Math.max(1, manual.h * sh) };
  }
  if (square) { const m = Math.min(sw, sh); return { sx: (sw - m) / 2, sy: (sh - m) / 2, sw: m, sh: m }; }
  return { sx: 0, sy: 0, sw, sh };
}
const clamp01 = (v: number, lo = 0, hi = 1) => Math.min(hi, Math.max(lo, v));
// کادرِ برشِ مرکزیِ متناسب با نسبتِ داده‌شده، درونِ تصویرِ natW×natH
function centeredRect(natW: number, natH: number, ratio: number | null): CropRect {
  if (!ratio || natW <= 0 || natH <= 0) return { x: 0.06, y: 0.06, w: 0.88, h: 0.88 };
  const imgRatio = natW / natH;
  let w: number, h: number;
  if (ratio >= imgRatio) { w = 0.9; h = clamp01((w * natW) / (ratio * natH)); }
  else { h = 0.9; w = clamp01((ratio * natH * h) / natW); }
  return { x: (1 - w) / 2, y: (1 - h) / 2, w, h };
}
function outDims(cw: number, ch: number, maxDim: number) {
  if (maxDim > 0) { const s = Math.min(1, maxDim / Math.max(cw, ch)); return { W: Math.round(cw * s), H: Math.round(ch * s) }; }
  return { W: cw, H: ch };
}
function luminance(hex: string) {
  const h = hex.replace("#", ""); const r = parseInt(h.slice(0, 2), 16), g = parseInt(h.slice(2, 4), 16), b = parseInt(h.slice(4, 6), 16);
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255;
}
const contrastOf = (hex: string) => (luminance(hex) > 0.6 ? "#000000" : "#FFFFFF");
function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath();
  ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
}

type Cache = { pix?: HTMLCanvasElement; layer?: HTMLCanvasElement };

function blit(ctx: CanvasRenderingContext2D, cache: Cache, src: CanvasImageSource, crop: { sx: number; sy: number; sw: number; sh: number }, W: number, H: number, filterCss: string, blocks: number) {
  const f = filterCss === "none" ? "none" : filterCss;
  if (blocks > 0) {
    const pw = Math.max(2, blocks), ph = Math.max(2, Math.round(blocks * H / W));
    if (!cache.pix) cache.pix = document.createElement("canvas");
    cache.pix.width = pw; cache.pix.height = ph;
    const pc = cache.pix.getContext("2d")!;
    pc.clearRect(0, 0, pw, ph); pc.filter = f;
    pc.drawImage(src, crop.sx, crop.sy, crop.sw, crop.sh, 0, 0, pw, ph);
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(cache.pix, 0, 0, pw, ph, 0, 0, W, H);
    ctx.imageSmoothingEnabled = true;
  } else {
    ctx.filter = f;
    ctx.drawImage(src, crop.sx, crop.sy, crop.sw, crop.sh, 0, 0, W, H);
    ctx.filter = "none";
  }
}

function paintStrokes(ctx: CanvasRenderingContext2D, cache: Cache, strokes: Stroke[], W: number, H: number) {
  if (!strokes.length) return;
  if (!cache.layer) cache.layer = document.createElement("canvas");
  cache.layer.width = W; cache.layer.height = H;
  const lc = cache.layer.getContext("2d")!;
  lc.clearRect(0, 0, W, H); lc.lineJoin = "round"; lc.lineCap = "round";
  for (const s of strokes) {
    lc.globalCompositeOperation = s.erase ? "destination-out" : "source-over";
    lc.strokeStyle = s.erase ? "rgba(0,0,0,1)" : s.color;
    lc.lineWidth = Math.max(1, s.width * W);
    lc.beginPath();
    s.points.forEach((p, i) => { const x = p.nx * W, y = p.ny * H; if (i === 0) lc.moveTo(x, y); else lc.lineTo(x, y); });
    if (s.points.length === 1) lc.lineTo(s.points[0].nx * W + 0.1, s.points[0].ny * H);
    lc.stroke();
  }
  lc.globalCompositeOperation = "source-over";
  ctx.drawImage(cache.layer, 0, 0);
}

function textFont(ov: Overlay, fs: number) {
  return ov.kind === "emoji" ? `${fs}px "Segoe UI Emoji","Noto Color Emoji",sans-serif` : `bold ${fs}px ${ov.fontCss}`;
}
// اندازهٔ کادرِ هر لایه (برای border و hit-test)
function measureOverlay(ctx: CanvasRenderingContext2D, ov: Overlay, W: number) {
  if (ov.kind === "image") { const w = Math.max(8, ov.size * W); return { w, h: w / (ov.aspect || 1) }; }
  const fs = Math.max(8, ov.size * W);
  ctx.font = textFont(ov, fs);
  const w = (ov.kind === "emoji" ? fs * 1.15 : ctx.measureText(ov.value).width) + fs * 0.4;
  return { w, h: fs * 1.3 };
}
function paintBorder(ctx: CanvasRenderingContext2D, ov: Overlay, cx: number, cy: number, w: number, h: number) {
  if (!ov.border) return;
  const pad = Math.min(w, h) * 0.08;
  const bw = Math.max(2, Math.min(w, h) * 0.05);
  ctx.save();
  ctx.strokeStyle = ov.border; ctx.lineWidth = bw;
  roundRect(ctx, cx - w / 2 - pad, cy - h / 2 - pad, w + pad * 2, h + pad * 2, Math.min(w, h) * 0.14);
  ctx.stroke(); ctx.restore();
}
// ترسیمِ لایهٔ تصویری با فیلتر/شطرنجیِ مخصوصِ خودِ لایه
function drawOverlayImage(ctx: CanvasRenderingContext2D, el: HTMLImageElement, dx: number, dy: number, dw: number, dh: number, filterCss: string, blocks: number) {
  const f = filterCss && filterCss !== "none" ? filterCss : "none";
  if (blocks > 0) {
    const pw = Math.max(2, blocks), ph = Math.max(2, Math.round(blocks * dh / dw));
    const pc = document.createElement("canvas"); pc.width = pw; pc.height = ph;
    const pctx = pc.getContext("2d")!;
    pctx.filter = f; pctx.drawImage(el, 0, 0, pw, ph);
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(pc, dx, dy, dw, dh);
    ctx.imageSmoothingEnabled = true;
  } else {
    ctx.filter = f; ctx.drawImage(el, dx, dy, dw, dh); ctx.filter = "none";
  }
}
function paintOverlays(ctx: CanvasRenderingContext2D, overlays: Overlay[], W: number, H: number) {
  for (const ov of overlays) {
    const x = ov.nx * W, y = ov.ny * H;
    if (ov.kind === "image") {
      const box = measureOverlay(ctx, ov, W);
      if (ov.el) {
        ctx.save();
        ctx.shadowColor = "rgba(0,0,0,0.3)"; ctx.shadowBlur = box.w * 0.03;
        drawOverlayImage(ctx, ov.el, x - box.w / 2, y - box.h / 2, box.w, box.h, ov.filterCss || "none", ov.blocks || 0);
        ctx.restore();
      }
      paintBorder(ctx, ov, x, y, box.w, box.h);
      continue;
    }
    const fs = Math.max(8, ov.size * W);
    ctx.save();
    ctx.textAlign = "center"; ctx.textBaseline = "middle";
    ctx.font = textFont(ov, fs);
    if (ov.kind === "emoji") {
      ctx.shadowColor = "rgba(0,0,0,0.35)"; ctx.shadowBlur = fs * 0.08;
      ctx.fillText(ov.value, x, y);
    } else {
      const t = ov.value;
      if (ov.effect === "shadow") {
        ctx.shadowColor = "rgba(0,0,0,0.7)"; ctx.shadowBlur = fs * 0.22; ctx.shadowOffsetX = fs * 0.05; ctx.shadowOffsetY = fs * 0.05;
        ctx.fillStyle = ov.color; ctx.fillText(t, x, y);
      } else if (ov.effect === "neon") {
        ctx.shadowColor = ov.color; ctx.shadowBlur = fs * 0.55; ctx.fillStyle = "#fff";
        ctx.fillText(t, x, y); ctx.fillText(t, x, y);
      } else if (ov.effect === "label") {
        const w = ctx.measureText(t).width; const px = fs * 0.35, py = fs * 0.2;
        ctx.fillStyle = ov.color; roundRect(ctx, x - w / 2 - px, y - fs * 0.62 - py, w + px * 2, fs * 1.24 + py * 2, fs * 0.28); ctx.fill();
        ctx.fillStyle = contrastOf(ov.color); ctx.fillText(t, x, y);
      } else if (ov.effect === "plain") {
        ctx.fillStyle = ov.color; ctx.fillText(t, x, y);
      } else {
        ctx.lineJoin = "round"; ctx.lineWidth = Math.max(2, fs * 0.16);
        ctx.strokeStyle = ov.color === "#000000" ? "#FFFFFF" : "rgba(0,0,0,0.85)";
        ctx.strokeText(t, x, y); ctx.fillStyle = ov.color; ctx.fillText(t, x, y);
      }
    }
    ctx.restore();
    const box = measureOverlay(ctx, ov, W);
    paintBorder(ctx, ov, x, y, box.w, box.h);
  }
}
function overlayBox(ctx: CanvasRenderingContext2D, ov: Overlay, W: number, H: number) {
  const { w, h } = measureOverlay(ctx, ov, W);
  return { cx: ov.nx * W, cy: ov.ny * H, w, h };
}
function paintFrame(ctx: CanvasRenderingContext2D, id: string, W: number, H: number) {
  if (!id || id === "none") return;
  ctx.save();
  const t = Math.max(6, Math.round(Math.min(W, H) * 0.035));
  if (id === "white" || id === "black" || id === "gold") {
    if (id === "gold") { const g = ctx.createLinearGradient(0, 0, W, H); g.addColorStop(0, "#f7d774"); g.addColorStop(0.5, "#c9922e"); g.addColorStop(1, "#f7d774"); ctx.strokeStyle = g; }
    else ctx.strokeStyle = id === "white" ? "#FFFFFF" : "#000000";
    ctx.lineWidth = t; ctx.strokeRect(t / 2, t / 2, W - t, H - t);
  } else if (id === "polaroid") {
    ctx.fillStyle = "#FFFFFF";
    const b = t, bottom = t * 3.2;
    ctx.fillRect(0, 0, W, b); ctx.fillRect(0, H - bottom, W, bottom); ctx.fillRect(0, 0, b, H); ctx.fillRect(W - b, 0, b, H);
  } else if (id === "film") {
    const b = Math.round(H * 0.07);
    ctx.fillStyle = "#000"; ctx.fillRect(0, 0, W, b); ctx.fillRect(0, H - b, W, b);
    ctx.fillStyle = "#fff"; const hw = b * 0.42, hh = b * 0.4, gap = hw * 2.2;
    for (let x = gap; x < W - hw; x += gap) { ctx.fillRect(x, b * 0.3, hw, hh); ctx.fillRect(x, H - b + b * 0.3, hw, hh); }
  } else if (id === "neon") {
    ctx.strokeStyle = "#6366f1"; ctx.lineWidth = t * 0.7; ctx.shadowColor = "#6366f1"; ctx.shadowBlur = t * 1.6;
    ctx.strokeRect(t / 2, t / 2, W - t, H - t);
  }
  ctx.restore();
}
function drawScene(ctx: CanvasRenderingContext2D, cache: Cache, src: CanvasImageSource, natW: number, natH: number, W: number, H: number, o: SceneOpts) {
  const crop = baseCrop(natW, natH, o.square, o.manual);
  blit(ctx, cache, src, crop, W, H, o.filterCss, o.blocks);
  paintStrokes(ctx, cache, o.strokes, W, H);
  paintOverlays(ctx, o.overlays, W, H);
  paintFrame(ctx, o.frame, W, H);
}

function transcodeVideo(file: File, o: SceneOpts & { maxDim: number; bitrate: number }, onProgress: (p: number) => void): Promise<Blob> {
  return new Promise((resolve, reject) => {
    const v = document.createElement("video");
    v.src = URL.createObjectURL(file); v.muted = false; v.playsInline = true;
    v.onloadedmetadata = () => {
      const crop = baseCrop(v.videoWidth, v.videoHeight, o.square, o.manual);
      const { W, H } = outDims(crop.sw, crop.sh, o.maxDim);
      const canvas = document.createElement("canvas"); canvas.width = W; canvas.height = H;
      const ctx = canvas.getContext("2d"); if (!ctx) return reject(new Error("no ctx"));
      const cache: Cache = {};
      const out = canvas.captureStream(30);
      let ac: AudioContext | null = null;
      try {
        ac = new AudioContext();
        const node = ac.createMediaElementSource(v); const dest = ac.createMediaStreamDestination();
        node.connect(dest); const at = dest.stream.getAudioTracks()[0]; if (at) out.addTrack(at);
      } catch { /* silent */ }
      const mime = MediaRecorder.isTypeSupported("video/webm;codecs=vp9,opus") ? "video/webm;codecs=vp9,opus" : "video/webm";
      const opts: MediaRecorderOptions = { mimeType: mime };
      if (o.bitrate > 0) opts.videoBitsPerSecond = o.bitrate;
      const mr = new MediaRecorder(out, opts); const chunks: Blob[] = [];
      mr.ondataavailable = (e) => { if (e.data.size > 0) chunks.push(e.data); };
      mr.onstop = () => { try { ac?.close(); } catch { /* ignore */ } resolve(new Blob(chunks, { type: "video/webm" })); };
      let raf = 0;
      const draw = () => { drawScene(ctx, cache, v, v.videoWidth, v.videoHeight, W, H, o); if (v.duration) onProgress(Math.min(1, v.currentTime / v.duration)); raf = requestAnimationFrame(draw); };
      v.onended = () => { cancelAnimationFrame(raf); if (mr.state !== "inactive") mr.stop(); };
      mr.start(); v.play().then(draw).catch(() => reject(new Error("play")));
    };
    v.onerror = () => reject(new Error("video load"));
  });
}

// ── component ────────────────────────────────────────────────
export default function MediaEditor({ file, kind, onCancel, onDone }: Props) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const imgInputRef = useRef<HTMLInputElement | null>(null);
  const cacheRef = useRef<Cache>({});
  const srcElRef = useRef<HTMLImageElement | HTMLVideoElement | null>(null);
  const natRef = useRef<{ w: number; h: number }>({ w: 0, h: 0 });
  const rafRef = useRef(0);

  const [ready, setReady] = useState(false);
  const [box, setBox] = useState<{ w: number; h: number }>({ w: 320, h: 320 });

  const [square, setSquare] = useState(false);
  const [manualCrop, setManualCrop] = useState<CropRect | null>(null);
  const [cropEditing, setCropEditing] = useState(false);
  const [cropRect, setCropRect] = useState<CropRect>({ x: 0.08, y: 0.08, w: 0.84, h: 0.84 });
  const [cropRatioId, setCropRatioId] = useState("free");
  const [filter, setFilter] = useState(FILTERS[0]);
  const [pixel, setPixel] = useState(PIXEL_LEVELS[0]);
  const [adjust, setAdjust] = useState<Adjust>(ADJUST_DEFAULT);
  const [frame, setFrame] = useState(FRAMES[0]);
  const [overlays, setOverlays] = useState<Overlay[]>([]);
  const [strokes, setStrokes] = useState<Stroke[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [preset, setPreset] = useState(kind === "image" ? IMG_PRESETS[1] : VID_PRESETS[1]);

  const [tool, setTool] = useState<"move" | "draw">("move");
  const [mtab, setMtab] = useState<"layer" | "filter" | "tune" | "adjust">("layer");
  const [draft, setDraft] = useState("");
  const [textColor, setTextColor] = useState(COLORS[0]);
  const [textFontId, setTextFontId] = useState(FONTS[0].id);
  const [fontsReady, setFontsReady] = useState(false);
  const [textEffect, setTextEffect] = useState<EffectId>("stroke");
  const [showEmoji, setShowEmoji] = useState(false);
  const [showTr, setShowTr] = useState(false);
  const [translating, setTranslating] = useState(false);

  const [brushColor, setBrushColor] = useState(COLORS[2]);
  const [brushSize, setBrushSize] = useState(BRUSH_SIZES[1]);
  const [eraser, setEraser] = useState(false);

  const [outSize, setOutSize] = useState<number | null>(null);
  const [working, setWorking] = useState(false);
  const [progress, setProgress] = useState(0);
  const origSize = file.size;

  const selected = overlays.find((o) => o.id === selectedId) || null;
  const selectedText = selected?.kind === "text" ? selected : null;
  const selectedImage = selected?.kind === "image" ? selected : null;

  // فیلتر/شطرنجی: اگر لایهٔ تصویری انتخاب شده باشد روی همان لایه، وگرنه روی تصویرِ پایه اعمال می‌شود
  const activeFilterCss = selectedImage ? (selectedImage.filterCss || "none") : filter.css;
  const activeBlocks = selectedImage ? (selectedImage.blocks || 0) : pixel.blocks;
  const applyFilter = (f: typeof FILTERS[number]) => {
    if (selectedImage) setOverlays((p) => p.map((o) => o.id === selectedImage.id ? { ...o, filterCss: f.css } : o));
    else setFilter(f);
  };
  const applyPixel = (pl: typeof PIXEL_LEVELS[number]) => {
    if (selectedImage) setOverlays((p) => p.map((o) => o.id === selectedImage.id ? { ...o, blocks: pl.blocks } : o));
    else setPixel(pl);
  };

  // فیلترِ پایه = فیلترِ آماده + تنظیمِ دستیِ نور/رنگ (روی کلِ تصویر)
  const baseFilterCss = useMemo(() => combineFilter(filter.css, adjustToCss(adjust)), [filter, adjust]);
  const adjusted = adjust.brightness !== 1 || adjust.contrast !== 1 || adjust.saturate !== 1 || adjust.warmth !== 0 || adjust.blur !== 0;
  const TUNE_SLIDERS = [
    { key: "brightness" as const, label: "روشنایی", Icon: Sun,         min: 0.5, max: 1.5, step: 0.02, fmt: (v: number) => `${Math.round((v - 1) * 100)}` },
    { key: "contrast"   as const, label: "کنتراست", Icon: Contrast,    min: 0.5, max: 1.5, step: 0.02, fmt: (v: number) => `${Math.round((v - 1) * 100)}` },
    { key: "saturate"   as const, label: "اشباع",   Icon: Droplet,     min: 0,   max: 2,   step: 0.02, fmt: (v: number) => `${Math.round((v - 1) * 100)}` },
    { key: "warmth"     as const, label: "گرما",    Icon: Thermometer, min: -100, max: 100, step: 2,   fmt: (v: number) => `${Math.round(v)}` },
    { key: "blur"       as const, label: "محو",     Icon: Aperture,    min: 0,   max: 5,   step: 0.2,  fmt: (v: number) => v.toFixed(1) },
  ];

  // fit box from natural aspect
  const fitBox = useCallback((w: number, h: number) => {
    const maxW = Math.min(window.innerWidth * 0.92, 440);
    const maxH = window.innerHeight * 0.46;
    // در حالتِ ویرایشِ برش، همیشه تصویرِ کاملِ اصلی نمایش داده می‌شود
    let aw = w, ah = h;
    if (!cropEditing) {
      if (manualCrop) { aw = manualCrop.w * w; ah = manualCrop.h * h; }
      else if (square) { aw = Math.min(w, h); ah = aw; }
    }
    const aspect = aw / ah;
    let dw = maxW, dh = dw / aspect;
    if (dh > maxH) { dh = maxH; dw = dh * aspect; }
    setBox({ w: Math.round(dw), h: Math.round(dh) });
  }, [square, manualCrop, cropEditing]);

  // load source
  useEffect(() => {
    const url = URL.createObjectURL(file);
    if (kind === "image") {
      const im = new Image();
      im.onload = () => { srcElRef.current = im; natRef.current = { w: im.naturalWidth, h: im.naturalHeight }; fitBox(im.naturalWidth, im.naturalHeight); setReady(true); };
      im.src = url;
    } else {
      const v = document.createElement("video");
      v.src = url; v.muted = true; v.loop = true; v.playsInline = true;
      v.onloadedmetadata = () => { srcElRef.current = v; natRef.current = { w: v.videoWidth, h: v.videoHeight }; fitBox(v.videoWidth, v.videoHeight); setReady(true); v.play().catch(() => {}); };
    }
    return () => { URL.revokeObjectURL(url); cancelAnimationFrame(rafRef.current); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [file, kind]);

  useEffect(() => { if (ready) fitBox(natRef.current.w, natRef.current.h); }, [square, ready, fitBox]);

  // پیش‌بارگذاریِ فونت‌های فارسی تا رویِ canvas قابلِ استفاده باشند (وگرنه fallback بی‌صدا)
  useEffect(() => {
    const fs = (document as unknown as { fonts?: { load: (s: string) => Promise<unknown> } }).fonts;
    if (!fs) { setFontsReady(true); return; }
    const specs = ME_FONT_FAMS.flatMap((f) => [`40px "${f}"`, `bold 40px "${f}"`]);
    Promise.all(specs.map((s) => fs.load(s).catch(() => {}))).finally(() => setFontsReady(true));
  }, []);

  const sceneOpts = useCallback((): SceneOpts => ({
    square: cropEditing ? false : square,
    filterCss: baseFilterCss, blocks: pixel.blocks, overlays, strokes, frame: frame.id,
    manual: cropEditing ? null : manualCrop,
  }), [square, baseFilterCss, pixel, overlays, strokes, frame, manualCrop, cropEditing]);

  // paint preview
  const paint = useCallback(() => {
    const canvas = canvasRef.current, src = srcElRef.current;
    if (!canvas || !src) return;
    const ctx = canvas.getContext("2d"); if (!ctx) return;
    const W = canvas.width, H = canvas.height;
    drawScene(ctx, cacheRef.current, src, natRef.current.w, natRef.current.h, W, H, sceneOpts());
    // selection ring
    if (selectedId) {
      const ov = overlays.find((o) => o.id === selectedId);
      if (ov) {
        const b = overlayBox(ctx, ov, W, H);
        ctx.save(); ctx.strokeStyle = "rgba(255,255,255,0.9)"; ctx.lineWidth = Math.max(1, W * 0.004); ctx.setLineDash([W * 0.02, W * 0.02]);
        roundRect(ctx, b.cx - b.w / 2, b.cy - b.h / 2, b.w, b.h, W * 0.02); ctx.stroke(); ctx.restore();
      }
    }
  }, [sceneOpts, selectedId, overlays]);

  // size canvas backing store
  useEffect(() => {
    const canvas = canvasRef.current; if (!canvas) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    canvas.width = Math.round(box.w * dpr); canvas.height = Math.round(box.h * dpr);
  }, [box]);

  // repaint on change (image) + rAF loop (video)
  useEffect(() => {
    if (!ready) return;
    if (kind === "video") {
      const loop = () => { paint(); rafRef.current = requestAnimationFrame(loop); };
      rafRef.current = requestAnimationFrame(loop);
      return () => cancelAnimationFrame(rafRef.current);
    }
    paint();
  }, [ready, kind, paint, box, fontsReady]);

  const hasEdits = square || !!manualCrop || filter.id !== "none" || pixel.blocks > 0 || overlays.length > 0 || strokes.length > 0 || frame.id !== "none" || adjusted;

  // live image size
  useEffect(() => {
    if (kind !== "image" || !ready) return;
    let cancelled = false;
    const t = setTimeout(async () => {
      try { const blob = await renderImageOutput(); if (!cancelled) setOutSize(blob.size); } catch { if (!cancelled) setOutSize(null); }
    }, 300);
    return () => { cancelled = true; clearTimeout(t); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [kind, ready, square, manualCrop, filter, pixel, overlays, strokes, preset, frame, adjust]);

  const renderImageOutput = useCallback((): Promise<Blob> => {
    return new Promise((resolve, reject) => {
      const src = srcElRef.current as HTMLImageElement; if (!src) return reject(new Error("no img"));
      const crop = baseCrop(natRef.current.w, natRef.current.h, square, manualCrop);
      const { W, H } = outDims(crop.sw, crop.sh, preset.maxDim);
      const c = document.createElement("canvas"); c.width = W; c.height = H;
      const ctx = c.getContext("2d"); if (!ctx) return reject(new Error("no ctx"));
      drawScene(ctx, {}, src, natRef.current.w, natRef.current.h, W, H, { square, filterCss: baseFilterCss, blocks: pixel.blocks, overlays, strokes, frame: frame.id, manual: manualCrop });
      c.toBlob((b) => b ? resolve(b) : reject(new Error("toBlob")), "image/jpeg", (preset as { q: number }).q);
    });
  }, [square, manualCrop, preset, baseFilterCss, pixel, overlays, strokes, frame]);

  // ── pointer interactions ─────────────────────────────────
  const normFromEvent = (e: React.PointerEvent) => {
    const c = canvasRef.current!; const r = c.getBoundingClientRect();
    return { nx: Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)), ny: Math.min(1, Math.max(0, (e.clientY - r.top) / r.height)) };
  };
  const dragRef = useRef<{ id: string; dx: number; dy: number } | null>(null);
  const drawingRef = useRef(false);

  const onDown = (e: React.PointerEvent) => {
    (e.target as HTMLElement).setPointerCapture?.(e.pointerId);
    const p = normFromEvent(e);
    if (tool === "draw") {
      drawingRef.current = true;
      setStrokes((prev) => [...prev, { points: [p], color: brushColor, width: brushSize.w, erase: eraser }]);
      return;
    }
    // move: hit test topmost
    const canvas = canvasRef.current!; const ctx = canvas.getContext("2d")!; const W = canvas.width, H = canvas.height;
    for (let i = overlays.length - 1; i >= 0; i--) {
      const b = overlayBox(ctx, overlays[i], W, H);
      const px = p.nx * W, py = p.ny * H;
      if (px >= b.cx - b.w / 2 && px <= b.cx + b.w / 2 && py >= b.cy - b.h / 2 && py <= b.cy + b.h / 2) {
        setSelectedId(overlays[i].id);
        dragRef.current = { id: overlays[i].id, dx: overlays[i].nx - p.nx, dy: overlays[i].ny - p.ny };
        if (overlays[i].kind === "text") { setDraft(overlays[i].value); setTextColor(overlays[i].color); setTextEffect(overlays[i].effect); const f = FONTS.find((x) => x.css === overlays[i].fontCss); if (f) setTextFontId(f.id); }
        return;
      }
    }
    setSelectedId(null);
  };
  const onMove = (e: React.PointerEvent) => {
    const p = normFromEvent(e);
    if (tool === "draw" && drawingRef.current) {
      setStrokes((prev) => { if (!prev.length) return prev; const last = prev[prev.length - 1]; const np = { ...last, points: [...last.points, p] }; return [...prev.slice(0, -1), np]; });
      return;
    }
    const d = dragRef.current; if (!d) return;
    setOverlays((prev) => prev.map((o) => o.id === d.id ? { ...o, nx: Math.min(1, Math.max(0, p.nx + d.dx)), ny: Math.min(1, Math.max(0, p.ny + d.dy)) } : o));
  };
  const onUp = () => { dragRef.current = null; drawingRef.current = false; };

  // ── برشِ دستی: کادرِ کشیدنی/تغییرِ اندازه ──────────────────
  const cropWrapRef = useRef<HTMLDivElement | null>(null);
  const cropDragRef = useRef<{ mode: string; sx: number; sy: number; rect: CropRect } | null>(null);
  const cropNorm = (e: React.PointerEvent) => {
    const r = cropWrapRef.current!.getBoundingClientRect();
    return { nx: (e.clientX - r.left) / r.width, ny: (e.clientY - r.top) / r.height };
  };
  const onCropDown = (mode: string) => (e: React.PointerEvent) => {
    e.stopPropagation(); (e.target as HTMLElement).setPointerCapture?.(e.pointerId);
    const p = cropNorm(e);
    cropDragRef.current = { mode, sx: p.nx, sy: p.ny, rect: { ...cropRect } };
  };
  const onCropMove = (e: React.PointerEvent) => {
    const d = cropDragRef.current; if (!d) return;
    const p = cropNorm(e); const dx = p.nx - d.sx, dy = p.ny - d.sy; const MIN = 0.08;
    let { x, y, w, h } = d.rect;
    if (d.mode === "move") {
      x = clamp01(x + dx, 0, 1 - w); y = clamp01(y + dy, 0, 1 - h);
    } else {
      let x2 = x + w, y2 = y + h;
      if (d.mode.includes("n")) y = Math.min(clamp01(y + dy), y2 - MIN);
      if (d.mode.includes("s")) y2 = Math.max(clamp01(y2 + dy), y + MIN);
      if (d.mode.includes("w")) x = Math.min(clamp01(x + dx), x2 - MIN);
      if (d.mode.includes("e")) x2 = Math.max(clamp01(x2 + dx), x + MIN);
      w = x2 - x; h = y2 - y;
      if (cropRatioId !== "free") setCropRatioId("free");  // کشیدنِ گوشه → نسبتِ آزاد
    }
    setCropRect({ x, y, w, h });
  };
  const onCropUp = () => { cropDragRef.current = null; };

  const startCrop = () => {
    setCropRect(manualCrop ?? { x: 0.08, y: 0.08, w: 0.84, h: 0.84 });
    setCropRatioId("free");
    setSelectedId(null); setTool("move"); setCropEditing(true);
  };
  const applyCrop = () => {
    const r = cropRect;
    const full = r.x <= 0.002 && r.y <= 0.002 && r.w >= 0.998 && r.h >= 0.998;
    setManualCrop(full ? null : { ...r });
    if (!full) setSquare(false);
    setCropEditing(false);
  };
  const cancelCrop = () => setCropEditing(false);
  const clearCrop = () => setManualCrop(null);
  const pickRatio = (r: typeof CROP_RATIOS[number]) => {
    setCropRatioId(r.id);
    if (r.ratio) setCropRect(centeredRect(natRef.current.w, natRef.current.h, r.ratio));
    else setCropRect({ x: 0.06, y: 0.06, w: 0.88, h: 0.88 });
  };

  // ── overlay editing ──────────────────────────────────────
  const addText = () => {
    const val = draft.trim(); if (!val) return;
    const ov: Overlay = { id: uid(), kind: "text", value: val, nx: 0.5, ny: 0.5, size: 0.09, color: textColor, fontCss: FONTS.find((f) => f.id === textFontId)!.css, effect: textEffect };
    setOverlays((p) => [...p, ov]); setSelectedId(ov.id);
  };
  const addEmoji = (e: string) => {
    const ov: Overlay = { id: uid(), kind: "emoji", value: e, nx: 0.5, ny: 0.5, size: 0.16, color: "#fff", fontCss: "sans-serif", effect: "plain" };
    setOverlays((p) => [...p, ov]); setSelectedId(ov.id);
  };
  const patchSelectedText = (patch: Partial<Overlay>) => { if (!selectedText) return; setOverlays((p) => p.map((o) => o.id === selectedText.id ? { ...o, ...patch } : o)); };
  const onDraftChange = (v: string) => { setDraft(v); if (selectedText) patchSelectedText({ value: v }); };
  const setColor = (c: string) => { setTextColor(c); patchSelectedText({ color: c }); };
  const setFont = (id: string) => { setTextFontId(id); patchSelectedText({ fontCss: FONTS.find((f) => f.id === id)!.css }); };
  const setEffect = (id: EffectId) => { setTextEffect(id); patchSelectedText({ effect: id }); };
  const resizeSelected = (delta: number) => setOverlays((p) => p.map((o) => o.id === selectedId ? { ...o, size: Math.min(0.85, Math.max(0.04, o.size + delta)) } : o));
  const deleteSelected = () => { if (!selectedId) return; setOverlays((p) => p.filter((o) => o.id !== selectedId)); setSelectedId(null); setDraft(""); };
  const setBorder = (color: string | null) => { if (!selectedId) return; setOverlays((p) => p.map((o) => o.id === selectedId ? { ...o, border: color } : o)); };

  // تصویر در تصویر: افزودنِ لایهٔ تصویری
  const addImageOverlay = (f: File) => {
    const url = URL.createObjectURL(f);
    const im = new Image();
    im.onload = () => {
      const ov: Overlay = { id: uid(), kind: "image", value: url, nx: 0.5, ny: 0.5, size: 0.42, color: "#fff", fontCss: "sans-serif", effect: "plain", aspect: im.naturalWidth / im.naturalHeight, el: im, border: "#FFFFFF" };
      setOverlays((p) => [...p, ov]); setSelectedId(ov.id); setTool("move");
    };
    im.onerror = () => { toast.error("بارگذاریِ تصویر ناموفق بود"); URL.revokeObjectURL(url); };
    im.src = url;
  };

  const translate = async (lang: string) => {
    const text = (selectedText?.value ?? draft).trim(); if (!text) { setShowTr(false); return; }
    setTranslating(true);
    try {
      const res = await messagesApi.translateText(text, lang);
      const out = res.data.translated_text as string;
      setDraft(out); if (selectedText) patchSelectedText({ value: out }); else addTextValue(out);
      setShowTr(false);
    } catch { toast.error("ترجمه ناموفق بود"); } finally { setTranslating(false); }
  };
  const addTextValue = (val: string) => {
    const ov: Overlay = { id: uid(), kind: "text", value: val, nx: 0.5, ny: 0.5, size: 0.09, color: textColor, fontCss: FONTS.find((f) => f.id === textFontId)!.css, effect: textEffect };
    setOverlays((p) => [...p, ov]); setSelectedId(ov.id);
  };

  const undoStroke = () => setStrokes((p) => p.slice(0, -1));
  const clearStrokes = () => setStrokes([]);

  // ── send ─────────────────────────────────────────────────
  const send = async () => {
    if (preset.id === "orig" && !hasEdits) { onDone(file); return; }
    setSelectedId(null);
    if (kind === "image") {
      setWorking(true);
      try { const blob = await renderImageOutput(); onDone(new File([blob], `photo-${Date.now()}.jpg`, { type: "image/jpeg" })); }
      catch { toast.error("پردازشِ تصویر ناموفق بود"); setWorking(false); }
    } else {
      setWorking(true); setProgress(0);
      try {
        const blob = await transcodeVideo(file, { square, manual: manualCrop, filterCss: baseFilterCss, blocks: pixel.blocks, overlays, strokes, frame: frame.id, maxDim: preset.maxDim, bitrate: (preset as { bitrate: number }).bitrate }, (p) => setProgress(p));
        toast.success(`حجم: ${toPersianDigits(fmtBytes(origSize))} ← ${toPersianDigits(fmtBytes(blob.size))}`);
        onDone(new File([blob], `video-${Date.now()}.webm`, { type: "video/webm" }));
      } catch { toast.error("فشرده‌سازیِ ویدیو ناموفق بود — فایلِ اصلی ارسال شد"); onDone(file); }
    }
  };

  const presets = kind === "image" ? IMG_PRESETS : VID_PRESETS;
  const changed = outSize !== null && kind === "image";

  const chip = (active: boolean) => `shrink-0 px-3 py-1.5 rounded-full text-xs border ${active ? "bg-indigo-600/25 border-indigo-400/50 text-white" : "bg-white/5 border-white/10 text-white/70"}`;

  return (
    <div className="fixed inset-0 z-[70] bg-black flex flex-col">
      {/* header */}
      <div className="flex items-center justify-between px-4 py-3 safe-top">
        <button onClick={onCancel} disabled={working} className="p-2 rounded-xl bg-white/10 text-white/80 disabled:opacity-40"><X size={20} /></button>
        <span className="text-white/70 text-sm">{kind === "image" ? "ویرایشِ تصویر" : "ویرایشِ ویدیو"}</span>
        {/* tool switch */}
        <div className="flex gap-1 bg-white/5 rounded-xl p-0.5">
          <button onClick={() => { setTool("move"); }} className={`p-1.5 rounded-lg ${tool === "move" ? "bg-indigo-600 text-white" : "text-white/60"}`}><Move size={16} /></button>
          <button onClick={() => { setTool("draw"); setSelectedId(null); }} className={`p-1.5 rounded-lg ${tool === "draw" ? "bg-indigo-600 text-white" : "text-white/60"}`}><Pencil size={16} /></button>
        </div>
      </div>

      {/* preview (canvas) */}
      <div className="flex-1 flex items-center justify-center p-3 overflow-hidden relative">
        <div className="relative" style={{ width: box.w, height: box.h }}>
          <canvas
            ref={canvasRef}
            onPointerDown={onDown} onPointerMove={onMove} onPointerUp={onUp} onPointerCancel={onUp}
            style={{ width: box.w, height: box.h, touchAction: "none" }}
            className="rounded-2xl bg-white/5 block"
          />
          {cropEditing && (
            <div ref={cropWrapRef} className="absolute inset-0 rounded-2xl overflow-hidden" style={{ touchAction: "none" }}>
              <div
                className="absolute border-2 border-white/90 cursor-move"
                style={{
                  left: `${cropRect.x * 100}%`, top: `${cropRect.y * 100}%`,
                  width: `${cropRect.w * 100}%`, height: `${cropRect.h * 100}%`,
                  boxShadow: "0 0 0 9999px rgba(0,0,0,0.55)", touchAction: "none",
                }}
                onPointerDown={onCropDown("move")} onPointerMove={onCropMove} onPointerUp={onCropUp} onPointerCancel={onCropUp}
              >
                {/* خطوطِ سه‌گانه (قانونِ یک‌سوم) */}
                <div className="absolute inset-0 pointer-events-none">
                  <div className="absolute top-0 bottom-0 w-px bg-white/25" style={{ left: "33.333%" }} />
                  <div className="absolute top-0 bottom-0 w-px bg-white/25" style={{ left: "66.666%" }} />
                  <div className="absolute left-0 right-0 h-px bg-white/25" style={{ top: "33.333%" }} />
                  <div className="absolute left-0 right-0 h-px bg-white/25" style={{ top: "66.666%" }} />
                </div>
                {/* دستگیره‌های گوشه */}
                {(["nw", "ne", "sw", "se"] as const).map((cn) => (
                  <div
                    key={cn}
                    onPointerDown={onCropDown(cn)} onPointerMove={onCropMove} onPointerUp={onCropUp} onPointerCancel={onCropUp}
                    className="absolute w-6 h-6 rounded-full bg-white border-2 border-indigo-500 shadow-md"
                    style={{
                      left: cn.includes("w") ? -12 : undefined, right: cn.includes("e") ? -12 : undefined,
                      top: cn.includes("n") ? -12 : undefined, bottom: cn.includes("s") ? -12 : undefined,
                      touchAction: "none",
                      cursor: cn === "nw" || cn === "se" ? "nwse-resize" : "nesw-resize",
                    }}
                  />
                ))}
              </div>
            </div>
          )}
        </div>
        {!ready && <div className="absolute inset-0 flex items-center justify-center"><Loader2 size={30} className="text-white/50 animate-spin" /></div>}
        {tool === "move" && overlays.length === 0 && ready && (
          <span className="absolute bottom-4 text-white/40 text-[11px] px-3 py-1 rounded-full bg-black/40 pointer-events-none">متن/ایموجی را اضافه و با انگشت جابه‌جا کن</span>
        )}
        {working && (
          <div className="absolute inset-0 bg-black/70 flex flex-col items-center justify-center gap-3">
            <Loader2 size={34} className="text-white animate-spin" />
            <p className="text-white/80 text-sm">{kind === "video" ? `در حالِ فشرده‌سازی… ${toPersianDigits(String(Math.round(progress * 100)))}٪` : "در حالِ پردازش…"}</p>
          </div>
        )}
      </div>

      {/* controls */}
      <div className="px-4 pb-safe pt-2 space-y-2.5 bg-[#0c0c0c] border-t border-white/8 max-h-[46vh] overflow-y-auto">
        {cropEditing ? (
          <div className="space-y-2.5">
            <p className="text-white/50 text-[12px] text-center">کادر را جابه‌جا کن و گوشه‌ها را برای تغییرِ اندازه بکش</p>
            <div className="flex gap-1.5 overflow-x-auto pb-0.5">
              <span className="text-white/40 text-[11px] self-center shrink-0 ml-1">نسبت</span>
              {CROP_RATIOS.map((r) => (
                <button key={r.id} onClick={() => pickRatio(r)} className={chip(cropRatioId === r.id)}>{r.label}</button>
              ))}
            </div>
            <div className="flex gap-2">
              <button onClick={cancelCrop} className="flex-1 py-2.5 rounded-xl bg-white/8 text-white/70 text-sm">لغو</button>
              <button onClick={applyCrop} className="flex-1 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-sm flex items-center justify-center gap-1.5"><Check size={16} /> تأیید برش</button>
            </div>
          </div>
        ) : tool === "draw" ? (
          <>
            <div className="flex items-center gap-2">
              <button onClick={() => setEraser((e) => !e)} className={`flex items-center gap-1.5 px-3 py-2 rounded-xl text-xs shrink-0 ${eraser ? "bg-rose-500/20 text-rose-300" : "bg-white/5 text-white/70"}`}>
                <Eraser size={15} /> {eraser ? "پاک‌کن" : "قلم"}
              </button>
              <div className="flex gap-1.5 overflow-x-auto">
                {BRUSH_SIZES.map((b) => (
                  <button key={b.id} onClick={() => { setBrushSize(b); setEraser(false); }} className={chip(brushSize.id === b.id && !eraser)}>{b.label}</button>
                ))}
              </div>
              <button onClick={undoStroke} disabled={!strokes.length} className="p-2 rounded-xl bg-white/5 text-white/70 disabled:opacity-30 shrink-0"><Undo2 size={15} /></button>
              <button onClick={clearStrokes} disabled={!strokes.length} className="p-2 rounded-xl bg-white/5 text-white/70 disabled:opacity-30 shrink-0"><Trash2 size={15} /></button>
            </div>
            {!eraser && (
              <div className="flex items-center gap-2">
                <span className="text-white/40 text-[11px] w-12 shrink-0">رنگِ قلم</span>
                <div className="flex-1"><SpectrumPicker value={brushColor} onPick={setBrushColor} /></div>
              </div>
            )}
          </>
        ) : (
          <>
            {/* دسته‌بندیِ تنظیمات */}
            <div className="flex gap-1 bg-white/5 rounded-xl p-0.5 text-xs">
              {([["layer", "نوشته"], ["filter", "فیلتر"], ["tune", "تنظیم"], ["adjust", "برش"]] as const).map(([id, label]) => (
                <button key={id} onClick={() => setMtab(id)} className={`flex-1 py-1.5 rounded-lg transition ${mtab === id ? "bg-indigo-600 text-white" : "text-white/60"}`}>{label}</button>
              ))}
            </div>

            {/* ── تبِ نوشته و لایه ── */}
            {mtab === "layer" && (
              <>
                <div className="flex items-center gap-2">
                  <button onClick={() => setShowEmoji((s) => !s)} className={`p-2 rounded-xl shrink-0 ${showEmoji ? "bg-indigo-500/20 text-indigo-300" : "bg-white/5 text-white/60"}`}><Smile size={18} /></button>
                  <button onClick={() => imgInputRef.current?.click()} className="p-2 rounded-xl shrink-0 bg-white/5 text-white/60" title="تصویر در تصویر"><ImagePlus size={18} /></button>
                  <input ref={imgInputRef} type="file" accept="image/*" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) addImageOverlay(f); e.target.value = ""; }} />
                  <input value={draft} onChange={(e) => onDraftChange(e.target.value)} maxLength={80} placeholder={selectedText ? "ویرایشِ متنِ انتخاب‌شده" : "متن روی رسانه"}
                    className="flex-1 bg-white/5 border border-white/10 rounded-xl px-3 py-2 text-white text-sm placeholder-white/30 focus:outline-none min-w-0" />
                  <button onClick={() => setShowTr((s) => !s)} className={`p-2 rounded-xl shrink-0 ${showTr ? "bg-emerald-500/20 text-emerald-300" : "bg-white/5 text-white/60"}`} title="ترجمه"><Languages size={18} /></button>
                  {!selectedText && <button onClick={addText} disabled={!draft.trim()} className="px-3 py-2 rounded-xl bg-indigo-600 text-white text-xs disabled:opacity-40 shrink-0 flex items-center gap-1"><TypeIcon size={14} /> افزودن</button>}
                </div>
                {selectedText && (
                  <button onClick={() => { setSelectedId(null); setDraft(""); }} className="text-[11px] text-indigo-300/80">＋ نوشتهٔ جدید (لغوِ انتخاب)</button>
                )}
                {showTr && (
                  <div className="flex gap-1.5 overflow-x-auto pb-0.5">
                    {translating ? <span className="text-white/50 text-xs flex items-center gap-2 px-2"><Loader2 size={14} className="animate-spin" /> در حالِ ترجمه…</span> :
                      TRANSLATE_LANGS.map((l) => (<button key={l.code} onClick={() => translate(l.code)} className={chip(false)}>{l.label}</button>))}
                  </div>
                )}
                {showEmoji && (
                  <div className="flex gap-1 flex-wrap max-h-40 overflow-y-auto">
                    {QUICK_EMOJIS.map((e, i) => (<button key={`${e}-${i}`} onClick={() => addEmoji(e)} className="w-8 h-8 rounded-lg hover:bg-white/10 text-lg flex items-center justify-center shrink-0">{e}</button>))}
                  </div>
                )}
                {selected ? (
                  <div className="space-y-2 rounded-xl bg-white/[0.03] p-2">
                    <div className="flex items-center justify-between">
                      <span className="text-indigo-300/80 text-[11px]">{selected.kind === "emoji" ? "ایموجیِ انتخاب‌شده" : selected.kind === "image" ? "تصویرِ انتخاب‌شده" : "متنِ انتخاب‌شده"}</span>
                      <div className="flex items-center gap-1">
                        <button onClick={() => resizeSelected(-0.015)} className="w-7 h-7 rounded-lg bg-white/5 text-white/70 text-sm">ــ</button>
                        <button onClick={() => resizeSelected(0.015)} className="w-7 h-7 rounded-lg bg-white/5 text-white/70 text-sm">＋</button>
                        <button onClick={deleteSelected} className="w-7 h-7 rounded-lg bg-rose-500/15 text-rose-300 flex items-center justify-center"><Trash2 size={14} /></button>
                      </div>
                    </div>
                    {selectedText && (
                      <>
                        <div className="flex gap-1.5 overflow-x-auto">
                          {FONTS.map((f) => (<button key={f.id} onClick={() => setFont(f.id)} className={chip(textFontId === f.id)} style={{ fontFamily: f.css }}>{f.label}</button>))}
                        </div>
                        <div className="flex gap-1.5 overflow-x-auto">
                          {TEXT_EFFECTS.map((e) => (<button key={e.id} onClick={() => setEffect(e.id)} className={chip(textEffect === e.id)}>{e.label}</button>))}
                        </div>
                        <SpectrumPicker value={textColor} onPick={setColor} />
                      </>
                    )}
                    <div className="flex items-center gap-1.5 overflow-x-auto">
                      <span className="text-white/40 text-[11px] shrink-0 ml-1">حاشیه</span>
                      {BORDER_COLORS.map((b) => (
                        <button key={b.id} onClick={() => setBorder(b.color)} className={chip((selected.border ?? null) === b.color)}>{b.label}</button>
                      ))}
                    </div>
                    {selectedImage && (
                      <p className="text-white/35 text-[10px] leading-relaxed">فیلتر و شطرنجیِ این تصویر را از تبِ «فیلتر و افکت» تنظیم کن.</p>
                    )}
                  </div>
                ) : (
                  <p className="text-white/35 text-[11px] text-center py-1">برای ویرایش، لایه‌ای را روی تصویر لمس کن.</p>
                )}
              </>
            )}

            {/* ── تبِ فیلتر و افکت ── */}
            {mtab === "filter" && (
              <>
                <p className={`text-[11px] text-center ${selectedImage ? "text-indigo-300/80" : "text-white/40"}`}>
                  {selectedImage ? "روی لایهٔ تصویرِ انتخاب‌شده اعمال می‌شود" : "روی کلِ تصویر اعمال می‌شود"}
                </p>
                <div className="flex gap-2 overflow-x-auto pb-0.5">
                  {FILTERS.map((f) => (<button key={f.id} onClick={() => applyFilter(f)} className={chip(activeFilterCss === f.css)}>{f.label}</button>))}
                </div>
                <div className="flex gap-2 overflow-x-auto pb-0.5">
                  {PIXEL_LEVELS.map((p) => (<button key={p.id} onClick={() => applyPixel(p)} className={chip(activeBlocks === p.blocks)}>{p.label}</button>))}
                </div>
              </>
            )}

            {/* ── تبِ تنظیمِ نور و رنگ ── */}
            {mtab === "tune" && (
              <div className="space-y-2.5">
                <div className="flex items-center justify-between">
                  <span className="text-white/40 text-[11px]">نور و رنگِ کلِ تصویر</span>
                  <button onClick={() => setAdjust(ADJUST_DEFAULT)} disabled={!adjusted} className="flex items-center gap-1 text-[11px] text-white/50 hover:text-white/80 disabled:opacity-30">
                    <RotateCcw size={12} /> بازنشانی
                  </button>
                </div>
                {TUNE_SLIDERS.map((s) => (
                  <div key={s.key} className="flex items-center gap-2.5">
                    <s.Icon size={15} className="text-white/50 shrink-0" />
                    <span className="text-white/60 text-xs w-12 shrink-0">{s.label}</span>
                    <input
                      type="range" min={s.min} max={s.max} step={s.step} value={adjust[s.key]}
                      onChange={(e) => { const v = parseFloat(e.target.value); setAdjust((a) => ({ ...a, [s.key]: v })); }}
                      className="flex-1 accent-indigo-500 h-1"
                    />
                    <span className="text-white/40 text-[10px] w-8 text-left tabular-nums">{s.fmt(adjust[s.key])}</span>
                  </div>
                ))}
              </div>
            )}

            {/* ── تبِ برش و کیفیت ── */}
            {mtab === "adjust" && (
              <>
                <div className="flex items-center gap-2 overflow-x-auto pb-0.5">
                  <span className="text-white/40 text-[11px] shrink-0 ml-1">قاب</span>
                  <FrameIcon size={14} className="text-white/40 shrink-0" />
                  {FRAMES.map((f) => (<button key={f.id} onClick={() => setFrame(f)} className={chip(frame.id === f.id)}>{f.label}</button>))}
                </div>
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="text-white/40 text-[11px] shrink-0 ml-1">برش</span>
                  <button onClick={() => { setManualCrop(null); setSquare((s) => !s); }} className={`flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs shrink-0 border ${square && !manualCrop ? "bg-indigo-600/25 border-indigo-400/50 text-white" : "bg-white/5 border-white/10 text-white/70"}`}>
                    {square ? <Square size={14} /> : <Crop size={14} />} {square ? "مربع" : "کامل"}
                  </button>
                  <button onClick={startCrop} className={`flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs shrink-0 border ${manualCrop ? "bg-indigo-600/25 border-indigo-400/50 text-white" : "bg-white/5 border-white/10 text-white/70"}`}>
                    <Crop size={14} /> برشِ دستی
                  </button>
                  {manualCrop && (
                    <button onClick={clearCrop} className="flex items-center gap-1 px-3 py-1.5 rounded-full text-xs shrink-0 border bg-rose-500/15 border-rose-400/30 text-rose-300">
                      <X size={13} /> حذف
                    </button>
                  )}
                </div>
                <div className="flex gap-1.5 overflow-x-auto pb-0.5">
                  <span className="text-white/40 text-[11px] self-center shrink-0 ml-1">کیفیت</span>
                  {presets.map((p) => (<button key={p.id} onClick={() => setPreset(p)} className={chip(preset.id === p.id)}>{p.label}</button>))}
                </div>
                <div className="flex items-center justify-center gap-2 text-[12px]">
                  <span className="text-white/40">حجمِ اصلی: <span className="text-white/70">{toPersianDigits(fmtBytes(origSize))}</span></span>
                  {changed && (<>
                    <span className="text-white/30">←</span>
                    <span className="text-emerald-400">جدید: {toPersianDigits(fmtBytes(outSize!))}</span>
                    {outSize! < origSize && <span className="text-emerald-400/70">({toPersianDigits(String(Math.round((1 - outSize! / origSize) * 100)))}٪ کمتر)</span>}
                  </>)}
                  {kind === "video" && preset.id !== "orig" && <span className="text-white/40">— پس از فشرده‌سازی</span>}
                </div>
              </>
            )}
          </>
        )}

        {/* send */}
        {!cropEditing && (
          <button onClick={send} disabled={working || !ready} className="w-full flex items-center justify-center gap-2 px-4 py-3 rounded-2xl bg-indigo-600 hover:bg-indigo-500 text-white text-sm disabled:opacity-50">
            {working ? <Loader2 size={18} className="animate-spin" /> : <><Send size={18} /> ارسال</>}
            {!working && preset.id === "orig" && !hasEdits && <span className="text-white/60 text-xs">(اصل)</span>}
          </button>
        )}
      </div>
    </div>
  );
}
