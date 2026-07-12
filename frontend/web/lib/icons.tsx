// شیمِ آیکون — جایگزینِ `lucide-react` بدونِ وابستگیِ خارجی.
// هر آیکون یک span با گلیفِ متنی/ایموجی است که با prop اندازهٔ `size` مقیاس می‌شود.
// امضای props با lucide سازگار است تا محلِ استفاده بدون تغییر بماند
// (size/className/style؛ سایرِ propها مثلِ strokeWidth نادیده گرفته می‌شوند).
import type { CSSProperties } from "react";

export interface IconProps {
  size?: number | string;
  className?: string;
  style?: CSSProperties;
  strokeWidth?: number;
  color?: string;
}

function makeIcon(glyph: string) {
  function Icon({ size = 18, className, style, color }: IconProps) {
    return (
      <span
        aria-hidden
        className={className}
        style={{
          fontSize: typeof size === "number" ? `${size}px` : size,
          lineHeight: 1,
          display: "inline-flex",
          alignItems: "center",
          justifyContent: "center",
          color,
          ...style,
        }}
      >
        {glyph}
      </span>
    );
  }
  return Icon;
}

export const Plus = makeIcon("＋");
export const Loader2 = makeIcon("⏳");
export const Check = makeIcon("✓");
export const Globe = makeIcon("🌐");
export const Users = makeIcon("👥");
export const Briefcase = makeIcon("💼");
export const Home = makeIcon("🏠");
export const Heart = makeIcon("❤");
export const X = makeIcon("✕");
export const Trash2 = makeIcon("🗑");
export const Eye = makeIcon("👁");
export const ChevronLeft = makeIcon("‹");
export const ChevronRight = makeIcon("›");
export const Search = makeIcon("🔍");
export const Star = makeIcon("★");
export const Download = makeIcon("⬇");
export const ArrowRight = makeIcon("→");
export const FolderPlus = makeIcon("📁");
export const Image = makeIcon("🖼");
export const Play = makeIcon("▶");
export const Volume2 = makeIcon("🔊");
export const Sticker = makeIcon("🙂");
export const Send = makeIcon("➤");
export const Type = makeIcon("T");
export const Square = makeIcon("▢");
export const Crop = makeIcon("⛶");
export const Smile = makeIcon("🙂");
export const Pencil = makeIcon("✏");
export const Eraser = makeIcon("🧽");
export const Move = makeIcon("✥");
export const Languages = makeIcon("🔤");
export const Undo2 = makeIcon("↩");
export const ImagePlus = makeIcon("🖼");
export const Frame = makeIcon("🖼");
export const Sun = makeIcon("☀");
export const Contrast = makeIcon("◐");
export const Droplet = makeIcon("💧");
export const Thermometer = makeIcon("🌡");
export const Aperture = makeIcon("◉");
export const RotateCcw = makeIcon("↺");
