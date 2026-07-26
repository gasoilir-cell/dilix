/**
 * Dilix — Call Store (Zustand)
 * پلِ بین دکمه‌های تماس (در هر صفحه) و CallManager سراسری.
 */
import { create } from "zustand";

export type CallMedia = "audio" | "video";

export interface CallRequest {
  earthId: string;
  name: string;
  media: CallMedia;
  nonce: number;   // تا زنگ‌زدنِ دوباره به همان نفر هم trigger شود
}

interface CallStore {
  request: CallRequest | null;
  startCall: (earthId: string, name: string, media: CallMedia) => void;
  consume: () => void;
}

export const useCallStore = create<CallStore>((set) => ({
  request: null,
  startCall: (earthId, name, media) =>
    set({ request: { earthId, name, media, nonce: Date.now() } }),
  consume: () => set({ request: null }),
}));
