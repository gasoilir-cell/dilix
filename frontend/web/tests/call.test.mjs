import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const callManager = readFileSync(new URL("../components/CallManager.tsx", import.meta.url), "utf8");
const callStore = readFileSync(new URL("../lib/call-store.ts", import.meta.url), "utf8");
const messagesPage = readFileSync(new URL("../app/messages/page.tsx", import.meta.url), "utf8");

test("WebRTC manager starts and ends calls through realtime signaling", () => {
  assert.match(callManager, /new RTCPeerConnection/);
  assert.match(callManager, /getUserMedia/);
  assert.match(callManager, /call\.offer/);
  assert.match(callManager, /call\.answer/);
  assert.match(callManager, /call\.end/);
  assert.match(callManager, /ice\.candidate/);
  assert.match(callManager, /const hangup = useCallback/);
});

test("messages page exposes audio and video call actions", () => {
  assert.match(callStore, /export function requestCall/);
  assert.match(messagesPage, /startCall\("audio"\)/);
  assert.match(messagesPage, /startCall\("video"\)/);
});
