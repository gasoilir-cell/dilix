"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Plus } from "lucide-react";
import { liveApi } from "@/lib/api";
import { toPersianNum } from "@/lib/utils";

interface LiveItem {
  session_id: string;
  title?: string | null;
  host: { earth_id: string; name: string; avatar_url?: string | null };
  viewer_count: number;
  is_mine: boolean;
}

// نوارِ افقیِ پخش‌های زنده در بالای فیدِ کاوش — دکمهٔ «شروع» + میزبان‌های زنده
export default function LiveBar() {
  const router = useRouter();
  const [items, setItems] = useState<LiveItem[]>([]);

  useEffect(() => {
    let on = true;
    const load = () =>
      liveApi.list(20).then((r) => { if (on) setItems(r.data?.items ?? []); }).catch(() => {});
    load();
    const id = setInterval(load, 8000);
    return () => { on = false; clearInterval(id); };
  }, []);

  return (
    <div className="flex gap-3 overflow-x-auto px-4 pb-3 no-scrollbar">
      <button
        onClick={() => router.push("/live?go=1")}
        className="shrink-0 flex flex-col items-center gap-1"
      >
        <div className="w-16 h-16 rounded-full flex items-center justify-center border-2 border-dashed border-rose-500/60 bg-rose-500/10">
          <Plus className="w-6 h-6 text-rose-400" />
        </div>
        <span className="text-[11px] text-white/70">پخش زنده</span>
      </button>

      {items.map((it) => (
        <button
          key={it.session_id}
          onClick={() => router.push(`/live?watch=${it.session_id}`)}
          className="shrink-0 flex flex-col items-center gap-1 w-16"
        >
          <div className="relative w-16 h-16 rounded-full p-[2px] bg-gradient-to-tr from-rose-500 to-orange-400">
            <div className="w-full h-full rounded-full overflow-hidden bg-surface-800 flex items-center justify-center">
              {it.host.avatar_url ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={it.host.avatar_url} alt="" className="w-full h-full object-cover" />
              ) : (
                <span className="text-lg font-bold text-white">{it.host.name.charAt(0)}</span>
              )}
            </div>
            <span className="absolute -bottom-0.5 left-1/2 -translate-x-1/2 text-[9px] font-bold text-white bg-rose-600 px-1.5 rounded-full leading-4">
              LIVE
            </span>
          </div>
          <span className="text-[11px] text-white/70 truncate w-16 text-center">
            {it.viewer_count > 0 ? `${toPersianNum(it.viewer_count)} بیننده` : it.host.name}
          </span>
        </button>
      ))}
    </div>
  );
}
