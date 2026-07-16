"use client";

export type CallMedia = "audio" | "video";

export interface CallRequest {
  earthId: string;
  name: string;
  media: CallMedia;
}

type Listener = (request: CallRequest | null) => void;
let request: CallRequest | null = null;
const listeners = new Set<Listener>();

export function requestCall(next: CallRequest): void {
  request = next;
  listeners.forEach((listener) => listener(request));
}

export function consumeCall(): CallRequest | null {
  const current = request;
  request = null;
  listeners.forEach((listener) => listener(request));
  return current;
}

export function subscribeCall(listener: Listener): () => void {
  listeners.add(listener);
  listener(request);
  return () => listeners.delete(listener);
}

export function getPendingCall(): CallRequest | null {
  return request;
}
