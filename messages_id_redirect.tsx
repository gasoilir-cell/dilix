"use client";

import { useEffect } from "react";
import { useParams, useRouter } from "next/navigation";

/**
 * /messages/[id] → redirect to /messages?to=[id]
 * The messages page handles room creation and displays the ChatView
 */
export default function MessagesChatRedirect() {
  const params = useParams();
  const router = useRouter();
  const id = params?.id as string;

  useEffect(() => {
    if (id) {
      router.replace(`/messages?to=${encodeURIComponent(id)}`);
    } else {
      router.replace("/messages");
    }
  }, [id, router]);

  return (
    <div className="flex items-center justify-center h-screen bg-[#0A0A0A]">
      <div className="w-6 h-6 border-2 border-indigo-500 border-t-transparent rounded-full animate-spin" />
    </div>
  );
}
