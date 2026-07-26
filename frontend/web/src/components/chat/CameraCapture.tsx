"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { X, Camera, SwitchCamera, Loader2, Check, RotateCcw, Zap, ZapOff, Grid3x3, Timer, Video, Square, Circle } from "lucide-react";
import toast from "react-hot-toast";

interface Props {
  onClose: () => void;
  onCapture: (file: File, kind: "image" | "video") => void;
  // عنوانِ فایلِ خروجی
  namePrefix?: string;
}

type Facing = "environment" | "user";
type Mode = "photo" | "video";

const TIMERS = [0, 3, 10] as const;

// دوربینِ زندهٔ داخلِ اپ: عکس/ویدیو، فلاش، زوم، تایمر، گرید، تعویضِ جلو/عقب.
export default function CameraCapture({ onClose, onCapture, namePrefix = "photo" }: Props) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const trackRef = useRef<MediaStreamTrack | null>(null);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const recTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const countdownRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const [facing, setFacing] = useState<Facing>("environment");
  const [mode, setMode] = useState<Mode>("photo");
  const [starting, setStarting] = useState(true);
  const [shot, setShot] = useState<string | null>(null); // dataURL/objectURL پیش‌نمایش
  const [shotKind, setShotKind] = useState<"image" | "video">("image");
  const shotBlobRef = useRef<Blob | null>(null);

  // قابلیت‌های سخت‌افزاری
  const [torchOn, setTorchOn] = useState(false);
  const [torchAvail, setTorchAvail] = useState(false);
  const [zoomCaps, setZoomCaps] = useState<{ min: number; max: number; step: number } | null>(null);
  const [zoom, setZoom] = useState(1);

  // تنظیماتِ کاربر
  const [grid, setGrid] = useState(false);
  const [timerSec, setTimerSec] = useState<0 | 3 | 10>(0);
  const [countdown, setCountdown] = useState(0);
  const [recording, setRecording] = useState(false);
  const [recSec, setRecSec] = useState(0);

  const stop = useCallback(() => {
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
    trackRef.current = null;
  }, []);

  const start = useCallback(async (m: Facing, wantAudio: boolean) => {
    stop();
    setStarting(true);
    setTorchOn(false);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: m, width: { ideal: 1920 }, height: { ideal: 1080 } },
        audio: wantAudio,
      });
      streamRef.current = stream;
      const track = stream.getVideoTracks()[0] || null;
      trackRef.current = track;
      // بررسیِ قابلیت‌ها (فلاش/زوم) — روی همهٔ دستگاه‌ها موجود نیست
      try {
        const caps = (track?.getCapabilities?.() || {}) as MediaTrackCapabilities & { torch?: boolean; zoom?: { min: number; max: number; step: number } };
        setTorchAvail(!!caps.torch);
        if (caps.zoom && caps.zoom.max > caps.zoom.min) {
          setZoomCaps({ min: caps.zoom.min, max: caps.zoom.max, step: caps.zoom.step || 0.1 });
          setZoom(caps.zoom.min <= 1 ? 1 : caps.zoom.min);
        } else {
          setZoomCaps(null);
        }
      } catch {
        setTorchAvail(false);
        setZoomCaps(null);
      }
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        await videoRef.current.play().catch(() => {});
      }
    } catch {
      toast.error("دسترسی به دوربین ممکن نشد");
      onClose();
    } finally {
      setStarting(false);
    }
  }, [stop, onClose]);

  useEffect(() => {
    start(facing, mode === "video");
    return () => stop();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [facing, mode]);

  useEffect(() => () => {
    if (recTimerRef.current) clearInterval(recTimerRef.current);
    if (countdownRef.current) clearInterval(countdownRef.current);
  }, []);

  const flip = () => { if (!recording) setFacing((f) => (f === "environment" ? "user" : "environment")); };

  const applyZoom = (z: number) => {
    setZoom(z);
    const track = trackRef.current;
    if (!track) return;
    try { track.applyConstraints({ advanced: [{ zoom: z } as MediaTrackConstraintSet] }); } catch { /* noop */ }
  };

  const toggleTorch = async () => {
    const track = trackRef.current;
    if (!track || !torchAvail) return;
    const next = !torchOn;
    try {
      await track.applyConstraints({ advanced: [{ torch: next } as MediaTrackConstraintSet] });
      setTorchOn(next);
    } catch { toast.error("فلاش پشتیبانی نمی‌شود"); }
  };

  const doCapturePhoto = () => {
    const v = videoRef.current;
    if (!v || !v.videoWidth) return;
    const canvas = document.createElement("canvas");
    canvas.width = v.videoWidth;
    canvas.height = v.videoHeight;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    if (facing === "user") { ctx.translate(canvas.width, 0); ctx.scale(-1, 1); } // آینه‌ایِ دوربینِ جلو
    ctx.drawImage(v, 0, 0, canvas.width, canvas.height);
    canvas.toBlob((blob) => {
      if (!blob) return;
      shotBlobRef.current = blob;
      setShotKind("image");
      setShot(URL.createObjectURL(blob));
      stop();
    }, "image/jpeg", 0.92);
  };

  const capturePhoto = () => {
    if (timerSec === 0) { doCapturePhoto(); return; }
    setCountdown(timerSec);
    countdownRef.current = setInterval(() => {
      setCountdown((c) => {
        if (c <= 1) {
          if (countdownRef.current) clearInterval(countdownRef.current);
          doCapturePhoto();
          return 0;
        }
        return c - 1;
      });
    }, 1000);
  };

  const pickRecMime = () => {
    const cands = ["video/webm;codecs=vp9,opus", "video/webm;codecs=vp8,opus", "video/webm", "video/mp4"];
    for (const c of cands) { if (typeof MediaRecorder !== "undefined" && MediaRecorder.isTypeSupported(c)) return c; }
    return "";
  };

  const startRecording = () => {
    const stream = streamRef.current;
    if (!stream) return;
    chunksRef.current = [];
    const mime = pickRecMime();
    let rec: MediaRecorder;
    try { rec = new MediaRecorder(stream, mime ? { mimeType: mime } : undefined); }
    catch { toast.error("ضبطِ ویدیو پشتیبانی نمی‌شود"); return; }
    recorderRef.current = rec;
    rec.ondataavailable = (e) => { if (e.data && e.data.size) chunksRef.current.push(e.data); };
    rec.onstop = () => {
      const blob = new Blob(chunksRef.current, { type: mime || "video/webm" });
      shotBlobRef.current = blob;
      setShotKind("video");
      setShot(URL.createObjectURL(blob));
      stop();
    };
    rec.start();
    setRecording(true);
    setRecSec(0);
    recTimerRef.current = setInterval(() => {
      setRecSec((s) => {
        if (s >= 59) { stopRecording(); return 60; } // سقفِ ۶۰ ثانیه
        return s + 1;
      });
    }, 1000);
  };

  const stopRecording = () => {
    if (recTimerRef.current) { clearInterval(recTimerRef.current); recTimerRef.current = null; }
    setRecording(false);
    try { recorderRef.current?.stop(); } catch { /* noop */ }
    recorderRef.current = null;
  };

  const shutter = () => {
    if (mode === "photo") capturePhoto();
    else if (recording) stopRecording();
    else startRecording();
  };

  const retake = () => {
    if (shot) URL.revokeObjectURL(shot);
    setShot(null);
    shotBlobRef.current = null;
    start(facing, mode === "video");
  };

  const confirm = () => {
    const blob = shotBlobRef.current;
    if (!blob) return;
    if (shotKind === "video") {
      const ext = (blob.type.includes("mp4")) ? "mp4" : "webm";
      onCapture(new File([blob], `clip-${Date.now()}.${ext}`, { type: blob.type || "video/webm" }), "video");
    } else {
      onCapture(new File([blob], `${namePrefix}-${Date.now()}.jpg`, { type: "image/jpeg" }), "image");
    }
  };

  const fmt = (s: number) => `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
  const cycleTimer = () => setTimerSec((t) => TIMERS[(TIMERS.indexOf(t) + 1) % TIMERS.length]);

  return (
    <div className="fixed inset-0 z-[70] bg-black flex flex-col">
      {/* header */}
      <div className="flex items-center justify-between px-4 py-3 safe-top">
        <button onClick={onClose} className="p-2 rounded-xl bg-white/10 text-white/80"><X size={20} /></button>
        <span className="text-white/70 text-sm">{shot ? "پیش‌نمایش" : (mode === "video" ? "ویدیو" : "دوربین")}</span>
        {!shot ? (
          <button onClick={flip} disabled={recording} className="p-2 rounded-xl bg-white/10 text-white/80 disabled:opacity-40" title="تعویضِ دوربین">
            <SwitchCamera size={20} />
          </button>
        ) : <span className="w-9" />}
      </div>

      {/* toolbar بالای پیش‌نمایشِ زنده */}
      {!shot && (
        <div className="flex items-center justify-center gap-2 px-4 pb-1">
          {torchAvail && (
            <button onClick={toggleTorch} className={`px-3 py-1.5 rounded-full text-xs flex items-center gap-1 ${torchOn ? "bg-yellow-400 text-black" : "bg-white/10 text-white/80"}`}>
              {torchOn ? <Zap size={14} /> : <ZapOff size={14} />} فلاش
            </button>
          )}
          <button onClick={() => setGrid((g) => !g)} className={`px-3 py-1.5 rounded-full text-xs flex items-center gap-1 ${grid ? "bg-white text-black" : "bg-white/10 text-white/80"}`}>
            <Grid3x3 size={14} /> گرید
          </button>
          {mode === "photo" && (
            <button onClick={cycleTimer} className={`px-3 py-1.5 rounded-full text-xs flex items-center gap-1 ${timerSec ? "bg-white text-black" : "bg-white/10 text-white/80"}`}>
              <Timer size={14} /> {timerSec ? `${timerSec}s` : "تایمر"}
            </button>
          )}
        </div>
      )}

      {/* preview / live */}
      <div className="flex-1 relative flex items-center justify-center overflow-hidden">
        {shot ? (
          shotKind === "video" ? (
            <video src={shot} controls playsInline loop autoPlay className="max-h-full max-w-full object-contain" />
          ) : (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={shot} alt="" className="max-h-full max-w-full object-contain" />
          )
        ) : (
          <>
            <video
              ref={videoRef}
              playsInline muted
              className={`max-h-full max-w-full object-contain ${facing === "user" ? "-scale-x-100" : ""}`}
            />
            {/* گریدِ قانونِ سه‌گانه */}
            {grid && !starting && (
              <div className="absolute inset-0 pointer-events-none">
                <div className="absolute top-1/3 left-0 right-0 h-px bg-white/25" />
                <div className="absolute top-2/3 left-0 right-0 h-px bg-white/25" />
                <div className="absolute left-1/3 top-0 bottom-0 w-px bg-white/25" />
                <div className="absolute left-2/3 top-0 bottom-0 w-px bg-white/25" />
              </div>
            )}
            {/* شمارشِ معکوسِ تایمر */}
            {countdown > 0 && (
              <div className="absolute inset-0 flex items-center justify-center">
                <span className="text-white text-7xl font-bold drop-shadow-lg">{countdown}</span>
              </div>
            )}
            {/* نشانگرِ ضبط */}
            {recording && (
              <div className="absolute top-3 left-1/2 -translate-x-1/2 flex items-center gap-1.5 bg-black/50 px-3 py-1 rounded-full">
                <span className="w-2.5 h-2.5 rounded-full bg-red-500 animate-pulse" />
                <span className="text-white text-sm tabular-nums">{fmt(recSec)}</span>
              </div>
            )}
            {starting && (
              <div className="absolute inset-0 flex items-center justify-center">
                <Loader2 size={32} className="text-white/70 animate-spin" />
              </div>
            )}
          </>
        )}
      </div>

      {/* زوم */}
      {!shot && zoomCaps && !starting && (
        <div className="px-8 pb-1 flex items-center gap-3">
          <span className="text-white/60 text-xs">زوم</span>
          <input
            type="range" min={zoomCaps.min} max={zoomCaps.max} step={zoomCaps.step} value={zoom}
            onChange={(e) => applyZoom(parseFloat(e.target.value))}
            className="flex-1 accent-white"
          />
          <span className="text-white/60 text-xs w-8 tabular-nums">{zoom.toFixed(1)}x</span>
        </div>
      )}

      {/* controls */}
      <div className="px-6 py-5 pb-safe flex items-center justify-center gap-10">
        {shot ? (
          <>
            <button onClick={retake} className="flex flex-col items-center gap-1 text-white/80">
              <span className="w-14 h-14 rounded-full bg-white/10 flex items-center justify-center"><RotateCcw size={22} /></span>
              <span className="text-xs">دوباره</span>
            </button>
            <button onClick={confirm} className="flex flex-col items-center gap-1 text-white">
              <span className="w-16 h-16 rounded-full bg-indigo-600 flex items-center justify-center"><Check size={28} /></span>
              <span className="text-xs">ارسال</span>
            </button>
          </>
        ) : (
          <div className="flex items-center gap-8">
            {/* سوییچِ عکس/ویدیو (چپ) */}
            {!recording ? (
              <button onClick={() => setMode(mode === "photo" ? "video" : "photo")} className="flex flex-col items-center gap-0.5 text-white/70 w-14">
                {mode === "photo" ? <Video size={22} /> : <Camera size={22} />}
                <span className="text-[10px]">{mode === "photo" ? "ویدیو" : "عکس"}</span>
              </button>
            ) : <span className="w-14" />}

            {/* شاتر */}
            <button onClick={shutter} disabled={starting} className="disabled:opacity-40" title={mode === "video" ? "ضبط" : "گرفتنِ عکس"}>
              {mode === "video" ? (
                recording ? (
                  <span className="w-16 h-16 rounded-full bg-white flex items-center justify-center ring-4 ring-red-500/40">
                    <Square size={26} className="text-red-600 fill-red-600" />
                  </span>
                ) : (
                  <span className="w-16 h-16 rounded-full bg-white flex items-center justify-center ring-4 ring-white/30">
                    <Circle size={26} className="text-red-600 fill-red-600" />
                  </span>
                )
              ) : (
                <span className="w-16 h-16 rounded-full bg-white flex items-center justify-center ring-4 ring-white/30">
                  <Camera size={26} className="text-black" />
                </span>
              )}
            </button>

            <span className="w-14" />
          </div>
        )}
      </div>
    </div>
  );
}
