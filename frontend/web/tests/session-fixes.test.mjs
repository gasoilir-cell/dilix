import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const read = (p) => readFileSync(new URL(p, import.meta.url), "utf8");
const api = read("../lib/api.ts");
const authPanel = read("../components/AuthPanel.tsx");
const home = read("../app/page.tsx");
const css = read("../app/globals.css");
const callManager = read("../components/CallManager.tsx");

test("session persists via refresh token and 401 auto-retry", () => {
  assert.match(api, /export function setSession/);
  assert.match(api, /export function getRefreshToken/);
  assert.match(api, /token\/refresh/);
  assert.match(api, /res\.status === 401/);
  assert.match(api, /tryRefresh/);
});

test("auth panel exposes only email login/register", () => {
  assert.match(authPanel, /emailLogin/);
  assert.match(authPanel, /emailRegister/);
  assert.match(authPanel, /setSession/);
  assert.doesNotMatch(authPanel, /SOCIAL_PROVIDERS/);
  assert.doesNotMatch(authPanel, /socialLogin/);
  assert.doesNotMatch(authPanel, /otpRequest/);
});

test("feed provides a comment composer", () => {
  assert.match(home, /submitComment/);
  assert.match(home, /api\.social\.comment/);
  assert.match(home, /نظر خود را بنویسید/);
});

test("call overlay uses a theme-aware token", () => {
  assert.match(css, /--color-overlay/);
  assert.match(css, /\.call-overlay[\s\S]*background: var\(--color-overlay\)/);
});

test("call manager buffers ICE candidates and survives transient drops", () => {
  assert.match(callManager, /pendingCandidatesRef/);
  assert.match(callManager, /flushPendingCandidates/);
  assert.doesNotMatch(callManager, /"failed", "closed", "disconnected"/);
});
