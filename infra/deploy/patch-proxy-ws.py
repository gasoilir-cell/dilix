#!/usr/bin/env python3
"""
وصلهٔ idempotent برای پروکسیِ معکوسِ پلتفرم: مسیریابیِ ارتقاءِ WebSocket بر اساسِ
پیشوندِ مسیر.

چرا لازم است: مرورگر `wss://dilix.ir/api/v1/ws` را صدا می‌زند. پروکسی ارتقاء را
بر اساسِ Host به Nextِ :3003 می‌فرستد، ولی **rewriteهای Next ارتقاءِ WebSocket را
عبور نمی‌دهند** و اتصال همان‌جا می‌میرد. این وصله فقط برای مسیرهای اعلام‌شده در
`ws-routes.json` مقصد را عوض می‌کند.

ایمنی: کاملاً افزایشی است. اگر `ws-routes.json` نباشد `getWsBackend` همیشه null
می‌دهد و رفتار **دقیقاً** مثلِ قبل است. اجرای دوباره no-op است.

    python3 patch-proxy-ws.py /var/www/proxy/server.js
"""
import sys

WS_HELPERS = """

// ─── قواعدِ اختیاریِ WebSocket (بر اساسِ پیشوندِ مسیر) ─────────────
// نبودِ فایلِ ws-routes.json ⇒ رفتارِ پروکسی دقیقاً مثلِ قبل. فقط برای موردی است
// که ارتقاءِ WS نباید به بک‌اندِ پیش‌فرضِ همان دامنه برود (مثلاً Next که WS رد نمی‌کند).
const WS_CONFIG_FILE = path.join(__dirname, 'ws-routes.json');
let wsRoutes = loadWsRoutes();
setInterval(() => { wsRoutes = loadWsRoutes(); }, 10_000);

function loadWsRoutes() {
  try {
    return JSON.parse(fs.readFileSync(WS_CONFIG_FILE, 'utf8'));
  } catch {
    return {};
  }
}

function getWsBackend(host, url) {
  if (!host || !url) return null;
  const domain = host.split(':')[0].toLowerCase().replace(/^www\\./, '');
  const rules = wsRoutes[domain];
  if (!Array.isArray(rules)) return null;
  for (const rule of rules) {
    if (rule && typeof rule.prefix === 'string' && url.startsWith(rule.prefix)) {
      return rule.target;
    }
  }
  return null;
}"""

ANCHOR_LOAD = """let routes = loadRoutes();
setInterval(() => { routes = loadRoutes(); }, 10_000);"""

ANCHOR_UPGRADE = """  const host    = req.headers['host'] || '';
  const backend = getBackend(host);
  if (!backend) { socket.destroy(); return; }"""

REPLACE_UPGRADE = """  const host    = req.headers['host'] || '';
  const backend = getWsBackend(host, req.url) || getBackend(host);
  if (!backend) { socket.destroy(); return; }"""


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "/var/www/proxy/server.js"
    src = open(path, encoding="utf-8").read()

    if "ws-routes.json" in src:
        print("ALREADY_PATCHED")
        return 0

    if ANCHOR_LOAD not in src:
        print("ERROR: نقطهٔ اتصالِ بارگذاریِ routes پیدا نشد — وصله اعمال نشد")
        return 1
    if ANCHOR_UPGRADE not in src:
        print("ERROR: نقطهٔ اتصالِ handleUpgrade پیدا نشد — وصله اعمال نشد")
        return 1

    out = src.replace(ANCHOR_LOAD, ANCHOR_LOAD + WS_HELPERS, 1)
    out = out.replace(ANCHOR_UPGRADE, REPLACE_UPGRADE, 1)
    open(path, "w", encoding="utf-8").write(out)
    print("PATCHED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
