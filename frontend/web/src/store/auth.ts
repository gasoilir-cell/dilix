/**
 * Dilix — Auth Store (Zustand)
 * مدیریت state احراز هویت و کاربر فعلی
 */
import { create } from "zustand";
import { persist, createJSONStorage } from "zustand/middleware";

interface User {
  id: string;
  earth_id: string;
  phone: string | null;
  email: string | null;
  full_name: string | null;
  username: string | null;
  avatar_url: string | null;
  bio: string | null;
  role: string;
  tier: string;
  status: string;
  kyc_level: number;
  kyc_status?: string;
  national_id_set?: boolean;
  locale: string;
  country_code: string | null;
  is_driver: boolean;
  trust_score: number;
  avg_rating: number;
  total_trips: number;
  privacy_on_map: boolean;
  created_at: string;
}

interface AuthState {
  user: User | null;
  accessToken: string | null;
  refreshToken: string | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  // آیا state از localStorage بازیابی (hydrate) شده؟ تا قبل از آن نباید ریدایرکت شود.
  hasHydrated: boolean;

  // Actions
  setUser: (user: User) => void;
  setTokens: (access: string, refresh: string) => void;
  setLoading: (v: boolean) => void;
  setHasHydrated: (v: boolean) => void;
  logout: () => void;
  updateUser: (partial: Partial<User>) => void;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      user: null,
      accessToken: null,
      refreshToken: null,
      isAuthenticated: false,
      isLoading: false,
      hasHydrated: false,

      setUser: (user) => set({ user, isAuthenticated: true }),

      setTokens: (access, refresh) =>
        set({ accessToken: access, refreshToken: refresh }),

      setLoading: (v) => set({ isLoading: v }),

      setHasHydrated: (v) => set({ hasHydrated: v }),

      logout: () =>
        set({
          user: null,
          accessToken: null,
          refreshToken: null,
          isAuthenticated: false,
        }),

      updateUser: (partial) => {
        const current = get().user;
        if (current) {
          set({ user: { ...current, ...partial } });
        }
      },
    }),
    {
      name: "dilix-auth",
      storage: createJSONStorage(() =>
        typeof window !== "undefined" ? localStorage : ({} as Storage)
      ),
      partialize: (state) => ({
        user: state.user,
        accessToken: state.accessToken,
        refreshToken: state.refreshToken,
        isAuthenticated: state.isAuthenticated,
      }),
      // پس از بازیابیِ state از localStorage، پرچمِ hydrate را روشن کن تا
      // لایه‌های محافظ (MainLayout/AuthGuard) بدونِ خطای «خروج زودهنگام» ریدایرکت کنند.
      onRehydrateStorage: () => (state) => {
        state?.setHasHydrated(true);
      },
    }
  )
);
