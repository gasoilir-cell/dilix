// دریافتِ توکنِ ورودِ اجتماعی در مرورگر.
// هر تابع SDK مربوطه را به‌صورتِ تنبل (lazy) بارگذاری می‌کند و توکنی برمی‌گرداند
// که سپس به بک‌اند (POST /v1/auth/oauth/{provider}) فرستاده می‌شود.
//
// Client IDها از متغیرهای محیطیِ NEXT_PUBLIC_* خوانده می‌شوند.

/* eslint-disable @typescript-eslint/no-explicit-any */

export class SocialAuthError extends Error {}

const env = (key: string): string => process.env[key] ?? "";

function loadScript(src: string): Promise<void> {
  return new Promise((resolve, reject) => {
    if (typeof document === "undefined") return reject(new SocialAuthError("بدونِ مرورگر"));
    const existing = document.querySelector<HTMLScriptElement>(`script[src="${src}"]`);
    if (existing) {
      if (existing.dataset.loaded === "1") return resolve();
      existing.addEventListener("load", () => resolve());
      existing.addEventListener("error", () => reject(new SocialAuthError(`بارگذاریِ ${src} ناموفق`)));
      return;
    }
    const s = document.createElement("script");
    s.src = src;
    s.async = true;
    s.defer = true;
    s.addEventListener("load", () => {
      s.dataset.loaded = "1";
      resolve();
    });
    s.addEventListener("error", () => reject(new SocialAuthError(`بارگذاریِ ${src} ناموفق`)));
    document.head.appendChild(s);
  });
}

function requireEnv(key: string, label: string): string {
  const v = env(key);
  if (!v) throw new SocialAuthError(`${label} پیکربندی نشده است (${key}).`);
  return v;
}

// ── Google Identity Services → id_token ──────────────────────────────────────
export async function getGoogleIdToken(): Promise<string> {
  const clientId = requireEnv("NEXT_PUBLIC_GOOGLE_CLIENT_ID", "ورود با Google");
  await loadScript("https://accounts.google.com/gsi/client");
  const google = (window as any).google;
  if (!google?.accounts?.id) throw new SocialAuthError("Google SDK در دسترس نیست.");
  return new Promise<string>((resolve, reject) => {
    google.accounts.id.initialize({
      client_id: clientId,
      callback: (resp: any) => {
        if (resp?.credential) resolve(resp.credential as string);
        else reject(new SocialAuthError("ورود با Google لغو شد."));
      },
    });
    google.accounts.id.prompt((notification: any) => {
      if (notification?.isNotDisplayed?.() || notification?.isSkippedMoment?.()) {
        reject(new SocialAuthError("پنجره‌ی ورودِ Google نمایش داده نشد."));
      }
    });
  });
}

// ── Microsoft (MSAL) → id_token ──────────────────────────────────────────────
export async function getMicrosoftIdToken(): Promise<string> {
  const clientId = requireEnv("NEXT_PUBLIC_MICROSOFT_CLIENT_ID", "ورود با Microsoft");
  const authority = env("NEXT_PUBLIC_MICROSOFT_AUTHORITY") || "https://login.microsoftonline.com/common";
  await loadScript("https://alcdn.msftauth.net/lib/1.4.18/js/msal-browser.min.js");
  const msal = (window as any).msal;
  if (!msal?.PublicClientApplication) throw new SocialAuthError("Microsoft SDK در دسترس نیست.");
  const app = new msal.PublicClientApplication({
    auth: { clientId, authority, redirectUri: window.location.origin },
  });
  await app.initialize?.();
  const result = await app.loginPopup({ scopes: ["openid", "email", "profile"] });
  if (!result?.idToken) throw new SocialAuthError("توکنِ Microsoft دریافت نشد.");
  return result.idToken as string;
}

// ── Apple (Sign in with Apple JS) → id_token ─────────────────────────────────
export async function getAppleIdToken(): Promise<string> {
  const clientId = requireEnv("NEXT_PUBLIC_APPLE_CLIENT_ID", "ورود با Apple");
  const redirectURI = env("NEXT_PUBLIC_APPLE_REDIRECT_URI") || window.location.origin;
  await loadScript(
    "https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js",
  );
  const AppleID = (window as any).AppleID;
  if (!AppleID?.auth) throw new SocialAuthError("Apple SDK در دسترس نیست.");
  AppleID.auth.init({ clientId, scope: "name email", redirectURI, usePopup: true });
  const resp = await AppleID.auth.signIn();
  const idToken = resp?.authorization?.id_token;
  if (!idToken) throw new SocialAuthError("توکنِ Apple دریافت نشد.");
  return idToken as string;
}

// ── Facebook SDK → access_token ──────────────────────────────────────────────
export async function getFacebookAccessToken(): Promise<string> {
  const appId = requireEnv("NEXT_PUBLIC_FACEBOOK_APP_ID", "ورود با Facebook");
  await loadScript("https://connect.facebook.net/en_US/sdk.js");
  const FB = (window as any).FB;
  if (!FB) throw new SocialAuthError("Facebook SDK در دسترس نیست.");
  FB.init({ appId, cookie: true, xfbml: false, version: "v19.0" });
  return new Promise<string>((resolve, reject) => {
    FB.login(
      (resp: any) => {
        const token = resp?.authResponse?.accessToken;
        if (token) resolve(token as string);
        else reject(new SocialAuthError("ورود با Facebook لغو شد."));
      },
      { scope: "public_profile,email" },
    );
  });
}

import type { OAuthProvider } from "@/lib/api";

export function getProviderCredential(provider: OAuthProvider): Promise<string> {
  switch (provider) {
    case "google":
      return getGoogleIdToken();
    case "microsoft":
      return getMicrosoftIdToken();
    case "apple":
      return getAppleIdToken();
    case "facebook":
      return getFacebookAccessToken();
  }
}
