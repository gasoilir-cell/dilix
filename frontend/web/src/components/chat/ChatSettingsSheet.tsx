"use client";

import { useRef } from "react";
import { X, ImagePlus, Check } from "lucide-react";
import toast from "react-hot-toast";
import { ChatTheme, CHAT_BACKGROUNDS, CHAT_ACCENTS, bgStyle } from "@/lib/chatTheme";

interface Props {
  theme: ChatTheme;
  onChange: (t: ChatTheme) => void;
  onClose: () => void;
}

// شخصی‌سازیِ ظاهرِ چت: انتخابِ پس‌زمینه (پیش‌فرض/گرادیان/طرح‌دار/تصویرِ سفارشی) و رنگِ حباب‌ها.
export default function ChatSettingsSheet({ theme, onChange, onClose }: Props) {
  const fileRef = useRef<HTMLInputElement>(null);

  const pickImage = (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0];
    e.target.value = "";
    if (!f) return;
    if (!f.type.startsWith("image/")) { toast.error("فقط تصویر"); return; }
    if (f.size > 3 * 1024 * 1024) { toast.error("حجمِ تصویر نباید بیش از ۳ مگابایت باشد"); return; }
    const reader = new FileReader();
    reader.onload = () => onChange({ ...theme, bg: `img:${reader.result as string}` });
    reader.readAsDataURL(f);
  };

  const isCustom = theme.bg.startsWith("img:");

  return (
    <div className="fixed inset-0 z-[60] flex items-end justify-center bg-black/50" onClick={onClose}>
      <div
        className="w-full max-w-md bg-[#1C1C1E] rounded-t-3xl p-4 pb-safe animate-[slideUp_0.2s_ease] max-h-[85vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between mb-4">
          <p className="text-white font-semibold">شخصی‌سازیِ چت</p>
          <button onClick={onClose} className="p-1.5 rounded-lg text-white/50 hover:bg-white/5"><X size={18} /></button>
        </div>

        {/* preview */}
        <div className="rounded-2xl overflow-hidden border border-white/8 mb-4" style={bgStyle(theme.bg)}>
          <div className="p-4 space-y-2">
            <div className="flex justify-start">
              <span className="px-3 py-2 rounded-2xl rounded-bl-sm bg-[#2C2C2E] text-white/90 text-xs">سلام 👋</span>
            </div>
            <div className="flex justify-end">
              <span className="px-3 py-2 rounded-2xl rounded-br-sm text-white text-xs" style={{ backgroundColor: theme.accent }}>
                سلام، خوبی؟
              </span>
            </div>
          </div>
        </div>

        {/* backgrounds */}
        <p className="text-white/50 text-xs mb-2">پس‌زمینه</p>
        <div className="grid grid-cols-4 gap-2 mb-3">
          {CHAT_BACKGROUNDS.map((b) => {
            const active = !isCustom && theme.bg === b.id;
            return (
              <button
                key={b.id}
                onClick={() => onChange({ ...theme, bg: b.id })}
                className={`relative h-16 rounded-xl border-2 overflow-hidden ${active ? "border-indigo-500" : "border-white/10"}`}
                style={bgStyle(b.id)}
                title={b.label}
              >
                {active && (
                  <span className="absolute inset-0 flex items-center justify-center">
                    <span className="w-5 h-5 rounded-full bg-indigo-600 flex items-center justify-center"><Check size={12} className="text-white" /></span>
                  </span>
                )}
                <span className="absolute bottom-0 inset-x-0 bg-black/40 text-[9px] text-white/80 text-center py-0.5">{b.label}</span>
              </button>
            );
          })}
          <button
            onClick={() => fileRef.current?.click()}
            className={`relative h-16 rounded-xl border-2 overflow-hidden flex flex-col items-center justify-center gap-1 ${isCustom ? "border-indigo-500" : "border-white/10"}`}
            style={isCustom ? bgStyle(theme.bg) : { backgroundColor: "#141414" }}
            title="تصویرِ سفارشی"
          >
            <ImagePlus size={18} className="text-white/70" />
            <span className="text-[9px] text-white/70">تصویرِ من</span>
          </button>
          <input ref={fileRef} type="file" accept="image/*" hidden onChange={pickImage} />
        </div>

        {/* accents */}
        <p className="text-white/50 text-xs mb-2">رنگِ حباب‌ها</p>
        <div className="flex flex-wrap gap-2.5 mb-2">
          {CHAT_ACCENTS.map((a) => {
            const active = theme.accent === a.color;
            return (
              <button
                key={a.id}
                onClick={() => onChange({ ...theme, accent: a.color })}
                className={`w-9 h-9 rounded-full flex items-center justify-center ring-2 ${active ? "ring-white" : "ring-transparent"}`}
                style={{ backgroundColor: a.color }}
              >
                {active && <Check size={16} className="text-white" />}
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}
