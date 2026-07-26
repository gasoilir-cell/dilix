"use client";

import ReelsFeed from "@/components/reels/ReelsFeed";
import BottomNav from "@/components/layout/BottomNav";
import AiFloatButton from "@/components/shared/AiFloatButton";

export default function ReelsPage() {
  return (
    <div className="min-h-screen min-h-dvh bg-[var(--color-bg)]">
      <div className="relative mx-auto w-full max-w-lg h-screen h-dvh">
        <ReelsFeed />
        <AiFloatButton className="top-16 bottom-auto" />
        <BottomNav />
      </div>
    </div>
  );
}
