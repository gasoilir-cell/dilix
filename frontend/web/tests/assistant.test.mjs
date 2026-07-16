import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const api = readFileSync(new URL("../lib/api.ts", import.meta.url), "utf8");
const panel = readFileSync(new URL("../components/AssistantPanel.tsx", import.meta.url), "utf8");
const page = readFileSync(new URL("../app/assistant/page.tsx", import.meta.url), "utf8");

test("assistant api uses persisted conversation endpoints", () => {
  assert.match(api, /createConversation/);
  assert.match(api, /\/v1\/ai\/conversations/);
  assert.match(api, /\/history\?limit=/);
  assert.match(api, /\/chat`/);
});

test("assistant panel manages history, loading and error state", () => {
  assert.match(panel, /api\.ai\.conversations/);
  assert.match(panel, /api\.ai\.history/);
  assert.match(panel, /api\.ai\.chat/);
  assert.match(panel, /setLoading/);
  assert.match(panel, /setError/);
  assert.match(page, /AssistantPanel/);
});
