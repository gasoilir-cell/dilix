"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { X, ImagePlus, Camera, SwitchCamera, Type as TypeIcon, Crop, Loader2, Send, Circle, Square, RotateCcw, Mic, Play, Pause, Trash2 } from "lucide-react";
import toast from "react-hot-toast";

type MediaKind = "image" | "video" | "voice";

interface Props {
  onClose: () => void;
  onSend: (file: File, kind: MediaKind) => void;
}

const AUDIO_EMOJIS = ["😀", "😂", "😍", "🥳", "😎", "😭", "😱", "🥰", "🤩", "😴", "🔥", "❤️", "👏", "🎉", "🙏", "💯"];

const FILTERS: { id: string; label: string; css: string }[] = [
  { id: "none", label: "عادی", css: "none" },
  { id: "mono", label: "سیاه‌سفید", css: "grayscale(1)" },
  { id: "warm", label: "گرم", css: "sepia(0.4) saturate(1.5)" },
  { id: "cool", label: "سرد", css: "hue-rotate(180deg) saturate(1.2)" },
  { id: "vintage", label: "قدیمی", css: "sepia(0.6) contrast(0.9) brightness(1.1)" },
  { id: "bright", label: "روشن", css: "brightness(1.3) saturate(1.2)" },
  { id: "punch", label: "کنتراست", css: "contrast(1.4) saturate(1.3)" },
];

const HIGHLIGHTS: { id: string; label: string; rgba: string }[] = [
  { id: "none", label: "بدون", rgba: "" },
  { id: "yellow", label: "زرد", rgba: "rgba(250,204,21,0.28)" },
  { id: "pink", label: "صورتی", rgba: "rgba(236,72,153,0.28)" },
  { id: "blue", label: "آبی", rgba: "rgba(56,189,248,0.28)" },
  { id: "green", label: "سبز", rgba: "rgba(52,211,153,0.28)" },
  { id: "purple", label: "بنفش", rgba: "rgba(167,139,250,0.30)" },
];

const TEXT_COLORS = ["#FFFFFF", "#000000", "#FACC15", "#EC4899", "#38BDF8", "#34D399", "#F87171"];

export default function StickerStudio({ onClose, onSend }: Props) {
  const [mode, setMode] = useState<"still" | "animated" | "audio" | "fusion">("still");
  return (
    <div className="fixed inset-0 z-[70] bg-black flex flex-col">
      <div className="flex items-center justify-between px-4 py-3 safe-top">
        <button onClick={onClose} className="p-2 rounded-xl bg-white/10 text-white/80"><X size={20} /></button>
        <div className="flex bg-white/10 rounded-full p-1">
          <button
            onClick={() => setMode("still")}
            className={`px-4 py-1.5 rounded-full text-xs ${mode === "still" ? "bg-fuchsia-600 text-white" : "text-white/70"}`}
          >استیکر</button>
          <button
            onClick={() => setMode("animated")}
            className={`px-4 py-1.5 rounded-full text-xs ${mode === "animated" ? "bg-fuchsia-600 text-white" : "text-white/70"}`}
          >متحرک</button>
          <button
            onClick={() => setMode("audio")}
            className={`px-4 py-1.5 rounded-full text-xs ${mode === "audio" ? "bg-fuchsia-600 text-white" : "text-white/70"}`}
          >صوتی</button>
          <button
            onClick={() => setMode("fusion")}
            className={`px-4 py-1.5 rounded-full text-xs ${mode === "fusion" ? "bg-fuchsia-600 text-white" : "text-white/70"}`}
          >ادغام</button>
        </div>
        <span className="w-9" />
      </div>
      {mode === "still" ? <StillEditor onSend={onSend} />
        : mode === "animated" ? <AnimatedEditor onSend={onSend} />
        : mode === "audio" ? <AudioEditor onSend={onSend} />
        : <FusionEditor onSend={onSend} />}
    </div>
  );
}

// ── اموجی/استیکرِ صوتی: ضبطِ صدای کوتاه + انتخابِ اموجی ─────────
function AudioEditor({ onSend }: { onSend: (f: File, k: MediaKind) => void }) {
  const recRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const streamRef = useRef<MediaStream | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [emoji, setEmoji] = useState(AUDIO_EMOJIS[0]);
  const [recording, setRecording] = useState(false);
  const [secs, setSecs] = useState(0);
  const [preview, setPreview] = useState<string | null>(null);
  const blobRef = useRef<Blob | null>(null);
  const [playing, setPlaying] = useState(false);

  const cleanup = useCallback(() => {
    if (timerRef.current) clearInterval(timerRef.current);
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
  }, []);
  useEffect(() => () => cleanup(), [cleanup]);

  const start = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      streamRef.current = stream;
      const mime = MediaRecorder.isTypeSupported("audio/webm;codecs=opus") ? "audio/webm;codecs=opus" : "audio/webm";
      const mr = new MediaRecorder(stream, { mimeType: mime });
      chunksRef.current = [];
      mr.ondataavailable = (e) => { if (e.data.size > 0) chunksRef.current.push(e.data); };
      mr.onstop = () => {
        cleanup();
        const blob = new Blob(chunksRef.current, { type: "audio/webm" });
        blobRef.current = blob;
        setPreview(URL.createObjectURL(blob));
      };
      recRef.current = mr;
      mr.start();
      setRecording(true);
      setSecs(0);
      timerRef.current = setInterval(() => {
        setSecs((s) => {
          if (s + 1 >= 15) { stop(); return 15; }
          return s + 1;
        });
      }, 1000);
    } catch { toast.error("دسترسی به میکروفون ممکن نشد"); }
  };

  const stop = () => {
    if (timerRef.current) clearInterval(timerRef.current);
    const mr = recRef.current;
    if (mr && mr.state !== "inactive") mr.stop();
    setRecording(false);
  };

  const discard = () => {
    if (preview) URL.revokeObjectURL(preview);
    setPreview(null); blobRef.current = null; setSecs(0); setPlaying(false);
  };

  const togglePlay = () => {
    const a = audioRef.current; if (!a) return;
    if (a.paused) { a.play(); setPlaying(true); } else { a.pause(); setPlaying(false); }
  };

  const send = () => {
    const blob = blobRef.current;
    if (!blob) return;
    onSend(new File([blob], `voice-sticker-${Date.now()}.webm`, { type: "audio/webm" }), "voice");
  };

  return (
    <div className="flex-1 flex flex-col items-center justify-center gap-6 px-8">
      <div className="text-7xl">{emoji}</div>
      <div className="flex gap-1.5 flex-wrap justify-center max-w-xs">
        {AUDIO_EMOJIS.map((e) => (
          <button key={e} onClick={() => setEmoji(e)}
            className={`w-9 h-9 rounded-lg text-xl flex items-center justify-center ${emoji === e ? "bg-fuchsia-600/30 ring-1 ring-fuchsia-400" : "hover:bg-white/10"}`}>{e}</button>
        ))}
      </div>

      {preview ? (
        <div className="flex flex-col items-center gap-4 w-full">
          <audio ref={audioRef} src={preview} onEnded={() => setPlaying(false)} className="hidden" />
          <button onClick={togglePlay} className="flex items-center gap-2 px-5 py-3 rounded-2xl bg-white/10 text-white">
            {playing ? <Pause size={20} /> : <Play size={20} />} پخشِ پیش‌نمایش
          </button>
          <div className="flex gap-3">
            <button onClick={discard} className="flex items-center gap-2 px-4 py-2.5 rounded-xl bg-white/5 text-white/70 text-sm"><Trash2 size={16} /> حذف</button>
            <button onClick={send} className="flex items-center gap-2 px-5 py-2.5 rounded-xl bg-fuchsia-600 text-white text-sm"><Send size={16} /> ارسال</button>
          </div>
        </div>
      ) : (
        <div className="flex flex-col items-center gap-3">
          {recording && <span className="text-red-400 font-mono text-sm">{secs}s / 15s</span>}
          {!recording ? (
            <button onClick={start} className="w-20 h-20 rounded-full bg-red-600 ring-4 ring-red-500/30 flex items-center justify-center"><Mic size={30} className="text-white" /></button>
          ) : (
            <button onClick={stop} className="w-20 h-20 rounded-full bg-white ring-4 ring-white/30 flex items-center justify-center"><Square size={26} className="text-red-600 fill-current" /></button>
          )}
          <p className="text-white/40 text-xs">{recording ? "برای توقف بزن" : "برای ضبطِ اموجیِ صوتی بزن (حداکثر ۱۵ ثانیه)"}</p>
        </div>
      )}
    </div>
  );
}

// ── استیکرِ تصویرِ ثابت ─────────────────────────────────────────
function StillEditor({ onSend }: { onSend: (f: File, k: "image" | "video") => void }) {
  const fileRef = useRef<HTMLInputElement>(null);
  const imgRef = useRef<HTMLImageElement | null>(null);
  const [src, setSrc] = useState<string | null>(null);
  const [filter, setFilter] = useState(FILTERS[0]);
  const [hl, setHl] = useState(HIGHLIGHTS[0]);
  const [caption, setCaption] = useState("");
  const [textColor, setTextColor] = useState(TEXT_COLORS[0]);
  const [square, setSquare] = useState(true);
  const [showCam, setShowCam] = useState(false);
  const [busy, setBusy] = useState(false);

  const loadFile = (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0];
    e.target.value = "";
    if (!f) return;
    if (!f.type.startsWith("image/")) { toast.error("فقط تصویر"); return; }
    const url = URL.createObjectURL(f);
    const im = new Image();
    im.onload = () => { imgRef.current = im; setSrc(url); };
    im.src = url;
  };

  const onSnap = (im: HTMLImageElement, url: string) => {
    imgRef.current = im; setSrc(url); setShowCam(false);
  };

  const build = async () => {
    const im = imgRef.current;
    if (!im) return;
    setBusy(true);
    try {
      const canvas = document.createElement("canvas");
      const size = 512;
      let sx = 0, sy = 0, sw = im.naturalWidth, sh = im.naturalHeight;
      if (square) {
        const m = Math.min(sw, sh);
        sx = (sw - m) / 2; sy = (sh - m) / 2; sw = m; sh = m;
        canvas.width = size; canvas.height = size;
      } else {
        const ratio = sh / sw;
        canvas.width = size; canvas.height = Math.round(size * ratio);
      }
      const ctx = canvas.getContext("2d");
      if (!ctx) return;
      ctx.filter = filter.css === "none" ? "none" : filter.css;
      ctx.drawImage(im, sx, sy, sw, sh, 0, 0, canvas.width, canvas.height);
      ctx.filter = "none";
      if (hl.rgba) { ctx.fillStyle = hl.rgba; ctx.fillRect(0, 0, canvas.width, canvas.height); }
      const cap = caption.trim();
      if (cap) {
        const fs = Math.round(canvas.width * 0.09);
        ctx.font = `bold ${fs}px Tahoma, sans-serif`;
        ctx.textAlign = "center";
        ctx.textBaseline = "bottom";
        ctx.lineWidth = Math.max(3, fs * 0.14);
        ctx.strokeStyle = textColor === "#000000" ? "#FFFFFF" : "rgba(0,0,0,0.85)";
        ctx.fillStyle = textColor;
        const y = canvas.height - fs * 0.5;
        ctx.strokeText(cap, canvas.width / 2, y);
        ctx.fillText(cap, canvas.width / 2, y);
      }
      canvas.toBlob((blob) => {
        setBusy(false);
        if (!blob) { toast.error("ساختِ استیکر ناموفق بود"); return; }
        onSend(new File([blob], `sticker-${Date.now()}.png`, { type: "image/png" }), "image");
      }, "image/png");
    } catch {
      setBusy(false);
      toast.error("خطا در ساختِ استیکر");
    }
  };

  if (showCam) return <CameraSnap onCancel={() => setShowCam(false)} onSnap={onSnap} />;

  if (!src) {
    return (
      <div className="flex-1 flex flex-col items-center justify-center gap-4 px-8">
        <p className="text-white/50 text-sm mb-2">یک منبع انتخاب کن</p>
        <button onClick={() => fileRef.current?.click()} className="w-full max-w-xs flex items-center gap-3 px-5 py-4 rounded-2xl bg-white/5 hover:bg-white/10 text-white">
          <span className="w-10 h-10 rounded-full bg-sky-500/20 flex items-center justify-center"><ImagePlus size={20} className="text-sky-400" /></span>
          وارد کردنِ تصویر
        </button>
        <button onClick={() => setShowCam(true)} className="w-full max-w-xs flex items-center gap-3 px-5 py-4 rounded-2xl bg-white/5 hover:bg-white/10 text-white">
          <span className="w-10 h-10 rounded-full bg-indigo-500/20 flex items-center justify-center"><Camera size={20} className="text-indigo-400" /></span>
          گرفتنِ عکس با دوربین
        </button>
        <input ref={fileRef} type="file" accept="image/*" hidden onChange={loadFile} />
      </div>
    );
  }

  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      {/* canvas preview */}
      <div className="flex-1 flex items-center justify-center p-4 overflow-hidden">
        <div className="relative" style={{ maxWidth: "88vw", maxHeight: "44vh" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={src} alt=""
            className={`rounded-2xl object-cover ${square ? "aspect-square w-72 h-72" : "max-h-[44vh]"}`}
            style={{ filter: filter.css === "none" ? undefined : filter.css }}
          />
          {hl.rgba && <div className="absolute inset-0 rounded-2xl" style={{ backgroundColor: hl.rgba }} />}
          {caption.trim() && (
            <div className="absolute inset-x-0 bottom-3 text-center px-2">
              <span
                className="font-bold text-2xl"
                style={{ color: textColor, WebkitTextStroke: `1px ${textColor === "#000000" ? "#fff" : "rgba(0,0,0,0.8)"}` }}
              >{caption}</span>
            </div>
          )}
        </div>
      </div>

      {/* controls */}
      <div className="px-4 pb-safe pt-2 space-y-3 bg-[#0c0c0c] border-t border-white/8">
        <div className="flex gap-2 overflow-x-auto pb-1">
          {FILTERS.map((f) => (
            <button key={f.id} onClick={() => setFilter(f)}
              className={`shrink-0 px-3 py-1.5 rounded-full text-xs border ${filter.id === f.id ? "bg-fuchsia-600/20 border-fuchsia-400/50 text-white" : "bg-white/5 border-white/10 text-white/70"}`}>
              {f.label}
            </button>
          ))}
        </div>
        <div className="flex items-center gap-2">
          <span className="text-white/40 text-[11px] w-10">رنگ</span>
          {HIGHLIGHTS.map((h) => (
            <button key={h.id} onClick={() => setHl(h)}
              className={`w-7 h-7 rounded-full border ${hl.id === h.id ? "border-white" : "border-white/20"} flex items-center justify-center`}
              style={{ backgroundColor: h.rgba || "transparent" }}>
              {h.id === "none" && <X size={12} className="text-white/60" />}
            </button>
          ))}
        </div>
        <div className="flex items-center gap-2">
          <TypeIcon size={16} className="text-white/50 shrink-0" />
          <input value={caption} onChange={(e) => setCaption(e.target.value)} maxLength={40} placeholder="متن (اختیاری)"
            className="flex-1 bg-white/5 border border-white/10 rounded-xl px-3 py-2 text-white text-sm placeholder-white/30 focus:outline-none" />
          {TEXT_COLORS.map((c) => (
            <button key={c} onClick={() => setTextColor(c)}
              className={`w-6 h-6 rounded-full border-2 shrink-0 ${textColor === c ? "border-white" : "border-white/20"}`}
              style={{ backgroundColor: c }} />
          ))}
        </div>
        <div className="flex items-center gap-2">
          <button onClick={() => setSquare((s) => !s)}
            className="flex items-center gap-1.5 px-3 py-2 rounded-xl bg-white/5 text-white/70 text-xs">
            {square ? <Square size={15} /> : <Crop size={15} />} {square ? "مربع" : "کامل"}
          </button>
          <button onClick={() => { setSrc(null); imgRef.current = null; }}
            className="flex items-center gap-1.5 px-3 py-2 rounded-xl bg-white/5 text-white/70 text-xs">
            <RotateCcw size={15} /> تعویضِ تصویر
          </button>
          <button onClick={build} disabled={busy}
            className="flex-1 flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl bg-fuchsia-600 hover:bg-fuchsia-500 text-white text-sm disabled:opacity-50">
            {busy ? <Loader2 size={16} className="animate-spin" /> : <><Send size={16} /> ارسالِ استیکر</>}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── گرفتنِ تک‌فریم از دوربین برای استیکرِ ثابت ─────────────────
function CameraSnap({ onCancel, onSnap }: { onCancel: () => void; onSnap: (im: HTMLImageElement, url: string) => void }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const [facing, setFacing] = useState<"environment" | "user">("user");

  const stop = useCallback(() => { streamRef.current?.getTracks().forEach((t) => t.stop()); streamRef.current = null; }, []);
  const start = useCallback(async (mode: "environment" | "user") => {
    stop();
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: mode }, audio: false });
      streamRef.current = stream;
      if (videoRef.current) { videoRef.current.srcObject = stream; await videoRef.current.play().catch(() => {}); }
    } catch { toast.error("دوربین در دسترس نیست"); onCancel(); }
  }, [stop, onCancel]);

  useEffect(() => { start(facing); return () => stop(); /* eslint-disable-next-line */ }, [facing]);

  const snap = () => {
    const v = videoRef.current;
    if (!v || !v.videoWidth) return;
    const c = document.createElement("canvas");
    c.width = v.videoWidth; c.height = v.videoHeight;
    const ctx = c.getContext("2d"); if (!ctx) return;
    if (facing === "user") { ctx.translate(c.width, 0); ctx.scale(-1, 1); }
    ctx.drawImage(v, 0, 0);
    c.toBlob((blob) => {
      if (!blob) return;
      const url = URL.createObjectURL(blob);
      const im = new Image();
      im.onload = () => { stop(); onSnap(im, url); };
      im.src = url;
    }, "image/jpeg", 0.92);
  };

  return (
    <div className="flex-1 flex flex-col">
      <div className="flex-1 relative flex items-center justify-center overflow-hidden">
        <video ref={videoRef} playsInline muted className={`max-h-full max-w-full ${facing === "user" ? "-scale-x-100" : ""}`} />
        <button onClick={() => setFacing((f) => f === "user" ? "environment" : "user")}
          className="absolute top-3 left-3 p-2 rounded-xl bg-white/10 text-white/80"><SwitchCamera size={18} /></button>
      </div>
      <div className="px-6 py-6 pb-safe flex items-center justify-center gap-8">
        <button onClick={onCancel} className="text-white/70 text-sm">لغو</button>
        <button onClick={snap} className="w-16 h-16 rounded-full bg-white ring-4 ring-white/30 flex items-center justify-center">
          <Camera size={24} className="text-black" />
        </button>
        <span className="w-10" />
      </div>
    </div>
  );
}

// ── اموجیِ متحرک: ضبطِ ویدیوی کوتاه با فیلترِ baked ─────────────
function AnimatedEditor({ onSend }: { onSend: (f: File, k: "image" | "video") => void }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const recRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const rafRef = useRef<number>(0);
  const [facing, setFacing] = useState<"user" | "environment">("user");
  const [filter, setFilter] = useState(FILTERS[0]);
  const [recording, setRecording] = useState(false);
  const [secs, setSecs] = useState(0);
  const [preview, setPreview] = useState<string | null>(null);
  const previewBlobRef = useRef<Blob | null>(null);
  const filterRef = useRef(filter);
  useEffect(() => { filterRef.current = filter; }, [filter]);

  const stop = useCallback(() => {
    cancelAnimationFrame(rafRef.current);
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
  }, []);

  const start = useCallback(async (mode: "user" | "environment") => {
    stop();
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: mode }, audio: false });
      streamRef.current = stream;
      if (videoRef.current) { videoRef.current.srcObject = stream; await videoRef.current.play().catch(() => {}); }
    } catch { toast.error("دوربین در دسترس نیست"); }
  }, [stop]);

  useEffect(() => { if (!preview) start(facing); return () => stop(); /* eslint-disable-next-line */ }, [facing, preview]);

  const record = () => {
    const v = videoRef.current;
    if (!v || !v.videoWidth || !streamRef.current) return;
    const size = 480;
    const canvas = document.createElement("canvas");
    canvas.width = size; canvas.height = size;
    canvasRef.current = canvas;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    const draw = () => {
      const vw = v.videoWidth, vh = v.videoHeight;
      const m = Math.min(vw, vh);
      const sx = (vw - m) / 2, sy = (vh - m) / 2;
      ctx.save();
      if (facing === "user") { ctx.translate(size, 0); ctx.scale(-1, 1); }
      ctx.filter = filterRef.current.css === "none" ? "none" : filterRef.current.css;
      ctx.drawImage(v, sx, sy, m, m, 0, 0, size, size);
      ctx.restore();
      rafRef.current = requestAnimationFrame(draw);
    };
    draw();
    const outStream = canvas.captureStream(25);
    const mime = MediaRecorder.isTypeSupported("video/webm;codecs=vp9") ? "video/webm;codecs=vp9" : "video/webm";
    const mr = new MediaRecorder(outStream, { mimeType: mime });
    chunksRef.current = [];
    mr.ondataavailable = (e) => { if (e.data.size > 0) chunksRef.current.push(e.data); };
    mr.onstop = () => {
      cancelAnimationFrame(rafRef.current);
      const blob = new Blob(chunksRef.current, { type: "video/webm" });
      previewBlobRef.current = blob;
      setPreview(URL.createObjectURL(blob));
      stop();
    };
    recRef.current = mr;
    mr.start();
    setRecording(true);
    setSecs(0);
    const iv = setInterval(() => {
      setSecs((s) => {
        if (s + 1 >= 6) { clearInterval(iv); if (mr.state !== "inactive") mr.stop(); setRecording(false); }
        return s + 1;
      });
    }, 1000);
    (mr as unknown as { _iv?: ReturnType<typeof setInterval> })._iv = iv;
  };

  const stopRec = () => {
    const mr = recRef.current;
    const iv = (mr as unknown as { _iv?: ReturnType<typeof setInterval> })?._iv;
    if (iv) clearInterval(iv);
    if (mr && mr.state !== "inactive") mr.stop();
    setRecording(false);
  };

  const retake = () => {
    if (preview) URL.revokeObjectURL(preview);
    setPreview(null);
    previewBlobRef.current = null;
    setSecs(0);
  };

  const send = () => {
    const blob = previewBlobRef.current;
    if (!blob) return;
    onSend(new File([blob], `sticker-${Date.now()}.webm`, { type: "video/webm" }), "video");
  };

  if (preview) {
    return (
      <div className="flex-1 flex flex-col">
        <div className="flex-1 flex items-center justify-center p-4">
          <video src={preview} className="rounded-2xl w-72 h-72 object-cover" autoPlay loop muted playsInline />
        </div>
        <div className="px-6 py-6 pb-safe flex items-center justify-center gap-8">
          <button onClick={retake} className="flex flex-col items-center gap-1 text-white/80">
            <span className="w-14 h-14 rounded-full bg-white/10 flex items-center justify-center"><RotateCcw size={22} /></span>
            <span className="text-xs">دوباره</span>
          </button>
          <button onClick={send} className="flex flex-col items-center gap-1 text-white">
            <span className="w-16 h-16 rounded-full bg-fuchsia-600 flex items-center justify-center"><Send size={26} /></span>
            <span className="text-xs">ارسال</span>
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 flex flex-col">
      <div className="flex-1 relative flex items-center justify-center overflow-hidden">
        <video ref={videoRef} playsInline muted className={`w-72 h-72 object-cover rounded-2xl ${facing === "user" ? "-scale-x-100" : ""}`}
          style={{ filter: filter.css === "none" ? undefined : filter.css }} />
        {!recording && (
          <button onClick={() => setFacing((f) => f === "user" ? "environment" : "user")}
            className="absolute top-3 left-3 p-2 rounded-xl bg-white/10 text-white/80"><SwitchCamera size={18} /></button>
        )}
        {recording && (
          <div className="absolute top-3 right-3 flex items-center gap-1.5 bg-black/50 px-2.5 py-1 rounded-full">
            <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse" />
            <span className="text-white text-xs font-mono">{secs}s / 6s</span>
          </div>
        )}
      </div>
      <div className="px-4 pb-safe pt-2 space-y-3 bg-[#0c0c0c] border-t border-white/8">
        <div className="flex gap-2 overflow-x-auto pb-1">
          {FILTERS.map((f) => (
            <button key={f.id} onClick={() => setFilter(f)}
              className={`shrink-0 px-3 py-1.5 rounded-full text-xs border ${filter.id === f.id ? "bg-fuchsia-600/20 border-fuchsia-400/50 text-white" : "bg-white/5 border-white/10 text-white/70"}`}>
              {f.label}
            </button>
          ))}
        </div>
        <div className="flex items-center justify-center py-1">
          {!recording ? (
            <button onClick={record} className="w-16 h-16 rounded-full bg-red-600 ring-4 ring-red-500/30 flex items-center justify-center" title="شروعِ ضبط">
              <Circle size={24} className="text-white fill-current" />
            </button>
          ) : (
            <button onClick={stopRec} className="w-16 h-16 rounded-full bg-white ring-4 ring-white/30 flex items-center justify-center" title="توقف">
              <Square size={22} className="text-red-600 fill-current" />
            </button>
          )}
        </div>
        <p className="text-center text-white/40 text-[11px]">حداکثر ۶ ثانیه — فیلتر روی ویدیو اعمال می‌شود</p>
      </div>
    </div>
  );
}


// ── ایموجی‌ساز (ادغام): ترکیبِ دو ایموجی در یک استیکرِ واحد — الهام از Emoji Kitchen ─────
const FUSION_EMOJIS = [
  "\ud83d\ude00","\ud83d\ude02","\ud83e\udd79","\ud83d\ude0d","\ud83e\udd70","\ud83d\ude0e","\ud83e\udd29","\ud83d\ude2d","\ud83d\ude31","\ud83e\udd14","\ud83d\ude34","\ud83e\udd2f","\ud83e\udd73","\ud83d\ude07","\ud83e\udd20","\ud83e\udd76",
  "\ud83d\udd25","\u2764\ufe0f","\ud83d\udca5","\u2b50","\ud83c\udf1f","\u2728","\ud83d\udcab","\ud83c\udf08","\u2600\ufe0f","\ud83c\udf19","\ud83e\ude90","\u26a1","\u2744\ufe0f","\ud83d\udca7","\ud83c\udf40","\ud83c\udf38",
  "\ud83e\uddb7","\ud83d\udc41\ufe0f","\ud83e\udde0","\ud83d\udc51","\ud83c\udfa9","\ud83d\udd76\ufe0f","\ud83d\udc8e","\ud83c\udf88","\ud83c\udf89","\ud83c\udf55","\ud83c\udf54","\ud83c\udf69","\ud83c\udf66","\u2615","\ud83c\udf7a","\ud83c\udfb8",
  "\u26bd","\ud83c\udfc0","\ud83d\ude80","\u2708\ufe0f","\ud83d\ude97","\ud83d\udc36","\ud83d\udc31","\ud83e\udd8a","\ud83d\udc3c","\ud83e\udd81","\ud83d\udc38","\ud83d\udc22","\ud83e\udd84","\ud83d\udc1d","\ud83e\udd8b","\ud83d\udc19",
];

const FUSION_LAYOUTS: { id: string; label: string }[] = [
  { id: "overlay", label: "روی‌هم" },
  { id: "side",    label: "کنارِهم" },
  { id: "stack",   label: "بالا‌پایین" },
  { id: "badge",   label: "نشان" },
];

function FusionEditor({ onSend }: { onSend: (f: File, k: "image" | "video") => void }) {
  const [a, setA] = useState("\ud83e\uddb7");
  const [b, setB] = useState("\ud83e\ude90");
  const [slot, setSlot] = useState<"a" | "b">("a");
  const [layout, setLayout] = useState(FUSION_LAYOUTS[0].id);
  const [busy, setBusy] = useState(false);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  const render = useCallback((ctx: CanvasRenderingContext2D, size: number) => {
    ctx.clearRect(0, 0, size, size);
    const emojiFont = (px: number) =>
      `${px}px "Apple Color Emoji","Segoe UI Emoji","Noto Color Emoji",EmojiOne,sans-serif`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    const draw = (emo: string, cx: number, cy: number, px: number) => {
      ctx.save();
      ctx.font = emojiFont(px);
      ctx.fillText(emo, cx, cy);
      ctx.restore();
    };
    if (layout === "overlay") {
      draw(a, size / 2, size / 2, size * 0.72);
      draw(b, size * 0.68, size * 0.68, size * 0.42);
    } else if (layout === "side") {
      draw(a, size * 0.30, size / 2, size * 0.52);
      draw(b, size * 0.70, size / 2, size * 0.52);
    } else if (layout === "stack") {
      draw(a, size / 2, size * 0.32, size * 0.50);
      draw(b, size / 2, size * 0.70, size * 0.50);
    } else {
      draw(a, size / 2, size / 2, size * 0.78);
      ctx.save();
      ctx.beginPath();
      ctx.arc(size * 0.74, size * 0.26, size * 0.21, 0, Math.PI * 2);
      ctx.fillStyle = "rgba(255,255,255,0.92)";
      ctx.fill();
      ctx.restore();
      draw(b, size * 0.74, size * 0.26, size * 0.32);
    }
  }, [a, b, layout]);

  useEffect(() => {
    const c = canvasRef.current;
    if (!c) return;
    const ctx = c.getContext("2d");
    if (ctx) render(ctx, c.width);
  }, [render]);

  const build = async () => {
    setBusy(true);
    try {
      const size = 512;
      const canvas = document.createElement("canvas");
      canvas.width = size; canvas.height = size;
      const ctx = canvas.getContext("2d");
      if (!ctx) { setBusy(false); return; }
      render(ctx, size);
      canvas.toBlob((blob) => {
        setBusy(false);
        if (!blob) { toast.error("ساختِ ایموجی ناموفق بود"); return; }
        onSend(new File([blob], `emoji-fusion-${Date.now()}.png`, { type: "image/png" }), "image");
      }, "image/png");
    } catch {
      setBusy(false);
      toast.error("خطا در ساختِ ایموجی");
    }
  };

  const swap = () => { setA(b); setB(a); };

  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <div className="flex-1 flex flex-col items-center justify-center gap-4 p-4">
        <div className="rounded-3xl bg-white/5 border border-white/10 p-3">
          <canvas ref={canvasRef} width={256} height={256} className="w-56 h-56" />
        </div>
        <div className="flex items-center gap-3">
          <button onClick={() => setSlot("a")}
            className={`w-14 h-14 rounded-2xl text-3xl flex items-center justify-center border ${slot === "a" ? "border-fuchsia-400 bg-fuchsia-600/20" : "border-white/10 bg-white/5"}`}>{a}</button>
          <button onClick={swap} className="p-2 rounded-xl bg-white/10 text-white/70" title="جابه‌جایی"><RotateCcw size={18} /></button>
          <button onClick={() => setSlot("b")}
            className={`w-14 h-14 rounded-2xl text-3xl flex items-center justify-center border ${slot === "b" ? "border-fuchsia-400 bg-fuchsia-600/20" : "border-white/10 bg-white/5"}`}>{b}</button>
        </div>
        <p className="text-white/40 text-[11px]">ایموجیِ {slot === "a" ? "اول" : "دوم"} را از پایین انتخاب کن</p>
      </div>

      <div className="px-4 pb-safe pt-2 space-y-3 bg-[#0c0c0c] border-t border-white/8">
        <div className="flex gap-2 overflow-x-auto pb-1">
          {FUSION_LAYOUTS.map((l) => (
            <button key={l.id} onClick={() => setLayout(l.id)}
              className={`shrink-0 px-3 py-1.5 rounded-full text-xs border ${layout === l.id ? "bg-fuchsia-600/20 border-fuchsia-400/50 text-white" : "bg-white/5 border-white/10 text-white/70"}`}>
              {l.label}
            </button>
          ))}
        </div>
        <div className="grid grid-cols-8 gap-1 max-h-32 overflow-y-auto">
          {FUSION_EMOJIS.map((emo, i) => (
            <button key={`${emo}-${i}`}
              onClick={() => (slot === "a" ? setA(emo) : setB(emo))}
              className="h-9 rounded-lg text-xl hover:bg-white/10 flex items-center justify-center">{emo}</button>
          ))}
        </div>
        <button onClick={build} disabled={busy}
          className="w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl bg-fuchsia-600 hover:bg-fuchsia-500 text-white text-sm disabled:opacity-50">
          {busy ? <Loader2 size={16} className="animate-spin" /> : <><Send size={16} /> ارسالِ ایموجیِ ترکیبی</>}
        </button>
      </div>
    </div>
  );
}
