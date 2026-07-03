"use client";

import { useState, useEffect, useCallback } from "react";
import { useRouter } from "next/navigation";
import {
  Bell, BellOff, CheckCheck, Loader2,
  Package, CreditCard, Shield, MessageCircle, Gift, Info,
} from "lucide-react";
import api from "@/lib/api";
import AppShell from "@/components/layout/AppShell";
import { toPersianNum } from "@/lib/utils";
import toast from "react-hot-toast";

interface NotifItem {
  id: string;
  type: "info" | "success" | "warning" | "error" | string;
  title: string;
  body: string | null;
  is_read: boolean;
  action_url: string | null;
  created_at: string;
}

const TYPE_ICON: Record<string, React.ReactNode> = {
  info:    <Info size={18} className="text-blue-400" />,
  success: <CheckCheck size={18} className="text-accent-400" />,
  warning: <Bell size={18} className="text-yellow-400" />,
  error:   <BellOff size={18} className="text-red-400" />,
  freight: <Package size={18} className="text-primary-400" />,
  payment: <CreditCard size={18} className="text-green-400" />,
  kyc:     <Shield size={18} className="text-indigo-400" />,
  message: <MessageCircle size={18} className="text-cyan-400" />,
  referral:<Gift size={18} className="text-violet-400" />,
};

const TYPE_BG: Record<string, string> = {
  info:    "bg-blue-500/10",
  success: "bg-accent-500/10",
  warning: "bg-yellow-500/10",
  error:   "bg-red-500/10",
  freight: "bg-primary-500/10",
  payment: "bg-green-500/10",
  kyc:     "bg-indigo-500/10",
  message: "bg-cyan-500/10",
  referral:"bg-violet-500/10",
};

function relativeTime(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const m = Math.floor(diff / 60000);
  const h = Math.floor(m / 60);
  const d = Math.floor(h / 24);
  if (m < 1)  return "همین الان";
  if (m < 60) return `${toPersianNum(m)} دقیقه پیش`;
  if (h < 24) return `${toPersianNum(h)} ساعت پیش`;
  return `${toPersianNum(d)} روز پیش`;
}

export default function NotificationsPage() {
  const router = useRouter();
  const [items,   setItems]   = useState<NotifItem[]>([]);
  const [unread,  setUnread]  = useState(0);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      const res = await api.get("/notifications");
      setItems(res.data.items ?? []);
      setUnread(res.data.unread ?? 0);
    } catch {
      // silent
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  const handleMarkAll = async () => {
    try {
      await api.post("/notifications/read-all");
      setItems((prev) => prev.map((n) => ({ ...n, is_read: true })));
      setUnread(0);
      toast.success("همه خوانده شدند");
    } catch {
      toast.error("خطا");
    }
  };

  const handleClick = async (item: NotifItem) => {
    if (!item.is_read) {
      await api.post(`/notifications/${item.id}/read`).catch(() => {});
      setItems((prev) =>
        prev.map((n) => n.id === item.id ? { ...n, is_read: true } : n)
      );
      setUnread((p) => Math.max(0, p - 1));
    }
    if (item.action_url) {
      router.push(item.action_url);
    }
  };

  return (
    <AppShell title="اعلان‌ها">
      <div className="page-inner pb-safe">

        {/* Header action */}
        {unread > 0 && (
          <div className="flex justify-end mb-3">
            <button
              onClick={handleMarkAll}
              className="flex items-center gap-1.5 text-sm text-primary-400 hover:text-primary-300 transition-colors"
            >
              <CheckCheck size={16} />
              خواندن همه
            </button>
          </div>
        )}

        {loading ? (
          <div className="flex justify-center py-16">
            <Loader2 size={28} className="text-primary-400 animate-spin" />
          </div>
        ) : items.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-20 text-center">
            <div className="w-16 h-16 rounded-full bg-surface-800 flex items-center justify-center mb-4">
              <BellOff size={28} className="text-surface-500" />
            </div>
            <p className="text-surface-400 text-sm">اعلانی وجود ندارد</p>
          </div>
        ) : (
          <div className="card divide-y divide-surface-800/60">
            {items.map((item) => {
              const icon = TYPE_ICON[item.type] ?? TYPE_ICON.info;
              const bg   = TYPE_BG[item.type]  ?? TYPE_BG.info;
              return (
                <button
                  key={item.id}
                  onClick={() => handleClick(item)}
                  className={`w-full flex items-start gap-3 p-4 text-right transition-colors hover:bg-surface-800/30 ${
                    !item.is_read ? "bg-surface-800/20" : ""
                  }`}
                >
                  <div className={`w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0 ${bg}`}>
                    {icon}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-start justify-between gap-2">
                      <p className={`text-sm font-semibold leading-snug ${
                        item.is_read ? "text-surface-300" : "text-white"
                      }`}>
                        {item.title}
                      </p>
                      {!item.is_read && (
                        <span className="w-2 h-2 rounded-full bg-primary-400 flex-shrink-0 mt-1" />
                      )}
                    </div>
                    {item.body && (
                      <p className="text-xs text-surface-500 mt-0.5 leading-relaxed line-clamp-2">
                        {item.body}
                      </p>
                    )}
                    <p className="text-[11px] text-surface-600 mt-1">{relativeTime(item.created_at)}</p>
                  </div>
                </button>
              );
            })}
          </div>
        )}
      </div>
    </AppShell>
  );
}
