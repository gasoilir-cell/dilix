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
      } catch {
        useAuthStore.getState().logout();
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
  send: (roomId: string, content: string) =>
    api.post(`/messages/rooms/${roomId}/messages`, { content }),
};

// ─── Health API ───────────────────────────────────────────────
export const healthApi = {
  check: () => api.get("/health"),
};

export default api;
