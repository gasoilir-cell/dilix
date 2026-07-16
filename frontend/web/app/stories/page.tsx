"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { isAuthenticated } from "@/lib/api";
import StoryBar from "@/components/StoryBar";

export default function StoriesPage() {
  const [authed, setAuthed] = useState(false);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    setAuthed(isAuthenticated());
    setReady(true);
  }, []);

  if (!ready) return null;

  return (
    <main className="page">
      <div className="row-between">
        <Link href="/" className="link-btn">
          ← خانه
        </Link>
        <h1 style={{ fontSize: "1.2rem" }}>داستان‌ها</h1>
      </div>
      <p className="muted">نوارِ داستان‌های ۲۴ساعته — انتشار، تماشا و حلقه‌های مخاطب</p>

      {authed ? (
        <StoryBar />
      ) : (
        <div className="card danger">برای مشاهده و انتشارِ داستان ابتدا وارد شوید.</div>
      )}
    </main>
  );
}
