"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Phone, PhoneOff, Video, VideoOff, Mic, MicOff, User as UserIcon, Languages } from "lucide-react";
import { callsApi, messagesApi } from "@/lib/api";
import { useAuthStore } from "@/store/auth";
import { useCallStore, type CallMedia } from "@/store/call";
import { toPersianNum } from "@/lib/utils";
import toast from "react-hot-toast";

// نگاشتِ کدِ زبان (همان کلیدِ ترجمهٔ چت) به locale برای Web Speech API
const MY_LANG_KEY = "dilix_tr_lang";
const STT_LOCALE: Record<string, string> = {
  fa: "fa-IR", en: "en-US", ar: "ar-SA", tr: "tr-TR", ru: "ru-RU",
  "zh-CN": "zh-CN", fr: "fr-FR", de: "de-DE", es: "es-ES", hi: "hi-IN", ur: "ur-PK", ku: "ckb",
};
function myLang(): string {
  try { return localStorage.getItem(MY_LANG_KEY) || "fa"; } catch { return "fa"; }
}

type Phase = "idle" | "outgoing" | "incoming" | "connecting" | "active";

interface Signal {
  type: string;
  call_id?: string;
  from?: string;
  from_name?: string;
  from_avatar?: string | null;
  media?: string;
  sdp?: string;
  text?: string;
  lang?: string;
}

const FALLBACK_ICE = [
  { urls: "stun:stun.l.google.com:19302" },
  { urls: "stun:stun1.l.google.com:19302" },
];

// ── تنظیماتِ کیفیت برای اینترنتِ ضعیف (بین‌المللی) ─────────────
const VIDEO_CAPTURE: MediaTrackConstraints = {
  facingMode: "user",
  width: { ideal: 640, max: 1280 },
  height: { ideal: 360, max: 720 },
  frameRate: { ideal: 24, max: 30 },
};
const AUDIO_CAPTURE: MediaTrackConstraints = {
  echoCancellation: true,
  noiseSuppression: true,
  autoGainControl: true,
};
const MAX_VIDEO_BITRATE = 600000; // ~۶۰۰kbps سقف؛ WebRTC خودش پایین‌تر می‌آید

// سقفِ بیت‌ریت/فریمِ ویدیو + ترجیحِ حفظِ فریم (کاهشِ رزولوشن پیش از فریم → حسِ روان‌تر)
function tuneSenders(pc: RTCPeerConnection): void {
  pc.getSenders().forEach((sender) => {
    if (sender.track?.kind !== "video") return;
    try {
      const p = sender.getParameters();
      if (!p.encodings || p.encodings.length === 0) p.encodings = [{}];
      p.encodings[0].maxBitrate = MAX_VIDEO_BITRATE;
      p.encodings[0].maxFramerate = 24;
      (p as RTCRtpSendParameters & { degradationPreference?: string }).degradationPreference = "maintain-framerate";
      sender.setParameters(p).catch(() => { /* noop */ });
    } catch { /* noop */ }
  });
}

// Opus: FEC + DTX + سقفِ بیت‌ریت → صدای شفاف حتی با پرت‌لاسِ بالا
function tuneSdp(sdp: string): string {
  const lines = sdp.split(/\r\n|\n/);
  const opusPts = new Set<string>();
  for (const l of lines) {
    const m = l.match(/^a=rtpmap:(\d+)\s+opus\/48000/i);
    if (m) opusPts.add(m[1]);
  }
  if (opusPts.size === 0) return sdp;
  const extra = "useinbandfec=1;usedtx=1;maxaveragebitrate=24000;stereo=0";
  const seen = new Set<string>();
  const merge = (params: string): string => {
    let out = params;
    for (const kv of extra.split(";")) {
      const key = kv.split("=")[0];
      if (!new RegExp("(^|;)" + key + "=").test(out)) out += ";" + kv;
    }
    return out;
  };
  const pass1: string[] = [];
  for (const l of lines) {
    const fm = l.match(/^a=fmtp:(\d+)\s+(.*)$/);
    if (fm && opusPts.has(fm[1])) {
      seen.add(fm[1]);
      pass1.push("a=fmtp:" + fm[1] + " " + merge(fm[2]));
    } else {
      pass1.push(l);
    }
  }
  if (seen.size >= opusPts.size) return pass1.join("\r\n");
  const res: string[] = [];
  for (const l of pass1) {
    res.push(l);
    const rm = l.match(/^a=rtpmap:(\d+)\s+opus\/48000/i);
    if (rm && !seen.has(rm[1])) {
      res.push("a=fmtp:" + rm[1] + " " + extra);
      seen.add(rm[1]);
    }
  }
  return res.join("\r\n");
}
const RING_TIMEOUT_MS = 35_000;

// آهنگِ pollِ fallback — همان ۱.۵ثانیهٔ قبل. فقط تا وقتی WebSocket باز نشده فعال است.
const POLL_MS = 1_500;
// pingِ کلاینت: پروکسی/CDN اتصالِ بی‌ترافیک را معمولاً بعدِ ۶۰ثانیه می‌بندد.
const PING_MS = 25_000;

function fmtDur(s: number): string {
  const m = Math.floor(s / 60);
  const ss = Math.floor(s % 60);
  return toPersianNum(`${m}:${ss.toString().padStart(2, "0")}`);
}

export default function CallManager() {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);
  const request = useCallStore((s) => s.request);
  const consume = useCallStore((s) => s.consume);

  const [phase, setPhase] = useState<Phase>("idle");
  const [peerName, setPeerName] = useState("");
  const [peerAvatar, setPeerAvatar] = useState<string | null>(null);
  const [media, setMedia] = useState<CallMedia>("audio");
  const [muted, setMuted] = useState(false);
  const [camOff, setCamOff] = useState(false);
  const [switching, setSwitching] = useState(false);
  const [dur, setDur] = useState(0);
  const [remoteStream, setRemoteStream] = useState<MediaStream | null>(null);
  const [localStream, setLocalStream] = useState<MediaStream | null>(null);
  const [liveTr, setLiveTr] = useState(false);
  const [peerCaption, setPeerCaption] = useState("");
  const [myCaption, setMyCaption] = useState("");

  // refs (mutable call context — used inside async/poll callbacks)
  const phaseRef = useRef<Phase>("idle");
  const pcRef = useRef<RTCPeerConnection | null>(null);
  const localRef = useRef<MediaStream | null>(null);
  const callIdRef = useRef<string>("");
  const peerRef = useRef<string>("");
  const isCallerRef = useRef(false);
  const mediaRef = useRef<CallMedia>("audio");
  const offerRef = useRef<string>("");
  const ringTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const durTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const startTsRef = useRef<number>(0);
  const iceRef = useRef<RTCIceServer[] | null>(null);
  const pollBusyRef = useRef(false);
  const switchingRef = useRef(false);
  // trickle ICE — تحویلِ زندهٔ کاندیدها (به‌ویژه relay/TURN که دیرتر آماده می‌شوند)
  const pendingLocalIceRef = useRef<RTCIceCandidateInit[]>([]);
  const pendingRemoteIceRef = useRef<RTCIceCandidateInit[]>([]);
  const remoteSetRef = useRef(false);
  // ترجمهٔ زندهٔ گفتار (Web Speech API — سمتِ کاربر، بدونِ نیازِ سرور)
  const recogRef = useRef<{ stop: () => void; start: () => void } | null>(null);
  const liveTrRef = useRef(false);
  const capTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const remoteVideoRef = useRef<HTMLVideoElement>(null);
  const remoteAudioRef = useRef<HTMLAudioElement>(null);
  const localVideoRef = useRef<HTMLVideoElement>(null);

  useEffect(() => { phaseRef.current = phase; }, [phase]);

  // attach media streams to elements
  useEffect(() => {
    if (remoteVideoRef.current && remoteStream) remoteVideoRef.current.srcObject = remoteStream;
    if (remoteAudioRef.current && remoteStream) remoteAudioRef.current.srcObject = remoteStream;
    if (localVideoRef.current && localStream) localVideoRef.current.srcObject = localStream;
  }, [remoteStream, localStream, phase]);

  const getIce = useCallback(async (): Promise<RTCIceServer[]> => {
    if (iceRef.current) return iceRef.current;
    try {
      const res = await callsApi.iceServers();
      iceRef.current = res.data?.iceServers ?? FALLBACK_ICE;
    } catch {
      iceRef.current = FALLBACK_ICE;
    }
    return iceRef.current ?? FALLBACK_ICE;
  }, []);

  // ── trickle ICE helpers ─────────────────────────────────
  const sendIce = useCallback((cand: RTCIceCandidateInit) => {
    if (!callIdRef.current || !peerRef.current) { pendingLocalIceRef.current.push(cand); return; }
    callsApi.signal({ callId: callIdRef.current, toEarthId: peerRef.current, type: "ice", sdp: JSON.stringify(cand) }).catch(() => { /* noop */ });
  }, []);
  const flushLocalIce = useCallback(() => {
    const q = pendingLocalIceRef.current; pendingLocalIceRef.current = [];
    for (const c of q) sendIce(c);
  }, [sendIce]);
  const flushRemoteIce = useCallback(async () => {
    const pc = pcRef.current; if (!pc) return;
    const q = pendingRemoteIceRef.current; pendingRemoteIceRef.current = [];
    for (const c of q) { try { await pc.addIceCandidate(c); } catch { /* noop */ } }
  }, []);

  const clearTimers = useCallback(() => {
    if (ringTimerRef.current) { clearTimeout(ringTimerRef.current); ringTimerRef.current = null; }
    if (durTimerRef.current) { clearInterval(durTimerRef.current); durTimerRef.current = null; }
  }, []);

  const cleanup = useCallback(() => {
    clearTimers();
    if (capTimerRef.current) { clearTimeout(capTimerRef.current); capTimerRef.current = null; }
    liveTrRef.current = false;
    try { recogRef.current?.stop(); } catch { /* noop */ }
    recogRef.current = null;
    try { window.speechSynthesis?.cancel(); } catch { /* noop */ }
    try { pcRef.current?.getSenders().forEach((s) => s.track?.stop()); } catch { /* noop */ }
    try { pcRef.current?.close(); } catch { /* noop */ }
    pcRef.current = null;
    localRef.current?.getTracks().forEach((t) => t.stop());
    localRef.current = null;
    offerRef.current = "";
    callIdRef.current = "";
    peerRef.current = "";
    pendingLocalIceRef.current = [];
    pendingRemoteIceRef.current = [];
    remoteSetRef.current = false;
    setRemoteStream(null);
    setLocalStream(null);
    setMuted(false);
    setCamOff(false);
    setDur(0);
    setLiveTr(false);
    setPeerCaption(""); setMyCaption("");
    setPhase("idle");
  }, [clearTimers]);

  const logCall = useCallback(async (status: string, duration: number) => {
    if (!isCallerRef.current || !peerRef.current) return;
    try { await callsApi.callLog(peerRef.current, mediaRef.current, status, duration); } catch { /* noop */ }
  }, []);

  const currentDuration = () =>
    startTsRef.current ? Math.round((Date.now() - startTsRef.current) / 1000) : 0;

  const startDurTimer = useCallback(() => {
    startTsRef.current = Date.now();
    setDur(0);
    if (durTimerRef.current) clearInterval(durTimerRef.current);
    durTimerRef.current = setInterval(() => setDur((d) => d + 1), 1000);
  }, []);

  // ── ترجمهٔ زندهٔ گفتار (زیرنویس) ─────────────────────────
  const stopRecognition = useCallback(() => {
    try { recogRef.current?.stop(); } catch { /* noop */ }
    recogRef.current = null;
  }, []);

  const startRecognition = useCallback((): boolean => {
    const W = window as unknown as { SpeechRecognition?: new () => unknown; webkitSpeechRecognition?: new () => unknown };
    const SR = W.SpeechRecognition || W.webkitSpeechRecognition;
    if (!SR) return false;
    const rec = new SR() as {
      lang: string; continuous: boolean; interimResults: boolean;
      onresult: (e: { resultIndex: number; results: ArrayLike<{ isFinal: boolean; 0: { transcript: string } }> }) => void;
      onend: () => void; onerror: (e: { error?: string }) => void; start: () => void; stop: () => void;
    };
    rec.lang = STT_LOCALE[myLang()] || "fa-IR";
    rec.continuous = true;
    rec.interimResults = false;
    rec.onresult = (e) => {
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const r = e.results[i];
        if (r.isFinal) {
          const text = (r[0]?.transcript || "").trim();
          if (text && peerRef.current) {
            setMyCaption(text);
            callsApi.signal({ callId: callIdRef.current, toEarthId: peerRef.current, type: "caption", text, lang: myLang() }).catch(() => { /* noop */ });
          }
        }
      }
    };
    rec.onend = () => {
      if (liveTrRef.current && phaseRef.current === "active") { try { rec.start(); } catch { /* noop */ } }
    };
    rec.onerror = (ev) => {
      const err = ev?.error || "";
      if (err === "not-allowed" || err === "service-not-allowed") {
        liveTrRef.current = false; setLiveTr(false);
        toast.error("مرورگر در حینِ تماس اجازهٔ تشخیصِ گفتار را نداد؛ ترجمهٔ زنده در این دستگاه ممکن نیست");
      }
    };
    try { rec.start(); recogRef.current = rec; return true; } catch { return false; }
  }, []);

  const toggleLiveTr = useCallback(() => {
    const next = !liveTrRef.current;
    if (next) {
      // حالتِ ترجمهٔ زنده را روشن می‌کنیم تا زیرنویسِ گفتارِ طرفِ مقابل ترجمه و نمایش داده شود؛
      // این مستقل از پشتیبانیِ مرورگر از تشخیصِ گفتار است. سپس تشخیصِ گفتارِ خودمان را
      // به‌صورتِ best-effort روشن می‌کنیم (اگر مرورگر پشتیبانی کند) تا طرفِ مقابل هم زیرنویسِ ما را ببیند.
      liveTrRef.current = true;
      setLiveTr(true);
      const ok = startRecognition();
      toast(ok
        ? "ترجمهٔ زندهٔ گفتار روشن شد"
        : "زیرنویسِ ترجمه روشن شد؛ گفتارِ طرفِ مقابل ترجمه می‌شود (این مرورگر تشخیصِ گفتارِ شما را پشتیبانی نمی‌کند)");
    } else {
      liveTrRef.current = false;
      setLiveTr(false);
      stopRecognition();
      try { window.speechSynthesis?.cancel(); } catch { /* noop */ }
      setPeerCaption(""); setMyCaption("");
    }
  }, [startRecognition, stopRecognition]);

  const waitIce = (pc: RTCPeerConnection) =>
    new Promise<void>((resolve) => {
      if (pc.iceGatheringState === "complete") return resolve();
      const check = () => {
        if (pc.iceGatheringState === "complete") {
          pc.removeEventListener("icegatheringstatechange", check);
          resolve();
        }
      };
      pc.addEventListener("icegatheringstatechange", check);
      setTimeout(resolve, 3000); // cap
    });

  const newPeerConnection = useCallback((ice: RTCIceServer[]): RTCPeerConnection => {
    const pc = new RTCPeerConnection({ iceServers: ice, iceCandidatePoolSize: 2, bundlePolicy: "max-bundle" });
    pc.ontrack = (e) => setRemoteStream(e.streams[0]);
    pc.onicecandidate = (e) => { if (e.candidate) sendIce(e.candidate.toJSON()); };
    pc.onconnectionstatechange = () => {
      const st = pc.connectionState;
      if (st === "connected") tuneSenders(pc);
      if (st === "failed" || st === "closed" || st === "disconnected") {
        if (phaseRef.current === "active" || phaseRef.current === "connecting") {
          const d = currentDuration();
          if (isCallerRef.current) logCall(d > 0 ? "answered" : "failed", d);
          if (st === "failed") toast.error("تماس قطع شد");
          cleanup();
        }
      }
    };
    return pc;
  }, [cleanup, logCall, sendIce]);

  const attachLocal = useCallback(async (pc: RTCPeerConnection, m: CallMedia) => {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: AUDIO_CAPTURE,
      video: m === "video" ? VIDEO_CAPTURE : false,
    });
    localRef.current = stream;
    setLocalStream(stream);
    stream.getTracks().forEach((t) => pc.addTrack(t, stream));
  }, []);

  // تعویضِ حالتِ تماس (صوتی↔تصویری) — افزودن/حذفِ ترکِ ویدیوی محلی و همگام‌سازیِ state
  const applyLocalMedia = useCallback(async (pc: RTCPeerConnection, target: CallMedia) => {
    if (target === "video") {
      const hasV = (localRef.current?.getVideoTracks().length ?? 0) > 0;
      if (!hasV) {
        const vs = await navigator.mediaDevices.getUserMedia({ video: VIDEO_CAPTURE });
        const vt = vs.getVideoTracks()[0];
        if (!localRef.current) localRef.current = new MediaStream();
        localRef.current.addTrack(vt);
        pc.addTrack(vt, localRef.current);
      }
    } else {
      pc.getSenders().filter((s) => s.track?.kind === "video").forEach((s) => {
        try { s.track?.stop(); pc.removeTrack(s); } catch { /* noop */ }
      });
      localRef.current?.getVideoTracks().forEach((t) => {
        try { t.stop(); localRef.current?.removeTrack(t); } catch { /* noop */ }
      });
    }
    mediaRef.current = target;
    setMedia(target);
    setCamOff(false);
    setLocalStream(localRef.current ? new MediaStream(localRef.current.getTracks()) : null);
  }, []);

  // ── Outgoing ────────────────────────────────────────────
  const startOutgoing = useCallback(async (earthId: string, name: string, m: CallMedia) => {
    if (phaseRef.current !== "idle") { toast("در حال حاضر یک تماس فعال دارید"); return; }
    isCallerRef.current = true;
    remoteSetRef.current = false; pendingLocalIceRef.current = []; pendingRemoteIceRef.current = [];
    peerRef.current = earthId.toUpperCase();
    mediaRef.current = m;
    setMedia(m); setPeerName(name); setPeerAvatar(null);
    setPhase("outgoing");
    try {
      const ice = await getIce();
      const pc = newPeerConnection(ice);
      pcRef.current = pc;
      await attachLocal(pc, m);
      const offer = await pc.createOffer();
      offer.sdp = tuneSdp(offer.sdp!);
      await pc.setLocalDescription(offer);
      await waitIce(pc);
      const desc = JSON.stringify({ type: pc.localDescription!.type, sdp: pc.localDescription!.sdp });
      const res = await callsApi.invite(peerRef.current, m, desc);
      if (res.data?.status === "offline") {
        toast("مخاطب در دسترس نیست");
        await logCall("no_answer", 0);
        cleanup();
        return;
      }
      callIdRef.current = res.data.call_id;
      flushLocalIce();
      ringTimerRef.current = setTimeout(async () => {
        if (peerRef.current) {
          try { await callsApi.signal({ callId: callIdRef.current, toEarthId: peerRef.current, type: "cancel" }); } catch { /* noop */ }
        }
        toast("پاسخی داده نشد");
        await logCall("no_answer", 0);
        cleanup();
      }, RING_TIMEOUT_MS);
    } catch (e) {
      const err = e as { name?: string };
      toast.error(err?.name === "NotAllowedError" ? "دسترسی به میکروفون/دوربین رد شد" : "برقراری تماس ناموفق بود");
      cleanup();
    }
  }, [attachLocal, cleanup, getIce, logCall, newPeerConnection, flushLocalIce]);

  // trigger from store
  useEffect(() => {
    if (request) {
      startOutgoing(request.earthId, request.name, request.media);
      consume();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [request]);

  // ── Incoming accept / decline ───────────────────────────
  const acceptIncoming = useCallback(async () => {
    setPhase("connecting");
    remoteSetRef.current = false; pendingRemoteIceRef.current = [];
    try {
      const ice = await getIce();
      const pc = newPeerConnection(ice);
      pcRef.current = pc;
      await attachLocal(pc, mediaRef.current);
      await pc.setRemoteDescription(JSON.parse(offerRef.current));
      remoteSetRef.current = true; await flushRemoteIce();
      const answer = await pc.createAnswer();
      answer.sdp = tuneSdp(answer.sdp!);
      await pc.setLocalDescription(answer);
      await waitIce(pc);
      const desc = JSON.stringify({ type: pc.localDescription!.type, sdp: pc.localDescription!.sdp });
      await callsApi.signal({ callId: callIdRef.current, toEarthId: peerRef.current, type: "answer", sdp: desc });
      setPhase("active");
      startDurTimer();
    } catch (e) {
      const err = e as { name?: string };
      toast.error(err?.name === "NotAllowedError" ? "دسترسی به میکروفون/دوربین رد شد" : "اتصال ناموفق بود");
      try { await callsApi.signal({ callId: callIdRef.current, toEarthId: peerRef.current, type: "reject" }); } catch { /* noop */ }
      cleanup();
    }
  }, [attachLocal, cleanup, getIce, newPeerConnection, startDurTimer, flushRemoteIce]);

  const declineIncoming = useCallback(async () => {
    try { await callsApi.signal({ callId: callIdRef.current, toEarthId: peerRef.current, type: "reject" }); } catch { /* noop */ }
    cleanup();
  }, [cleanup]);

  // ── Hang up (context-aware) ─────────────────────────────
  const hangup = useCallback(async () => {
    const p = phaseRef.current;
    if (p === "incoming") { declineIncoming(); return; }
    if (p === "outgoing") {
      try { await callsApi.signal({ callId: callIdRef.current, toEarthId: peerRef.current, type: "cancel" }); } catch { /* noop */ }
      await logCall("no_answer", 0);
      cleanup();
      return;
    }
    if (p === "active" || p === "connecting") {
      const d = currentDuration();
      try { await callsApi.signal({ callId: callIdRef.current, toEarthId: peerRef.current, type: "end" }); } catch { /* noop */ }
      await logCall(d > 0 ? "answered" : "no_answer", d);
      cleanup();
    }
  }, [cleanup, declineIncoming, logCall]);

  // ── Signal handling ─────────────────────────────────────
  const handleSignal = useCallback(async (s: Signal) => {
    const p = phaseRef.current;
    switch (s.type) {
      case "incoming": {
        if (p !== "idle") {
          try { await callsApi.signal({ callId: s.call_id!, toEarthId: s.from!, type: "busy" }); } catch { /* noop */ }
          return;
        }
        isCallerRef.current = false;
        peerRef.current = (s.from || "").toUpperCase();
        callIdRef.current = s.call_id || "";
        offerRef.current = s.sdp || "";
        mediaRef.current = s.media === "video" ? "video" : "audio";
        setMedia(mediaRef.current);
        setPeerName(s.from_name || s.from || "تماس");
        setPeerAvatar(s.from_avatar || null);
        setPhase("incoming");
        ringTimerRef.current = setTimeout(() => {
          if (phaseRef.current === "incoming") cleanup(); // missed (caller logs)
        }, RING_TIMEOUT_MS + 5000);
        break;
      }
      case "answer": {
        if (isCallerRef.current && p === "outgoing" && s.call_id === callIdRef.current && pcRef.current) {
          if (ringTimerRef.current) { clearTimeout(ringTimerRef.current); ringTimerRef.current = null; }
          try {
            await pcRef.current.setRemoteDescription(JSON.parse(s.sdp || "{}"));
            remoteSetRef.current = true; await flushRemoteIce();
            setPhase("active");
            startDurTimer();
          } catch { toast.error("اتصال ناموفق بود"); await logCall("failed", 0); cleanup(); }
        }
        break;
      }
      case "reject": {
        if (isCallerRef.current && p === "outgoing" && s.call_id === callIdRef.current) {
          toast("تماس رد شد");
          await logCall("rejected", 0);
          cleanup();
        }
        break;
      }
      case "busy": {
        if (isCallerRef.current && p === "outgoing" && s.call_id === callIdRef.current) {
          toast("مخاطب مشغول است");
          await logCall("no_answer", 0);
          cleanup();
        }
        break;
      }
      case "cancel": {
        if (!isCallerRef.current && p === "incoming" && s.call_id === callIdRef.current) {
          cleanup(); // caller canceled → missed (caller logs)
        }
        break;
      }
      case "end": {
        if ((p === "active" || p === "connecting") && s.call_id === callIdRef.current) {
          const d = currentDuration();
          if (isCallerRef.current) await logCall(d > 0 ? "answered" : "no_answer", d);
          cleanup();
        }
        break;
      }
      case "reoffer": {
        if ((p === "active" || p === "connecting") && s.call_id === callIdRef.current && pcRef.current) {
          const pc = pcRef.current;
          try {
            const parsed = JSON.parse(s.sdp || "{}");
            const target: CallMedia = parsed.media === "video" ? "video" : "audio";
            await pc.setRemoteDescription(parsed);
            remoteSetRef.current = true; await flushRemoteIce();
            if (target !== mediaRef.current) { try { await applyLocalMedia(pc, target); } catch { /* noop */ } }
            const answer = await pc.createAnswer();
            answer.sdp = tuneSdp(answer.sdp!);
            await pc.setLocalDescription(answer);
            await waitIce(pc);
            const desc = JSON.stringify({ type: pc.localDescription!.type, sdp: pc.localDescription!.sdp, media: mediaRef.current });
            await callsApi.signal({ callId: callIdRef.current, toEarthId: peerRef.current, type: "reanswer", sdp: desc });
            if (target === "video") toast("تماس به تصویری تغییر کرد");
          } catch { /* noop */ }
        }
        break;
      }
      case "reanswer": {
        if ((p === "active" || p === "connecting") && s.call_id === callIdRef.current && pcRef.current) {
          try { await pcRef.current.setRemoteDescription(JSON.parse(s.sdp || "{}")); remoteSetRef.current = true; await flushRemoteIce(); } catch { /* noop */ }
        }
        break;
      }
      case "ice": {
        if (s.call_id !== callIdRef.current || !s.sdp) break;
        try {
          const cand = JSON.parse(s.sdp) as RTCIceCandidateInit;
          if (pcRef.current && remoteSetRef.current) { await pcRef.current.addIceCandidate(cand); }
          else { pendingRemoteIceRef.current.push(cand); }
        } catch { /* noop */ }
        break;
      }
      case "caption": {
        if ((p === "active" || p === "connecting") && s.call_id === callIdRef.current && s.text) {
          const target = myLang();
          try {
            const res = await messagesApi.translateText(s.text, target);
            const tr = (res.data?.translated_text as string) || s.text;
            setPeerCaption(tr);
            if (capTimerRef.current) clearTimeout(capTimerRef.current);
            capTimerRef.current = setTimeout(() => setPeerCaption(""), 8000);
          } catch { /* noop */ }
        }
        break;
      }
    }
  }, [cleanup, logCall, startDurTimer, applyLocalMedia, flushRemoteIce]);

  // ── تحویلِ سیگنال: WebSocket با fallbackِ خودکار به poll ────
  //
  // چرا هر دو مسیر می‌مانند: در حالتِ poll هر کاربرِ لاگین‌کرده — حتی بی‌کار —
  // هر ۱.۵ ثانیه یک درخواست می‌زند و ~۹۹٪ پاسخ‌ها خالی است؛ این تنها محرکِ
  // ظرفیتِ سرویس بود. با WebSocket کاربرِ بی‌کار عملاً صفر درخواست می‌زند.
  // ولی «تماسِ ازدست‌رفته» خرابیِ شدیدی است، پس اگر WS به هر دلیلی برقرار نشود
  // (پروکسی، شبکهٔ سخت‌گیر، فیلترِ میانی) poll خودکار برمی‌گردد و تماس کار می‌کند.
  // منبعِ حقیقت در هر دو مسیر همان صفِ سمتِ سرور است و درِین اتمی است، پس
  // هم‌پوشانیِ لحظه‌ایِ دو مسیر باعثِ تحویلِ تکراری نمی‌شود.
  const handleSignalRef = useRef(handleSignal);
  useEffect(() => { handleSignalRef.current = handleSignal; }, [handleSignal]);

  useEffect(() => {
    if (!isAuthenticated) return;

    let stopped = false;
    let ws: WebSocket | null = null;
    let pollTimer: ReturnType<typeof setInterval> | null = null;
    let pingTimer: ReturnType<typeof setInterval> | null = null;
    let retryTimer: ReturnType<typeof setTimeout> | null = null;
    let attempt = 0;

    const drain = async () => {
      if (pollBusyRef.current) return;
      pollBusyRef.current = true;
      try {
        const res = await callsApi.poll();
        const signals: Signal[] = res.data?.signals ?? [];
        for (const s of signals) await handleSignalRef.current(s);
      } catch { /* noop */ } finally { pollBusyRef.current = false; }
    };

    const startPoll = () => {
      if (pollTimer || stopped) return;
      drain();
      pollTimer = setInterval(drain, POLL_MS);
    };
    const stopPoll = () => {
      if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
    };

    const scheduleRetry = () => {
      if (stopped || retryTimer) return;
      attempt += 1;
      // عقب‌نشینیِ نمایی + jitter تا رعدِ اتصالِ هم‌زمانِ همهٔ کلاینت‌ها بعدِ ری‌استارت نشود
      const delay = Math.min(30_000, 1_000 * 2 ** Math.min(attempt, 5)) + Math.random() * 500;
      retryTimer = setTimeout(() => { retryTimer = null; connect(); }, delay);
    };

    const connect = () => {
      if (stopped) return;
      const token = useAuthStore.getState().accessToken;
      if (!token) { startPoll(); scheduleRetry(); return; }

      const base = process.env.NEXT_PUBLIC_API_URL || "";
      const origin = base
        ? base.replace(/^http/, "ws")
        : `${location.protocol === "https:" ? "wss:" : "ws:"}//${location.host}`;
      const url = `${origin}/api/v1/ws?token=${encodeURIComponent(token)}`;

      let sock: WebSocket;
      try { sock = new WebSocket(url); } catch { startPoll(); scheduleRetry(); return; }
      ws = sock;

      sock.onopen = () => {
        if (stopped) { sock.close(); return; }
        attempt = 0;
        stopPoll();  // ← لحظه‌ای که بارِ دائمیِ این کاربر روی سرور صفر می‌شود
        pingTimer = setInterval(() => {
          try { sock.send("ping"); } catch { /* noop */ }
        }, PING_MS);
      };

      sock.onmessage = async (ev) => {
        const data = ev.data;
        if (typeof data !== "string" || data === "pong") return;
        try {
          const msg = JSON.parse(data) as { type?: string; signals?: Signal[] };
          if (msg.type === "signals" && Array.isArray(msg.signals)) {
            for (const s of msg.signals) await handleSignalRef.current(s);
          }
        } catch { /* noop */ }
      };

      sock.onclose = () => {
        if (pingTimer) { clearInterval(pingTimer); pingTimer = null; }
        if (ws === sock) ws = null;
        if (stopped) return;
        startPoll();     // تا بازگشتِ WS، تماس نباید از کار بیفتد
        scheduleRetry();
      };
      // onerror همیشه با onclose دنبال می‌شود؛ منطقِ بازگشت فقط یک‌جا بماند.
      sock.onerror = () => { /* noop */ };
    };

    startPoll();  // پوششِ کامل تا لحظهٔ برقراریِ WS
    connect();

    return () => {
      stopped = true;
      stopPoll();
      if (pingTimer) clearInterval(pingTimer);
      if (retryTimer) clearTimeout(retryTimer);
      if (ws) { ws.onclose = null; try { ws.close(); } catch { /* noop */ } }
    };
  }, [isAuthenticated]);

  // cleanup on unmount
  useEffect(() => () => cleanup(), [cleanup]);

  const toggleMute = () => {
    const next = !muted;
    setMuted(next);
    localRef.current?.getAudioTracks().forEach((t) => { t.enabled = !next; });
  };
  const toggleCam = () => {
    const next = !camOff;
    setCamOff(next);
    localRef.current?.getVideoTracks().forEach((t) => { t.enabled = !next; });
  };

  // تعویضِ حالتِ تماس در میانِ مکالمه (renegotiation)
  const switchMedia = useCallback(async (target: CallMedia) => {
    const pc = pcRef.current;
    if (!pc || phaseRef.current !== "active" || mediaRef.current === target || switchingRef.current) return;
    switchingRef.current = true;
    setSwitching(true);
    try {
      await applyLocalMedia(pc, target);
      const offer = await pc.createOffer();
      offer.sdp = tuneSdp(offer.sdp!);
      await pc.setLocalDescription(offer);
      await waitIce(pc);
      const desc = JSON.stringify({ type: pc.localDescription!.type, sdp: pc.localDescription!.sdp, media: target });
      await callsApi.signal({ callId: callIdRef.current, toEarthId: peerRef.current, type: "reoffer", sdp: desc });
      toast(target === "video" ? "تماس به تصویری تغییر کرد" : "تماس به صوتی تغییر کرد");
    } catch {
      toast.error("تغییرِ حالتِ تماس ناموفق بود");
    } finally {
      switchingRef.current = false;
      setSwitching(false);
    }
  }, [applyLocalMedia]);

  if (phase === "idle") {
    return <audio ref={remoteAudioRef} autoPlay style={{ display: "none" }} />;
  }

  const isVideo = media === "video";
  const statusText =
    phase === "outgoing" ? "در حال تماس…"
      : phase === "incoming" ? (isVideo ? "تماس تصویری ورودی" : "تماس صوتی ورودی")
        : phase === "connecting" ? "در حال اتصال…"
          : fmtDur(dur);

  return (
    <div className="fixed inset-0 z-[100] flex flex-col bg-[var(--color-bg)] overscroll-none select-none" style={{ touchAction: "none" }}>
      {/* audio sink (always present for audio path) */}
      {!isVideo && <audio ref={remoteAudioRef} autoPlay style={{ display: "none" }} />}

      {/* remote video (video active) */}
      {isVideo && (phase === "active" || phase === "connecting") ? (
        <video
          ref={remoteVideoRef} autoPlay playsInline
          className="absolute inset-0 w-full h-full object-cover bg-black"
        />
      ) : (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-5 bg-gradient-to-b from-indigo-600/10 to-[var(--color-bg)]">
          <div className="w-28 h-28 shrink-0 aspect-square rounded-full bg-indigo-600/25 flex items-center justify-center overflow-hidden ring-4 ring-white/10">
            {peerAvatar
              ? <img src={peerAvatar} alt="" className="w-full h-full object-cover" />
              : <UserIcon size={52} className="text-indigo-200" />}
          </div>
          <p className="text-white text-2xl font-bold">{peerName}</p>
          <p className="text-white/50 text-sm flex items-center gap-2">
            {(phase === "outgoing" || phase === "incoming") && (
              <span className="w-2 h-2 rounded-full bg-indigo-400 animate-pulse" />
            )}
            {statusText}
          </p>
        </div>
      )}

      {/* local preview (video) */}
      {isVideo && localStream && (phase === "active" || phase === "connecting") && (
        <video
          ref={localVideoRef} autoPlay playsInline muted
          className="absolute top-4 left-4 w-24 h-36 rounded-2xl object-cover border border-white/20 shadow-lg bg-black"
        />
      )}

      {/* top status over video */}
      {isVideo && (phase === "active" || phase === "connecting") && (
        <div className="absolute top-4 right-4 px-3 py-1.5 rounded-full bg-black/50 backdrop-blur">
          <p className="text-white text-sm font-medium">{peerName} · {statusText}</p>
        </div>
      )}

      {/* زیرنویسِ ترجمهٔ زنده */}
      {(phase === "active" || phase === "connecting") && (peerCaption || myCaption) && (
        <div className="absolute bottom-32 inset-x-0 px-6 z-10 flex flex-col items-center gap-1.5 pointer-events-none">
          {peerCaption && (
            <p className="max-w-lg text-center text-white text-base font-medium leading-relaxed px-4 py-2 rounded-2xl bg-black/60 backdrop-blur">
              {peerCaption}
            </p>
          )}
          {myCaption && (
            <p className="max-w-lg text-center text-white/45 text-xs px-3 py-1 rounded-xl bg-black/40">
              {myCaption}
            </p>
          )}
        </div>
      )}

      {/* controls */}
      <div className="mt-auto relative z-10 pb-[max(2rem,env(safe-area-inset-bottom))] pt-8 px-8">
        {phase === "incoming" ? (
          <div className="flex items-center justify-around max-w-xs mx-auto">
            <button onClick={declineIncoming} className="flex flex-col items-center gap-2">
              <span className="w-16 h-16 rounded-full bg-red-500 flex items-center justify-center shadow-lg active:scale-95">
                <PhoneOff size={26} className="text-white" style={{ color: "#fff" }} />
              </span>
              <span className="text-white/70 text-xs">رد</span>
            </button>
            <button onClick={acceptIncoming} className="flex flex-col items-center gap-2">
              <span className="w-16 h-16 rounded-full bg-emerald-500 flex items-center justify-center shadow-lg active:scale-95 animate-pulse">
                {isVideo ? <Video size={26} className="text-white" style={{ color: "#fff" }} /> : <Phone size={26} className="text-white" style={{ color: "#fff" }} />}
              </span>
              <span className="text-white/70 text-xs">پاسخ</span>
            </button>
          </div>
        ) : (
          <div className="flex items-center justify-center gap-5">
            <button
              onClick={toggleMute}
              className={`w-14 h-14 rounded-full flex items-center justify-center ${muted ? "bg-white text-black" : "bg-white/15 text-white"}`}
            >
              {muted ? <MicOff size={22} /> : <Mic size={22} />}
            </button>
            <button
              onClick={hangup}
              className="w-16 h-16 rounded-full bg-red-500 flex items-center justify-center shadow-lg active:scale-95"
            >
              <PhoneOff size={28} className="text-white" style={{ color: "#fff" }} />
            </button>
            {(phase === "active" || phase === "connecting") && (
              <button
                onClick={toggleLiveTr}
                title="ترجمهٔ زندهٔ گفتار"
                className={`relative w-14 h-14 rounded-full flex items-center justify-center ${liveTr ? "bg-emerald-500 text-white" : "bg-white/15 text-white"}`}
              >
                <Languages size={22} />
                {liveTr && <span className="absolute top-2 right-2 w-2 h-2 rounded-full bg-white animate-pulse" />}
              </button>
            )}
            {phase === "active" && (
              <button
                onClick={() => switchMedia(isVideo ? "audio" : "video")}
                disabled={switching}
                title={isVideo ? "تبدیل به تماس صوتی" : "تبدیل به تماس تصویری"}
                className="w-14 h-14 rounded-full flex items-center justify-center bg-white/15 text-white disabled:opacity-50"
              >
                {isVideo ? <Phone size={22} /> : <Video size={22} />}
              </button>
            )}
            {isVideo && (
              <button
                onClick={toggleCam}
                className={`w-14 h-14 rounded-full flex items-center justify-center ${camOff ? "bg-white text-black" : "bg-white/15 text-white"}`}
              >
                {camOff ? <VideoOff size={22} /> : <Video size={22} />}
              </button>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
