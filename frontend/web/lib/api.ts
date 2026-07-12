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
let accessToken: string | null = null;

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

export function isAuthenticated(): boolean {
  return getAccessToken() != null;
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set("Accept", "application/json");
  if (init.body) headers.set("Content-Type", "application/json");
  const token = getAccessToken();
  if (token) headers.set("Authorization", `Bearer ${token}`);

  const res = await fetch(`${baseUrl()}${path}`, { ...init, headers });
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
    feed: (limit = 30) => request<PostOut[]>(`/v1/social/feed?limit=${limit}`),
    createPost: (body: { post_type?: string; content?: string; visibility?: string }) =>
      request<PostOut>("/v1/social/posts", { method: "POST", body: JSON.stringify(body) }),
    react: (postId: string, reaction: string) =>
      request<PostOut>(`/v1/social/posts/${postId}/reactions`, {
        method: "POST",
        body: JSON.stringify({ reaction }),
      }),
  },

  messaging: {
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
    invoke: (conversationId: string, message: string) =>
      request<{ reply: string }>(`/v1/ai/conversations/${conversationId}/messages`, {
        method: "POST",
        body: JSON.stringify({ message }),
      }),
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
