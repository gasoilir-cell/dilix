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

  // ─── KYC (تأیید هویت — سطحِ ۲: مدارکِ هویتی) ───
  kycStatus: () => api.get("/auth/me/kyc"),
  submitKyc: (p: {
    national_id: string;
    full_name: string;
    date_of_birth: string;
    front: File | Blob;
    selfie: File | Blob;
  }) => {
    const fd = new FormData();
    fd.append("national_id", p.national_id);
    fd.append("full_name", p.full_name);
    fd.append("date_of_birth", p.date_of_birth);
    fd.append("front", p.front, "id_front.jpg");
    fd.append("selfie", p.selfie, "selfie.jpg");
    return api.post("/auth/me/kyc", fd, {
      headers: { "Content-Type": "multipart/form-data" },
      timeout: 90_000,
    });
  },

  // ─── KYC admin (بررسیِ صفِ درخواست‌ها) ───
  adminKycList: (status = "pending") =>
    api.get("/auth/admin/kyc", { params: { status } }),
  adminKycReview: (reqId: string, approve: boolean, note?: string) => {
    const fd = new FormData();
    fd.append("approve", approve ? "true" : "false");
    if (note) fd.append("note", note);
    return api.post(`/auth/admin/kyc/${reqId}/review`, fd, {
      headers: { "Content-Type": "multipart/form-data" },
    });
  },
};

// ─── Wallet API ───────────────────────────────────────────────
export const walletApi = {
  get: () => api.get("/wallet/"),
  transactions: (page = 1) => api.get(`/wallet/transactions?page=${page}`),
  transfer: (to_earth_id: string, amount: number, description?: string) =>
    api.post("/wallet/transfer", { to_earth_id, amount, description }),

  // ─── پرداختِ QR ───
  // مبلغ همه‌جا **ریال** است (واحدِ خردِ کیف)؛ تبدیل به تومان کارِ UI است.
  qrPayload: (amount?: number, note?: string) =>
    api.get("/wallet/qr/payload", { params: { amount, note } }),
  // بازگشاییِ بارِ اسکن‌شده پیش از کسرِ پول: سرور دامنه و شناسه را اعتبارسنجی
  // می‌کند و نام/آواتارِ گیرنده را می‌دهد تا کاربر مقصد را ببیند.
  qrResolve: (payload: string) => api.post("/wallet/qr/resolve", { payload }),
  // SVGِ کدِ «به من پرداخت کن». مسیر احراز می‌خواهد، پس نمی‌شود آن را در `src`ِ
  // یک <img> گذاشت؛ متن را می‌گیریم و خودمان رندر می‌کنیم.
  // `transformResponse` لازم است چون تبدیلِ پیش‌فرضِ axios روی متن JSON.parse
  // امتحان می‌کند و برای بارهای مرزی می‌تواند رشته را عوض کند.
  qrSvg: (amount?: number, note?: string) =>
    api.get<string>("/wallet/qr", {
      params: { amount, note },
      responseType: "text",
      headers: { Accept: "image/svg+xml" },
      transformResponse: (d) => d,
    }),
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
  createRedPacket: (
    roomId: string,
    p: { total_amount: number; count: number; mode: "equal" | "random"; greeting?: string; replyToId?: string | null }
  ) =>
    api.post(`/messages/rooms/${roomId}/red-packet`, {
      total_amount: p.total_amount, count: p.count, mode: p.mode,
      ...(p.greeting ? { greeting: p.greeting } : {}),
      ...(p.replyToId ? { reply_to_id: p.replyToId } : {}),
    }),
  openRedPacket: (packetId: string) =>
    api.post(`/messages/red-packets/${packetId}/open`),
  getRedPacket: (packetId: string) =>
    api.get(`/messages/red-packets/${packetId}`),
  // 💸 پولِ درون‌چت — مبلغ در واحدِ خرد (ریال) فرستاده می‌شود، نه تومان.
  sendMoney: (roomId: string, amount: number, note?: string, replyToId?: string | null) =>
    api.post(`/messages/rooms/${roomId}/money`, {
      amount,
      ...(note ? { note } : {}),
      ...(replyToId ? { reply_to_id: replyToId } : {}),
    }),
  requestMoney: (roomId: string, amount: number, note?: string, replyToId?: string | null) =>
    api.post(`/messages/rooms/${roomId}/money-request`, {
      amount,
      ...(note ? { note } : {}),
      ...(replyToId ? { reply_to_id: replyToId } : {}),
    }),
  payMoneyRequest: (moneyId: string) =>
    api.post(`/messages/money-requests/${moneyId}/pay`),
  declineMoneyRequest: (moneyId: string) =>
    api.post(`/messages/money-requests/${moneyId}/decline`),
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
  shareContact: (roomId: string, earth_id: string, replyToId?: string | null) =>
    api.post(`/messages/rooms/${roomId}/contact`, {
      earth_id,
      ...(replyToId ? { reply_to_id: replyToId } : {}),
    }),
  createEvent: (
    roomId: string,
    p: { title: string; starts_at: string; location?: string; description?: string; replyToId?: string | null }
  ) =>
    api.post(`/messages/rooms/${roomId}/event`, {
      title: p.title,
      starts_at: p.starts_at,
      ...(p.location ? { location: p.location } : {}),
      ...(p.description ? { description: p.description } : {}),
      ...(p.replyToId ? { reply_to_id: p.replyToId } : {}),
    }),
  setDisappearing: (roomId: string, seconds: number) =>
    api.post(`/messages/rooms/${roomId}/disappearing`, { seconds }),
  reportUser: (
    earthId: string,
    p: { reason: string; note?: string; message_id?: string }
  ) =>
    api.post(`/messages/users/${earthId}/report`, {
      reason: p.reason,
      ...(p.note ? { note: p.note } : {}),
      ...(p.message_id ? { message_id: p.message_id } : {}),
    }),
};

// ─── Sticker / Emoji Library API ──────────────────────────────
export const stickersApi = {
  createPack: (title: string, description?: string, isPublic = false, price = 0) =>
    api.post("/stickers/packs", { title, description, is_public: isPublic, price }),
  updatePack: (packId: string, body: { title?: string; description?: string; is_public?: boolean; price?: number }) =>
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
  // بازارِ استیکر (فاز ۵)
  market: (params?: { q?: string; kind?: "all" | "paid" | "free"; limit?: number; offset?: number }) =>
    api.get("/stickers/market", { params }),
  purchase: (packId: string) => api.post(`/stickers/packs/${packId}/purchase`),
  purchases: () => api.get("/stickers/purchases"),
  sales: () => api.get("/stickers/sales"),
};

// ─── Gamification API (امتیاز، نشان، streak، تابلوی رتبه — فاز ۵) ──
export const gamificationApi = {
  me: () => api.get("/gamification/me"),
  checkIn: () => api.post("/gamification/check-in"),
  badges: () => api.get("/gamification/badges"),
  sync: () => api.post("/gamification/sync"),
  history: (limit = 50) => api.get("/gamification/history", { params: { limit } }),
  leaderboard: (period: "all" | "week" = "all", limit = 20) =>
    api.get("/gamification/leaderboard", { params: { period, limit } }),
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

// ─── Live API (پخشِ زندهٔ ویدیویی ۱-به-چند) ────────────────────
export const liveApi = {
  list: (limit = 30) => api.get("/live", { params: { limit } }),
  start: (title?: string) => api.post("/live/start", { title }),
  join: (id: string) => api.post(`/live/${id}/join`),
  leave: (id: string) => api.post(`/live/${id}/leave`),
  state: (id: string) => api.get(`/live/${id}/state`),
  stop: (id: string) => api.post(`/live/${id}/stop`),
  chat: (id: string, text: string) => api.post(`/live/${id}/chat`, { text }),
  messages: (id: string, limit = 50) => api.get(`/live/${id}/messages`, { params: { limit } }),
  heart: (id: string, count = 1) => api.post(`/live/${id}/heart`, { count }),
  poll: () => api.get("/live/poll"),
  signal: (p: { sessionId: string; toEarthId: string; type: string; sdp?: string; candidate?: unknown }) =>
    api.post("/live/signal", {
      session_id: p.sessionId, to_earth_id: p.toEarthId, type: p.type,
      ...(p.sdp ? { sdp: p.sdp } : {}),
      ...(p.candidate ? { candidate: p.candidate } : {}),
    }),
};

// ─── Health API ───────────────────────────────────────────────
export const healthApi = {
  check: () => api.get("/health"),
};


export const referralApi = {
  stats: () => api.get("/referral/stats"),
  apply: (ref_code: string) => api.post("/referral/apply", { ref_code }),
  network: () => api.get("/referral/network"),
  commissions: () => api.get("/referral/commissions"),
  // QRِ دعوت — SVG است، پس باید به‌شکلِ blob گرفته شود نه JSON.
  qr: () => api.get("/referral/qr", { responseType: "blob" }),
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

// ─── Story Highlights (مجموعهٔ ماندگارِ داستان‌ها روی پروفایل) ───
export const highlightsApi = {
  list: (earthId: string) => api.get(`/stories/highlights/user/${earthId}`),
  get: (id: string) => api.get(`/stories/highlights/${id}`),
  create: (title: string, story_ids: string[], cover_url?: string) =>
    api.post("/stories/highlights", { title, story_ids, cover_url }),
  update: (id: string, data: { title?: string; cover_url?: string }) =>
    api.patch(`/stories/highlights/${id}`, data),
  addItems: (id: string, story_ids: string[]) =>
    api.post(`/stories/highlights/${id}/items`, { story_ids }),
  removeItem: (id: string, itemId: string) =>
    api.delete(`/stories/highlights/${id}/items/${itemId}`),
  remove: (id: string) => api.delete(`/stories/highlights/${id}`),
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
  interests: (cursor?: string, limit = 12) => api.get(`/posts/interests`, { params: { cursor, limit } }),
  topics: (limit = 20) => api.get(`/posts/topics`, { params: { limit } }),
  topicFeed: (tag: string, cursor?: string, limit = 12) =>
    api.get(`/posts/topic/${encodeURIComponent(tag)}`, { params: { cursor, limit } }),
  search: (q: string, cursor?: string, limit = 12) => api.get(`/posts/search`, { params: { q, cursor, limit } }),
  saved: () => api.get(`/posts/saved`),
  userPosts: (earthId: string) => api.get(`/posts/user/${earthId}`),
  moments: (bbox?: { min_lat: number; max_lat: number; min_lng: number; max_lng: number }, limit = 200) =>
    api.get(`/posts/moments`, { params: { ...(bbox ?? {}), limit } }),
  get: (id: string) => api.get(`/posts/${id}`),
  create: (
    file: File | Blob,
    caption?: string,
    filename?: string,
    loc?: { lat: number; lng: number; place_name?: string },
  ) => {
    const fd = new FormData();
    fd.append("file", file, filename ?? "post.jpg");
    if (caption) fd.append("caption", caption);
    if (loc) {
      fd.append("lat", String(loc.lat));
      fd.append("lng", String(loc.lng));
      if (loc.place_name) fd.append("place_name", loc.place_name);
    }
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

// ─── i18n / Globalization (زبان/ارز/تشخیصِ خودکار + ترجیحاتِ کاربر) ──────
export const i18nApi = {
  catalog: () => api.get("/i18n/catalog"),
  detect: () => api.get("/i18n/detect"),
  getPreferences: () => api.get("/i18n/preferences"),
  setPreferences: (p: {
    locale?: string;
    currency?: string;
    country_code?: string;
    timezone?: string;
  }) => api.put("/i18n/preferences", p),
};

// ─── Paygate API (درگاه‌های پرداختِ pluggable + شارژِ کیف‌پول) ──
export const paygateApi = {
  gateways: (params?: { currency?: string; country?: string }) =>
    api.get("/paygate/gateways", { params }),
  initiate: (
    gateway_code: string,
    amount: number,
    currency?: string,
    description?: string,
    credit_to?: string,
  ) =>
    api.post("/paygate/topup/initiate", { gateway_code, amount, currency, description, credit_to }),
  verify: (intent_id: string, authority?: string) =>
    api.post("/paygate/topup/verify", { intent_id, authority }),
  intent: (id: string) => api.get(`/paygate/intents/${id}`),
};

// ─── FX API (نرخِ ارز + تبدیلِ بین‌ارزی) ───────────────────────
export const fxApi = {
  rates: () => api.get("/fx/rates"),
  quote: (amount: number, from_currency: string, to_currency: string) =>
    api.post("/fx/quote", { amount, from_currency, to_currency }),
};

// ─── Bills API (قبوض و خدماتِ شهری) ───────────────────────────
// مبلغ همیشه **ریال** برمی‌گردد (واحدِ خردِ کیف)؛ تبدیل به تومان کارِ UI است.
export const billsApi = {
  types: () => api.get("/bills/types"),
  // یا زوجِ شناسه بده، یا بارکدِ ۲۶رقمیِ چاپ‌شده روی قبض.
  inquiry: (body: { bill_id?: string; payment_id?: string; barcode?: string }) =>
    api.post("/bills/inquiry", body),
  pay: (body: { bill_id?: string; payment_id?: string; barcode?: string; title?: string }) =>
    api.post("/bills/pay", body),
  history: (limit = 30, offset = 0) =>
    api.get("/bills", { params: { limit, offset } }),
  receipt: (ref: string) => api.get(`/bills/${ref}`),
  saved: () => api.get("/bills/saved"),
  save: (title: string, bill_id: string) =>
    api.post("/bills/saved", { title, bill_id }),
  unsave: (id: string) => api.delete(`/bills/saved/${id}`),
};

// ─── Business / Creator API (حسابِ رسمی + Insights) ──────────────────────────
// نشانِ تأیید (verified) دستی نیست؛ از سطحِ KYC کاربر محاسبه می‌شود.
export type BusinessPayload = {
  kind?: string;
  display_name?: string;
  category?: string;
  about?: string | null;
  website?: string | null;
  contact_phone?: string | null;
  contact_email?: string | null;
  address?: string | null;
  lat?: number | null;
  lng?: number | null;
};

export const businessApi = {
  categories: () => api.get("/business/categories"),
  kinds: () => api.get("/business/kinds"),
  me: () => api.get("/business/me"),
  create: (body: BusinessPayload) => api.post("/business/me", body),
  update: (body: BusinessPayload) => api.patch("/business/me", body),
  remove: () => api.delete("/business/me"),
  insights: () => api.get("/business/insights"),
  profile: (earth_id: string) => api.get(`/business/${earth_id}`),
  // ثبتِ بازدید؛ سرور خودبازدید را نادیده می‌گیرد و هر بیننده را روزی یک‌بار می‌شمارد.
  view: (earth_id: string) => api.post(`/business/${earth_id}/view`),
};

// ─── Subscriptions API (اشتراکِ پولیِ سازندگان) ──────────────────────────────
// همهٔ مبلغ‌ها ریال‌اند؛ تبدیل به تومان کارِ UI است.
export const subscriptionsApi = {
  myTiers: () => api.get("/subscriptions/tiers/mine"),
  createTier: (body: { name: string; price: number; perks?: string | null }) =>
    api.post("/subscriptions/tiers", body),
  updateTier: (
    id: string,
    body: { name?: string; price?: number; perks?: string | null; is_active?: boolean },
  ) => api.patch(`/subscriptions/tiers/${id}`, body),
  deactivateTier: (id: string) => api.delete(`/subscriptions/tiers/${id}`),
  tiersOf: (earth_id: string) => api.get(`/subscriptions/tiers/of/${earth_id}`),
  subscribe: (tier_id: string) => api.post("/subscriptions/subscribe", { tier_id }),
  mine: () => api.get("/subscriptions/mine"),
  subscribers: () => api.get("/subscriptions/subscribers"),
  cancel: (id: string) => api.post(`/subscriptions/${id}/cancel`),
  renew: (id: string) => api.post(`/subscriptions/${id}/renew`),
};

// ─── Shop API (فروشگاه + پرداختِ امانی درون‌چت) ───────────────────────────────
// مبالغ همه‌جا ریال‌اند؛ تبدیل به تومان فقط در لایهٔ نمایش انجام می‌شود.
export type ProductPayload = {
  title: string;
  price: number;
  description?: string | null;
  image_url?: string | null;
  stock?: number;
};

export const shopApi = {
  products: (params?: { q?: string; seller?: string; limit?: number; offset?: number }) =>
    api.get("/shop/products", { params }),
  myProducts: () => api.get("/shop/products/mine"),
  product: (id: string) => api.get(`/shop/products/${id}`),
  createProduct: (body: ProductPayload) => api.post("/shop/products", body),
  updateProduct: (id: string, body: Partial<ProductPayload> & { is_active?: boolean }) =>
    api.patch(`/shop/products/${id}`, body),
  removeProduct: (id: string) => api.delete(`/shop/products/${id}`),
  shareProduct: (id: string, roomId: string) =>
    api.post(`/shop/products/${id}/share`, { room_id: roomId }),

  createOrder: (body: {
    product_id: string;
    qty?: number;
    room_id?: string | null;
    note?: string | null;
    address?: string | null;
  }) => api.post("/shop/orders", body),
  myOrders: () => api.get("/shop/orders/mine"),
  mySales: () => api.get("/shop/orders/sales"),
  order: (ref: string) => api.get(`/shop/orders/${ref}`),
  accept: (id: string) => api.post(`/shop/orders/${id}/accept`),
  ship: (id: string) => api.post(`/shop/orders/${id}/ship`),
  complete: (id: string) => api.post(`/shop/orders/${id}/complete`),
  cancel: (id: string) => api.post(`/shop/orders/${id}/cancel`),
};

// ─── Mini Apps API (برنامه‌های کوچکِ درون‌پلتفرم) ─────────────────────────────
// `app_secret` فقط در پاسخِ ساخت و چرخشِ کلید برمی‌گردد؛ سرور جز هشِ آن چیزی
// نگه نمی‌دارد، پس UI باید همان‌جا به سازنده نشانش دهد.
export type MiniAppPayload = {
  name: string;
  entry_url: string;
  tagline?: string | null;
  description?: string | null;
  icon_url?: string | null;
  category?: string;
  scopes?: string[];
};

export const miniappsApi = {
  list: (params?: { q?: string; category?: string; limit?: number; offset?: number }) =>
    api.get("/miniapps", { params }),
  mine: () => api.get("/miniapps/mine"),
  installed: () => api.get("/miniapps/installed"),
  get: (app_id: string) => api.get(`/miniapps/${app_id}`),
  create: (body: MiniAppPayload) => api.post("/miniapps", body),
  update: (app_id: string, body: Partial<MiniAppPayload>) =>
    api.patch(`/miniapps/${app_id}`, body),
  submit: (app_id: string) => api.post(`/miniapps/${app_id}/submit`),
  rotateSecret: (app_id: string) => api.post(`/miniapps/${app_id}/secret`),
  install: (app_id: string, scopes?: string[]) =>
    api.post(`/miniapps/${app_id}/install`, { scopes: scopes ?? null }),
  uninstall: (app_id: string) => api.delete(`/miniapps/${app_id}/install`),
  // کدِ یک‌بارمصرفِ ورود؛ هر بار اجرا کدِ قبلی را باطل می‌کند.
  launch: (app_id: string) => api.post(`/miniapps/${app_id}/launch`),
  pendingPayments: () => api.get("/miniapps/payments/pending"),
  confirmPayment: (ref: string) => api.post(`/miniapps/payments/${ref}/confirm`),
  cancelPayment: (ref: string) => api.post(`/miniapps/payments/${ref}/cancel`),
};

// ─── Ads API (تبلیغاتِ خودخدمت) ───────────────────────────────────────────────
// مبالغ ریال‌اند. بودجه هنگامِ فعال‌سازی از موجودی بلوکه می‌شود و با
// توقف/پایان، بخشِ خرج‌نشده برمی‌گردد.
export type CampaignPayload = {
  title: string;
  target_url: string;
  body?: string | null;
  image_url?: string | null;
  cta?: string | null;
  placement?: string;
  bid_cpc: number;
  budget_total: number;
  target_countries?: string[] | null;
  target_locales?: string[] | null;
  ends_at?: string | null;
};

export const adsApi = {
  campaigns: () => api.get("/ads/campaigns"),
  campaign: (id: string) => api.get(`/ads/campaigns/${id}`),
  create: (body: CampaignPayload) => api.post("/ads/campaigns", body),
  update: (id: string, body: Partial<CampaignPayload>) =>
    api.patch(`/ads/campaigns/${id}`, body),
  activate: (id: string) => api.post(`/ads/campaigns/${id}/activate`),
  pause: (id: string) => api.post(`/ads/campaigns/${id}/pause`),
  stop: (id: string) => api.post(`/ads/campaigns/${id}/stop`),
  stats: (id: string) => api.get(`/ads/campaigns/${id}/stats`),
  // نمایش: تکرارِ همان کمپین برای همان کاربر در همان روز شمرده نمی‌شود.
  serve: (placement = "feed", limit = 1) =>
    api.get("/ads/serve", { params: { placement, limit } }),
  click: (id: string) => api.post(`/ads/${id}/click`),
};

// ─── Holdings API (کیف‌پولِ چندارزی + تبدیلِ درون‌کیفی) ───────────────────────
export const holdingsApi = {
  list: () => api.get("/holdings"),
  exchange: (from_currency: string, to_currency: string, amount: number) =>
    api.post("/holdings/exchange", { from_currency, to_currency, amount }),
  // ارز دیجیتال: دریافت (آدرس/شبکه)، تاریخچهٔ جیب، انتقالِ درون‌شبکه‌ای، برداشتِ بیرونی
  receive: (currency: string) => api.get(`/holdings/${currency}/receive`),
  transactions: (currency?: string, page = 1) =>
    api.get("/holdings/transactions", { params: { currency, page } }),
  transfer: (to_earth_id: string, currency: string, amount: number, description?: string) =>
    api.post("/holdings/transfer", { to_earth_id, currency, amount, description }),
  withdraw: (currency: string, amount: number, address: string, description?: string) =>
    api.post("/holdings/withdraw", { currency, amount, address, description }),
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
