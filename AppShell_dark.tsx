"use client";
import { ReactNode } from "react";
import Link from "next/link";
import { Bot, Bell, Search } from "lucide-react";
import BottomNav from "./BottomNav";
import { cn } from "@/lib/utils";
import { useAuthStore } from "@/store/auth";

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

  return (
    <div className="min-h-dvh flex flex-col" style={{ background: "#0A0A0A" }}>

      {/* ── Header ── */}
      {showHeader && (
        <header
          className="sticky top-0 z-40"
          style={{
            background:     "rgba(10,10,10,0.92)",
            backdropFilter: "blur(24px)",
            borderBottom:   "1px solid rgba(255,255,255,0.09)",
          }}
        >
          <div className="flex items-center justify-between px-4 h-14">
            <div className="flex items-center gap-3">
              {title ? (
                <h1 className="text-base font-bold text-white">{title}</h1>
              ) : (
                <Link href="/dashboard" className="flex items-center gap-2">
                  <span className="text-xl font-black text-gradient-primary">Dilix</span>
                  <span className="text-xs mt-0.5" style={{ color: "rgba(255,255,255,0.4)" }}>
                    دیلیکس
                  </span>
                </Link>
              )}
            </div>

            <div className="flex items-center gap-1">
              {showSearch && (
                <button
                  className="p-2 rounded-xl transition-colors"
                  style={{ color: "rgba(255,255,255,0.55)" }}
                >
                  <Search className="w-5 h-5" />
                </button>
              )}
              <button
                className="relative p-2 rounded-xl transition-colors"
                style={{ color: "rgba(255,255,255,0.55)" }}
              >
                <Bell className="w-5 h-5" />
                <span
                  className="absolute top-1.5 right-1.5 w-2 h-2 rounded-full ring-2"
                  style={{ background: "#F97316" }}
                />
              </button>
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
      <Link
        href="/ai"
        className="fixed bottom-20 left-4 z-50 w-12 h-12 rounded-2xl flex items-center justify-center
                   shadow-lg transition-transform hover:scale-110 active:scale-95"
        style={{
          background:  "linear-gradient(135deg,#A855F7,#7C3AED)",
          boxShadow:   "0 4px 20px rgba(168,85,247,0.45)",
        }}
      >
        <Bot className="w-6 h-6 text-white" />
      </Link>
    </div>
  );
}
