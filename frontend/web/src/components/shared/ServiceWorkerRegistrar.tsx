"use client";

import { useEffect } from "react";

/**
 * ثبتِ Service Worker — یک اثرِ جانبیِ محض، بدونِ هیچ خروجیِ بصری.
 *
 * چرا کامپوننت و نه یک `<script>` در layout؟ چون ثبت باید بعد از `load` انجام
 * شود: در لحظهٔ اولِ بارگذاری، دانلودِ SW با دانلودِ خودِ صفحه بر سرِ پهنای باند
 * رقابت می‌کند و اولین رندر را کند می‌کند — دقیقاً برعکسِ چیزی که SW برایش آمده.
 *
 * روی HTTP (به‌جز localhost) مرورگر `navigator.serviceWorker` را نمی‌دهد، پس
 * گاردِ `"serviceWorker" in navigator` هم پوششِ محیطِ توسعه است و هم پوششِ
 * مرورگرهای قدیمی.
 */
export default function ServiceWorkerRegistrar() {
  useEffect(() => {
    if (!("serviceWorker" in navigator)) return;

    const register = () => {
      navigator.serviceWorker.register("/sw.js").catch(() => {
        // شکستِ ثبت نباید چیزی را بشکند: اپ بدونِ SW کاملاً کار می‌کند.
      });
    };

    if (document.readyState === "complete") register();
    else {
      window.addEventListener("load", register);
      return () => window.removeEventListener("load", register);
    }
  }, []);

  return null;
}
