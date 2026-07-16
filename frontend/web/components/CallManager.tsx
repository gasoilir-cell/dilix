"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { api, getAccessToken, type WsCallSignal } from "@/lib/api";
import { consumeCall, subscribeCall, type CallMedia, type CallRequest } from "@/lib/call-store";

type Phase = "idle" | "outgoing" | "incoming" | "connecting" | "active";

const FALLBACK_ICE = [{ urls: "stun:stun.l.google.com:19302" }];

function newCallId(): string {
  return typeof crypto !== "undefined" && crypto.randomUUID ? crypto.randomUUID() : `call-${Date.now()}`;
}

function fmtDur(s: number): string {
  const m = Math.floor(s / 60);
  const ss = Math.floor(s % 60).toString().padStart(2, "0");
  return `${m}:${ss}`;
}

export default function CallManager() {
  const [phase, setPhase] = useState<Phase>("idle");
  const [peerName, setPeerName] = useState("");
  const [media, setMedia] = useState<CallMedia>("audio");
  const [error, setError] = useState<string | null>(null);
  const [muted, setMuted] = useState(false);
  const [camOff, setCamOff] = useState(false);
  const [dur, setDur] = useState(0);
  const [localStream, setLocalStream] = useState<MediaStream | null>(null);
  const [remoteStream, setRemoteStream] = useState<MediaStream | null>(null);

  const phaseRef = useRef<Phase>("idle");
  const pcRef = useRef<RTCPeerConnection | null>(null);
  const wsRef = useRef<WebSocket | null>(null);
  const localRef = useRef<MediaStream | null>(null);
  const peerRef = useRef("");
  const callIdRef = useRef("");
  const mediaRef = useRef<CallMedia>("audio");
  const offerRef = useRef<RTCSessionDescriptionInit | null>(null);
  const pendingCandidatesRef = useRef<RTCIceCandidateInit[]>([]);
  const outgoingRef = useRef(false);
  const durTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const localVideoRef = useRef<HTMLVideoElement>(null);
  const remoteVideoRef = useRef<HTMLVideoElement>(null);
  const remoteAudioRef = useRef<HTMLAudioElement>(null);

  useEffect(() => { phaseRef.current = phase; }, [phase]);
  useEffect(() => {
    if (localVideoRef.current && localStream) localVideoRef.current.srcObject = localStream;
    if (remoteVideoRef.current && remoteStream) remoteVideoRef.current.srcObject = remoteStream;
    if (remoteAudioRef.current && remoteStream) remoteAudioRef.current.srcObject = remoteStream;
  }, [localStream, remoteStream]);

  const sendSignal = useCallback((type: WsCallSignal["type"], payload: Record<string, unknown>) => {
    const ws = wsRef.current;
    if (!ws || ws.readyState !== WebSocket.OPEN || !peerRef.current) return;
    ws.send(JSON.stringify({
      type,
      payload: { to: peerRef.current, call_id: callIdRef.current, media: mediaRef.current, ...payload },
    }));
  }, []);

  const cleanup = useCallback(() => {
    if (durTimerRef.current) clearInterval(durTimerRef.current);
    durTimerRef.current = null;
    try { pcRef.current?.close(); } catch { /* noop */ }
    pcRef.current = null;
    localRef.current?.getTracks().forEach((track) => track.stop());
    localRef.current = null;
    offerRef.current = null;
    pendingCandidatesRef.current = [];
    peerRef.current = "";
    callIdRef.current = "";
    outgoingRef.current = false;
    setLocalStream(null);
    setRemoteStream(null);
    setMuted(false);
    setCamOff(false);
    setDur(0);
    setError(null);
    setPhase("idle");
  }, []);

  const startTimer = () => {
    if (durTimerRef.current) clearInterval(durTimerRef.current);
    setDur(0);
    durTimerRef.current = setInterval(() => setDur((n) => n + 1), 1000);
  };

  const attachLocal = async (pc: RTCPeerConnection, m: CallMedia) => {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: m === "video" });
    localRef.current = stream;
    setLocalStream(stream);
    stream.getTracks().forEach((track) => pc.addTrack(track, stream));
  };

  // کاندیداهای ICE که پیش از تنظیمِ remote description رسیده‌اند را پس از آماده‌شدنِ
  // اتصال اعمال می‌کند تا صدا/تصویر قطع نشود.
  const flushPendingCandidates = async () => {
    const pc = pcRef.current;
    if (!pc) return;
    const pending = pendingCandidatesRef.current;
    pendingCandidatesRef.current = [];
    for (const candidate of pending) {
      try { await pc.addIceCandidate(candidate); } catch { /* noop */ }
    }
  };

  const newPeerConnection = useCallback(() => {
    const pc = new RTCPeerConnection({ iceServers: FALLBACK_ICE });
    pc.onicecandidate = (event) => {
      if (event.candidate) sendSignal("ice.candidate", { candidate: event.candidate.toJSON() });
    };
    pc.ontrack = (event) => setRemoteStream(event.streams[0] ?? null);
    pc.onconnectionstatechange = () => {
      // «disconnected» اغلب گذرا است و ممکن است دوباره وصل شود؛ فقط روی قطعِ قطعی پایان می‌دهیم.
      if (["failed", "closed"].includes(pc.connectionState) && phaseRef.current !== "idle") cleanup();
    };
    return pc;
  }, [cleanup, sendSignal]);

  const startOutgoing = useCallback(async (req: CallRequest) => {
    if (phaseRef.current !== "idle") return;
    setError(null);
    outgoingRef.current = true;
    peerRef.current = req.earthId;
    callIdRef.current = newCallId();
    mediaRef.current = req.media;
    setPeerName(req.name);
    setMedia(req.media);
    setPhase("outgoing");
    try {
      const pc = newPeerConnection();
      pcRef.current = pc;
      await attachLocal(pc, req.media);
      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      sendSignal("call.offer", { sdp: offer });
    } catch {
      setError("شروع تماس ناموفق بود.");
      cleanup();
    }
  }, [cleanup, newPeerConnection, sendSignal]);

  const acceptIncoming = useCallback(async () => {
    if (!offerRef.current) return;
    setPhase("connecting");
    try {
      const pc = newPeerConnection();
      pcRef.current = pc;
      await attachLocal(pc, mediaRef.current);
      await pc.setRemoteDescription(offerRef.current);
      await flushPendingCandidates();
      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      sendSignal("call.answer", { sdp: answer });
      setPhase("active");
      startTimer();
    } catch {
      setError("پاسخ به تماس ناموفق بود.");
      sendSignal("call.end", { reason: "failed" });
      cleanup();
    }
  }, [cleanup, newPeerConnection, sendSignal]);

  const hangup = useCallback(() => {
    if (phaseRef.current !== "idle") sendSignal("call.end", { reason: "hangup" });
    cleanup();
  }, [cleanup, sendSignal]);

  const handleSignal = useCallback(async (signal: WsCallSignal) => {
    const payload = signal.payload ?? {};
    const from = String(payload.from ?? "");
    const callId = String(payload.call_id ?? "");
    if (signal.type === "call.offer") {
      if (phaseRef.current !== "idle") {
        if (from) {
          peerRef.current = from;
          callIdRef.current = callId;
          sendSignal("call.end", { reason: "busy" });
        }
        return;
      }
      peerRef.current = from;
      callIdRef.current = callId || newCallId();
      mediaRef.current = payload.media === "video" ? "video" : "audio";
      offerRef.current = payload.sdp as RTCSessionDescriptionInit;
      setMedia(mediaRef.current);
      setPeerName(from || "تماس ورودی");
      setPhase("incoming");
      return;
    }
    if (callId && callId !== callIdRef.current) return;
    if (signal.type === "call.answer" && outgoingRef.current && pcRef.current) {
      await pcRef.current.setRemoteDescription(payload.sdp as RTCSessionDescriptionInit);
      await flushPendingCandidates();
      setPhase("active");
      startTimer();
    } else if (signal.type === "ice.candidate" && payload.candidate) {
      const candidate = payload.candidate as RTCIceCandidateInit;
      // تا وقتی remote description تنظیم نشده، کاندیداها را بافر می‌کنیم.
      if (pcRef.current?.remoteDescription) {
        try { await pcRef.current.addIceCandidate(candidate); } catch { /* noop */ }
      } else {
        pendingCandidatesRef.current.push(candidate);
      }
    } else if (signal.type === "call.end") {
      cleanup();
    }
  }, [cleanup, sendSignal]);

  useEffect(() => {
    const unsub = subscribeCall((req) => {
      if (req) {
        consumeCall();
        startOutgoing(req);
      }
    });
    return unsub;
  }, [startOutgoing]);

  useEffect(() => {
    const token = getAccessToken();
    if (!token || typeof window === "undefined") return;
    const ws = api.realtime.open(token);
    wsRef.current = ws;
    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data) as WsCallSignal;
        if (["call.offer", "call.answer", "call.end", "ice.candidate"].includes(data.type)) handleSignal(data);
      } catch { /* noop */ }
    };
    ws.onclose = () => { if (wsRef.current === ws) wsRef.current = null; };
    return () => {
      if (wsRef.current === ws) wsRef.current = null;
      ws.close();
    };
  }, [handleSignal]);

  useEffect(() => () => cleanup(), [cleanup]);

  const toggleMute = () => {
    const next = !muted;
    setMuted(next);
    localRef.current?.getAudioTracks().forEach((track) => { track.enabled = !next; });
  };

  const toggleCam = () => {
    const next = !camOff;
    setCamOff(next);
    localRef.current?.getVideoTracks().forEach((track) => { track.enabled = !next; });
  };

  if (phase === "idle") return <audio ref={remoteAudioRef} autoPlay style={{ display: "none" }} />;

  const video = media === "video";
  const status = phase === "outgoing" ? "در حال تماس…" : phase === "incoming" ? "تماس ورودی" : phase === "connecting" ? "در حال اتصال…" : fmtDur(dur);

  return (
    <div className="call-overlay" role="dialog" aria-label="تماس صوتی و تصویری">
      {!video && <audio ref={remoteAudioRef} autoPlay style={{ display: "none" }} />}
      {video && phase !== "incoming" && <video ref={remoteVideoRef} autoPlay playsInline className="call-remote-video" />}
      {video && localStream && <video ref={localVideoRef} autoPlay playsInline muted className="call-local-video" />}
      <div className="call-card">
        <div className="call-avatar" aria-hidden>{video ? "🎥" : "📞"}</div>
        <h2>{peerName || "تماس"}</h2>
        <p className="muted">{status}</p>
        {error && <p className="danger-text">{error}</p>}
        <div className="row" style={{ justifyContent: "center", gap: 12 }}>
          {phase === "incoming" ? (
            <>
              <button className="btn" onClick={acceptIncoming}>پاسخ</button>
              <button className="btn secondary" onClick={hangup}>رد</button>
            </>
          ) : (
            <>
              <button className="btn secondary" onClick={toggleMute}>{muted ? "روشن کردن میکروفون" : "بی‌صدا"}</button>
              {video && <button className="btn secondary" onClick={toggleCam}>{camOff ? "روشن کردن دوربین" : "خاموش کردن دوربین"}</button>}
              <button className="btn" onClick={hangup}>پایان تماس</button>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
