"use client";

import { useEffect } from "react";
import { useParams, useRouter, useSearchParams } from "next/navigation";

/**
 * /messages/[id] → redirect to /messages?to=[id]
 * The messages page handles room creation and displays the ChatView.
 * type=collaboration → intent=collaboration (پیش‌نویسِ همکاری در گفتگو)
 */
export default function MessagesChatRedirect() {
  const params = useParams();
  const router = useRouter();
  const searchParams = useSearchParams();
  const id = params?.id as string;

  useEffect(() => {
    if (id) {
      const q = new URLSearchParams({ to: id });
      if (searchParams.get("type") === "collaboration") q.set("intent", "collaboration");
      router.replace(`/messages?${q.toString()}`);
    } else {
      router.replace("/messages");
    }
  }, [id, router, searchParams]);

  return (
    <div className="flex items-center justify-center h-screen bg-[#0A0A0A]">
      <div className="w-6 h-6 border-2 border-indigo-500 border-t-transparent rounded-full animate-spin" />
    </div>
  );
}
