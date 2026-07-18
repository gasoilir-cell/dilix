// کلاینتِ تایپ‌دارِ API — هم‌خوان با سند ۵ (مشخصاتِ API).
// در مرورگر از پراکسیِ /api استفاده می‌شود (next.config.mjs rewrites)؛
// در سرور از NEXT_PUBLIC_API_BASE_URL مستقیم.

const isServer = typeof window === "undefined";
const SERVER_BASE = process.env.NEXT_PUBLIC_API_BASE_URL || "http://localhost:8000";

function baseUrl(): string {
  return isServer ? SERVER_BASE : "/api";
}

export interface ProblemDetail {
  type: string;
  title: string;
  status: number;
  detail: string;
  instance?: string;
  trace_id?: string;
}

export class ApiError extends Error {
  constructor(public problem: ProblemDetail) {
    super(problem.detail || problem.title);
    this.name = "ApiError";
  }
}

const TOKEN_KEY = "dilix.access_token";
const REFRESH_KEY = "dilix.refresh_token";
const REFRESH_PATH = "/v1/auth/token/refresh";
let accessToken: string | null = null;
let refreshToken: string | null = null;

export function setAccessToken(token: string | null): void {
  accessToken = token;
  if (!isServer) {
    if (token) window.localStorage.setItem(TOKEN_KEY, token);
    else window.localStorage.removeItem(TOKEN_KEY);
  }
}

export function getAccessToken(): string | null {
  if (accessToken) return accessToken;
  if (!isServer) accessToken = window.localStorage.getItem(TOKEN_KEY);
  return accessToken;
}

export function setRefreshToken(token: string | null): void {
  refreshToken = token;
  if (!isServer) {
    if (token) window.localStorage.setItem(REFRESH_KEY, token);
    else window.localStorage.removeItem(REFRESH_KEY);
  }
}

export function getRefreshToken(): string | null {
  if (refreshToken) return refreshToken;
  if (!isServer) refreshToken = window.localStorage.getItem(REFRESH_KEY);
  return refreshToken;
}

// نشستِ کامل را ذخیره می‌کند: هم access و هم refresh (برای پایداریِ نشست پس از رفرش).
export function setSession(tokens: TokenPair): void {
  setAccessToken(tokens.access_token);
  setRefreshToken(tokens.refresh_token);
}

export function clearSession(): void {
  setAccessToken(null);
  setRefreshToken(null);
}

export function isAuthenticated(): boolean {
  return getAccessToken() != null || getRefreshToken() != null;
}

// تجدیدِ access token با refresh token. برای جلوگیری از چند درخواستِ هم‌زمان،
// نتیجه در یک Promise مشترک نگه داشته می‌شود.
let refreshing: Promise<boolean> | null = null;
async function tryRefresh(): Promise<boolean> {
  if (refreshing) return refreshing;
  const rt = getRefreshToken();
  if (!rt) return false;
  refreshing = (async () => {
    try {
      const res = await fetch(`${baseUrl()}${REFRESH_PATH}`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify({ refresh_token: rt }),
      });
      if (!res.ok) {
        clearSession();
        return false;
      }
      setSession((await res.json()) as TokenPair);
      return true;
    } catch {
      return false;
    } finally {
      refreshing = null;
    }
  })();
  return refreshing;
}

async function request<T>(path: string, init: RequestInit = {}, retried = false): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set("Accept", "application/json");
  if (init.body) headers.set("Content-Type", "application/json");
  const token = getAccessToken();
  if (token) headers.set("Authorization", `Bearer ${token}`);

  const res = await fetch(`${baseUrl()}${path}`, { ...init, headers });
  // اگر access token منقضی شده باشد، یک‌بار با refresh token تجدید و درخواست را تکرار می‌کنیم.
  if (res.status === 401 && !retried && path !== REFRESH_PATH && getRefreshToken()) {
    if (await tryRefresh()) return request<T>(path, init, true);
  }
  if (!res.ok) {
    let problem: ProblemDetail;
    try {
      problem = (await res.json()) as ProblemDetail;
    } catch {
      problem = { type: "about:blank", title: res.statusText, status: res.status, detail: res.statusText };
    }
    throw new ApiError(problem);
  }
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

// ─────────────────────── Domain types ──────────────────────────

export interface TokenPair {
  access_token: string;
  refresh_token: string;
  token_type: string;
  mfa_required: boolean;
}

export interface RegisterResponse {
  earth_id: string;
  tokens: TokenPair;
}

export type OAuthProvider = "google" | "microsoft" | "apple" | "facebook";

export interface OAuthLoginResponse {
  earth_id: string;
  tokens: TokenPair;
}

export type OtpChannel = "sms" | "facebook";

export interface OtpRequestResponse {
  challenge_id: string;
  channel: OtpChannel;
  expires_at: string;
}

export interface ProfileOut {
  display_name: string;
  gender: string | null;
  marital_status: string | null;
  languages: string[];
  interests: string[];
  bio: string | null;
  avatar_url: string | null;
}

export interface Identity {
  earth_id: string;
  entity_type: string;
  status: string;
  kyc_level: number;
  home_region: string;
  created_at: string;
  profile: ProfileOut | null;
}

export interface VisibilityUpdate {
  discoverable: boolean;
  audience: "public" | "verified" | "connections";
  geo_precision: "exact" | "city" | "region";
  visible_fields: Array<"gender" | "age_range" | "marital_status" | "profession" | "interests">;
}

export interface RoleOption {
  entity_type: string;
  label: string;
  description: string;
  self_service: boolean;
}

export interface PostOut {
  id: string;
  author_earth_id: string;
  post_type: string;
  content: string | null;
  media: unknown[];
  visibility: string;
  reaction_counts: Record<string, number>;
  comment_count: number;
  created_at: string;
}

export interface RoomOut {
  id: string;
  room_type: string;
  title: string | null;
  is_e2ee: boolean;
  created_by: string;
}

export interface MessageOut {
  id: string;
  room_id: string;
  sender_earth_id: string;
  msg_type: string;
  content: string;
  file_ref: string | null;
  is_e2ee: boolean;
  sent_at: string;
  deleted: boolean;
}

export interface CargoPostOut {
  id: string;
  owner_earth_id: string;
  title: string;
  origin: string;
  destination: string;
  weight_grams: number;
  budget_minor: number | null;
  currency: string;
  status: string;
  accepted_bid_id: string | null;
  payment_order_id: string | null;
  shipment_id: string | null;
}

export interface ListingOut {
  id: string;
  provider_earth_id: string;
  title: string;
  description: string;
  category: string;
  base_price_minor: number;
  currency: string;
  delivery_days: number;
  tags: string[];
  status: string;
  is_featured: boolean;
}

export interface TopUpOut {
  id: string;
  msisdn: string;
  product_code: string;
  amount_minor: number;
  currency: string;
  status: string;
  external_ref: string | null;
}

export interface EsimOut {
  id: string;
  iccid: string;
  country_code: string;
  status: string;
}

export interface PolicyOut {
  id: string;
  holder_earth_id: string;
  provider_code: string;
  product_code: string;
  coverage_minor: number;
  premium_minor: number;
  currency: string;
  external_ref: string | null;
  status: string;
}

export interface NearbyPerson {
  earth_id: string;
  entity_type: string;
  display_name: string | null;
  avatar_url: string | null;
  lat: number;
  lon: number;
  geo_precision: string;
  gender: string | null;
  age_range: string | null;
  marital_status: string | null;
  profession: string | null;
  interests: string[] | null;
  languages: string[] | null;
}

export interface ReferralLink {
  code: string;
  url: string;
  total_referred: number;
}

export interface RewardBalance {
  currency: string;
  amount_minor: number;
  reward_count: number;
}

export interface RewardWallet {
  balances: RewardBalance[];
  pending_count: number;
}

export interface RevenueShare {
  eligible: boolean;
  plan: string;
  entitlement_bps: number;
  investment_units: number;
  note: string;
}

export interface PaymentOrderOut {
  id: string;
  payer_earth_id: string;
  payee_earth_id: string;
  amount_minor: number;
  currency: string;
  provider_code: string;
  external_ref: string | null;
  status: string;
}

export interface ProviderOut {
  id: string;
  legal_name: string;
  provider_type: string;
  country: string;
  kyb_status: string;
}

export interface ProviderApiOut {
  id: string;
  name: string;
  env: string;
  status: string;
}

export interface SandboxTestResult {
  api_id: string;
  reachable: boolean;
  http_status: number | null;
  latency_ms: number | null;
  detail: string;
}

export interface WebhookOut {
  id: string;
  url: string;
  event_types: string[];
  status: string;
  secret: string | null;
}

export interface CredentialOut {
  id: string;
  env: string;
  key_prefix: string;
  status: string;
  api_key: string | null;
}

export interface NotificationOut {
  id: string;
  recipient_earth_id: string;
  channel: string;
  title: string;
  body: string;
  status: string;
  read: boolean;
  created_at: string;
}

export interface AiConversationOut {
  id: string;
  agent_type: string;
  title: string | null;
  created_at: string;
}

export interface AiMessageOut {
  id: string;
  conversation_id: string;
  role: "user" | "assistant" | "system" | string;
  content: string;
  tool_calls: unknown[];
  sent_at: string;
}

export interface WsCallSignal {
  type: "call.offer" | "call.answer" | "call.end" | "ice.candidate" | string;
  payload: Record<string, unknown>;
  ts?: string;
}

// داستان‌ها (stories) — قرارداد: media_url (بدونِ آپلودِ فایل؛ data-URL هم می‌پذیرد).
export interface StoryRingOut {
  author_earth_id: string;
  story_count: number;
  has_unseen: boolean;
  is_me: boolean;
  latest_at: string;
}

export interface StoryOut {
  id: string;
  author_earth_id: string;
  media_url: string;
  media_type: string;
  caption: string | null;
  audience: string;
  view_count: number;
  viewed_by_me: boolean;
  is_mine: boolean;
  created_at: string;
}

export interface StoryViewerOut {
  viewer_earth_id: string;
  viewed_at: string;
}

export interface CircleMember {
  earth_id: string;
}

export interface CirclesOut {
  colleagues: CircleMember[];
  family: CircleMember[];
  friends: CircleMember[];
}

// استیکرها (stickers)
export interface StickerOut {
  id: string;
  pack_id: string;
  media_url: string;
  media_type: string;
  emoji_tag: string | null;
  title: string | null;
  is_starred: boolean;
  created_at: string;
}

export interface StickerPackOut {
  id: string;
  owner_earth_id: string;
  title: string;
  description: string | null;
  cover_url: string | null;
  is_public: boolean;
  is_animated: boolean;
  is_mine: boolean;
  is_installed: boolean;
  install_count: number;
  sticker_count: number;
  created_at: string;
}

export interface StickerPackDetailOut extends StickerPackOut {
  stickers: StickerOut[];
}

export interface CommentOut {
  id: string;
  post_id: string;
  author_earth_id: string;
  parent_id: string | null;
  content: string;
  created_at: string;
}

// سرمایه‌گذاری (investment)
export interface NavOut {
  fund_code: string;
  nav_minor: number;
}

export interface PositionOut {
  id: string;
  fund_code: string;
  units: number;
  status: string;
}

// عضویت (membership)
export interface MembershipOut {
  id: string;
  earth_id: string;
  plan: string;
  status: string;
  cashback_bps: number;
  expires_at: string | null;
}

// بازی‌وارسازی (gamification)
export interface PointsOut {
  balance: number;
}

export interface BadgeOut {
  id: string;
  badge_code: string;
  description: string | null;
  awarded_at: string;
}

// اعتبار (reputation)
export interface ScoreOut {
  earth_id: string;
  domain: string;
  score: number;
  review_count: number;
}

export interface ReviewOut {
  id: string;
  reviewee_earth_id: string;
  reviewer_earth_id: string;
  domain: string;
  transaction_ref: string;
  rating: number;
  comment: string | null;
}

// ─────────────────────── API surface ──────────────────────────

export const api = {
  health: () => request<{ status: string }>("/health"),

  auth: {
    register: (body: {
      display_name: string;
      entity_type?: string;
      home_region?: string;
      email?: string;
      phone?: string;
      password: string;
    }) =>
      request<RegisterResponse>("/v1/auth/register", {
        method: "POST",
        body: JSON.stringify(body),
      }),
    login: (identifier: string, password: string) =>
      request<TokenPair>("/v1/auth/login", {
        method: "POST",
        body: JSON.stringify({ identifier, password }),
      }),
    // ورود با Google/Microsoft/Apple/Facebook — credential همان id_token (یا
    // برای فیسبوک access_token) است که کلاینت پس از رضایتِ کاربر می‌گیرد.
    oauthLogin: (provider: OAuthProvider, credential: string, homeRegion = "IR") =>
      request<OAuthLoginResponse>(`/v1/auth/oauth/${provider}`, {
        method: "POST",
        body: JSON.stringify({ credential, home_region: homeRegion }),
      }),
    // ارسالِ کدِ تأیید به موبایل (پیامک) یا شبکه‌ی اجتماعی (Facebook Messenger).
    otpRequest: (channel: OtpChannel, destination: string, purpose: "login" | "register" = "login") =>
      request<OtpRequestResponse>("/v1/auth/otp/request", {
        method: "POST",
        body: JSON.stringify({ channel, destination, purpose }),
      }),
    otpVerify: (challengeId: string, code: string) =>
      request<OAuthLoginResponse>("/v1/auth/otp/verify", {
        method: "POST",
        body: JSON.stringify({ challenge_id: challengeId, code }),
      }),
  },

  identity: {
    me: () => request<Identity>("/v1/identity/me"),
    updateProfile: (body: Partial<ProfileOut>) =>
      request<Identity>("/v1/identity/me", { method: "PATCH", body: JSON.stringify(body) }),
    setVisibility: (body: VisibilityUpdate) =>
      request<void>("/v1/identity/me/visibility", { method: "PUT", body: JSON.stringify(body) }),
    // کاتالوگِ نقش‌های خودسرویس که کاربر می‌تواند به آن‌ها سوییچ کند.
    roles: () => request<RoleOption[]>("/v1/identity/roles"),
    // سوییچِ نقشِ کاربر جاری (فقط نقش‌های خودسرویس؛ بک‌اند اعتبارسنجی می‌کند).
    changeRole: (entityType: string) =>
      request<Identity>("/v1/identity/me/role", {
        method: "POST",
        body: JSON.stringify({ entity_type: entityType }),
      }),
  },

  social: {
    // فیدِ اجتماعی؛ با postType (مثلاً "reel") فقط همان نوعِ پست را می‌گیرد.
    feed: (limit = 30, postType?: string) => {
      const q = new URLSearchParams({ limit: String(limit) });
      if (postType) q.set("post_type", postType);
      return request<PostOut[]>(`/v1/social/feed?${q.toString()}`);
    },
    createPost: (body: { post_type?: string; content?: string; media?: unknown[]; visibility?: string }) =>
      request<PostOut>("/v1/social/posts", { method: "POST", body: JSON.stringify(body) }),
    deletePost: (postId: string) =>
      request<void>(`/v1/social/posts/${postId}`, { method: "DELETE" }),
    react: (postId: string, reaction: string) =>
      request<PostOut>(`/v1/social/posts/${postId}/reactions`, {
        method: "POST",
        body: JSON.stringify({ reaction }),
      }),
    comment: (postId: string, content: string) =>
      request<CommentOut>(`/v1/social/posts/${postId}/comments`, {
        method: "POST",
        body: JSON.stringify({ content }),
      }),
  },

  messaging: {
    listRooms: (limit = 100) =>
      request<RoomOut[]>(`/v1/messaging/rooms?limit=${limit}`),
    createRoom: (body: { room_type?: string; title?: string; member_ids?: string[] }) =>
      request<RoomOut>("/v1/messaging/rooms", { method: "POST", body: JSON.stringify(body) }),
    messages: (roomId: string) => request<MessageOut[]>(`/v1/messaging/rooms/${roomId}/messages`),
    send: (roomId: string, content: string) =>
      request<MessageOut>(`/v1/messaging/rooms/${roomId}/messages`, {
        method: "POST",
        body: JSON.stringify({ content }),
      }),
  },

  freight: {
    listCargo: () => request<CargoPostOut[]>("/v1/freight/cargo"),
    createCargo: (body: {
      title: string;
      origin: string;
      destination: string;
      weight_grams: number;
      budget_minor?: number;
      currency?: string;
    }) => request<CargoPostOut>("/v1/freight/cargo", { method: "POST", body: JSON.stringify(body) }),
  },

  marketplace: {
    listListings: (params: { category?: string; keyword?: string } = {}) => {
      const q = new URLSearchParams();
      Object.entries(params).forEach(([k, v]) => v != null && v !== "" && q.set(k, String(v)));
      const qs = q.toString();
      return request<ListingOut[]>(`/v1/marketplace/listings${qs ? `?${qs}` : ""}`);
    },
    createListing: (body: {
      title: string;
      description: string;
      category: string;
      base_price_minor: number;
      currency?: string;
      delivery_days?: number;
      tags?: string[];
    }) => request<ListingOut>("/v1/marketplace/listings", { method: "POST", body: JSON.stringify(body) }),
  },

  telecom: {
    topUp: (body: {
      msisdn: string;
      product_code: string;
      amount_minor: number;
      currency?: string;
      provider_code?: string;
    }) => request<TopUpOut>("/v1/telecom/top-up", { method: "POST", body: JSON.stringify(body) }),
    activateEsim: (body: { iccid: string; country_code: string; provider_code?: string }) =>
      request<EsimOut>("/v1/telecom/esim/activate", { method: "POST", body: JSON.stringify(body) }),
  },

  insurance: {
    createQuote: (body: {
      product_code: string;
      coverage_minor: number;
      currency?: string;
      provider_code?: string;
    }) => request<PolicyOut>("/v1/insurance/quotes", { method: "POST", body: JSON.stringify(body) }),
  },

  discovery: {
    nearby: (params: {
      bbox: string;
      entity_type?: string;
      gender?: string;
      age_range?: string;
      profession?: string;
      language?: string;
      marital_status?: string;
      business_category?: string;
      limit?: number;
    }) => {
      const q = new URLSearchParams();
      Object.entries(params).forEach(([k, v]) => v != null && q.set(k, String(v)));
      return request<NearbyPerson[]>(`/v1/discovery/nearby?${q.toString()}`);
    },
    contactRequest: (earthId: string, message: string) =>
      request<unknown>(`/v1/discovery/${earthId}/contact-request`, {
        method: "POST",
        body: JSON.stringify({ message }),
      }),
  },

  growth: {
    referralLink: () => request<ReferralLink>("/v1/growth/referrals/link"),
    rewards: () => request<RewardWallet>("/v1/growth/rewards"),
    revenueShare: () => request<RevenueShare>("/v1/growth/revenue-share"),
  },

  investment: {
    nav: (fundCode: string) => request<NavOut>(`/v1/investment/nav?fund_code=${encodeURIComponent(fundCode)}`),
    positions: () => request<PositionOut[]>("/v1/investment/positions"),
    buy: (body: { fund_code: string; amount_minor: number; currency?: string; provider_code?: string }) =>
      request<PositionOut>("/v1/investment/buy", { method: "POST", body: JSON.stringify(body) }),
    sell: (body: { position_id: string; units: number }) =>
      request<PositionOut>("/v1/investment/sell", { method: "POST", body: JSON.stringify(body) }),
  },

  membership: {
    get: () => request<MembershipOut>("/v1/membership"),
    upgrade: (body: { plan: "free" | "standard" | "premium"; months?: number }) =>
      request<MembershipOut>("/v1/membership/upgrade", { method: "POST", body: JSON.stringify(body) }),
    cancel: () => request<MembershipOut>("/v1/membership/cancel", { method: "POST" }),
  },

  gamification: {
    points: () => request<PointsOut>("/v1/gamification/points"),
    badges: () => request<BadgeOut[]>("/v1/gamification/badges"),
  },

  reputation: {
    scores: (earthId: string) => request<ScoreOut[]>(`/v1/reputation/scores/${earthId}`),
    reviews: (earthId: string) => request<ReviewOut[]>(`/v1/reputation/reviews/${earthId}`),
    submitReview: (body: {
      reviewee_earth_id: string;
      domain: string;
      transaction_ref: string;
      rating: number;
      comment?: string;
    }) => request<ReviewOut>("/v1/reputation/reviews", { method: "POST", body: JSON.stringify(body) }),
  },

  stories: {
    feed: () => request<StoryRingOut[]>("/v1/stories/feed"),
    userStories: (earthId: string) => request<StoryOut[]>(`/v1/stories/user/${earthId}`),
    create: (body: { media_url: string; media_type?: string; caption?: string; audience?: string }) =>
      request<StoryOut>("/v1/stories", { method: "POST", body: JSON.stringify(body) }),
    view: (storyId: string) => request<void>(`/v1/stories/${storyId}/view`, { method: "POST" }),
    viewers: (storyId: string) => request<StoryViewerOut[]>(`/v1/stories/${storyId}/viewers`),
    remove: (storyId: string) => request<void>(`/v1/stories/${storyId}`, { method: "DELETE" }),
    circles: () => request<CirclesOut>("/v1/stories/circles"),
    addToCircle: (circle: string, earthId: string) =>
      request<CircleMember>(`/v1/stories/circles/${circle}`, {
        method: "POST",
        body: JSON.stringify({ earth_id: earthId }),
      }),
    removeFromCircle: (circle: string, earthId: string) =>
      request<void>(`/v1/stories/circles/${circle}/${earthId}`, { method: "DELETE" }),
  },

  stickers: {
    starred: () => request<StickerOut[]>("/v1/stickers/starred"),
    myPacks: () => request<StickerPackOut[]>("/v1/stickers/packs/mine"),
    installedPacks: () => request<StickerPackOut[]>("/v1/stickers/packs/installed"),
    publicPacks: (q?: string) => {
      const qs = q && q.trim() ? `?q=${encodeURIComponent(q.trim())}` : "";
      return request<StickerPackOut[]>(`/v1/stickers/packs/public${qs}`);
    },
    packDetail: (packId: string) => request<StickerPackDetailOut>(`/v1/stickers/packs/${packId}`),
    createPack: (body: { title: string; description?: string; is_public?: boolean }) =>
      request<StickerPackOut>("/v1/stickers/packs", { method: "POST", body: JSON.stringify(body) }),
    updatePack: (packId: string, body: { title?: string; description?: string; is_public?: boolean }) =>
      request<StickerPackOut>(`/v1/stickers/packs/${packId}`, { method: "PATCH", body: JSON.stringify(body) }),
    deletePack: (packId: string) => request<void>(`/v1/stickers/packs/${packId}`, { method: "DELETE" }),
    install: (packId: string) => request<void>(`/v1/stickers/packs/${packId}/install`, { method: "POST" }),
    uninstall: (packId: string) => request<void>(`/v1/stickers/packs/${packId}/install`, { method: "DELETE" }),
    addSticker: (
      packId: string,
      body: { media_url: string; media_type?: string; emoji_tag?: string; title?: string },
    ) =>
      request<StickerOut>(`/v1/stickers/packs/${packId}/stickers`, {
        method: "POST",
        body: JSON.stringify(body),
      }),
    deleteSticker: (stickerId: string) => request<void>(`/v1/stickers/${stickerId}`, { method: "DELETE" }),
    star: (stickerId: string) => request<void>(`/v1/stickers/${stickerId}/star`, { method: "POST" }),
    unstar: (stickerId: string) => request<void>(`/v1/stickers/${stickerId}/star`, { method: "DELETE" }),
  },

  payments: {
    createEscrow: (body: { payee_earth_id: string; amount_minor: number; currency: string; provider_code?: string }) =>
      request<PaymentOrderOut>("/v1/payments/escrow", {
        method: "POST",
        body: JSON.stringify(body),
      }),
    capture: (orderId: string) =>
      request<PaymentOrderOut>(`/v1/payments/${orderId}/capture`, { method: "POST" }),
    refund: (orderId: string) =>
      request<PaymentOrderOut>(`/v1/payments/${orderId}/refund`, { method: "POST" }),
  },

  notifications: {
    list: (unreadOnly = false, limit = 50) =>
      request<NotificationOut[]>(`/v1/notifications?unread_only=${unreadOnly}&limit=${limit}`),
    markRead: (id: string) =>
      request<void>(`/v1/notifications/${id}/read`, { method: "POST" }),
  },

  ai: {
    createConversation: (body: { agent_type?: string; title?: string } = {}) =>
      request<AiConversationOut>("/v1/ai/conversations", { method: "POST", body: JSON.stringify(body) }),
    conversations: () => request<AiConversationOut[]>("/v1/ai/conversations"),
    history: (conversationId: string, limit = 50) =>
      request<AiMessageOut[]>(`/v1/ai/conversations/${conversationId}/history?limit=${limit}`),
    chat: (conversationId: string, message: string) =>
      request<AiMessageOut>(`/v1/ai/conversations/${conversationId}/chat`, {
        method: "POST",
        body: JSON.stringify({ message }),
      }),
    invoke: async (conversationId: string, message: string) => {
      const msg = await request<AiMessageOut>(`/v1/ai/conversations/${conversationId}/chat`, {
        method: "POST",
        body: JSON.stringify({ message }),
      });
      return { reply: msg.content };
    },
  },

  realtime: {
    open: (token: string) => {
      const base = baseUrl();
      const httpBase = base.startsWith("/") ? window.location.origin + base : base;
      const url = new URL("/v1/ws", httpBase);
      url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
      url.searchParams.set("token", token);
      return new WebSocket(url);
    },
  },

  provider: {
    register: (body: {
      legal_name: string;
      provider_type: "insurer" | "carrier" | "psp" | "telecom" | "third_party";
      country?: string;
      license_no?: string;
    }) => request<ProviderOut>("/v1/providers/register", { method: "POST", body: JSON.stringify(body) }),
    listApis: (providerId: string) =>
      request<ProviderApiOut[]>(`/v1/providers/${providerId}/apis`),
    registerApi: (
      providerId: string,
      body: { name: string; spec_url?: string; webhook_url?: string },
    ) =>
      request<ProviderApiOut>(`/v1/providers/${providerId}/apis`, {
        method: "POST",
        body: JSON.stringify(body),
      }),
    sandboxTest: (providerId: string, apiId: string) =>
      request<SandboxTestResult>(`/v1/providers/${providerId}/apis/${apiId}/sandbox-test`, {
        method: "POST",
        body: "{}",
      }),
    registerWebhook: (providerId: string, body: { url: string; event_types?: string[] }) =>
      request<WebhookOut>(`/v1/providers/${providerId}/webhooks`, {
        method: "POST",
        body: JSON.stringify(body),
      }),
    issueCredential: (providerId: string, env: "sandbox" | "production") =>
      request<CredentialOut>(`/v1/providers/${providerId}/credentials`, {
        method: "POST",
        body: JSON.stringify({ env }),
      }),
  },
};
