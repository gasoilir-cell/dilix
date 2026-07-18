import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const read = (p) => readFileSync(new URL(p, import.meta.url), "utf8");
const api = read("../lib/api.ts");
const page = read("../app/services/marketplace/page.tsx");

test("marketplace api exposes the full order lifecycle", () => {
  assert.match(api, /interface OrderOut/);
  assert.match(api, /placeOrder:/);
  assert.match(api, /listOrders:/);
  assert.match(api, /acceptOrder:/);
  assert.match(api, /deliverOrder:/);
  assert.match(api, /completeOrder:/);
  assert.match(api, /\/v1\/marketplace\/orders/);
});

test("marketplace page renders listings from api and handles empty/error state", () => {
  assert.match(page, /api\.marketplace\.listListings/);
  assert.match(page, /listings\.map/);
  assert.match(page, /setError/);
  assert.match(page, /خدمتی ثبت نشده است/);
  assert.match(page, /در حال بارگذاری/);
});

test("marketplace page wires the order flow and my-orders tab", () => {
  assert.match(page, /api\.marketplace\.placeOrder/);
  assert.match(page, /api\.marketplace\.listOrders/);
  assert.match(page, /سفارش‌های من/);
  assert.match(page, /orderActions/);
  assert.match(page, /acceptOrder|deliverOrder|completeOrder/);
});

test("marketplace page uses only existing css primitives", () => {
  assert.match(page, /className="card"/);
  assert.match(page, /className="badge"/);
  assert.match(page, /className="row-between"/);
  assert.doesNotMatch(page, /from "react-query"/);
  assert.doesNotMatch(page, /from "axios"/);
});
