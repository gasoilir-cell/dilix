"use client";

import { useState } from "react";
import { usePathname } from "next/navigation";
import AssistantPanel from "@/components/AssistantPanel";

const HIDE_ON = ["/login", "/assistant"];

export default function AssistantFab() {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  if (HIDE_ON.some((p) => pathname === p || pathname.startsWith(`${p}/`))) return null;

  return (
    <>
      <button
        className="assistant-fab"
        aria-label="دستیار هوشمند"
        onClick={() => setOpen((v) => !v)}
      >
        {open ? "✕" : "✨"}
      </button>

      {open && (
        <div className="assistant-panel" role="dialog" aria-label="گفتگو با دستیار">
          <header>
            <strong>دستیار هوشمند</strong>
            <a className="btn link" href="/assistant">صفحه کامل</a>
          </header>
          <AssistantPanel compact />
        </div>
      )}
    </>
  );
}
