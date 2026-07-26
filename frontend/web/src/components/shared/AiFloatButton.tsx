"use client";

import Link from "next/link";
import { Bot } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * دکمهٔ شناورِ دستیارِ هوشِ مصنوعی — روی هر صفحه‌ای که AppShell ندارد
 * (کره‌زمین، ریلز) هم قابل استفاده است تا کاربر همه‌جا به دستیار دسترسی داشته باشد.
 */
export default function AiFloatButton({ className }: { className?: string }) {
  return (
    <Link
      href="/ai"
      aria-label="دستیارِ هوشِ مصنوعی"
      className={cn(
        "fixed bottom-20 left-4 z-50 w-12 h-12 rounded-2xl flex items-center justify-center",
        "shadow-lg transition-transform hover:scale-110 active:scale-95",
        className
      )}
      style={{
        background: "linear-gradient(135deg,#A855F7,#7C3AED)",
        boxShadow:  "0 4px 20px rgba(168,85,247,0.45)",
      }}
    >
      <Bot className="w-6 h-6 text-white" />
    </Link>
  );
}
