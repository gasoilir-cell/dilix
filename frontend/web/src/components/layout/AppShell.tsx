"use client";
import { ReactNode, useEffect, useState, useCallback } from "react";
import Link from "next/link";
import { Bell, Search } from "lucide-react";
import BottomNav from "./BottomNav";
import AiFloatButton from "@/components/shared/AiFloatButton";
import ThemeToggleButton from "@/components/shared/ThemeToggleButton";
import { cn } from "@/lib/utils";
import { useAuthStore } from "@/store/auth";
import { useI18nStore } from "@/store/i18n";
import { getLocale } from "@/lib/i18n";
import api from "@/lib/api";

interface AppShellProps {
  children: ReactNode;
  title?: string;
  showHeader?: boolean;
  showSearch?: boolean;
  className?: string;
}

export default function AppShell({
  children,
  title,
  showHeader = true,
  showSearch = false,
  className,
}: AppShellProps) {
  const user = useAuthStore((s) => s.user);
  const setLocale = useI18nStore((s) => s.setLocale);
  const [unread, setUnread] = useState(0);

  // همگام‌سازیِ زبانِ store با انتخابِ ذخیره‌شده در localStorage (پس از mount → بدون hydration mismatch)
  useEffect(() => {
    const saved = getLocale();
    if (saved) setLocale(saved);
  }, [setLocale]);

  const fetchUnread = useCallback(async () => {
    if (!user) return;
    try {
      const res = await api.get("/notifications");
      setUnread(res.data.unread ?? 0);
    } catch {
      // silent
    }
  }, [user]);

  useEffect(() => {
    fetchUnread();
    // poll every 60 seconds
    const id = setInterval(fetchUnread, 60_000);
    return () => clearInterval(id);
  }, [fetchUnread]);

  return (
    <div className="min-h-screen min-h-dvh" style={{ background: "var(--color-bg)" }}>
    <div className="relative mx-auto flex flex-col min-h-screen min-h-dvh w-full max-w-lg" style={{ background: "var(--color-bg)" }}>

      {/* ── Header ── */}
      {showHeader && (
        <header className="app-header sticky top-0 z-40">
          <div className="flex items-center justify-between px-4 h-14">
            <div className="flex items-center gap-3">
              {title ? (
                <h1 className="text-base font-bold text-white">{title}</h1>
              ) : (
                <Link href="/dashboard" className="flex items-center gap-2">
                  <span className="text-xl font-black text-gradient-primary">Dilix</span>
                  <span className="text-xs mt-0.5" style={{ color: "var(--color-muted)" }}>
                    دیلیکس
                  </span>
                </Link>
              )}
            </div>

            <div className="flex items-center gap-1">
              <ThemeToggleButton />
              {showSearch && (
                <Link
                  href="/discover"
                  aria-label="کشف افراد"
                  className="app-header-icon p-2 rounded-xl transition-colors"
                >
                  <Search className="w-5 h-5" />
                </Link>
              )}
              <Link
                href="/notifications"
                className="app-header-icon relative p-2 rounded-xl transition-colors"
              >
                <Bell className="w-5 h-5" />
                {unread > 0 && (
                  <span
                    className="absolute top-1.5 right-1.5 min-w-[8px] h-2 rounded-full ring-2 ring-[color:var(--color-bg)] flex items-center justify-center"
                    style={{ background: "#F97316" }}
                  />
                )}
              </Link>
              {user && (
                <Link href="/profile">
                  <div
                    className="w-8 h-8 rounded-xl flex items-center justify-center text-white text-xs font-bold overflow-hidden"
                    style={{ background: "linear-gradient(135deg,#6366F1,#A855F7)" }}
                  >
                    {user.avatar_url ? (
                      <img
                        src={user.avatar_url}
                        className="w-full h-full rounded-xl object-cover"
                        alt=""
                      />
                    ) : (
                      user.full_name?.[0] || user.earth_id[4]
                    )}
                  </div>
                </Link>
              )}
            </div>
          </div>
        </header>
      )}

      {/* ── Content ── */}
      <main className={cn("flex-1 pb-20", className)}>{children}</main>

      {/* ── BottomNav ── */}
      <BottomNav />

      {/* ── AI Float Button ── */}
      <AiFloatButton />
    </div>
    </div>
  );
}
