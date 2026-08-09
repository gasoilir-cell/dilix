/*
 * Dilix — Service Worker
 *
 * هدفِ این فایل «آفلاین‌کردنِ اپ» نیست؛ دیلیکس یک اپِ زندهٔ حسابداری و گفتگوست
 * و نشان‌دادنِ موجودیِ کیف یا پیامِ کهنه از خطای شبکه بدتر است. کاری که اینجا
 * انجام می‌شود دقیقاً دو چیز است:
 *   ۱) داراییِ ثابتِ نسخه‌دار (`/_next/static/…`) از کش بیاید تا بازکردنِ دوباره
 *      روی اینترنتِ ضعیفِ موبایل سریع باشد،
 *   ۲) وقتی شبکه قطع است، به‌جای صفحهٔ خطای مرورگر یک صفحهٔ فارسیِ خودمان
 *      نشان داده شود.
 *
 * ناوردای امنیتی/درستیِ داده — **هیچ پاسخِ APIای کش نمی‌شود.** مسیرهای
 * `/api/` و `/uploads/` کلاً از دستِ SW رد می‌شوند. اگر پاسخِ `/api/v1/wallet`
 * کش می‌شد، کاربرِ بعدی روی همان دستگاه می‌توانست موجودی و پیامِ نفرِ قبل را
 * ببیند و SW عملاً به یک نشتِ اطلاعاتی تبدیل می‌شد.
 */
const VERSION = "dilix-v1";
const STATIC_CACHE = `${VERSION}-static`;
const OFFLINE_URL = "/offline.html";

// مسیرهایی که SW اصلاً نباید به آن‌ها دست بزند.
const BYPASS = [/^\/api\//, /^\/uploads\//, /^\/_next\/image/, /^\/ws/];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(STATIC_CACHE).then((c) => c.addAll([OFFLINE_URL, "/manifest.json"]))
  );
  // بدونِ این، نسخهٔ تازه تا بستنِ همهٔ تب‌ها منتظر می‌مانَد و کاربر پس از
  // دیپلوی همچنان کدِ قدیمی را اجرا می‌کند.
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((k) => !k.startsWith(VERSION)).map((k) => caches.delete(k)))
      )
      .then(() => self.clients.claim())
  );
});

function isStaticAsset(url) {
  return (
    url.pathname.startsWith("/_next/static/") ||
    url.pathname.startsWith("/icons/") ||
    url.pathname.startsWith("/me-fonts/") ||
    url.pathname === "/favicon.ico" ||
    url.pathname === "/apple-touch-icon.png"
  );
}

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;

  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;   // فقط دامنهٔ خودمان
  if (BYPASS.some((re) => re.test(url.pathname))) return;
  // درخواستِ بازه‌ای (پخشِ ویدیو/صوت) را دست نمی‌زنیم؛ کشِ پاسخِ 206 خراب است.
  if (req.headers.has("range")) return;

  // ── داراییِ ثابت: cache-first ─────────────────────────────────────────────
  // نامِ فایل‌های `_next/static` هش دارد، پس «کهنه‌شدن» بی‌معناست؛ تغییرِ محتوا
  // یعنی تغییرِ URL.
  if (isStaticAsset(url)) {
    event.respondWith(
      caches.match(req).then(
        (hit) =>
          hit ||
          fetch(req).then((res) => {
            if (res.ok) {
              const copy = res.clone();
              caches.open(STATIC_CACHE).then((c) => c.put(req, copy));
            }
            return res;
          })
      )
    );
    return;
  }

  // ── ناوبری: network-first با پشتوانهٔ صفحهٔ آفلاین ─────────────────────────
  // HTML هرگز کش نمی‌شود؛ فقط وقتی شبکه شکست خورد صفحهٔ آفلاین می‌آید.
  if (req.mode === "navigate") {
    event.respondWith(
      fetch(req).catch(() => caches.match(OFFLINE_URL).then((r) => r || Response.error()))
    );
  }
});

// اجازهٔ فعال‌سازیِ فوریِ نسخهٔ تازه از سمتِ صفحه
self.addEventListener("message", (e) => {
  if (e.data === "SKIP_WAITING") self.skipWaiting();
});
