/**
 * Dilix — API Client
 * axios instance با interceptors برای JWT و refresh
 */
import axios, { AxiosError, AxiosInstance } from "axios";
import { useAuthStore } from "@/store/auth";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "";

const api: AxiosInstance = axios.create({
  baseURL: `${API_URL}/api/v1`,
  headers: {
    "Content-Type": "application/json",
    Accept: "application/json",
  },
  timeout: 30_000,
});

// ─── Request Interceptor — اضافه کردن Bearer Token ──────────
api.interceptors.request.use((config) => {
  const token = useAuthStore.getState().accessToken;
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// ─── Response Interceptor — refresh token خودکار ────────────
let isRefreshing = false;
let refreshQueue: Array<(token: string) => void> = [];

api.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    const original = error.config as any;

    if (error.response?.status === 401 && !original._retry) {
      const refreshToken = useAuthStore.getState().refreshToken;

      if (!refreshToken) {
        useAuthStore.getState().logout();
        return Promise.reject(error);
      }

      if (isRefreshing) {
        return new Promise((resolve) => {
          refreshQueue.push((token: string) => {
            original.headers.Authorization = `Bearer ${token}`;
            resolve(api(original));
          });
        });
      }

      original._retry = true;
      isRefreshing = true;

      try {
        const { data } = await axios.post(
          `${API_URL}/api/v1/auth/refresh`,
          { refresh_token: refreshToken }
        );

        const newToken = data.access_token;
        useAuthStore.getState().setTokens(newToken, data.refresh_token);

        refreshQueue.forEach((cb) => cb(newToken));
        refreshQueue = [];

        original.headers.Authorization = `Bearer ${newToken}`;
        return api(original);
      } catch (refreshErr) {
        refreshQueue = [];
        // فقط وقتی refresh token واقعاً نامعتبر است logout کن.
        // خطای شبکه/تایم‌اوت (به‌ویژه حین تماسِ تصویریِ پرترافیک) نباید کاربر را
        // به صفحهٔ ورود پرتاب کند؛ در این حالت اجازه می‌دهیم درخواستِ بعدی دوباره refresh کند.
        const re = refreshErr as AxiosError;
        if (re.response && [400, 401, 403].includes(re.response.status)) {
          useAuthStore.getState().logout();
        }
        return Promise.reject(error);
      } finally {
        isRefreshing = false;
      }
    }

    return Promise.reject(error);
  }
);

// ─── Auth API ────────────────────────────────────────────────
export const authApi = {
  sendOTP: (phone: string, purpose = "login") =>
    api.post("/auth/otp/send", { phone, purpose }),

  verifyOTP: (phone: string, otp: string) =>
    api.post("/auth/otp/verify", { phone, otp }),

  refreshToken: (refresh_token: string) =>
    api.post("/auth/refresh", { refresh_token }),

  oauthLogin: (provider: string, credential: string) =>
    api.post(`/auth/oauth/${provider}`, { credential }),

  register: (identifier: string, password: string, full_name: string) =>
    api.post("/auth/register", { identifier, password, full_name }),

  loginPassword: (identifier: string, password: string) =>
    api.post("/auth/login", { identifier, password }),

  getMe: () => api.get("/auth/me"),

  updateProfile: (data: {
    full_name?: string;
    username?: string;
    bio?: string;
    locale?: string;
    privacy_on_map?: boolean;
    role?: string;
  }) => api.patch("/auth/me", data),
};

// ─── Wallet API ───────────────────────────────────────────────
export const walletApi = {
  get: () => api.get("/wallet/"),
  transactions: (page = 1) => api.get(`/wallet/transactions?page=${page}`),
  transfer: (to_earth_id: string, amount: number, description?: string) =>
    api.post("/wallet/transfer", { to_earth_id, amount, description }),
};

// ─── Payment API ──────────────────────────────────────────────
export const paymentApi = {
  initiate: (amount: number, currency = "IRR", description = "شارژ کیف پول") =>
    api.post("/payment/initiate", { amount, currency, description }),
  verify: (authority: string, amount: number, currency = "IRR") =>
    api.post("/payment/verify", { authority, amount, currency }),
};

// ─── Earth API ────────────────────────────────────────────────
export const earthApi = {
  getUsers: (params?: { type?: string; country?: string; limit?: number }) =>
    api.get("/earth/users", { params }),
  updateLocation: (data: { lat: number; lng: number; accuracy?: number }) =>
    api.post("/earth/location", data),
};

// ─── Freight API ──────────────────────────────────────────────
export const freightApi = {
  list: (mine = false) => api.get(`/freight/posts?mine=${mine}`),
  get: (id: string) => api.get(`/freight/posts/${id}`),
  create: (data: {
    origin: string; destination: string;
    origin_lat?: number; origin_lng?: number;
    dest_lat?: number; dest_lng?: number;
    cargo_type: string; weight_kg: number;
    price: number; description?: string; pickup_date?: string;
  }) => api.post("/freight/posts", data),
  take: (id: string) => api.post(`/freight/posts/${id}/take`),
  deliver: (id: string) => api.put(`/freight/posts/${id}/deliver`),
  cancel: (id: string) => api.delete(`/freight/posts/${id}`),
};

// ─── Messages API ─────────────────────────────────────────────
export const messagesApi = {
  listRooms: () => api.get("/messages/rooms"),
  startRoom: (earth_id: string) => api.post("/messages/rooms", { earth_id }),
  getMessages: (roomId: string, limit = 50) =>
    api.get(`/messages/rooms/${roomId}/messages?limit=${limit}`),
  send: (roomId: string, content: string, replyToId?: string | null) =>
    api.post(`/messages/rooms/${roomId}/messages`, {
      content,
      ...(replyToId ? { reply_to_id: replyToId } : {}),
    }),
  sendMedia: (
    roomId: string,
    file: File | Blob,
    opts?: { caption?: string; replyToId?: string | null; filename?: string }
  ) => {
    const fd = new FormData();
    fd.append("file", file, opts?.filename);
    if (opts?.caption) fd.append("caption", opts.caption);
    if (opts?.replyToId) fd.append("reply_to_id", opts.replyToId);
    return api.post(`/messages/rooms/${roomId}/media`, fd, {
      headers: { "Content-Type": "multipart/form-data" },
      timeout: 60_000,
    });
  },
  sendLocation: (
    roomId: string,
    p: { lat: number; lng: number; label?: string; replyToId?: string | null }
  ) =>
    api.post(`/messages/rooms/${roomId}/location`, {
      lat: p.lat, lng: p.lng,
      ...(p.label ? { label: p.label } : {}),
      ...(p.replyToId ? { reply_to_id: p.replyToId } : {}),
    }),
  startLiveLocation: (
    roomId: string,
    p: { lat: number; lng: number; durationMinutes: number; replyToId?: string | null }
  ) =>
    api.post(`/messages/rooms/${roomId}/live-location`, {
      lat: p.lat, lng: p.lng, duration_minutes: p.durationMinutes,
      ...(p.replyToId ? { reply_to_id: p.replyToId } : {}),
    }),
  updateLiveLocation: (messageId: string, lat: number, lng: number) =>
    api.patch(`/messages/live-location/${messageId}`, { lat, lng }),
  stopLiveLocation: (messageId: string) =>
    api.post(`/messages/live-location/${messageId}/stop`),
  edit: (messageId: string, content: string) =>
    api.patch(`/messages/messages/${messageId}`, { content }),
  remove: (messageId: string) => api.delete(`/messages/messages/${messageId}`),
  react: (messageId: string, emoji: string) =>
    api.post(`/messages/messages/${messageId}/react`, { emoji }),
  forward: (messageId: string, roomId: string, anonymous: boolean) =>
    api.post(`/messages/messages/${messageId}/forward`, { room_id: roomId, anonymous }),
  searchMessages: (roomId: string, q: string) =>
    api.get(`/messages/rooms/${roomId}/messages/search`, { params: { q } }),
  markRead: (roomId: string) => api.post(`/messages/rooms/${roomId}/read`),
  roomStatus: (roomId: string) => api.get(`/messages/rooms/${roomId}/status`),
  setTyping: (roomId: string) => api.post(`/messages/rooms/${roomId}/typing`),
  pin: (messageId: string) => api.post(`/messages/messages/${messageId}/pin`),
  pins: (roomId: string) => api.get(`/messages/rooms/${roomId}/pins`),
  createPoll: (roomId: string, question: string, options: string[], multiple: boolean, replyToId?: string | null) =>
    api.post(`/messages/rooms/${roomId}/poll`, {
      question, options, multiple,
      ...(replyToId ? { reply_to_id: replyToId } : {}),
    }),
  votePoll: (pollId: string, optionIndex: number) =>
    api.post(`/messages/polls/${pollId}/vote`, { option_index: optionIndex }),
  createGroup: (name: string, memberEarthIds: string[]) =>
    api.post("/messages/groups", { name, member_earth_ids: memberEarthIds }),
  members: (roomId: string) => api.get(`/messages/rooms/${roomId}/members`),
  addMember: (roomId: string, earth_id: string) =>
    api.post(`/messages/rooms/${roomId}/members`, { earth_id }),
  removeMember: (roomId: string, earthId: string) =>
    api.delete(`/messages/rooms/${roomId}/members/${earthId}`),
  translateMessage: (messageId: string, targetLang: string) =>
    api.post(`/messages/messages/${messageId}/translate`, { target_lang: targetLang }),
  translateText: (text: string, targetLang: string) =>
    api.post(`/messages/translate`, { text, target_lang: targetLang }),
  sendSticker: (roomId: string, stickerId: string, replyToId?: string | null) =>
    api.post(`/messages/rooms/${roomId}/sticker`, {
      sticker_id: stickerId,
      ...(replyToId ? { reply_to_id: replyToId } : {}),
    }),
  blockUser: (earthId: string) => api.post(`/messages/users/${earthId}/block`),
  getBlocks: () => api.get(`/messages/blocks`),
  muteRoom: (roomId: string, muted: boolean, durationMinutes?: number | null) =>
    api.post(`/messages/rooms/${roomId}/mute`, {
      muted,
      ...(durationMinutes ? { duration_minutes: durationMinutes } : {}),
    }),
  clearChat: (roomId: string) => api.post(`/messages/rooms/${roomId}/clear`),
};

// ─── Sticker / Emoji Library API ──────────────────────────────
export const stickersApi = {
  createPack: (title: string, description?: string, isPublic = false) =>
    api.post("/stickers/packs", { title, description, is_public: isPublic }),
  updatePack: (packId: string, body: { title?: string; description?: string; is_public?: boolean }) =>
    api.patch(`/stickers/packs/${packId}`, body),
  deletePack: (packId: string) => api.delete(`/stickers/packs/${packId}`),
  myPacks: () => api.get("/stickers/packs/mine"),
  installedPacks: () => api.get("/stickers/packs/installed"),
  publicPacks: (q?: string) =>
    api.get("/stickers/packs/public", { params: q ? { q } : {} }),
  packDetail: (packId: string) => api.get(`/stickers/packs/${packId}`),
  install: (packId: string) => api.post(`/stickers/packs/${packId}/install`),
  uninstall: (packId: string) => api.delete(`/stickers/packs/${packId}/install`),
  addSticker: (packId: string, file: File | Blob, opts?: { emojiTag?: string; title?: string; filename?: string }) => {
    const fd = new FormData();
    fd.append("file", file, opts?.filename ?? "sticker.png");
    if (opts?.emojiTag) fd.append("emoji_tag", opts.emojiTag);
    if (opts?.title) fd.append("title", opts.title);
    return api.post(`/stickers/packs/${packId}/stickers`, fd, {
      headers: { "Content-Type": "multipart/form-data" },
      timeout: 60_000,
    });
  },
  deleteSticker: (stickerId: string) => api.delete(`/stickers/${stickerId}`),
  getSticker: (stickerId: string) => api.get(`/stickers/${stickerId}`),
  starred: () => api.get("/stickers/starred"),
  star: (stickerId: string) => api.post(`/stickers/${stickerId}/star`),
  unstar: (stickerId: string) => api.delete(`/stickers/${stickerId}/star`),
};

// ─── Calls API (WebRTC signaling — HTTP/Redis poll) ───────────
export const callsApi = {
  iceServers: () => api.get("/calls/ice-servers"),
  invite: (toEarthId: string, media: "audio" | "video", sdp: string, callId?: string) =>
    api.post("/calls/invite", { to_earth_id: toEarthId, media, sdp, call_id: callId }),
  signal: (p: { callId: string; toEarthId: string; type: string; sdp?: string; candidate?: unknown; text?: string; lang?: string }) =>
    api.post("/calls/signal", {
      call_id: p.callId, to_earth_id: p.toEarthId, type: p.type,
      ...(p.sdp ? { sdp: p.sdp } : {}),
      ...(p.candidate ? { candidate: p.candidate } : {}),
      ...(p.text ? { text: p.text } : {}),
      ...(p.lang ? { lang: p.lang } : {}),
    }),
  poll: () => api.get("/calls/poll"),
  callLog: (toEarthId: string, media: "audio" | "video", status: string, durationSeconds: number) =>
    api.post("/calls/call-log", { to_earth_id: toEarthId, media, status, duration_seconds: durationSeconds }),
};

// ─── Health API ───────────────────────────────────────────────
export const healthApi = {
  check: () => api.get("/health"),
};


export const referralApi = {
  stats: () => api.get("/referral/stats"),
  apply: (ref_code: string) => api.post("/referral/apply", { ref_code }),
};

// ─── Social Graph API (Follow) ────────────────────────────────
export const socialApi = {
  profile: (earthId: string) => api.get(`/social/profile/${earthId}`),
  follow: (earth_id: string) => api.post("/social/follow", { earth_id }),
  unfollow: (earthId: string) => api.delete(`/social/follow/${earthId}`),
  followers: (earthId: string) => api.get(`/social/followers/${earthId}`),
  following: (earthId: string) => api.get(`/social/following/${earthId}`),
  suggestions: () => api.get("/social/suggestions"),
  search: (q: string) => api.get(`/social/search?q=${encodeURIComponent(q)}`),
};


// ─── Stories API (داستان ۲۴ساعته) ────────────────
export const storiesApi = {
  feed: () => api.get("/stories/feed"),
  userStories: (earthId: string) => api.get(`/stories/user/${earthId}`),
  create: (file: File | Blob, caption?: string, filename?: string, audience?: string) => {
    const fd = new FormData();
    fd.append("file", file, filename ?? "story.jpg");
    if (caption) fd.append("caption", caption);
    if (audience) fd.append("audience", audience);
    return api.post("/stories", fd, {
      headers: { "Content-Type": "multipart/form-data" },
      timeout: 90_000,
    });
  },
  view: (storyId: string) => api.post(`/stories/${storyId}/view`),
  viewers: (storyId: string) => api.get(`/stories/${storyId}/viewers`),
  remove: (storyId: string) => api.delete(`/stories/${storyId}`),
  // تنظیماتِ مخاطبِ پیش‌فرضِ استوری
  settings: () => api.get("/stories/settings"),
  saveSettings: (default_audience: string) =>
    api.put("/stories/settings", { default_audience }),
  // حلقه‌های مخاطب (همکاران/خانواده/دوستان)
  circles: () => api.get("/stories/circles"),
  addToCircle: (circle: string, earth_id: string) =>
    api.post(`/stories/circles/${circle}`, { earth_id }),
  removeFromCircle: (circle: string, earthId: string) =>
    api.delete(`/stories/circles/${circle}/${earthId}`),
};

// ─── Reels API (ویدیوهای کوتاهِ عمودی) ────────────────
export const reelsApi = {
  feed: (cursor?: string, limit = 8) =>
    api.get(`/reels/feed`, { params: { cursor, limit } }),
  userReels: (earthId: string) => api.get(`/reels/user/${earthId}`),
  create: (file: File | Blob, caption?: string, filename?: string) => {
    const fd = new FormData();
    fd.append("file", file, filename ?? "reel.webm");
    if (caption) fd.append("caption", caption);
    return api.post("/reels", fd, {
      headers: { "Content-Type": "multipart/form-data" },
      timeout: 120_000,
    });
  },
  view: (id: string) => api.post(`/reels/${id}/view`),
  like: (id: string) => api.post(`/reels/${id}/like`),
  comments: (id: string) => api.get(`/reels/${id}/comments`),
  addComment: (id: string, body: string) => {
    const fd = new FormData();
    fd.append("body", body);
    return api.post(`/reels/${id}/comments`, fd, {
      headers: { "Content-Type": "multipart/form-data" },
    });
  },
  removeComment: (cid: string) => api.delete(`/reels/comments/${cid}`),
  remove: (id: string) => api.delete(`/reels/${id}`),
};

// ─── Posts API (فیدِ اجتماعی) ────────────────
export const postsApi = {
  feed: (cursor?: string, limit = 8) => api.get(`/posts/feed`, { params: { cursor, limit } }),
  explore: (cursor?: string, limit = 12) => api.get(`/posts/explore`, { params: { cursor, limit } }),
  saved: () => api.get(`/posts/saved`),
  userPosts: (earthId: string) => api.get(`/posts/user/${earthId}`),
  get: (id: string) => api.get(`/posts/${id}`),
  create: (file: File | Blob, caption?: string, filename?: string) => {
    const fd = new FormData();
    fd.append("file", file, filename ?? "post.jpg");
    if (caption) fd.append("caption", caption);
    return api.post("/posts", fd, {
      headers: { "Content-Type": "multipart/form-data" },
      timeout: 120_000,
    });
  },
  like: (id: string) => api.post(`/posts/${id}/like`),
  save: (id: string) => api.post(`/posts/${id}/save`),
  comments: (id: string) => api.get(`/posts/${id}/comments`),
  addComment: (id: string, body: string) => {
    const fd = new FormData();
    fd.append("body", body);
    return api.post(`/posts/${id}/comments`, fd, {
      headers: { "Content-Type": "multipart/form-data" },
    });
  },
  removeComment: (cid: string) => api.delete(`/posts/comments/${cid}`),
  remove: (id: string) => api.delete(`/posts/${id}`),
};

// ─── Error message helper ─────────────────────────────────────
// FastAPI خطاهای اعتبارسنجی را به شکل detail: Array<{type,loc,msg,input,ctx}>
// یا detail: string برمی‌گرداند. رندر مستقیم این آبجکت‌ها در React باعث
// خطای «Objects are not valid as a React child» (#31) و کرش کل اپ می‌شود.
// این تابع همیشه یک رشتهٔ امن برمی‌گرداند.
export function getApiErrorMessage(err: unknown, fallback = "خطایی رخ داد"): string {
  const clean = (t: string) =>
    t.replace(/^\s*value\s+error[,:]?\s*/i, "").trim();
  const detail = (err as { response?: { data?: { detail?: unknown } } })?.response
    ?.data?.detail;
  const fromItem = (it: unknown): string | null => {
    if (typeof it === "string") return it;
    if (it && typeof it === "object") {
      const m = (it as { msg?: unknown; message?: unknown }).msg ??
        (it as { message?: unknown }).message;
      if (typeof m === "string") return m;
    }
    return null;
  };
  if (typeof detail === "string" && detail.trim()) return clean(detail);
  if (Array.isArray(detail)) {
    const msgs = detail.map(fromItem).filter(Boolean) as string[];
    if (msgs.length) return msgs.map(clean).join("، ");
  }
  const single = fromItem(detail);
  if (single) return clean(single);
  return fallback;
}

export default api;
