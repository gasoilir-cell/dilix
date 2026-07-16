// نقش‌ها و پنل‌های مخصوصِ هر نقش (سمتِ کلاینت).
// منبعِ حقیقتِ «چه نقشی مجاز است» بک‌اند است (‎/v1/identity/roles‎)؛ این‌جا فقط
// نگاشتِ نقش → ناوبری/پنل برای رندرِ رابطِ کاربری تعریف می‌شود.

export type RoleKey =
  | "individual"
  | "driver"
  | "cargo_owner"
  | "freelancer"
  | string;

export interface NavItem {
  href: string;
  icon: string;
  label: string;
}

export interface RolePanelTile {
  href: string;
  icon: string;
  title: string;
  subtitle: string;
}

// ناوبریِ پایین به‌ازای هر نقش. نقش‌های ناشناخته به individual برمی‌گردند.
const NAV_INDIVIDUAL: NavItem[] = [
  { href: "/", icon: "🏠", label: "خانه" },
  { href: "/social", icon: "📣", label: "اجتماعی" },
  { href: "/earth", icon: "🌍", label: "کره" },
  { href: "/messages", icon: "💬", label: "پیام‌ها" },
  { href: "/services", icon: "🧩", label: "خدمات" },
  { href: "/me", icon: "👤", label: "من" },
];

export const NAV_BY_ROLE: Record<string, NavItem[]> = {
  individual: NAV_INDIVIDUAL,
  driver: [
    { href: "/", icon: "🏠", label: "خانه" },
    { href: "/services/freight", icon: "🚚", label: "بارها" },
    { href: "/earth", icon: "🌍", label: "نقشه" },
    { href: "/messages", icon: "💬", label: "پیام‌ها" },
    { href: "/me", icon: "👤", label: "من" },
  ],
  cargo_owner: [
    { href: "/", icon: "🏠", label: "خانه" },
    { href: "/services/freight", icon: "📦", label: "بارِ من" },
    { href: "/earth", icon: "🌍", label: "نقشه" },
    { href: "/messages", icon: "💬", label: "پیام‌ها" },
    { href: "/me", icon: "👤", label: "من" },
  ],
  freelancer: [
    { href: "/", icon: "🏠", label: "خانه" },
    { href: "/earth", icon: "🌍", label: "کره" },
    { href: "/services", icon: "💼", label: "کارها" },
    { href: "/messages", icon: "💬", label: "پیام‌ها" },
    { href: "/me", icon: "👤", label: "من" },
  ],
};

// پنل‌های میان‌برِ مخصوصِ هر نقش که در صفحه‌ی «من» نمایش داده می‌شوند.
export const PANELS_BY_ROLE: Record<string, RolePanelTile[]> = {
  driver: [
    {
      href: "/services/freight",
      icon: "🚚",
      title: "پنلِ راننده",
      subtitle: "بارهای موجود، ثبتِ پیشنهاد و سفرهای فعال",
    },
  ],
  cargo_owner: [
    {
      href: "/services/freight",
      icon: "📦",
      title: "پنلِ صاحبِ بار",
      subtitle: "ثبتِ بار، پذیرشِ پیشنهاد و پیگیریِ محموله",
    },
  ],
  freelancer: [
    {
      href: "/services",
      icon: "💼",
      title: "پنلِ فریلنسر",
      subtitle: "ارائه‌ی خدمات و جذبِ مشتری",
    },
  ],
};

export function navForRole(role: RoleKey | null | undefined): NavItem[] {
  if (!role) return NAV_INDIVIDUAL;
  return NAV_BY_ROLE[role] ?? NAV_INDIVIDUAL;
}

export function panelsForRole(role: RoleKey | null | undefined): RolePanelTile[] {
  if (!role) return [];
  return PANELS_BY_ROLE[role] ?? [];
}

// ─────────── وضعیتِ نقشِ جاری (localStorage + رویدادِ سراسری) ───────────
const ROLE_KEY = "dilix.role";
const ROLE_EVENT = "dilix:role-changed";

export function getStoredRole(): RoleKey | null {
  if (typeof window === "undefined") return null;
  return window.localStorage.getItem(ROLE_KEY);
}

export function setStoredRole(role: RoleKey | null): void {
  if (typeof window === "undefined") return;
  if (role) window.localStorage.setItem(ROLE_KEY, role);
  else window.localStorage.removeItem(ROLE_KEY);
  window.dispatchEvent(new CustomEvent(ROLE_EVENT, { detail: role }));
}

export function onRoleChange(handler: (role: RoleKey | null) => void): () => void {
  if (typeof window === "undefined") return () => {};
  const listener = (e: Event) => handler((e as CustomEvent).detail ?? getStoredRole());
  window.addEventListener(ROLE_EVENT, listener);
  // sync بین تب‌ها
  const storageListener = (e: StorageEvent) => {
    if (e.key === ROLE_KEY) handler(e.newValue);
  };
  window.addEventListener("storage", storageListener);
  return () => {
    window.removeEventListener(ROLE_EVENT, listener);
    window.removeEventListener("storage", storageListener);
  };
}
