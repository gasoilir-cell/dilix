"use client";

import { useState, useEffect, Suspense } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { motion } from "framer-motion";
import { Search, MessageCircle, Clock, Users } from "lucide-react";
import AppShell from "@/components/layout/AppShell";
import { toPersianNum } from "@/lib/utils";

const ROLE_AVATAR: Record<string, string> = {
  driver: "🚛",
  cargo_owner: "📦",
  freight_broker: "🤝",
  insurance_agent: "🛡️",
  creator: "📢",
  admin: "⚙️",
  user: "👤",
};

const ROLE_COLOR: Record<string, string> = {
  driver: "#f59e0b",
  cargo_owner: "#06b6d4",
  freight_broker: "#8b5cf6",
  insurance_agent: "#10b981",
  creator: "#f43f5e",
  admin: "#ec4899",
  user: "#6366f1",
};

type Conversation = {
  id: string;
  name: string;
  earth_id: string;
  role: string;
  avatar_url?: string;
  last_message: string;
  time: string;
  unread: number;
  online: boolean;
};

const MOCK_CONVERSATIONS: Conversation[] = [
  { id:"1", name:"احمد رضایی",           earth_id:"DLX-DEMO001", role:"driver",          last_message:"بار رو تحویل دادم، رسیدتون ارسال شد",              time:"۱۴:۳۲",        unread:2, online:true  },
  { id:"2", name:"شرکت فراز لجستیک",     earth_id:"DLX-DEMO002", role:"cargo_owner",     last_message:"قرارداد رو بررسی کردیم، شرایط قبوله",              time:"دیروز",        unread:0, online:false },
  { id:"3", name:"Sarah Klein",           earth_id:"DLX-DEMO012", role:"creator",         last_message:"Looking forward to our collaboration! 🤝",           time:"دیروز",        unread:1, online:true  },
  { id:"4", name:"Ali Hassan",            earth_id:"DLX-DEMO010", role:"driver",          last_message:"Ready for the next shipment",                        time:"دو روز پیش",  unread:0, online:true  },
  { id:"5", name:"نیلوفر صادقی",          earth_id:"DLX-DEMO005", role:"creator",         last_message:"از محتواهات خوشم اومد، می‌خوام باهات همکاری کنم",   time:"۳ روز پیش",   unread:0, online:false },
  { id:"6", name:"سیستم دیلیکس",          earth_id:"DLX-SYS00001", role:"admin",          last_message:"بار شما با موفقیت تحویل داده شد ✅",                 time:"هفته پیش",     unread:1, online:true  },
];

function MessagesContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [search, setSearch] = useState("");

  // وقتی از Earth با ?to=EARTH_ID می‌آد، مستقیم به chat ببر
  useEffect(() => {
    const to = searchParams.get("to");
    const type = searchParams.get("type");
    if (to) {
      router.replace(`/messages/${to}${type ? `?type=${type}` : ""}`);
    }
  }, [searchParams, router]);

  const filtered = MOCK_CONVERSATIONS.filter(
    (c) =>
      c.name.includes(search) ||
      c.earth_id.toLowerCase().includes(search.toLowerCase()) ||
      c.last_message.includes(search)
  );

  const totalUnread = MOCK_CONVERSATIONS.reduce((acc, c) => acc + c.unread, 0);

  return (
    <AppShell title={totalUnread > 0 ? `پیام‌ها (${toPersianNum(totalUnread)})` : "پیام‌ها"}>
      <div className="page-inner">
        {/* Search */}
        <div className="relative mb-4">
          <Search size={16} className="absolute right-3 top-1/2 -translate-y-1/2 text-surface-400" />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="جستجوی مکالمه‌ها..."
            className="input w-full pr-9 text-sm"
          />
        </div>

        {/* آنلاین‌ها */}
        <div className="flex gap-3 overflow-x-auto pb-3 mb-2 no-scrollbar">
          {MOCK_CONVERSATIONS.filter(c => c.online).map(c => (
            <button
              key={c.id}
              onClick={() => router.push(`/messages/${c.earth_id}`)}
              className="flex flex-col items-center gap-1 flex-shrink-0"
            >
              <div className="relative">
                <div
                  className="w-12 h-12 rounded-full flex items-center justify-center text-xl border-2"
                  style={{ borderColor: ROLE_COLOR[c.role] ?? "#6366f1", background: `${ROLE_COLOR[c.role] ?? "#6366f1"}15` }}
                >
                  {c.avatar_url
                    ? <img src={c.avatar_url} className="w-full h-full rounded-full object-cover" alt={c.name} />
                    : (ROLE_AVATAR[c.role] ?? "👤")}
                </div>
                <span className="absolute bottom-0 right-0 w-3 h-3 bg-emerald-500 rounded-full border-2 border-surface-900" />
              </div>
              <span className="text-[10px] text-surface-400 truncate max-w-[52px]">{c.name.split(" ")[0]}</span>
            </button>
          ))}
        </div>

        <div className="h-px bg-surface-800 mb-3" />

        {/* Conversations */}
        {filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <MessageCircle size={48} className="text-surface-700 mb-3" />
            <p className="text-surface-500 text-sm">مکالمه‌ای پیدا نشد</p>
          </div>
        ) : (
          <div className="space-y-0.5">
            {filtered.map((conv, i) => (
              <motion.button
                key={conv.id}
                initial={{ opacity: 0, y: 6 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: i * 0.04 }}
                onClick={() => router.push(`/messages/${conv.earth_id}`)}
                className="w-full flex items-center gap-3 p-3.5 rounded-xl hover:bg-surface-800/60 active:scale-[0.99] transition-all text-right"
              >
                {/* Avatar */}
                <div className="relative flex-shrink-0">
                  <div
                    className="w-12 h-12 rounded-full flex items-center justify-center text-xl border"
                    style={{ borderColor: `${ROLE_COLOR[conv.role] ?? "#6366f1"}40`, background: `${ROLE_COLOR[conv.role] ?? "#6366f1"}12` }}
                  >
                    {conv.avatar_url
                      ? <img src={conv.avatar_url} className="w-full h-full rounded-full object-cover" alt={conv.name} />
                      : (ROLE_AVATAR[conv.role] ?? "👤")}
                  </div>
                  {conv.online && (
                    <span className="absolute bottom-0 right-0 w-3 h-3 bg-emerald-500 rounded-full border-2 border-surface-900" />
                  )}
                </div>

                {/* Content */}
                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between mb-0.5">
                    <p className={`text-sm font-semibold truncate ${conv.unread > 0 ? "text-white" : "text-surface-200"}`}>
                      {conv.name}
                    </p>
                    <div className="flex items-center gap-2 flex-shrink-0 mr-2">
                      {conv.unread > 0 && (
                        <span
                          className="min-w-[20px] h-5 px-1 rounded-full text-white text-[10px] font-bold flex items-center justify-center"
                          style={{ background: ROLE_COLOR[conv.role] ?? "#6366f1" }}
                        >
                          {toPersianNum(conv.unread)}
                        </span>
                      )}
                      <span className="text-[11px] text-surface-500 flex items-center gap-1 whitespace-nowrap">
                        <Clock size={10} />
                        {conv.time}
                      </span>
                    </div>
                  </div>
                  <p className={`text-xs truncate ${conv.unread > 0 ? "text-surface-300" : "text-surface-500"}`}>
                    {conv.last_message}
                  </p>
                  <p className="text-[10px] text-surface-600 font-mono mt-0.5">{conv.earth_id}</p>
                </div>
              </motion.button>
            ))}
          </div>
        )}

        <div className="flex items-center justify-center gap-2 mt-8 text-surface-600">
          <Users size={14} />
          <p className="text-xs">برای شروع مکالمه جدید، از کره زمین افراد را انتخاب کن</p>
        </div>
      </div>
    </AppShell>
  );
}

export default function MessagesPage() {
  return (
    <Suspense fallback={
      <div className="flex items-center justify-center h-screen bg-surface-950 text-surface-400">
        در حال بارگذاری...
      </div>
    }>
      <MessagesContent />
    </Suspense>
  );
}
