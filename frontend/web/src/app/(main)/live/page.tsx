"use client";

import { Suspense, useCallback, useEffect, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import {
  Radio, Heart, Send, X, Users, Video, VideoOff, Mic, MicOff, ArrowRight, Loader2,
} from "lucide-react";
import { liveApi } from "@/lib/api";
import { useAuthStore } from "@/store/auth";
import { toPersianNum } from "@/lib/utils";
import toast from "react-hot-toast";
import { useTranslation } from "@/store/i18n";

const FALLBACK_ICE: RTCIceServer[] = [
  { urls: "stun:stun.l.google.com:19302" },
  { urls: "stun:stun1.l.google.com:19302" },
];

type Mode = "list" | "broadcast" | "watch";

interface HostInfo { earth_id: string; name: string; avatar_url?: string | null }
interface LiveItem {
  session_id: string; title?: string | null; host: HostInfo;
  viewer_count: number; hearts: number; is_mine: boolean;
}
interface ChatMsg {
  id: string; from: string; from_name: string; from_avatar?: string | null; text: string; ts: number;
}
interface Signal {
  type: string; session_id?: string; from?: string; sdp?: string;
  from_name?: string; from_avatar?: string | null;
}

// انتظار برای کاملِ ICE (non-trickle) تا با poll سازگار باشد
function waitIce(pc: RTCPeerConnection) {
  return new Promise<void>((resolve) => {
    if (pc.iceGatheringState === "complete") return resolve();
    const check = () => {
      if (pc.iceGatheringState === "complete") {
        pc.removeEventListener("icegatheringstatechange", check);
        resolve();
      }
    };
    pc.addEventListener("icegatheringstatechange", check);
    setTimeout(resolve, 3000);
  });
}

function LiveInner() {
  const { t } = useTranslation();
  const router = useRouter();
  const sp = useSearchParams();
  const isAuth = useAuthStore((s) => s.isAuthenticated);

  const initWatch = sp.get("watch");
  const initGo = sp.get("go");
  const [mode, setMode] = useState<Mode>(initWatch ? "watch" : initGo ? "broadcast" : "list");
  const [targetId, setTargetId] = useState<string | null>(initWatch);

  // ── مشترک ──
  const iceRef = useRef<RTCIceServer[] | null>(null);
  const sessionIdRef = useRef<string | null>(initWatch);
  const pollBusyRef = useRef(false);
  const [viewerCount, setViewerCount] = useState(0);
  const [hearts, setHearts] = useState(0);
  const [chat, setChat] = useState<ChatMsg[]>([]);
  const [chatText, setChatText] = useState("");
  const chatScrollRef = useRef<HTMLDivElement>(null);

  // ── فهرست ──
  const [items, setItems] = useState<LiveItem[]>([]);
  const [listLoading, setListLoading] = useState(true);

  // ── پخش (میزبان) ──
  const [title, setTitle] = useState("");
  const [broadcasting, setBroadcasting] = useState(false);
  const [starting, setStarting] = useState(false);
  const [muted, setMuted] = useState(false);
  const [camOff, setCamOff] = useState(false);
  const localVideoRef = useRef<HTMLVideoElement>(null);
  const localStreamRef = useRef<MediaStream | null>(null);
  const pcMapRef = useRef<Map<string, RTCPeerConnection>>(new Map());

  // ── تماشا (بیننده) ──
  const [joining, setJoining] = useState(false);
  const [host, setHost] = useState<HostInfo | null>(null);
  const [ended, setEnded] = useState(false);
  const [remoteStream, setRemoteStream] = useState<MediaStream | null>(null);
  const remoteVideoRef = useRef<HTMLVideoElement>(null);
  const hostEarthRef = useRef<string>("");
  const viewerPcRef = useRef<RTCPeerConnection | null>(null);
  const floatHeartsRef = useRef<HTMLDivElement>(null);

  const getIce = useCallback((fallback?: RTCIceServer[]) => {
    if (!iceRef.current) iceRef.current = fallback ?? FALLBACK_ICE;
    return iceRef.current;
  }, []);

  // اسکرول چت به پایین با پیامِ جدید
  useEffect(() => {
    const el = chatScrollRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [chat]);

  useEffect(() => {
    if (remoteVideoRef.current && remoteStream) remoteVideoRef.current.srcObject = remoteStream;
  }, [remoteStream]);

  // ─────────────── فهرستِ پخش‌ها ───────────────
  useEffect(() => {
    if (mode !== "list") return;
    let on = true;
    const load = () =>
      liveApi.list(50)
        .then((r) => { if (on) { setItems(r.data?.items ?? []); setListLoading(false); } })
        .catch(() => { if (on) setListLoading(false); });
    load();
    const id = setInterval(load, 5000);
    return () => { on = false; clearInterval(id); };
  }, [mode]);

  // ─────────────── میزبان: ساختِ اتصال برای هر بیننده ───────────────
  const offerToViewer = useCallback(async (viewer: string) => {
    const stream = localStreamRef.current;
    if (!stream) return;
    try {
      const pc = new RTCPeerConnection({ iceServers: getIce() });
      stream.getTracks().forEach((t) => pc.addTrack(t, stream));
      pc.onconnectionstatechange = () => {
        const st = pc.connectionState;
        if (st === "failed" || st === "closed" || st === "disconnected") {
          try { pc.close(); } catch { /* noop */ }
          pcMapRef.current.delete(viewer);
        }
      };
      // اگر اتصالِ قبلی برای این بیننده هست ببند
      const prev = pcMapRef.current.get(viewer);
      if (prev) { try { prev.close(); } catch { /* noop */ } }
      pcMapRef.current.set(viewer, pc);
      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await waitIce(pc);
      const desc = JSON.stringify({ type: pc.localDescription!.type, sdp: pc.localDescription!.sdp });
      await liveApi.signal({ sessionId: sessionIdRef.current!, toEarthId: viewer, type: "offer", sdp: desc });
    } catch { /* noop */ }
  }, [getIce]);

  // ─────────────── بیننده: پاسخ به offerِ میزبان ───────────────
  const answerHost = useCallback(async (s: Signal) => {
    if (!s.sdp || !s.from) return;
    try {
      const pc = new RTCPeerConnection({ iceServers: getIce() });
      pc.ontrack = (e) => setRemoteStream(e.streams[0]);
      pc.onconnectionstatechange = () => {
        if (pc.connectionState === "failed") toast.error(t("live.toast.connErr"));
      };
      if (viewerPcRef.current) { try { viewerPcRef.current.close(); } catch { /* noop */ } }
      viewerPcRef.current = pc;
      await pc.setRemoteDescription(JSON.parse(s.sdp));
      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      await waitIce(pc);
      const desc = JSON.stringify({ type: pc.localDescription!.type, sdp: pc.localDescription!.sdp });
      await liveApi.signal({ sessionId: sessionIdRef.current!, toEarthId: s.from, type: "answer", sdp: desc });
    } catch { /* noop */ }
  }, [getIce]);

  // ─────────────── حلقهٔ سیگنالینگ (میزبان یا بیننده) ───────────────
  const handleSignal = useCallback(async (s: Signal) => {
    if (mode === "broadcast") {
      if (s.type === "viewer-join" && s.from) await offerToViewer(s.from);
      else if (s.type === "answer" && s.from) {
        const pc = pcMapRef.current.get(s.from);
        if (pc && s.sdp) { try { await pc.setRemoteDescription(JSON.parse(s.sdp)); } catch { /* noop */ } }
      } else if (s.type === "viewer-leave" && s.from) {
        const pc = pcMapRef.current.get(s.from);
        if (pc) { try { pc.close(); } catch { /* noop */ } pcMapRef.current.delete(s.from); }
      }
    } else if (mode === "watch") {
      if (s.type === "offer" && s.from === hostEarthRef.current) await answerHost(s);
    }
  }, [mode, offerToViewer, answerHost]);

  useEffect(() => {
    if (!isAuth || (mode !== "broadcast" && mode !== "watch")) return;
    if (mode === "broadcast" && !broadcasting) return;
    if (mode === "watch" && !host) return;
    const tick = async () => {
      if (pollBusyRef.current) return;
      pollBusyRef.current = true;
      try {
        const res = await liveApi.poll();
        const sigs: Signal[] = res.data?.signals ?? [];
        for (const s of sigs) await handleSignal(s);
      } catch { /* noop */ } finally { pollBusyRef.current = false; }
    };
    tick();
    const id = setInterval(tick, 1500);
    return () => clearInterval(id);
  }, [isAuth, mode, broadcasting, host, handleSignal]);

  // ─────────────── حلقهٔ وضعیت + چت ───────────────
  useEffect(() => {
    const sid = sessionIdRef.current;
    if (!sid || (mode !== "broadcast" && mode !== "watch")) return;
    if (mode === "broadcast" && !broadcasting) return;
    if (mode === "watch" && !host) return;
    let on = true;
    const tick = async () => {
      try {
        const st = (await liveApi.state(sid)).data;
        if (!on) return;
        setViewerCount(st.viewer_count ?? 0);
        setHearts(st.hearts ?? 0);
        if (st.status === "ended" && mode === "watch") { setEnded(true); }
        const ms = (await liveApi.messages(sid, 50)).data?.items ?? [];
        if (on) setChat(ms);
      } catch { /* noop */ }
    };
    tick();
    const id = setInterval(tick, 2500);
    return () => { on = false; clearInterval(id); };
  }, [mode, broadcasting, host]);

  // ─────────────── شروعِ پخش ───────────────
  const startBroadcast = useCallback(async () => {
    if (starting || broadcasting) return;
    setStarting(true);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "user" }, audio: true,
      });
      localStreamRef.current = stream;
      if (localVideoRef.current) localVideoRef.current.srcObject = stream;
      const res = await liveApi.start(title.trim() || undefined);
      const sid = res.data.session_id as string;
      sessionIdRef.current = sid;
      iceRef.current = res.data.iceServers ?? FALLBACK_ICE;
      setBroadcasting(true);
      toast.success(t("live.toast.started"));
    } catch (e) {
      const err = e as { name?: string };
      localStreamRef.current?.getTracks().forEach((t) => t.stop());
      localStreamRef.current = null;
      toast.error(err?.name === "NotAllowedError" ? t("live.toast.camDenied") : t("live.toast.startErr"));
    } finally {
      setStarting(false);
    }
  }, [starting, broadcasting, title]);

  const stopBroadcast = useCallback(async (silent = false) => {
    const sid = sessionIdRef.current;
    pcMapRef.current.forEach((pc) => { try { pc.close(); } catch { /* noop */ } });
    pcMapRef.current.clear();
    localStreamRef.current?.getTracks().forEach((t) => t.stop());
    localStreamRef.current = null;
    if (sid) { try { await liveApi.stop(sid); } catch { /* noop */ } }
    setBroadcasting(false);
    sessionIdRef.current = null;
    if (!silent) { setMode("list"); router.replace("/live"); }
  }, [router]);

  // ─────────────── پیوستنِ بیننده ───────────────
  const joinWatch = useCallback(async (sid: string) => {
    if (joining) return;
    setJoining(true);
    try {
      const res = await liveApi.join(sid);
      const d = res.data;
      if (d.is_host) {
        toast(t("live.toast.isYours"));
        setJoining(false);
        setMode("list"); router.replace("/live");
        return;
      }
      sessionIdRef.current = sid;
      hostEarthRef.current = d.host_earth_id;
      iceRef.current = d.iceServers ?? FALLBACK_ICE;
      setHost(d.host);
      setViewerCount(d.viewer_count ?? 0);
      setHearts(d.hearts ?? 0);
      setEnded(false);
    } catch (e) {
      const err = e as { response?: { status?: number } };
      if (err?.response?.status === 410) { setEnded(true); }
      else toast.error(t("live.toast.joinErr"));
    } finally {
      setJoining(false);
    }
  }, [joining, router]);

  const leaveWatch = useCallback(async () => {
    const sid = sessionIdRef.current;
    if (viewerPcRef.current) { try { viewerPcRef.current.close(); } catch { /* noop */ } viewerPcRef.current = null; }
    setRemoteStream(null);
    if (sid) { try { await liveApi.leave(sid); } catch { /* noop */ } }
    setHost(null);
    sessionIdRef.current = null;
    setMode("list"); router.replace("/live");
  }, [router]);

  // ورودِ اولیه در حالتِ تماشا (deep-link ?watch=)
  useEffect(() => {
    if (mode === "watch" && targetId && !host && !ended && !joining) {
      joinWatch(targetId);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mode, targetId]);

  // پاک‌سازی هنگامِ خروج از صفحه
  useEffect(() => {
    return () => {
      pcMapRef.current.forEach((pc) => { try { pc.close(); } catch { /* noop */ } });
      localStreamRef.current?.getTracks().forEach((t) => t.stop());
      if (viewerPcRef.current) { try { viewerPcRef.current.close(); } catch { /* noop */ } }
      const sid = sessionIdRef.current;
      if (sid) {
        if (broadcasting) liveApi.stop(sid).catch(() => {});
        else liveApi.leave(sid).catch(() => {});
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ── اکشن‌ها ──
  const sendChat = useCallback(async () => {
    const msg = chatText.trim();
    const sid = sessionIdRef.current;
    if (!msg || !sid) return;
    setChatText("");
    try {
      const res = await liveApi.chat(sid, msg);
      setChat((c) => [...c.filter((m) => m.id !== res.data.id), res.data]);
    } catch { toast.error(t("live.toast.chatErr")); }
  }, [chatText]);

  const sendHeart = useCallback(async () => {
    const sid = sessionIdRef.current;
    if (!sid) return;
    setHearts((h) => h + 1); // خوش‌بینانه
    // انیمیشنِ قلبِ شناور
    const layer = floatHeartsRef.current;
    if (layer) {
      const el = document.createElement("div");
      el.textContent = "❤";
      el.style.cssText =
        "position:absolute;bottom:0;right:" + (10 + Math.random() * 30) + "px;font-size:" +
        (18 + Math.random() * 14) + "px;animation:floatUp 2.4s ease-out forwards;pointer-events:none;";
      layer.appendChild(el);
      setTimeout(() => el.remove(), 2400);
    }
    try { await liveApi.heart(sid, 1); } catch { /* noop */ }
  }, []);

  const toggleMute = () => {
    const next = !muted; setMuted(next);
    localStreamRef.current?.getAudioTracks().forEach((t) => { t.enabled = !next; });
  };
  const toggleCam = () => {
    const next = !camOff; setCamOff(next);
    localStreamRef.current?.getVideoTracks().forEach((t) => { t.enabled = !next; });
  };

  // ═══════════════ نمای فهرست ═══════════════
  if (mode === "list") {
    return (
      <div className="min-h-[100dvh] bg-[#0A0A0A] text-white pb-24">
        <div className="sticky top-0 z-20 flex items-center gap-3 px-4 h-14 border-b border-white/10 bg-[#0A0A0A]/95 backdrop-blur">
          <button onClick={() => router.back()} className="text-white/70"><ArrowRight size={22} /></button>
          <Radio className="text-rose-500" size={20} />
          <h1 className="text-base font-bold">{t("live.title")}</h1>
        </div>

        <div className="p-4">
          <button
            onClick={() => setMode("broadcast")}
            className="w-full flex items-center justify-center gap-2 py-3.5 rounded-2xl text-white font-bold active:scale-[0.98] transition-all mb-5"
            style={{ background: "linear-gradient(135deg,#F43F5E,#F97316)" }}
          >
            <Video size={19} /> {t("live.btn.start")}
          </button>

          {listLoading ? (
            <div className="flex justify-center py-16"><Loader2 className="animate-spin text-rose-500" /></div>
          ) : items.length === 0 ? (
            <div className="text-center py-16 text-white/40 text-sm">
              {t("live.empty")}
            </div>
          ) : (
            <div className="grid grid-cols-2 gap-3">
              {items.map((it) => (
                <button
                  key={it.session_id}
                  onClick={() => { setTargetId(it.session_id); sessionIdRef.current = it.session_id; setEnded(false); setHost(null); setMode("watch"); }}
                  className="relative rounded-2xl overflow-hidden aspect-[3/4] text-right"
                  style={{ background: "linear-gradient(160deg,#1e1030,#0A0A0A)" }}
                >
                  <div className="absolute inset-0 flex flex-col items-center justify-center gap-2 p-3">
                    <div className="w-16 h-16 rounded-full overflow-hidden bg-surface-800 flex items-center justify-center ring-2 ring-rose-500/60">
                      {it.host.avatar_url ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img src={it.host.avatar_url} alt="" className="w-full h-full object-cover" />
                      ) : (
                        <span className="text-2xl font-bold text-white">{it.host.name.charAt(0)}</span>
                      )}
                    </div>
                    <p className="text-sm font-semibold text-white text-center line-clamp-1">{it.host.name}</p>
                    {it.title && <p className="text-[11px] text-white/50 text-center line-clamp-2">{it.title}</p>}
                  </div>
                  <span className="absolute top-2 right-2 text-[10px] font-bold text-white bg-rose-600 px-2 py-0.5 rounded-full">LIVE</span>
                  <span className="absolute top-2 left-2 flex items-center gap-1 text-[11px] text-white bg-black/50 px-2 py-0.5 rounded-full">
                    <Users size={11} /> {toPersianNum(it.viewer_count)}
                  </span>
                </button>
              ))}
            </div>
          )}
        </div>
      </div>
    );
  }

  // ═══════════════ نمای پخش (میزبان) ═══════════════
  if (mode === "broadcast") {
    return (
      <div className="fixed inset-0 z-[90] bg-black flex flex-col">
        <video ref={localVideoRef} autoPlay playsInline muted className="absolute inset-0 w-full h-full object-cover" />
        <div ref={floatHeartsRef} className="absolute bottom-24 right-2 w-16 h-64 pointer-events-none z-10" />

        {/* هدر */}
        <div className="relative z-10 flex items-center justify-between px-4 pt-[max(1rem,env(safe-area-inset-top))]">
          <div className="flex items-center gap-2">
            <span className="text-[11px] font-bold text-white bg-rose-600 px-2.5 py-1 rounded-full flex items-center gap-1">
              <span className="w-1.5 h-1.5 rounded-full bg-white animate-pulse" /> LIVE
            </span>
            {broadcasting && (
              <span className="flex items-center gap-1 text-xs text-white bg-black/45 px-2.5 py-1 rounded-full">
                <Users size={13} /> {toPersianNum(viewerCount)}
              </span>
            )}
            {broadcasting && hearts > 0 && (
              <span className="flex items-center gap-1 text-xs text-white bg-black/45 px-2.5 py-1 rounded-full">
                <Heart size={12} className="fill-rose-500 text-rose-500" /> {toPersianNum(hearts)}
              </span>
            )}
          </div>
          <button
            onClick={() => broadcasting ? stopBroadcast() : (localStreamRef.current?.getTracks().forEach((t) => t.stop()), setMode("list"), router.replace("/live"))}
            className="w-9 h-9 rounded-full bg-black/50 flex items-center justify-center text-white"
          >
            <X size={20} />
          </button>
        </div>

        {!broadcasting ? (
          /* پیش از شروع — عنوان + دکمهٔ شروع */
          <div className="relative z-10 mt-auto p-5 pb-[max(1.5rem,env(safe-area-inset-bottom))] bg-gradient-to-t from-black/80 to-transparent">
            <input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              maxLength={120}
              placeholder={t("live.ph.title")}
              dir="rtl"
              className="w-full h-12 px-4 rounded-xl bg-white/10 border border-white/15 text-white placeholder:text-white/40 text-sm focus:outline-none mb-3"
            />
            <button
              onClick={startBroadcast}
              disabled={starting}
              className="w-full flex items-center justify-center gap-2 py-3.5 rounded-2xl text-white font-bold active:scale-[0.98] transition-all disabled:opacity-60"
              style={{ background: "linear-gradient(135deg,#F43F5E,#F97316)" }}
            >
              {starting ? <Loader2 size={19} className="animate-spin" /> : <Radio size={19} />}
              {starting ? t("live.btn.preparing") : t("live.btn.goLive")}
            </button>
          </div>
        ) : (
          /* حین پخش — چت + کنترل‌ها */
          <>
            <div ref={chatScrollRef} className="relative z-10 mt-auto max-h-52 overflow-y-auto no-scrollbar px-4 space-y-1.5 mb-2">
              {chat.map((m) => (
                <div key={m.id} className="flex items-start gap-2" dir="rtl">
                  <span className="text-xs font-bold text-rose-300 shrink-0">{m.from_name}</span>
                  <span className="text-xs text-white/90 break-words">{m.text}</span>
                </div>
              ))}
            </div>
            <div className="relative z-10 flex items-center gap-2 px-4 pb-[max(1rem,env(safe-area-inset-bottom))]">
              <button onClick={toggleMute} className={`w-11 h-11 rounded-full flex items-center justify-center ${muted ? "bg-white text-black" : "bg-white/15 text-white"}`}>
                {muted ? <MicOff size={19} /> : <Mic size={19} />}
              </button>
              <button onClick={toggleCam} className={`w-11 h-11 rounded-full flex items-center justify-center ${camOff ? "bg-white text-black" : "bg-white/15 text-white"}`}>
                {camOff ? <VideoOff size={19} /> : <Video size={19} />}
              </button>
              <button onClick={() => stopBroadcast()} className="flex-1 h-11 rounded-full bg-rose-600 text-white font-bold text-sm">
                {t("live.btn.end")}
              </button>
            </div>
          </>
        )}
        <style>{`@keyframes floatUp{0%{opacity:1;transform:translateY(0) scale(.8)}100%{opacity:0;transform:translateY(-220px) scale(1.3)}}`}</style>
      </div>
    );
  }

  // ═══════════════ نمای تماشا (بیننده) ═══════════════
  return (
    <div className="fixed inset-0 z-[90] bg-black flex flex-col">
      {remoteStream ? (
        <video ref={remoteVideoRef} autoPlay playsInline className="absolute inset-0 w-full h-full object-cover" />
      ) : (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-4 bg-gradient-to-b from-[#1e1030] to-black">
          {host?.avatar_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={host.avatar_url} alt="" className="w-24 h-24 rounded-full object-cover ring-4 ring-rose-500/40" />
          ) : (
            <div className="w-24 h-24 rounded-full bg-rose-500/20 flex items-center justify-center text-4xl">🎥</div>
          )}
          <p className="text-white/70 text-sm flex items-center gap-2">
            {!ended && <Loader2 size={15} className="animate-spin" />}
            {ended ? t("live.ended") : t("live.connecting")}
          </p>
        </div>
      )}

      <div ref={floatHeartsRef} className="absolute bottom-24 right-2 w-16 h-64 pointer-events-none z-10" />

      {/* هدر */}
      <div className="relative z-10 flex items-center justify-between px-4 pt-[max(1rem,env(safe-area-inset-top))]">
        <div className="flex items-center gap-2">
          <button onClick={() => host && router.push(`/u/${host.earth_id}`)} className="flex items-center gap-2 bg-black/45 rounded-full pr-1 pl-3 py-1">
            <div className="w-7 h-7 rounded-full overflow-hidden bg-surface-800 flex items-center justify-center">
              {host?.avatar_url ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={host.avatar_url} alt="" className="w-full h-full object-cover" />
              ) : <span className="text-xs font-bold text-white">{host?.name?.charAt(0)}</span>}
            </div>
            <span className="text-xs font-semibold text-white max-w-28 truncate">{host?.name ?? t("live.title")}</span>
          </button>
          <span className="flex items-center gap-1 text-xs text-white bg-black/45 px-2.5 py-1 rounded-full">
            <Users size={13} /> {toPersianNum(viewerCount)}
          </span>
        </div>
        <button onClick={leaveWatch} className="w-9 h-9 rounded-full bg-black/50 flex items-center justify-center text-white">
          <X size={20} />
        </button>
      </div>

      {ended ? (
        <div className="relative z-10 mt-auto p-6 pb-[max(1.5rem,env(safe-area-inset-bottom))]">
          <button onClick={leaveWatch} className="w-full py-3.5 rounded-2xl bg-white/10 text-white font-bold">
            {t("live.btn.backToList")}
          </button>
        </div>
      ) : (
        <>
          <div ref={chatScrollRef} className="relative z-10 mt-auto max-h-52 overflow-y-auto no-scrollbar px-4 space-y-1.5 mb-2">
            {chat.map((m) => (
              <div key={m.id} className="flex items-start gap-2" dir="rtl">
                <span className="text-xs font-bold text-rose-300 shrink-0">{m.from_name}</span>
                <span className="text-xs text-white/90 break-words">{m.text}</span>
              </div>
            ))}
          </div>
          <div className="relative z-10 flex items-center gap-2 px-4 pb-[max(1rem,env(safe-area-inset-bottom))]">
            <input
              value={chatText}
              onChange={(e) => setChatText(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter") sendChat(); }}
              maxLength={500}
              placeholder={t("live.ph.chat")}
              dir="rtl"
              className="flex-1 h-11 px-4 rounded-full bg-white/12 border border-white/15 text-white placeholder:text-white/40 text-sm focus:outline-none"
            />
            <button onClick={sendChat} className="w-11 h-11 rounded-full bg-white/15 text-white flex items-center justify-center shrink-0">
              <Send size={18} />
            </button>
            <button onClick={sendHeart} className="w-11 h-11 rounded-full bg-rose-600 text-white flex items-center justify-center shrink-0 active:scale-90 transition-transform">
              <Heart size={19} className="fill-white" />
            </button>
          </div>
        </>
      )}
      <style>{`@keyframes floatUp{0%{opacity:1;transform:translateY(0) scale(.8)}100%{opacity:0;transform:translateY(-220px) scale(1.3)}}`}</style>
    </div>
  );
}

export default function LivePage() {
  return (
    <Suspense fallback={<div className="min-h-[100dvh] bg-[#0A0A0A] flex items-center justify-center"><Loader2 className="animate-spin text-rose-500" /></div>}>
      <LiveInner />
    </Suspense>
  );
}
